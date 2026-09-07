"""Phase 28 — Shopkeeper subscription & payment routes.

All endpoints are shopkeeper-scoped: subscriptions are created/managed by the
owning user (admins bypass). The webhook endpoint is the one deliberately
UNAUTHENTICATED route — it is authenticated by HMAC signature via the
provider adapter instead.
"""

from fastapi import APIRouter, Depends, Header, Query, Request
from sqlalchemy.orm import Session

from app.core.dependencies import get_current_user
from app.core.exceptions import AppError, ForbiddenError, NotFoundError
from app.core.responses import error_response, success_response
from app.database.session import get_db
from app.models.subscription import Subscription
from app.models.user import User
from app.schemas.subscription import (
    CancelSubscriptionRequest,
    PaymentInitiateRequest,
    PaymentVerifyRequest,
    RefundRequest,
    RenewRequest,
    SubscribeRequest,
)
from app.services import subscription_service

router = APIRouter(prefix="/shopkeeper/subscription", tags=["shopkeeper-subscription"])


def _assert_owner(subscription_user_id: int, current_user: User) -> None:
    role_name = getattr(current_user.role, "name", None)
    if subscription_user_id != current_user.id and role_name != "admin":
        raise ForbiddenError("You do not own this subscription")


def _owned_subscription(db: Session, subscription_id: int, current_user: User) -> Subscription:
    subscription = db.query(Subscription).filter(Subscription.id == subscription_id).first()
    if subscription is None:
        raise NotFoundError("Subscription not found")
    _assert_owner(subscription.user_id, current_user)
    return subscription


# ── Plans ────────────────────────────────────────────────────────────────────
@router.get("/plans")
async def list_available_plans(db: Session = Depends(get_db)):
    """Plan catalogue with resolved entitlements."""
    plans = subscription_service.list_plans(db)
    return success_response(data={"plans": plans, "count": len(plans)}, message="OK")


@router.get("/providers")
async def list_payment_providers():
    """Registered payment providers (abstraction registry view)."""
    return success_response(data={"providers": subscription_service.list_providers_public()})


# ── Subscription lifecycle ───────────────────────────────────────────────────
@router.get("/current")
async def get_current_subscription(
    shop_id: int | None = Query(None),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Current subscription + effective entitlements for a shop."""
    try:
        if shop_id is not None:
            from app.services import shopkeeper_service

            shopkeeper_service.resolve_shop_access(db, current_user, shop_id)
        payload = subscription_service.get_current_subscription(db, current_user, shop_id)
    except AppError as exc:
        return error_response(message=exc.message, error_code=exc.error_code, status_code=exc.status_code)
    return success_response(data=payload, message="OK")


@router.post("/subscribe")
async def subscribe_to_plan(
    payload: SubscribeRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Create an INCOMPLETE subscription (activation follows verified payment)."""
    try:
        subscription = subscription_service.create_subscription(
            db, user=current_user, plan_id=payload.plan_id,
            shop_id=payload.shop_id, billing_cycle=payload.billing_cycle,
        )
    except AppError as exc:
        return error_response(message=exc.message, error_code=exc.error_code, status_code=exc.status_code)
    db.commit()
    return success_response(
        data=subscription_service.serialize_subscription(subscription),
        message="Subscription created — complete payment to activate",
        status_code=201,
    )


@router.post("/cancel")
async def cancel_my_subscription(
    payload: CancelSubscriptionRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Cancel at period end (default) or immediately."""
    try:
        subscription = _owned_subscription(db, payload.subscription_id, current_user)
        updated = subscription_service.cancel_subscription(db, subscription, immediate=payload.immediate)
    except AppError as exc:
        return error_response(message=exc.message, error_code=exc.error_code, status_code=exc.status_code)
    db.commit()
    return success_response(
        data=subscription_service.serialize_subscription(updated), message="Subscription canceled"
    )


@router.post("/renew")
async def renew_subscription(
    payload: RenewRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Initiate a renewal payment; the period extends once it is verified."""
    try:
        subscription = _owned_subscription(db, payload.subscription_id, current_user)
        intent = subscription_service.initiate_payment(
            db, subscription, payload.payment_method,
            provider_code=payload.provider_code, billing_cycle=payload.billing_cycle,
        )
    except AppError as exc:
        return error_response(message=exc.message, error_code=exc.error_code, status_code=exc.status_code)
    db.commit()
    return success_response(data=intent, message="Renewal payment initiated")


# ── Payments ─────────────────────────────────────────────────────────────────
@router.post("/payments/initiate")
async def initiate_payment(
    payload: PaymentInitiateRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Create a provider order for a subscription's next payment."""
    try:
        subscription = _owned_subscription(db, payload.subscription_id, current_user)
        intent = subscription_service.initiate_payment(
            db, subscription, payload.payment_method,
            provider_code=payload.provider_code, billing_cycle=payload.billing_cycle,
        )
    except AppError as exc:
        return error_response(message=exc.message, error_code=exc.error_code, status_code=exc.status_code)
    db.commit()
    return success_response(data=intent, message="Payment initiated", status_code=201)


@router.post("/payments/verify")
async def verify_payment(
    payload: PaymentVerifyRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Server-side verification of a checkout callback (signature checked here)."""
    try:
        payment = subscription_service.get_payment(db, payload.payment_id, current_user)
        result = subscription_service.verify_payment(
            db, payment.id, payload.provider_payment_id, payload.provider_signature
        )
    except AppError as exc:
        return error_response(message=exc.message, error_code=exc.error_code, status_code=exc.status_code)
    db.commit()
    message = "Payment verified" if result["status"] == "SUCCESS" else "Payment failed"
    return success_response(data=result, message=message)


@router.get("/payments/history")
async def payment_history(
    subscription_id: int = Query(..., gt=0),
    limit: int = Query(50, ge=1, le=200),
    offset: int = Query(0, ge=0),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Invoice/receipt history for a subscription."""
    try:
        _owned_subscription(db, subscription_id, current_user)
        history = subscription_service.payment_history(db, subscription_id, limit=limit, offset=offset)
    except AppError as exc:
        return error_response(message=exc.message, error_code=exc.error_code, status_code=exc.status_code)
    return success_response(data=history)


@router.post("/payments/{payment_id}/refund")
async def refund_payment(
    payment_id: int,
    payload: RefundRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Refund a successful payment where the provider supports it."""
    try:
        subscription_service.get_payment(db, payment_id, current_user)
        result = subscription_service.refund_payment(db, payment_id, reason=payload.reason)
    except AppError as exc:
        return error_response(message=exc.message, error_code=exc.error_code, status_code=exc.status_code)
    db.commit()
    return success_response(data=result, message="Payment refunded")


# ── Webhooks ─────────────────────────────────────────────────────────────────
@router.post("/webhooks/{provider_code}")
async def payment_webhook(
    provider_code: str,
    request: Request,
    x_payment_signature: str | None = Header(None),
    db: Session = Depends(get_db),
):
    """Provider webhook receiver (HMAC-authenticated, idempotent).

    Deliberately unauthenticated at the app layer — authenticity comes from
    the provider signature over the raw body; duplicates are ignored.
    """
    body = await request.body()
    try:
        result = subscription_service.handle_webhook(db, provider_code, body, x_payment_signature)
    except AppError as exc:
        return error_response(message=exc.message, error_code=exc.error_code, status_code=exc.status_code)
    db.commit()
    # Always 200 so providers stop retrying; duplicates are flagged in-body.
    return success_response(data=result, message="Webhook processed")

