"""Phase 28 — Subscription lifecycle + payment orchestration.

Business rules for shopkeeper monetization. Plan entitlement rules live in
:mod:`app.services.subscription.entitlements`; gateway specifics live behind
:mod:`app.services.payments`. This module is the only place where the two
meet.

Payment security model:
  * Client-reported success is NEVER trusted alone — ``verify_payment``
    delegates cryptographic signature checking to the provider adapter
    server-side before any state change.
  * Webhooks are HMAC-authenticated by the adapter and made idempotent via
    the ``payment_events`` ledger (unique per ``(provider, event_id)``).
"""

from __future__ import annotations

from datetime import datetime, timedelta, timezone
from typing import Any, Optional

from sqlalchemy.orm import Session

from app.core.exceptions import ConflictError, NotFoundError, ValidationError
from app.core.logging import get_logger
from app.models.subscription import (
    BillingCycle,
    Payment,
    PaymentEvent,
    Subscription,
    SubscriptionPlan,
    SubscriptionStatus,
)
from app.models.user import User
from app.services.payments import get_provider, list_providers
from app.services.subscription import entitlements

logger = get_logger("app.services.subscription")

PERIOD_DAYS = {
    BillingCycle.WEEKLY: 7,
    BillingCycle.MONTHLY: 30,
    BillingCycle.QUARTERLY: 90,
    BillingCycle.ANNUAL: 365,
}

PAYMENT_SUCCESS = "SUCCESS"
PAYMENT_FAILED = "FAILED"
PAYMENT_PENDING = "PENDING"
PAYMENT_REFUNDED = "REFUNDED"


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


def _aware(dt: Optional[datetime]) -> Optional[datetime]:
    if dt is None:
        return None
    return dt if dt.tzinfo else dt.replace(tzinfo=timezone.utc)


# ── Plans ────────────────────────────────────────────────────────────────────
def list_plans(db: Session, include_inactive: bool = False) -> list[dict]:
    """Available plans (entitlements resolved for display)."""
    query = db.query(SubscriptionPlan)
    if not include_inactive:
        query = query.filter(SubscriptionPlan.is_active == True)  # noqa: E712
    plans = query.order_by(SubscriptionPlan.sort_order, SubscriptionPlan.id).all()
    return [serialize_plan(p) for p in plans]


def get_plan(db: Session, plan_id: int) -> SubscriptionPlan:
    plan = db.query(SubscriptionPlan).filter(SubscriptionPlan.id == plan_id).first()
    if plan is None or not plan.is_active:
        raise NotFoundError("Subscription plan not found")
    return plan


def serialize_plan(plan: SubscriptionPlan) -> dict:
    return {
        "id": plan.id,
        "name": plan.name,
        "description": plan.description,
        "price_monthly": plan.price_monthly,
        "price_annual": plan.price_annual,
        "currency": plan.currency,
        "trial_days": plan.trial_days,
        "is_active": bool(plan.is_active),
        "entitlements": entitlements.resolve_entitlements(plan),
    }


def seed_plans(db: Session) -> list[dict]:
    """Ensure Basic/Pro/Premium exist; returns serialized plans."""
    return [serialize_plan(p) for p in entitlements.seed_plan_templates(db)]


# ── Subscription lifecycle ───────────────────────────────────────────────────
def create_subscription(
    db: Session,
    *,
    user: User,
    plan_id: int,
    shop_id: Optional[int] = None,
    billing_cycle: str = "MONTHLY",
) -> Subscription:
    """Create an INCOMPLETE subscription awaiting its first payment."""
    plan = get_plan(db, plan_id)
    try:
        cycle = BillingCycle(billing_cycle.upper())
    except ValueError as exc:
        raise ValidationError(f"Invalid billing cycle '{billing_cycle}'") from exc

    existing = _live_subscription_for_shop(db, shop_id)
    if existing is not None and existing.status == SubscriptionStatus.ACTIVE:
        raise ConflictError("This shop already has an active subscription — renew or change plan instead")

    subscription = Subscription(
        user_id=user.id,
        shop_id=shop_id,
        plan_id=plan.id,
        status=SubscriptionStatus.INCOMPLETE,
        is_auto_renew=True,
        cancel_at_period_end=False,
    )
    db.add(subscription)
    db.flush()
    logger.info(
        "Subscription created: id=%s user=%s shop=%s plan=%s cycle=%s",
        subscription.id, user.id, shop_id, plan.name, cycle.value,
    )
    return subscription


def activate_subscription(
    db: Session,
    subscription: Subscription,
    start: Optional[datetime] = None,
    billing_cycle: Optional[str] = None,
) -> Subscription:
    """Activate (or re-activate) with a fresh billing period."""
    now = _aware(start) or _utcnow()
    cycle = _cycle_of(subscription, billing_cycle)
    subscription.status = SubscriptionStatus.ACTIVE
    subscription.current_period_start = now
    subscription.current_period_end = now + timedelta(days=PERIOD_DAYS[cycle])
    subscription.cancel_at_period_end = False
    db.flush()
    logger.info("Subscription activated: id=%s period_end=%s", subscription.id, subscription.current_period_end)
    return subscription


def extend_subscription(
    db: Session,
    subscription: Subscription,
    billing_cycle: Optional[str] = None,
) -> Subscription:
    """Renewal: extend from the current period end (or now if already past)."""
    cycle = _cycle_of(subscription, billing_cycle)
    base = _aware(subscription.current_period_end)
    base = base if base and base > _utcnow() else _utcnow()
    subscription.status = SubscriptionStatus.ACTIVE
    subscription.current_period_start = base
    subscription.current_period_end = base + timedelta(days=PERIOD_DAYS[cycle])
    subscription.cancel_at_period_end = False
    db.flush()
    logger.info("Subscription renewed: id=%s new_period_end=%s", subscription.id, subscription.current_period_end)
    return subscription


def cancel_subscription(
    db: Session,
    subscription: Subscription,
    immediate: bool = False,
) -> Subscription:
    """Cancel at period end (default) or immediately."""
    if subscription.status == SubscriptionStatus.CANCELED:
        raise ConflictError("Subscription is already canceled")
    if immediate:
        subscription.status = SubscriptionStatus.CANCELED
        subscription.cancel_at_period_end = False
        subscription.current_period_end = _utcnow()
    elif subscription.status == SubscriptionStatus.INCOMPLETE:
        # Nothing ever paid → nothing to honour at period end.
        subscription.status = SubscriptionStatus.CANCELED
    else:
        subscription.cancel_at_period_end = True
    db.flush()
    logger.info("Subscription canceled: id=%s immediate=%s", subscription.id, immediate)
    return subscription


def process_expiries(db: Session, now: Optional[datetime] = None) -> dict:
    """Materialize lazy status transitions (cron-friendly batch sweep).

    ACTIVE past period end → PAST_DUE (grace); PAST_DUE past grace → EXPIRED;
    ACTIVE with cancel_at_period_end past end → CANCELED.
    """
    now = _aware(now) or _utcnow()
    grace_cutoff = now - timedelta(days=entitlements.GRACE_PERIOD_DAYS)

    def _sweep(from_status, predicate):
        rows = db.query(Subscription).filter(Subscription.status == from_status).all()
        picked = []
        for sub in rows:
            if predicate(_aware(sub.current_period_end), bool(sub.cancel_at_period_end)):
                picked.append(sub)
        return picked

    past_due = _sweep(
        SubscriptionStatus.ACTIVE,
        lambda end, cap_end: end is not None and end < now and not cap_end,
    )
    for sub in past_due:
        sub.status = SubscriptionStatus.PAST_DUE

    canceled_at_end = _sweep(
        SubscriptionStatus.ACTIVE,
        lambda end, cap_end: end is not None and end < now and cap_end,
    )
    for sub in canceled_at_end:
        sub.status = SubscriptionStatus.CANCELED

    expired = _sweep(
        SubscriptionStatus.PAST_DUE,
        lambda end, cap_end: end is not None and end < grace_cutoff,
    )
    for sub in expired:
        sub.status = SubscriptionStatus.EXPIRED

    db.flush()
    counts = {"past_due": len(past_due), "canceled": len(canceled_at_end), "expired": len(expired)}
    if any(counts.values()):
        logger.info("Expiry sweep: %s", counts)
    return counts


def _cycle_of(subscription: Subscription, override: Optional[str]) -> BillingCycle:
    if override:
        try:
            return BillingCycle(override.upper())
        except ValueError as exc:
            raise ValidationError(f"Invalid billing cycle '{override}'") from exc
    return getattr(subscription.plan, "billing_cycle", None) or BillingCycle.MONTHLY


def _live_subscription_for_shop(db: Session, shop_id: Optional[int]) -> Optional[Subscription]:
    if shop_id is None:
        return None
    return (
        db.query(Subscription)
        .filter(
            Subscription.shop_id == shop_id,
            Subscription.status.notin_([SubscriptionStatus.CANCELED, SubscriptionStatus.EXPIRED]),
        )
        .order_by(Subscription.id.desc())
        .first()
    )


def get_current_subscription(db: Session, user: User, shop_id: int | None = None) -> dict:
    """Current subscription payload + effective entitlements for a shop."""
    subscription = _live_subscription_for_shop(db, shop_id)
    payload = serialize_subscription(subscription) if subscription else {
        "subscription": None,
        "status": SubscriptionStatus.EXPIRED.value,
        "plan": None,
    }
    if shop_id is not None:
        resolved = entitlements.resolve_shop_entitlements(db, _ShopStub(shop_id))
        payload["effective_status"] = resolved["status"]
        payload["in_grace"] = resolved["in_grace"]
        payload["entitlements"] = resolved["entitlements"]
    return payload


class _ShopStub:
    """Minimal shop-like object for entitlement resolution by id."""

    def __init__(self, shop_id: int):
        self.id = shop_id


def serialize_subscription(subscription: Subscription) -> dict:
    plan = subscription.plan
    status = subscription.status
    return {
        "subscription": {
            "id": subscription.id,
            "user_id": subscription.user_id,
            "shop_id": subscription.shop_id,
            "plan_id": subscription.plan_id,
            "status": status.value if hasattr(status, "value") else str(status),
            "is_auto_renew": bool(subscription.is_auto_renew),
            "cancel_at_period_end": bool(subscription.cancel_at_period_end),
            "current_period_start": _iso(subscription.current_period_start),
            "current_period_end": _iso(subscription.current_period_end),
        },
        "status": entitlements.effective_status(subscription),
        "plan": serialize_plan(plan) if plan else None,
    }


def _iso(dt: Optional[datetime]) -> Optional[str]:
    return _aware(dt).isoformat() if dt else None


# ── Payments ─────────────────────────────────────────────────────────────────
def initiate_payment(
    db: Session,
    subscription: Subscription,
    payment_method: str,
    provider_code: str = "MOCK",
    billing_cycle: Optional[str] = None,
) -> dict:
    """Create a provider order + PENDING payment row for a subscription.

    The amount is computed from the plan price for the requested cycle —
    never accepted from the client.
    """
    if payment_method not in {"CARD", "UPI", "NETBANKING", "WALLET"}:
        raise ValidationError(f"Unsupported payment method '{payment_method}'")
    cycle = _cycle_of(subscription, billing_cycle)
    plan = subscription.plan

    amount = plan.price_annual if cycle == BillingCycle.ANNUAL else plan.price_monthly
    if amount is None or float(amount) <= 0:
        raise ValidationError("Plan has no payable price configured")

    try:
        provider = get_provider(provider_code)
    except LookupError as exc:
        raise ValidationError(str(exc)) from exc

    payment = Payment(
        subscription_id=subscription.id,
        payment_provider=provider.code,
        status=PAYMENT_PENDING,
        amount=float(amount),
        currency=plan.currency or "INR",
        payment_method=payment_method,
        billing_cycle=cycle.value,
        payment_metadata={"subscription_plan": plan.name},
    )
    db.add(payment)
    db.flush()

    intent = provider.create_order(
        order_ref=f"PAY-{payment.id}",
        amount=float(amount),
        currency=payment.currency,
        payment_method=payment_method,
        notes={"subscription_id": subscription.id, "plan": plan.name},
    )
    payment.provider_order_id = intent.provider_order_id
    payment.payment_metadata = {**(payment.payment_metadata or {}), **intent.checkout_payload}
    db.flush()
    logger.info(
        "Payment initiated: id=%s sub=%s order=%s amount=%s",
        payment.id, subscription.id, intent.provider_order_id, amount,
    )
    return {
        "payment_id": payment.id,
        "provider": provider.code,
        "provider_order_id": intent.provider_order_id,
        "amount": float(amount),
        "currency": payment.currency,
        "checkout_payload": intent.checkout_payload,
    }


def verify_payment(
    db: Session,
    payment_id: int,
    provider_payment_id: str,
    provider_signature: str,
) -> dict:
    """Verify a checkout callback SERVER-SIDE before granting entitlements.

    The client's claim of success carries no weight here: the provider
    adapter validates the HMAC signature of ``(order_id, payment_id)`` and
    may still report a gateway decline.
    """
    payment = _get_payment(db, payment_id)
    if payment.status == PAYMENT_SUCCESS:
        return serialize_payment(payment)  # already applied — idempotent
    if payment.status != PAYMENT_PENDING:
        raise ConflictError(f"Payment is {payment.status} and cannot be verified")

    provider = get_provider(payment.payment_provider)
    result = provider.verify_payment(
        payment.provider_order_id, provider_payment_id, provider_signature
    )
    if result.verified:
        _apply_successful_payment(db, payment, provider_payment_id=result.provider_payment_id)
    else:
        payment.status = PAYMENT_FAILED
        payment.failure_reason = result.reason or "VERIFICATION_FAILED"
        db.flush()
        logger.warning("Payment failed verification: id=%s reason=%s", payment.id, result.reason)
    return serialize_payment(payment)


def handle_webhook(
    db: Session,
    provider_code: str,
    body: bytes,
    signature: Optional[str],
) -> dict:
    """Process a signed provider webhook delivery — exactly once.

    Flow: adapter authenticates the raw body → event recorded in the
    ``payment_events`` ledger keyed by ``(provider, event_id)`` → state change
    applied only when the event was newly seen. Duplicate deliveries are
    acknowledged with ``duplicate=True`` without re-applying anything.
    """
    provider = get_provider(provider_code)
    event = provider.parse_webhook(body, signature)

    event_id = str(event["event_id"])
    duplicate = (
        db.query(PaymentEvent)
        .filter(PaymentEvent.provider == provider.code, PaymentEvent.event_id == event_id)
        .first()
        is not None
    )
    if duplicate:
        logger.info("Duplicate webhook ignored: provider=%s event=%s", provider.code, event_id)
        return {"duplicate": True, "event_id": event_id}

    ledger_entry = PaymentEvent(
        provider=provider.code,
        event_id=event_id,
        event_type=event.get("event_type"),
        payload=event.get("data") or {},
        received_at=_utcnow(),
    )
    db.add(ledger_entry)

    data = event.get("data") or {}
    payment = (
        db.query(Payment).filter(Payment.provider_order_id == data.get("provider_order_id")).first()
    )
    if payment is None:
        db.flush()
        return {"duplicate": False, "event_id": event_id, "matched": False}

    ledger_entry.payment_id = payment.id
    status = (data.get("status") or "").upper()
    if status == PAYMENT_SUCCESS and payment.status != PAYMENT_SUCCESS:
        _apply_successful_payment(db, payment, provider_payment_id=data.get("provider_payment_id"))
    elif status == PAYMENT_FAILED and payment.status == PAYMENT_PENDING:
        payment.status = PAYMENT_FAILED
        payment.failure_reason = data.get("reason") or "GATEWAY_REPORTED_FAILURE"
        db.flush()
    db.flush()
    return {"duplicate": False, "event_id": event_id, "matched": True}


def _apply_successful_payment(
    db: Session,
    payment: Payment,
    provider_payment_id: Optional[str] = None,
) -> None:
    """Single funnel for every success path (verify + webhook)."""
    now = _utcnow()
    payment.status = PAYMENT_SUCCESS
    payment.paid_at = now
    payment.transaction_id = provider_payment_id or payment.transaction_id
    if not payment.invoice_number:
        payment.invoice_number = f"INV-{now.year}-{payment.id:06d}"

    subscription = payment.subscription
    already_active = (
        subscription.status == SubscriptionStatus.ACTIVE
        and _aware(subscription.current_period_end) is not None
        and _aware(subscription.current_period_end) > now
    )
    if already_active:
        extend_subscription(db, subscription, billing_cycle=payment.billing_cycle)
    else:
        activate_subscription(db, subscription, start=now, billing_cycle=payment.billing_cycle)
    logger.info(
        "Payment succeeded: id=%s invoice=%s sub=%s",
        payment.id, payment.invoice_number, subscription.id,
    )


def refund_payment(
    db: Session,
    payment_id: int,
    reason: Optional[str] = None,
) -> dict:
    """Full refund via the provider where supported.

    Refunding a paid period revokes the subscription immediately — the shop
    falls back to free-tier entitlements.
    """
    payment = _get_payment(db, payment_id)
    if payment.status != PAYMENT_SUCCESS:
        raise ValidationError(f"Only successful payments can be refunded (status={payment.status})")
    provider = get_provider(payment.payment_provider)
    if not provider.supports_refund:
        raise ValidationError(f"Provider '{provider.code}' does not support refunds")

    result = provider.refund(payment.transaction_id, float(payment.amount), reason)
    payment.status = PAYMENT_REFUNDED
    payment.refunded_at = _utcnow()
    payment.refund_id = result.get("refund_id")
    db.flush()

    subscription = payment.subscription
    subscription.status = SubscriptionStatus.CANCELED
    subscription.current_period_end = _utcnow()
    db.flush()
    logger.info("Payment refunded: id=%s refund=%s", payment.id, payment.refund_id)
    return serialize_payment(payment)


def payment_history(
    db: Session,
    subscription_id: Optional[int] = None,
    limit: int = 50,
    offset: int = 0,
) -> dict:
    """Payment history for a subscription (newest first)."""
    query = db.query(Payment)
    if subscription_id is not None:
        query = query.filter(Payment.subscription_id == subscription_id)
    total = query.count()
    rows = query.order_by(Payment.id.desc()).offset(offset).limit(limit).all()
    return {"items": [serialize_payment(p) for p in rows], "total": total, "limit": limit, "offset": offset}


def get_payment(db: Session, payment_id: int, user: User) -> Payment:
    """Load a payment owned by *user* (or any admin)."""
    payment = _get_payment(db, payment_id)
    role_name = getattr(user.role, "name", None)
    if payment.subscription.user_id != user.id and role_name != "admin":
        raise NotFoundError("Payment not found")
    return payment


def list_providers_public() -> list[dict]:
    return list_providers()


def _get_payment(db: Session, payment_id: int) -> Payment:
    payment = db.query(Payment).filter(Payment.id == payment_id).first()
    if payment is None:
        raise NotFoundError("Payment not found")
    return payment


def serialize_payment(payment: Payment) -> dict:
    return {
        "id": payment.id,
        "subscription_id": payment.subscription_id,
        "provider": payment.payment_provider,
        "provider_order_id": payment.provider_order_id,
        "transaction_id": payment.transaction_id,
        "amount": float(payment.amount),
        "currency": payment.currency,
        "status": payment.status,
        "payment_method": payment.payment_method,
        "billing_cycle": payment.billing_cycle,
        "invoice_number": payment.invoice_number,
        "refund_id": payment.refund_id,
        "paid_at": _iso(payment.paid_at),
        "refunded_at": _iso(payment.refunded_at),
        "failure_reason": payment.failure_reason,
    }





