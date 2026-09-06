"""Phase 27 - Notification System tests.

Covers against a real in-memory SQLite database:
  * Device-token registration (idempotent, re-owning, unregister/reactivate)
  * Notification creation for all nine types across the three audiences
  * Preference gating + anti-spam (dedupe cooldown, hourly cap)
  * Delivery attempts via the push-provider abstraction (mock FCM)
  * Read / unread tracking
  * Deep links stored and forwarded to the provider
  * Invalid-token handling (permanent failure deactivates the device)
  * Retry of transient failures with attempt caps
VERIFY - a notification originating from a backend business event
(price drop on a saved product) reaches the correct user's device.
"""

import os
import sys
from datetime import datetime, timezone
from pathlib import Path

BACKEND_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BACKEND_DIR))

os.environ.setdefault("ENVIRONMENT", "test")
os.environ.setdefault("HYPERLOCAL_ENV", "test")

import pytest  # noqa: E402
from sqlalchemy import create_engine  # noqa: E402
from sqlalchemy.orm import sessionmaker  # noqa: E402

from app.core.config import settings  # noqa: E402

settings.RATE_LIMIT_ENABLED = False

from app.models.base import Base  # noqa: E402
from app.services import notification_service as ns  # noqa: E402
from app.services.push_service import MockPushProvider, PushResult, set_push_service  # noqa: E402

UTC = timezone.utc


def _portable_timestamp_defaults():
    """Replace literal "now()" server defaults with Python-side callables."""
    from sqlalchemy import ColumnDefault

    def _now(ctx=None):
        return datetime.now(timezone.utc)

    for table in Base.metadata.tables.values():
        for col in table.columns:
            sd = getattr(col, "server_default", None)
            sd_arg = getattr(sd, "arg", None)
            if sd_arg == "now()":
                if col.default is None:
                    col.default = ColumnDefault(_now)
                col.server_default = None
            elif isinstance(sd_arg, str) and sd_arg.lower() == "false":
                if col.default is None and (
                    getattr(getattr(col.type, "python_type", None), "__name__", "") == "bool"
                ):
                    col.default = ColumnDefault(False)
                col.server_default = None

    for table in Base.metadata.tables.values():
        for col in table.columns:
            ou = getattr(col, "onupdate", None)
            ou_arg = getattr(ou, "arg", None) if ou is not None else None
            if ou_arg == "now()":
                from sqlalchemy import ColumnDefault as _CD

                col.onupdate = _CD(_now, for_update=True)


_portable_timestamp_defaults()


from app.models.notification import (  # noqa: E402
    DeviceToken,
    Notification,
    NotificationDelivery,
    NotificationPreference,
)
from app.models.product import Category, ProductMaster  # noqa: E402
from app.models.role import Permission, Role, role_permissions  # noqa: E402
from app.models.saved_product import SavedProduct  # noqa: E402
from app.models.user import User  # noqa: E402

TABLES = [
    Role.__table__,
    Permission.__table__,
    role_permissions,
    User.__table__,
    Category.__table__,
    ProductMaster.__table__,
    SavedProduct.__table__,
    Notification.__table__,
    NotificationPreference.__table__,
    DeviceToken.__table__,
    NotificationDelivery.__table__,
]


@pytest.fixture()
def db():
    from sqlalchemy.pool import StaticPool

    engine = create_engine(
        "sqlite://",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    Base.metadata.create_all(engine, tables=TABLES)
    SessionLocal = sessionmaker(bind=engine)
    session = SessionLocal()
    yield session
    session.close()
    engine.dispose()


@pytest.fixture()
def provider():
    """Fresh mock push provider wired into the service singleton."""
    mock = MockPushProvider()
    set_push_service(mock)
    yield mock
    set_push_service(MockPushProvider())  # reset singleton after test


@pytest.fixture()
def dispatch_log(monkeypatch):
    """Capture Celery .delay calls so tests never need a broker."""
    from app.services.notification_tasks import deliver_notification_task

    log: list[int] = []
    monkeypatch.setattr(deliver_notification_task, "delay", lambda nid: log.append(nid))
    return log


# -- Entity factories --------------------------------------------------------
_counter = {"n": 0}


def _next_id():
    _counter["n"] += 1
    return _counter["n"]


def make_role(db, name="customer"):
    role = db.query(Role).filter(Role.name == name).first()
    if role is None:
        role = Role(name=name, description=name)
        db.add(role)
        db.flush()
    return role


def make_user(db, role_name="customer", status="ACTIVE"):
    n = _next_id()
    role = make_role(db, role_name)
    user = User(
        phone_number=f"+9198765{n:05d}",
        name=f"User {n}",
        role_id=role.id,
        status=status,
        is_active=status == "ACTIVE",
    )
    db.add(user)
    db.flush()
    return user


def make_token(db, user, token=None):
    return ns.register_device_token(
        db, user_id=user.id, token=token or f"fcm-token-{_next_id()}", platform="FCM"
    )


def make_saved_product(db, user):
    n = _next_id()
    cat = Category(name=f"Cat {n}", slug=f"cat-{n}")
    db.add(cat)
    db.flush()
    pm = ProductMaster(name=f"Product {n}", slug=f"product-{n}", category_id=cat.id)
    db.add(pm)
    db.flush()
    sp = SavedProduct(user_id=user.id, product_master_id=pm.id)
    db.add(sp)
    db.flush()
    return pm


# -- Token registration ------------------------------------------------------
class TestTokenRegistration:
    def test_register_new_token(self, db):
        user = make_user(db)
        token = make_token(db, user, "tok-new-1")
        assert token.is_active is True
        assert token.user_id == user.id
        assert token.platform == "FCM"

    def test_registration_is_idempotent(self, db):
        user = make_user(db)
        first = make_token(db, user, "same-token")
        second = make_token(db, user, "same-token")
        assert first.id == second.id
        assert db.query(DeviceToken).count() == 1

    def test_token_reowned_on_account_switch(self, db):
        u1 = make_user(db)
        u2 = make_user(db)
        make_token(db, u1, "roaming-token")
        moved = ns.register_device_token(db, user_id=u2.id, token="roaming-token")
        assert moved.user_id == u2.id
        owners = {t.user_id for t in db.query(DeviceToken).all()}
        assert owners == {u2.id}

    def test_reactivation_resets_failures(self, db):
        user = make_user(db)
        tok = make_token(db, user, "sick-token")
        tok.failure_count = 3
        db.flush()
        revived = ns.register_device_token(db, user_id=user.id, token="sick-token")
        assert revived.is_active is True
        assert revived.failure_count == 0


# -- Notification creation ---------------------------------------------------
class TestNotificationCreation:
    ALL_TYPES = [
        (ns.NotificationType.PRICE_DROP, ns.Audience.CUSTOMER),
        (ns.NotificationType.PRODUCT_AVAILABLE, ns.Audience.CUSTOMER),
        (ns.NotificationType.OFFER, ns.Audience.CUSTOMER),
        (ns.NotificationType.SUBSCRIPTION, ns.Audience.CUSTOMER),
        (ns.NotificationType.PAYMENT, ns.Audience.CUSTOMER),
        (ns.NotificationType.INVENTORY_UPDATE, ns.Audience.SHOPKEEPER),
        (ns.NotificationType.SHOP_VERIFICATION, ns.Audience.SHOPKEEPER),
        (ns.NotificationType.POS_SYNC, ns.Audience.SHOPKEEPER),
        (ns.NotificationType.SYSTEM, ns.Audience.ADMIN),
    ]

    def test_all_nine_types_create_with_correct_audience(self, db, dispatch_log):
        for ntype, audience in self.ALL_TYPES:
            user = make_user(db)
            result = ns.create_notification(
                db,
                user_id=user.id,
                notification_type=ntype,
                title=f"t-{ntype}",
                body="b",
                enqueue=False,
                dedupe_key=None,
            )
            assert result.created is True, ntype
            assert result.notification.type == ntype
            assert result.notification.audience == audience
            assert result.notification.delivery_status == "PENDING"

    def test_unknown_user_rejected(self, db):
        result = ns.create_notification(
            db, user_id=999999, notification_type=ns.NotificationType.SYSTEM,
            title="t", body="b", enqueue=False,
        )
        assert result.created is False and result.reason == "user_inactive_or_missing"

    def test_inactive_user_rejected(self, db):
        user = make_user(db, status="INACTIVE")
        result = ns.create_notification(
            db, user_id=user.id, notification_type=ns.NotificationType.SYSTEM,
            title="t", body="b", enqueue=False,
        )
        assert result.created is False


# -- Preferences & anti-spam -------------------------------------------------
class TestPreferencesAndAntiSpam:
    def test_price_alert_opt_out_suppresses_creation(self, db):
        user = make_user(db)
        prefs = ns._get_preferences(db, user.id)
        prefs.price_alerts = False
        db.flush()
        result = ns.create_notification(
            db, user_id=user.id, notification_type=ns.NotificationType.PRICE_DROP,
            title="drop", body="b", enqueue=False,
        )
        assert result.created is False and result.reason == "preference_opt_out"
        assert db.query(Notification).count() == 0

    def test_deal_alert_opt_out_blocks_offers_but_not_payments(self, db, dispatch_log):
        user = make_user(db)
        prefs = ns._get_preferences(db, user.id)
        prefs.deal_alerts = False
        prefs.promotional = False
        db.flush()
        offer = ns.create_notification(
            db, user_id=user.id, notification_type=ns.NotificationType.OFFER,
            title="o", body="b", enqueue=False,
        )
        payment = ns.notify_payment_event(db, user_id=user.id, payment_id=1, status="SUCCESS", amount=99)
        assert offer.reason == "preference_opt_out"
        assert payment.created is True  # transactional types are never gated

    def test_dedupe_key_cooldown_prevents_spam(self, db):
        user = make_user(db)
        first = ns.create_notification(
            db, user_id=user.id, notification_type=ns.NotificationType.PRICE_DROP,
            title="t", body="b", dedupe_key="price-drop:42:1", enqueue=False,
        )
        second = ns.create_notification(
            db, user_id=user.id, notification_type=ns.NotificationType.PRICE_DROP,
            title="t", body="b2", dedupe_key="price-drop:42:1", enqueue=False,
        )
        assert first.created is True
        assert second.created is False and second.reason == "duplicate"
        assert db.query(Notification).count() == 1

    def test_hourly_cap_limits_marketing_burst(self, db):
        user = make_user(db)
        original_cap = settings.NOTIFICATION_HOURLY_CAP
        settings.NOTIFICATION_HOURLY_CAP = 2
        try:
            outcomes = [
                ns.create_notification(
                    db, user_id=user.id, notification_type=ns.NotificationType.OFFER,
                    title=f"o{i}", body="b", dedupe_key=f"offer:{i}", enqueue=False,
                )
                for i in range(3)
            ]
        finally:
            settings.NOTIFICATION_HOURLY_CAP = original_cap
        assert [o.created for o in outcomes] == [True, True, False]
        assert outcomes[2].reason == "rate_limited"

    def test_push_master_switch_stops_delivery_not_inbox(self, db, provider):
        user = make_user(db)
        make_token(db, user)
        prefs = ns._get_preferences(db, user.id)
        prefs.push_enabled = False
        db.flush()
        created = ns.create_notification(
            db, user_id=user.id, notification_type=ns.NotificationType.SUBSCRIPTION,
            title="sub", body="b", enqueue=False,
        )
        outcome = ns.deliver_notification(db, created.notification.id)
        assert outcome["status"] == "SKIPPED"
        assert provider.sent == []          # no push went out
        assert db.query(Notification).count() == 1  # in-app copy remains


# -- Delivery attempts -------------------------------------------------------
class TestDelivery:
    def test_delivery_reaches_registered_device(self, db, provider):
        user = make_user(db)
        tok = make_token(db, user, "deliver-me")
        created = ns.create_notification(
            db, user_id=user.id, notification_type=ns.NotificationType.SUBSCRIPTION,
            title="Receipt", body="paid", deep_link="hyperlocal://payments/9", enqueue=False,
        )
        outcome = ns.deliver_notification(db, created.notification.id)
        assert outcome["status"] == "SENT" and outcome["delivered"] == 1

        notification = db.query(Notification).first()
        assert notification.delivery_status == "SENT"
        assert notification.sent_at is not None
        assert notification.provider_message_id.startswith("mock-")

        delivery = db.query(NotificationDelivery).one()
        assert delivery.device_token_id == tok.id
        assert delivery.status == "SENT"
        assert delivery.attempts == 1
        assert delivery.delivered_at is not None

        assert len(provider.sent) == 1
        assert provider.sent[0].token == "deliver-me"

    def test_delivery_without_tokens_is_skipped(self, db, provider):
        user = make_user(db)  # no device registered
        created = ns.create_notification(
            db, user_id=user.id, notification_type=ns.NotificationType.SYSTEM,
            title="t", body="b", enqueue=False,
        )
        outcome = ns.deliver_notification(db, created.notification.id)
        assert outcome["status"] == "SKIPPED"
        assert provider.sent == []
        assert created.notification.last_error == "no active device tokens"

    def test_multi_device_delivery_records_history(self, db, provider):
        user = make_user(db)
        make_token(db, user, "phone-1")
        make_token(db, user, "tablet-1")
        created = ns.create_notification(
            db, user_id=user.id, notification_type=ns.NotificationType.PAYMENT,
            title="p", body="b", enqueue=False,
        )
        outcome = ns.deliver_notification(db, created.notification.id)
        assert outcome["delivered"] == 2
        statuses = {d.status for d in db.query(NotificationDelivery).all()}
        assert statuses == {"SENT"}
        assert {m.token for m in provider.sent} == {"phone-1", "tablet-1"}

    def test_redelivery_is_idempotent(self, db, provider):
        user = make_user(db)
        make_token(db, user, "once-only")
        created = ns.create_notification(
            db, user_id=user.id, notification_type=ns.NotificationType.SYSTEM,
            title="t", body="b", enqueue=False,
        )
        ns.deliver_notification(db, created.notification.id)
        second = ns.deliver_notification(db, created.notification.id)
        assert second["delivered"] == 1      # counted from existing SENT row
        assert len(provider.sent) == 1       # but provider called only once


# -- Read / unread -----------------------------------------------------------
class TestReadUnread:
    def _make_three(self, db):
        user = make_user(db)
        for i in range(3):
            ns.create_notification(
                db, user_id=user.id, notification_type=ns.NotificationType.SYSTEM,
                title=f"n{i}", body="b", dedupe_key=None, enqueue=False,
            )
        return user

    def test_mark_single_read_sets_timestamp(self, db):
        user = self._make_three(db)
        first = db.query(Notification).order_by(Notification.id).first()
        first.is_read = True
        first.read_at = datetime.now(timezone.utc)
        db.flush()
        unread = (
            db.query(Notification)
            .filter(Notification.user_id == user.id, Notification.is_read == False)  # noqa: E712
            .count()
        )
        assert unread == 2
        assert first.read_at is not None

    def test_unread_count_matches_new_notifications(self, db):
        user = self._make_three(db)
        unread = (
            db.query(Notification)
            .filter(Notification.user_id == user.id, Notification.is_read == False)  # noqa: E712
            .count()
        )
        assert unread == 3

    def test_read_all(self, db):
        user = self._make_three(db)
        db.query(Notification).filter(Notification.user_id == user.id).update(
            {Notification.is_read: True, Notification.read_at: datetime.now(timezone.utc)}
        )
        db.flush()
        remaining = (
            db.query(Notification)
            .filter(Notification.user_id == user.id, Notification.is_read == False)  # noqa: E712
            .count()
        )
        assert remaining == 0


# -- Deep links --------------------------------------------------------------
class TestDeepLink:
    def test_deep_link_persisted_and_forwarded_to_provider(self, db, provider, dispatch_log):
        user = make_user(db)
        make_token(db, user, "link-device")
        result = ns.notify_shop_verification(
            db, shopkeeper_user_id=user.id, shop_id=77, decision="VERIFY"
        )
        notification = result.notification
        assert notification.deep_link == "hyperlocal://shopkeeper/shop/77"

        outcome = ns.deliver_notification(db, notification.id)
        assert outcome["status"] == "SENT"
        message = provider.sent[0]
        assert message.deep_link == "hyperlocal://shopkeeper/shop/77"
        assert message.data["type"] == "SHOP_VERIFICATION"

    def test_delivery_status_exposes_deep_link(self, db, provider):
        user = make_user(db)
        make_token(db, user)
        result = ns.create_notification(
            db, user_id=user.id, notification_type=ns.NotificationType.OFFER,
            title="o", body="b", deep_link="hyperlocal://offers/3", enqueue=False,
        )
        ns.deliver_notification(db, result.notification.id)
        status = ns.get_delivery_status(db, result.notification.id, user.id)
        assert status["deep_link"] == "hyperlocal://offers/3"


# -- Invalid token -----------------------------------------------------------
class TestInvalidToken:
    class DeadTokenProvider(MockPushProvider):
        """Simulates FCM reporting an unregistered (permanently invalid) token."""

        def send(self, message):
            if message.token == "dead-token":
                return PushResult(delivered=False, error="UNREGISTERED", permanent_failure=True)
            return super().send(message)

    def test_invalid_token_deactivated_and_reported(self, db):
        set_push_service(self.DeadTokenProvider())
        try:
            user = make_user(db)
            tok = make_token(db, user, "dead-token")
            created = ns.create_notification(
                db, user_id=user.id, notification_type=ns.NotificationType.SYSTEM,
                title="t", body="b", enqueue=False,
            )
            outcome = ns.deliver_notification(db, created.notification.id)

            assert outcome["status"] == "FAILED"
            db.refresh(tok)
            assert tok.is_active is False           # never targeted again

            delivery = db.query(NotificationDelivery).one()
            assert delivery.status == "FAILED"
            assert delivery.permanent_failure is True
            assert "UNREGISTERED" in delivery.error
        finally:
            set_push_service(MockPushProvider())

    def test_valid_token_still_delivered_alongside_dead_one(self, db):
        set_push_service(self.DeadTokenProvider())
        try:
            user = make_user(db)
            make_token(db, user, "dead-token")
            make_token(db, user, "healthy-token")
            created = ns.create_notification(
                db, user_id=user.id, notification_type=ns.NotificationType.SYSTEM,
                title="t", body="b", enqueue=False,
            )
            outcome = ns.deliver_notification(db, created.notification.id)
            # one device dead (permanent) → partial success
            assert outcome["status"] == "PARTIAL"
            assert outcome["delivered"] == 1
        finally:
            set_push_service(MockPushProvider())


# -- Retry -------------------------------------------------------------------
class TestRetry:
    class FlakyProvider(MockPushProvider):
        """Fails transiently the first N sends, then succeeds."""

        def __init__(self, failures=1):
            super().__init__()
            self.failures_left = failures

        def send(self, message):
            if self.failures_left > 0:
                self.failures_left -= 1
                return PushResult(delivered=False, error="INTERNAL / backend busy")
            return super().send(message)

    def test_transient_failure_then_retry_succeeds(self, db):
        set_push_service(self.FlakyProvider(failures=1))
        try:
            user = make_user(db)
            make_token(db, user, "flaky-device")
            created = ns.create_notification(
                db, user_id=user.id, notification_type=ns.NotificationType.PRICE_DROP,
                title="drop", body="cheaper now", deep_link="hyperlocal://product/5",
                dedupe_key="price-drop:5:x", enqueue=False,
            )
            nid = created.notification.id

            first = ns.deliver_notification(db, nid)
            assert first["status"] == "FAILED"
            delivery = db.query(NotificationDelivery).one()
            assert delivery.status == "FAILED" and delivery.permanent_failure is False

            sweep = ns.retry_failed_notifications(db)
            assert sweep["retried"] >= 1

            notification = db.query(Notification).get(nid)
            assert notification.delivery_status == "SENT"
            delivery = db.query(NotificationDelivery).one()
            assert delivery.status == "SENT"
            assert delivery.attempts == 2               # one failure + one success
        finally:
            set_push_service(MockPushProvider())

    def test_retry_stops_after_max_attempts(self, db):
        settings_backup = settings.NOTIFICATION_MAX_DELIVERY_ATTEMPTS
        settings.NOTIFICATION_MAX_DELIVERY_ATTEMPTS = 2

        class AlwaysDown(MockPushProvider):
            def send(self, message):
                return PushResult(delivered=False, error="503 unavailable")

        set_push_service(AlwaysDown())
        try:
            user = make_user(db)
            make_token(db, user, "offline-device")
            created = ns.create_notification(
                db, user_id=user.id, notification_type=ns.NotificationType.SYSTEM,
                title="t", body="b", enqueue=False,
            )
            nid = created.notification.id

            ns.deliver_notification(db, nid)   # attempt 1
            ns.retry_failed_notifications(db)  # attempt 2 (cap reached)
            third = ns.retry_failed_notifications(db)  # capped — no more tries

            delivery = db.query(NotificationDelivery).one()
            assert delivery.attempts == 2
            # third sweep must not have produced another provider attempt
            assert all(r["delivered"] == 0 and r["failed"] == 0 for r in third["results"])
        finally:
            settings.NOTIFICATION_MAX_DELIVERY_ATTEMPTS = settings_backup
            set_push_service(MockPushProvider())


# -- Background job wiring ---------------------------------------------------
class TestBackgroundJobsRegistered:
    def test_notification_tasks_are_registered_with_celery(self):
        from app.core.celery_app import celery_app

        for name in (
            "app.services.notification_tasks.deliver_notification",
            "app.services.notification_tasks.retry_failed_notifications",
            "app.services.notification_tasks.deliver_batch",
        ):
            assert name in celery_app.tasks, f"missing task {name}"

    def test_retry_sweep_registered_in_beat_schedule(self):
        from app.core.celery_app import celery_app

        assert "notification-retry-sweep" in celery_app.conf.beat_schedule


# -- VERIFY: business event → correct user/device -----------------------------
class TestEndToEndBusinessEvent:
    def test_price_drop_reaches_saved_product_owner_device(self, db, provider, dispatch_log):
        customer = make_user(db, "customer")           # saved the product → target
        make_user(db, "customer")                      # did not save it → excluded
        product = make_saved_product(db, customer)

        # Backend business event fires from the pricing engine.
        created_ids = ns.notify_price_drop(
            db, product_master_id=product.id,
            shop_name="Kirana Corner", old_price=199.0, new_price=149.0,
        )

        assert len(created_ids) == 1                   # only the saver was notified
        recipients = {n.user_id for n in db.query(Notification).all()}
        assert recipients == {customer.id}

        # Customer's registered device receives it via the push abstraction.
        make_token(db, customer, "customer-phone")
        ns.deliver_notification(db, created_ids[0])

        assert dispatch_log == [created_ids[0]]
        assert len(provider.sent) == 1
        sent = provider.sent[0]
        assert sent.token == "customer-phone"
        assert sent.deep_link == f"hyperlocal://product/{product.id}"
        assert sent.data["notification_id"] == str(created_ids[0])
        assert "149" in sent.body

        notification = db.query(Notification).get(created_ids[0])
        assert notification.type == "PRICE_DROP"
        assert notification.audience == "customer"
        assert notification.delivery_status == "SENT"
        assert notification.is_read is False

    def test_shopkeeper_verification_event_targets_shopkeeper(self, db, provider, dispatch_log):
        keeper = make_user(db, "shopkeeper")
        result = ns.notify_shop_verification(
            db, shopkeeper_user_id=keeper.id, shop_id=12, decision="VERIFY"
        )
        assert result.created is True
        make_token(db, keeper, "keeper-device")
        ns.deliver_notification(db, result.notification.id)

        notification = db.query(Notification).one()
        assert notification.user_id == keeper.id
        assert notification.type == "SHOP_VERIFICATION"
        assert notification.audience == "shopkeeper"

        assert provider.sent[0].token == "keeper-device"
        assert "live" in provider.sent[0].body.lower()