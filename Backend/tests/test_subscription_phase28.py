"""Phase 28 - Shopkeeper Subscription & Payment System tests.

Covers against a real in-memory SQLite database:
  * Plan selection (seeded Basic/Pro/Premium templates, entitlement resolution)
  * Subscription creation -> activation via verified payment
  * Successful payment (server-side verification, invoice reference, period)
  * Failed payment (gateway decline + invalid signature + webhook failure)
  * Webhooks (HMAC authentication, duplicate delivery idempotency)
  * Expiry sweep + grace period (PAST_DUE keeps features, EXPIRED revokes)
  * Renewal (extension from period end; reactivation after lapse)
  * Cancellation (at period end, immediate, double-cancel rejection)
  * Refund handling (provider-supported refunds revoke the subscription)
  * Entitlement enforcement (product limit, offers cap, POS gating)

VERIFY - subscription status correctly controls Shopkeeper features.
"""

import os
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

BACKEND_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BACKEND_DIR))

os.environ.setdefault("ENVIRONMENT", "test")
os.environ.setdefault("HYPERLOCAL_ENV", "test")

import pytest  # noqa: E402
from sqlalchemy import create_engine  # noqa: E402
from sqlalchemy.orm import sessionmaker  # noqa: E402
from sqlalchemy.pool import StaticPool  # noqa: E402

from app.core.config import settings  # noqa: E402

settings.RATE_LIMIT_ENABLED = False

from app.core.exceptions import AppError, ConflictError, NotFoundError  # noqa: E402
from app.models.base import Base  # noqa: E402
from app.services import shopkeeper_service, subscription_service  # noqa: E402
from app.services.payments import (  # noqa: E402
    build_webhook_payload,
    encode_webhook,
    mock_payment_provider,
)
from app.services.subscription import entitlements  # noqa: E402

UTC = timezone.utc


# Adapt PostGIS Geography columns for plain SQLite (shared, reversible helper).
from tests.geo_compat import strip_geo_columns  # noqa: E402

strip_geo_columns()


def _portable_timestamp_defaults():
    from sqlalchemy import ColumnDefault

    def _now(ctx=None):
        return datetime.utcnow()

    for table in Base.metadata.tables.values():
        for col in table.columns:
            sd = getattr(col, "server_default", None)
            sd_arg = getattr(sd, "arg", None)
            if isinstance(sd_arg, str) and sd_arg.lower() == "now()":
                if col.default is None:
                    col.default = ColumnDefault(_now)
                col.server_default = None
            elif isinstance(sd_arg, str) and sd_arg.lower() == "false":
                if col.default is None and (
                    getattr(getattr(col.type, "python_type", None), "__name__", "") == "bool"
                ):
                    col.default = ColumnDefault(False)
                col.server_default = None
            ou = getattr(col, "onupdate", None)
            ou_arg = getattr(ou, "arg", None)
            if ou is not None and str(ou_arg).strip().lower().startswith("now"):
                col.onupdate = ColumnDefault(_now, for_update=True)


_portable_timestamp_defaults()


# Tables required by the subscription/payment test matrix.
from app.models.product import (  # noqa: E402
    Brand,
    Category,
    Inventory,
    Offer,
    OfferProduct,
    ProductImage,
    ProductMaster,
    ShopProduct,
)
from app.models.role import Permission, Role, role_permissions  # noqa: E402
from app.models.shop import Shop  # noqa: E402
from app.models.subscription import (  # noqa: E402
    Payment,
    PaymentEvent,
    Subscription,
    SubscriptionPlan,
    SubscriptionStatus,
)
from app.models.user import User  # noqa: E402

TABLES = [
    Role.__table__,
    Permission.__table__,
    role_permissions,
    User.__table__,
    Shop.__table__,
    Category.__table__,
    Brand.__table__,
    ProductMaster.__table__,
    ProductImage.__table__,
    ShopProduct.__table__,
    Inventory.__table__,
    Offer.__table__,
    OfferProduct.__table__,
    SubscriptionPlan.__table__,
    Subscription.__table__,
    Payment.__table__,
    PaymentEvent.__table__,
]


@pytest.fixture()
def db():
    engine = create_engine(
        "sqlite://",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    Base.metadata.create_all(engine, tables=TABLES)
    session = sessionmaker(bind=engine)()
    yield session
    session.close()
    engine.dispose()


# ── Entity factories ─────────────────────────────────────────────────────────
_counter = {"n": 0}


def _next_id():
    _counter["n"] += 1
    return _counter["n"]


def make_user(db, role_name="shopkeeper"):
    from app.models.user import UserStatus

    n = _next_id()
    role = db.query(Role).filter(Role.name == role_name).first()
    if role is None:
        role = Role(name=role_name, description=role_name)
        db.add(role)
        db.flush()
    user = User(
        phone_number=f"+9198765{n:05d}",
        name=f"Keeper {n}",
        role_id=role.id,
        status=UserStatus.ACTIVE,
        is_active=True,
    )
    db.add(user)
    db.flush()
    return user


def make_shop(db, name=None):
    from app.models.shop import ShopStatus

    n = _next_id()
    shop = Shop(
        name=name or f"Shop {n}",
        description=f"desc {n}",
        status=ShopStatus.ACTIVE,
        latitude=25.59,
        longitude=85.13,
    )
    db.add(shop)
    db.flush()
    return shop


def make_plan(db, name=None, monthly=199.0, feats=None):
    plan = SubscriptionPlan(
        name=name or f"Plan {_next_id()}",
        price_monthly=monthly,
        price_annual=monthly * 10,
        features_json=feats,
    )
    db.add(plan)
    db.flush()
    return plan


def owner_access(shop):
    """Fully-privileged owner ShopAccess for enforcement tests."""
    from app.core.shopkeeper_permissions import effective_shop_permissions

    return shopkeeper_service.ShopAccess(
        shop=shop,
        role_name="owner",
        is_owner=True,
        permissions=effective_shop_permissions("owner", True, None),
    )


def _as_utc(value):
    """Normalize SQLite-loaded naive datetimes to UTC-aware for comparisons."""
    if value is None or value.tzinfo:
        return value
    return value.replace(tzinfo=UTC)


def subscribe_and_pay(db, user, shop, plan, cycle="MONTHLY", method="UPI"):
    """Full happy-path funnel: subscribe -> initiate -> verify."""
    sub = subscription_service.create_subscription(
        db, user=user, plan_id=plan.id, shop_id=shop.id, billing_cycle=cycle
    )
    intent = subscription_service.initiate_payment(db, sub, method, billing_cycle=cycle)
    provider = mock_payment_provider
    pay_id = f"pay_{sub.id}_{intent['payment_id']}"
    sig = provider.checkout_signature(intent["provider_order_id"], pay_id)
    result = subscription_service.verify_payment(db, intent["payment_id"], pay_id, sig)
    db.flush()
    return sub, intent, result


# ── Plan selection ───────────────────────────────────────────────────────────
class TestPlanSelection:
    def test_seed_creates_basic_pro_premium(self, db):
        plans = subscription_service.seed_plans(db)
        assert [p["name"] for p in plans] == ["Basic", "Pro", "Premium"]

        # Idempotent — second seed updates rather than duplicates.
        subscription_service.seed_plans(db)
        assert len(subscription_service.list_plans(db)) == 3

    def test_plan_entitlements_ladder(self, db):
        plans = {p["name"]: p for p in subscription_service.seed_plans(db)}
        assert plans["Basic"]["entitlements"]["max_products"] == 50
        assert plans["Basic"]["entitlements"]["pos_support"] is False
        assert plans["Pro"]["entitlements"]["pos_support"] is True
        assert plans["Pro"]["entitlements"]["advanced_analytics"] is False
        assert plans["Premium"]["entitlements"]["max_products"] is None  # unlimited
        assert plans["Premium"]["entitlements"]["advanced_analytics"] is True
        assert plans["Premium"]["entitlements"]["support_level"] == "PRIORITY"

    def test_unknown_template_lookup_returns_none(self):
        assert entitlements.get_plan_template("Enterprise") is None
        assert entitlements.get_plan_template("premium") is not None

    def test_subscribe_selects_plan_incomplete(self, db):
        user, shop, plan = make_user(db), make_shop(db), make_plan(db, monthly=299.0)
        sub = subscription_service.create_subscription(
            db, user=user, plan_id=plan.id, shop_id=shop.id
        )
        assert sub.status == SubscriptionStatus.INCOMPLETE
        assert sub.plan_id == plan.id
        # INCOMPLETE never grants paid features.
        resolved = entitlements.resolve_shop_entitlements(db, shop)
        assert resolved["is_paid"] is False
        assert resolved["entitlements"] == entitlements.FREE_TIER_ENTITLEMENTS

    def test_subscribe_invalid_cycle_rejected(self, db):
        from app.core.exceptions import ValidationError

        user, plan = make_user(db), make_plan(db)
        with pytest.raises(ValidationError):
            subscription_service.create_subscription(
                db, user=user, plan_id=plan.id, billing_cycle="BIWEEKLY"
            )


# ── Successful payment ───────────────────────────────────────────────────────
class TestSuccessfulPayment:
    def test_full_flow_activates_subscription(self, db):
        user, shop, plan = make_user(db), make_shop(db), make_plan(db, monthly=499.0)
        sub, intent, payment = subscribe_and_pay(db, user, shop, plan)

        assert payment["status"] == "SUCCESS"
        assert intent["amount"] == 499.0
        assert payment["invoice_number"].startswith("INV-")
        assert payment["transaction_id"]

        db.refresh(sub)
        assert sub.status == SubscriptionStatus.ACTIVE
        start = _as_utc(sub.current_period_start)
        end = _as_utc(sub.current_period_end)
        assert abs((end - start).days - 30) <= 1

    def test_verify_is_idempotent_after_success(self, db):
        user, shop, plan = make_user(db), make_shop(db), make_plan(db)
        sub, intent, payment = subscribe_and_pay(db, user, shop, plan)
        end_before = _as_utc(sub.current_period_end)

        again = subscription_service.verify_payment(
            db, intent["payment_id"], payment["transaction_id"], "ignored"
        )
        assert again["status"] == "SUCCESS"
        db.refresh(sub)
        assert _as_utc(sub.current_period_end) == end_before  # no double extension

    def test_annual_cycle_uses_annual_price_and_365d(self, db):
        user, shop = make_user(db), make_shop(db)
        plan = make_plan(db, monthly=100.0)
        sub, intent, _pay = subscribe_and_pay(db, user, shop, plan, cycle="ANNUAL")
        assert intent["amount"] == pytest.approx(1000.0)
        db.refresh(sub)
        days = (_as_utc(sub.current_period_end) - _as_utc(sub.current_period_start)).days
        assert 360 <= days <= 366


# ── Failed payment ───────────────────────────────────────────────────────────
class TestFailedPayment:
    def _pending(self, db):
        user, shop, plan = make_user(db), make_shop(db), make_plan(db)
        sub = subscription_service.create_subscription(
            db, user=user, plan_id=plan.id, shop_id=shop.id
        )
        intent = subscription_service.initiate_payment(db, sub, "UPI")
        return sub, intent

    def test_gateway_decline_marks_failed_and_keeps_incomplete(self, db):
        sub, intent = self._pending(db)
        mock_payment_provider.fail_next_payment()
        sig = mock_payment_provider.checkout_signature(intent["provider_order_id"], "pay_declined")
        result = subscription_service.verify_payment(db, intent["payment_id"], "pay_declined", sig)

        assert result["status"] == "FAILED"
        assert result["failure_reason"] == "GATEWAY_DECLINED"
        db.refresh(sub)
        assert sub.status == SubscriptionStatus.INCOMPLETE
        # A failed payment cannot be re-verified; a new intent is required.
        with pytest.raises(ConflictError):
            subscription_service.verify_payment(db, intent["payment_id"], "pay_x", "sig")

    def test_forged_client_signature_never_succeeds(self, db):
        """Client-side 'success' without a valid signature must not activate."""
        from app.services.payments import PaymentVerificationError

        sub, intent = self._pending(db)
        with pytest.raises(PaymentVerificationError):
            subscription_service.verify_payment(db, intent["payment_id"], "pay_fake", "forged-sig")
        db.refresh(sub)
        assert sub.status == SubscriptionStatus.INCOMPLETE
        resolved = entitlements.resolve_shop_entitlements(db, _shop_by_id(db, sub.shop_id))
        assert resolved["is_paid"] is False


def _shop_by_id(db, shop_id):
    return db.query(Shop).filter(Shop.id == shop_id).first()


# ── Webhooks ─────────────────────────────────────────────────────────────────
def _signed_webhook(event_id, order_id, status="SUCCESS", pay_id=None):
    payload = build_webhook_payload(
        event_id, "payment.captured", order_id, provider_payment_id=pay_id, status=status
    )
    body = encode_webhook(payload)
    return body, mock_payment_provider.webhook_signature(body)


class TestWebhooks:
    def test_webhook_activates_subscription(self, db):
        user, shop, plan = make_user(db), make_shop(db), make_plan(db)
        sub = subscription_service.create_subscription(db, user=user, plan_id=plan.id, shop_id=shop.id)
        intent = subscription_service.initiate_payment(db, sub, "UPI")

        body, sig = _signed_webhook("evt_001", intent["provider_order_id"])
        result = subscription_service.handle_webhook(db, "MOCK", body, sig)
        assert result["duplicate"] is False and result["matched"] is True

        db.refresh(sub)
        assert sub.status == SubscriptionStatus.ACTIVE
        ledger = db.query(PaymentEvent).all()
        assert len(ledger) == 1 and ledger[0].event_id == "evt_001"

    def test_duplicate_webhook_is_ignored(self, db):
        user, shop, plan = make_user(db), make_shop(db), make_plan(db)
        sub = subscription_service.create_subscription(db, user=user, plan_id=plan.id, shop_id=shop.id)
        intent = subscription_service.initiate_payment(db, sub, "UPI")
        body, sig = _signed_webhook("evt_dup", intent["provider_order_id"])

        first = subscription_service.handle_webhook(db, "MOCK", body, sig)
        assert first["duplicate"] is False
        end_after_first = _as_utc(sub.current_period_end)

        second = subscription_service.handle_webhook(db, "MOCK", body, sig)
        assert second["duplicate"] is True
        db.refresh(sub)
        assert _as_utc(sub.current_period_end) == end_after_first  # applied exactly once
        assert db.query(PaymentEvent).count() == 1

    def test_webhook_rejects_invalid_signature(self, db):
        from app.services.payments import WebhookSignatureError

        body, _sig = _signed_webhook("evt_evil", "order_nonexistent")
        with pytest.raises(WebhookSignatureError):
            subscription_service.handle_webhook(db, "MOCK", body, "bad-signature")

    def test_webhook_failure_event_marks_payment_failed(self, db):
        sub, intent = TestFailedPayment()._pending(db)
        body, sig = _signed_webhook("evt_fail", intent["provider_order_id"], status="FAILED")
        subscription_service.handle_webhook(db, "MOCK", body, sig)
        payment = db.query(Payment).filter(Payment.id == intent["payment_id"]).first()
        assert payment.status == "FAILED"
        db.refresh(sub)
        assert sub.status == SubscriptionStatus.INCOMPLETE


# ── Expiry & grace period ────────────────────────────────────────────────────
class TestExpiryGrace:
    def test_active_past_end_becomes_past_due_within_grace(self, db):
        user, shop, plan = make_user(db), make_shop(db), make_plan(db)
        sub, _i, _p = subscribe_and_pay(db, user, shop, plan)
        now = sub.current_period_end.replace(tzinfo=UTC) + timedelta(days=1)

        counts = subscription_service.process_expiries(db, now=now)
        assert counts["past_due"] == 1
        db.refresh(sub)
        assert sub.status == SubscriptionStatus.PAST_DUE

        # Grace keeps paid features available.
        resolved = entitlements.resolve_shop_entitlements(db, shop)
        assert resolved["status"] == "PAST_DUE"
        assert resolved["in_grace"] is True
        assert resolved["is_paid"] is True

    def test_grace_lapse_expires_and_revokes_features(self, db):
        user, shop, plan = make_user(db), make_shop(db), make_plan(db)
        sub, _i, _p = subscribe_and_pay(db, user, shop, plan)
        now = sub.current_period_end.replace(tzinfo=UTC) + timedelta(days=entitlements.GRACE_PERIOD_DAYS + 1)

        counts = subscription_service.process_expiries(db, now=now)
        assert counts["expired"] == 1
        db.refresh(sub)
        assert sub.status == SubscriptionStatus.EXPIRED

        resolved = entitlements.resolve_shop_entitlements(db, shop)
        assert resolved["status"] == "EXPIRED"
        assert resolved["entitlements"]["max_products"] == entitlements.FREE_TIER_ENTITLEMENTS["max_products"]
        assert resolved["is_paid"] is False

    def test_cancel_at_period_end_closes_on_expiry(self, db):
        user, shop, plan = make_user(db), make_shop(db), make_plan(db)
        sub, _i, _p = subscribe_and_pay(db, user, shop, plan)
        subscription_service.cancel_subscription(db, sub)  # at period end
        db.refresh(sub)
        assert sub.cancel_at_period_end is True and sub.status == SubscriptionStatus.ACTIVE

        now = sub.current_period_end.replace(tzinfo=UTC) + timedelta(days=1)
        counts = subscription_service.process_expiries(db, now=now)
        assert counts["canceled"] == 1
        db.refresh(sub)
        assert sub.status == SubscriptionStatus.CANCELED


# ── Renewal ──────────────────────────────────────────────────────────────────
class TestRenewal:
    def test_renewal_extends_period_from_period_end(self, db):
        user, shop, plan = make_user(db), make_shop(db), make_plan(db)
        sub, intent, _pay = subscribe_and_pay(db, user, shop, plan)
        original_end = sub.current_period_end

        renewal_intent = subscription_service.initiate_payment(db, sub, "UPI")
        pay_id = f"renew_{renewal_intent['payment_id']}"
        sig = mock_payment_provider.checkout_signature(renewal_intent["provider_order_id"], pay_id)
        subscription_service.verify_payment(db, renewal_intent["payment_id"], pay_id, sig)

        db.refresh(sub)
        assert sub.status == SubscriptionStatus.ACTIVE
        assert _as_utc(sub.current_period_end) > _as_utc(original_end)  # stacked on old period
        history = subscription_service.payment_history(db, subscription_id=sub.id)
        assert history["total"] == 2
        assert all(p["invoice_number"] for p in history["items"])  # both invoiced

    def test_lapsed_subscription_reactivates_from_now(self, db):
        user, shop, plan = make_user(db), make_shop(db), make_plan(db)
        sub, _i, _p = subscribe_and_pay(db, user, shop, plan)
        # Force into grace (period ended 2 days ago → lapsed).
        past_end = datetime.now(UTC) - timedelta(days=2)
        sub.current_period_end = past_end
        sub.status = SubscriptionStatus.PAST_DUE
        db.flush()

        renewal_intent = subscription_service.initiate_payment(db, sub, "UPI")
        pay_id = f"react_{renewal_intent['payment_id']}"
        sig = mock_payment_provider.checkout_signature(renewal_intent["provider_order_id"], pay_id)
        subscription_service.verify_payment(db, renewal_intent["payment_id"], pay_id, sig)

        db.refresh(sub)
        assert sub.status == SubscriptionStatus.ACTIVE
        assert _as_utc(sub.current_period_start) > _as_utc(past_end)  # fresh period from now


# ── Cancellation ─────────────────────────────────────────────────────────────
class TestCancellation:
    def test_cancel_at_period_end_keeps_features_until_end(self, db):
        user, shop, plan = make_user(db), make_shop(db), make_plan(db)
        sub, _i, _p = subscribe_and_pay(db, user, shop, plan)
        updated = subscription_service.cancel_subscription(db, sub)

        assert updated.cancel_at_period_end is True
        resolved = entitlements.resolve_shop_entitlements(db, shop)
        assert resolved["status"] == "ACTIVE"  # features still live this period
        assert resolved["is_paid"] is True

    def test_immediate_cancel_revokes_features(self, db):
        user, shop, plan = make_user(db), make_shop(db), make_plan(db)
        sub, _i, _p = subscribe_and_pay(db, user, shop, plan)
        subscription_service.cancel_subscription(db, sub, immediate=True)

        db.refresh(sub)
        assert sub.status == SubscriptionStatus.CANCELED
        resolved = entitlements.resolve_shop_entitlements(db, shop)
        assert resolved["is_paid"] is False
        assert resolved["entitlements"]["offers"] is False

    def test_double_cancel_conflicts(self, db):
        user, shop, plan = make_user(db), make_shop(db), make_plan(db)
        sub, _i, _p = subscribe_and_pay(db, user, shop, plan)
        subscription_service.cancel_subscription(db, sub, immediate=True)
        with pytest.raises(ConflictError):
            subscription_service.cancel_subscription(db, sub)

    def test_cancel_incomplete_closes_directly(self, db):
        user, shop, plan = make_user(db), make_shop(db), make_plan(db)
        sub = subscription_service.create_subscription(db, user=user, plan_id=plan.id, shop_id=shop.id)
        subscription_service.cancel_subscription(db, sub)
        db.refresh(sub)
        assert sub.status == SubscriptionStatus.CANCELED


# ── Refunds ──────────────────────────────────────────────────────────────────
class TestRefunds:
    def test_refund_success_revokes_subscription(self, db):
        user, shop, plan = make_user(db), make_shop(db), make_plan(db)
        sub, intent, _pay = subscribe_and_pay(db, user, shop, plan)
        result = subscription_service.refund_payment(db, intent["payment_id"], reason="chargeback")

        assert result["status"] == "REFUNDED"
        assert result["refund_id"]
        assert result["refunded_at"]
        db.refresh(sub)
        assert sub.status == SubscriptionStatus.CANCELED
        resolved = entitlements.resolve_shop_entitlements(db, shop)
        assert resolved["is_paid"] is False

    def test_refund_pending_payment_rejected(self, db):
        from app.core.exceptions import ValidationError

        user, shop, plan = make_user(db), make_shop(db), make_plan(db)
        sub = subscription_service.create_subscription(db, user=user, plan_id=plan.id, shop_id=shop.id)
        intent = subscription_service.initiate_payment(db, sub, "UPI")
        with pytest.raises(ValidationError):
            subscription_service.refund_payment(db, intent["payment_id"])

    def test_provider_without_refund_support_rejected(self, db):
        """A gateway that cannot refund must never be asked to."""
        from app.core.exceptions import ValidationError
        from app.services.payments import PaymentIntent, PaymentProvider
        from app.services.payments import VerificationResult, register_provider
        from app.services.payments.base import _PROVIDERS

        class NoRefundProvider(PaymentProvider):
            code = "NOREFUND"
            display_name = "No-refund gateway"
            supports_refund = False

            def create_order(self, order_ref, amount, currency, payment_method, notes=None):
                return PaymentIntent(provider_order_id=f"nr_{order_ref}", amount=amount, currency=currency)

            def verify_payment(self, order_id, payment_id, signature):
                return VerificationResult(verified=True, provider_payment_id=payment_id)

            def parse_webhook(self, body, signature):
                raise NotImplementedError

            def refund(self, payment_id, amount, reason=None):
                raise AssertionError("refund must not be called")

        register_provider(NoRefundProvider())
        try:
            user, shop, plan = make_user(db), make_shop(db), make_plan(db)
            sub = subscription_service.create_subscription(db, user=user, plan_id=plan.id, shop_id=shop.id)
            intent = subscription_service.initiate_payment(db, sub, "UPI", provider_code="NOREFUND")
            subscription_service.verify_payment(
                db, intent["payment_id"], f"nrp_{intent['payment_id']}", "any"
            )
            with pytest.raises(ValidationError):
                subscription_service.refund_payment(db, intent["payment_id"])
        finally:
            _PROVIDERS.pop("NOREFUND", None)


# ── Entitlement enforcement (VERIFY: status controls Shopkeeper features) ────
class TestEntitlementEnforcement:
    def _listing(self, db, access, name, user=None):
        user = user or make_user(db)
        return shopkeeper_service.create_product(
            access, db, user, {"name": name, "price": 10.0, "publish": True, "quantity": 5}
        )

    @staticmethod
    def _offer_data(listing_id):
        from datetime import datetime as dt

        return {
            "title": "Sale",
            "offer_type": "FLAT_DISCOUNT",
            "discount_value": 5.0,
            "start_date": dt.now(UTC) - timedelta(hours=1),
            "end_date": dt.now(UTC) + timedelta(days=7),
            "shop_product_ids": [listing_id],
        }

    def test_product_limit_blocks_at_cap(self, db):
        user, shop = make_user(db), make_shop(db)
        plan = make_plan(db, feats={"max_products": 2})
        subscribe_and_pay(db, user, shop, plan)
        access = owner_access(shop)

        self._listing(db, access, "Item A")
        self._listing(db, access, "Item B")
        with pytest.raises(AppError) as exc:
            self._listing(db, access, "Item C")
        assert exc.value.error_code == "PLAN_LIMIT_REACHED"
        assert exc.value.data["limit"] == 2

    def test_premium_unlimited_products(self, db):
        user, shop = make_user(db), make_shop(db)
        plan = make_plan(db, name="Premium", feats={"max_products": None})
        subscribe_and_pay(db, user, shop, plan)
        access = owner_access(shop)
        for i in range(5):
            self._listing(db, access, f"P{i}")
        count = db.query(ShopProduct).filter(ShopProduct.shop_id == shop.id).count()
        assert count == 5

    def test_offer_cap_enforced(self, db):
        user, shop = make_user(db), make_shop(db)
        plan = make_plan(db, feats={"offers": True, "max_active_offers": 1})
        subscribe_and_pay(db, user, shop, plan)
        access = owner_access(shop)
        listing = self._listing(db, access, "Offered item")
        offer_data = self._offer_data(listing["id"])

        first = shopkeeper_service.assign_offer(access, db, user, offer_data)
        assert first["offer_id"]

        with pytest.raises(AppError) as exc:
            shopkeeper_service.assign_offer(access, db, user, offer_data)
        assert exc.value.error_code == "PLAN_LIMIT_REACHED"

    def test_offers_blocked_without_offers_entitlement(self, db):
        """Expired (free tier) shops cannot run offers at all."""
        user, shop = make_user(db), make_shop(db)
        plan = make_plan(db, feats={"offers": True})
        subscribe_and_pay(db, user, shop, plan)
        access = owner_access(shop)
        listing = self._listing(db, access, "Item")

        sub = db.query(Subscription).filter(Subscription.shop_id == shop.id).first()
        sub.status = SubscriptionStatus.EXPIRED
        db.flush()

        with pytest.raises(AppError) as exc:
            shopkeeper_service.assign_offer(access, db, user, self._offer_data(listing["id"]))
        assert exc.value.error_code in {"ENTITLEMENT_DENIED", "SUBSCRIPTION_EXPIRED"}

    def test_pos_support_gating(self, db):
        user, basic_shop = make_user(db), make_shop(db)
        pro_shop, pro_user = make_shop(db), make_user(db)
        basic_plan = make_plan(db, name="Basic", feats=dict(entitlements.PLAN_TEMPLATES["Basic"]["entitlements"]))
        pro_plan = make_plan(db, name="Pro2", feats=dict(entitlements.PLAN_TEMPLATES["Pro"]["entitlements"]))
        subscribe_and_pay(db, user, basic_shop, basic_plan)
        subscribe_and_pay(db, pro_user, pro_shop, pro_plan)

        with pytest.raises(AppError) as exc:
            shopkeeper_service.enforce_pos_support(db, basic_shop.id)
        assert exc.value.error_code == "ENTITLEMENT_DENIED"
        # Pro passes silently.
        shopkeeper_service.enforce_pos_support(db, pro_shop.id)

    def test_unsubscribed_shops_keep_legacy_behaviour(self, db):
        """Shops that never subscribed are grandfathered, not blocked."""
        user, shop = make_user(db), make_shop(db)
        access = owner_access(shop)

        resolved = entitlements.resolve_shop_entitlements(db, shop)
        assert resolved["status"] == "UNSUBSCRIBED"
        assert resolved["grandfathered"] is True

        # Legacy capability stays available (no plan gates applied).
        listing = self._listing(db, access, "Legacy item")
        assert listing["id"]
        # And enforcement helpers are no-ops.
        entitlements.enforce_feature(resolved, "pos_support")
        entitlements.enforce_limit(resolved, "max_products", 10_000)

    def test_verify_status_controls_features_end_to_end(self, db):
        """VERIFY: INCOMPLETE -> ACTIVE -> PAST_DUE -> EXPIRED feature ladder."""
        from datetime import datetime as dt

        user, shop = make_user(db), make_shop(db)
        plan = make_plan(db, feats={"offers": True, "max_products": 3})
        sub = subscription_service.create_subscription(db, user=user, plan_id=plan.id, shop_id=shop.id)
        access = owner_access(shop)

        # INCOMPLETE → free tier: listings allowed but offers blocked.
        self._listing(db, access, "Free A")
        resolved = entitlements.resolve_shop_entitlements(db, shop)
        assert resolved["is_paid"] is False
        with pytest.raises(AppError):
            shopkeeper_service.enforce_pos_support(db, shop.id)

        # ACTIVE → paid limits apply (cap 3).
        intent = subscription_service.initiate_payment(db, sub, "UPI")
        pay_id = f"verify_e2e_{intent['payment_id']}"
        sig = mock_payment_provider.checkout_signature(intent["provider_order_id"], pay_id)
        subscription_service.verify_payment(db, intent["payment_id"], pay_id, sig)
        resolved = entitlements.resolve_shop_entitlements(db, shop)
        assert resolved["entitlements"]["max_products"] == 3
        self._listing(db, access, "Paid B")
        self._listing(db, access, "Paid C")
        with pytest.raises(AppError) as exc:
            self._listing(db, access, "Paid D")
        assert exc.value.error_code == "PLAN_LIMIT_REACHED"

        # PAST_DUE (grace) → features retained.
        sub.current_period_end = dt.now(UTC) - timedelta(days=1)
        sub.status = SubscriptionStatus.PAST_DUE
        db.flush()
        resolved = entitlements.resolve_shop_entitlements(db, shop)
        assert resolved["in_grace"] is True and resolved["is_paid"] is True

        # EXPIRED → back to free tier.
        sub.current_period_end = dt.now(UTC) - timedelta(days=entitlements.GRACE_PERIOD_DAYS + 1)
        sub.status = SubscriptionStatus.PAST_DUE
        db.flush()
        resolved = entitlements.resolve_shop_entitlements(db, shop)
        assert resolved["status"] == "EXPIRED"
        assert resolved["entitlements"]["offers"] is False


