"""Notification service — Phase 27.

Complete notification architecture for customers, shopkeepers and admins:

* Typed notifications (price drop, product available, inventory update,
  offer, shop verification, subscription, payment, POS sync, system).
* Preference gating — marketing-ish types are dropped entirely when the user
  opted out; transactional types are always created but push delivery still
  honours the master ``push_enabled`` switch.
* Anti-spam — per-user/per-type dedupe keys with a cooldown window plus an
  hourly cap on non-transactional notifications.
* Delivery engine — one :class:`NotificationDelivery` row per device token,
  provider calls via the swappable push abstraction, invalid-token handling,
  retry with attempt caps, and delivery-status tracking wherever the provider
  reports it.
"""

import json
import logging
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone

from sqlalchemy import func
from sqlalchemy.orm import Session

from app.core.config import settings
from app.models.notification import DeviceToken, Notification, NotificationDelivery, NotificationPreference
from app.models.user import User
from app.services.push_service import PushMessage, get_push_service

logger = logging.getLogger("app.services.notification")


# ── Types & audiences ────────────────────────────────────────────────────────
class NotificationType:
    PRICE_DROP = "PRICE_DROP"
    PRODUCT_AVAILABLE = "PRODUCT_AVAILABLE"
    INVENTORY_UPDATE = "INVENTORY_UPDATE"
    OFFER = "OFFER"
    SHOP_VERIFICATION = "SHOP_VERIFICATION"
    SUBSCRIPTION = "SUBSCRIPTION"
    PAYMENT = "PAYMENT"
    POS_SYNC = "POS_SYNC"
    SYSTEM = "SYSTEM"

    # ── Shopkeeper-facing operational categories ─────────────────────────────
    # These complete the merchant category taxonomy (Products, Pricing,
    # Imports, Offers, Account, Support) alongside the types above. They are
    # transactional: an operator receipt must never be silently dropped by a
    # marketing opt-out.
    PRODUCT = "PRODUCT"
    PRICING = "PRICING"
    IMPORT = "IMPORT"
    SHOP_OFFER = "SHOP_OFFER"
    ACCOUNT = "ACCOUNT"
    SUPPORT = "SUPPORT"


class Audience:
    CUSTOMER = "customer"
    SHOPKEEPER = "shopkeeper"
    ADMIN = "admin"


# Notification type → (audience, preference field, transactional)
_TYPE_REGISTRY: dict[str, tuple[str, str | None, bool]] = {
    NotificationType.PRICE_DROP: (Audience.CUSTOMER, "price_alerts", False),
    NotificationType.PRODUCT_AVAILABLE: (Audience.CUSTOMER, "availability_alerts", False),
    NotificationType.INVENTORY_UPDATE: (Audience.SHOPKEEPER, None, True),
    NotificationType.OFFER: (Audience.CUSTOMER, "deal_alerts", False),
    NotificationType.SHOP_VERIFICATION: (Audience.SHOPKEEPER, None, True),
    NotificationType.SUBSCRIPTION: (Audience.CUSTOMER, None, True),
    NotificationType.PAYMENT: (Audience.CUSTOMER, None, True),
    NotificationType.POS_SYNC: (Audience.SHOPKEEPER, None, True),
    # System messages are service-critical (never gated / throttled)
    NotificationType.SYSTEM: (Audience.ADMIN, None, True),
    # Shopkeeper operational categories — receipts, never marketing.
    NotificationType.PRODUCT: (Audience.SHOPKEEPER, None, True),
    NotificationType.PRICING: (Audience.SHOPKEEPER, None, True),
    NotificationType.IMPORT: (Audience.SHOPKEEPER, None, True),
    NotificationType.SHOP_OFFER: (Audience.SHOPKEEPER, None, True),
    NotificationType.ACCOUNT: (Audience.SHOPKEEPER, None, True),
    NotificationType.SUPPORT: (Audience.SHOPKEEPER, None, True),
}

DELIVERY_STATUS_PENDING = "PENDING"
DELIVERY_STATUS_SENT = "SENT"
DELIVERY_STATUS_PARTIAL = "PARTIAL"
DELIVERY_STATUS_FAILED = "FAILED"
DELIVERY_STATUS_SKIPPED = "SKIPPED"


def _utcnow() -> datetime:
    # Naive UTC keeps parity with TimestampMixin defaults and SQLite storage.
    return datetime.now(timezone.utc).replace(tzinfo=None)


def _get_preferences(db: Session, user_id: int) -> NotificationPreference:
    prefs = db.query(NotificationPreference).filter(NotificationPreference.user_id == user_id).first()
    if prefs is None:
        prefs = NotificationPreference(user_id=user_id)
        db.add(prefs)
        db.flush()
    return prefs


def _pref_allows_creation(ntype: str, prefs: NotificationPreference) -> bool:
    """Marketing-style types vanish entirely when opted out."""
    _, pref_field, transactional = _TYPE_REGISTRY.get(ntype, (Audience.CUSTOMER, None, False))
    if transactional or pref_field is None:
        return True
    return bool(getattr(prefs, pref_field, True))


def _within_hourly_cap(db: Session, user_id: int, ntype: str) -> bool:
    _, _, transactional = _TYPE_REGISTRY.get(ntype, (Audience.CUSTOMER, None, False))
    if transactional:
        return True  # receipts/verifications must never be throttled away
    since = _utcnow() - timedelta(hours=1)
    recent = (
        db.query(func.count(Notification.id))
        .filter(
            Notification.user_id == user_id,
            Notification.created_at >= since,
        )
        .scalar() or 0
    )
    return recent < settings.NOTIFICATION_HOURLY_CAP


def _is_duplicated(db: Session, user_id: int, dedupe_key: str) -> bool:
    """Same dedupe key inside the cooldown window → suppress (anti-spam)."""
    cooldown = settings.NOTIFICATION_DEDUPE_COOLDOWN_SECONDS
    if cooldown <= 0 or not dedupe_key:
        return False
    since = _utcnow() - timedelta(seconds=cooldown)
    existing = (
        db.query(Notification.id)
        .filter(
            Notification.user_id == user_id,
            Notification.dedupe_key == dedupe_key,
            Notification.created_at >= since,
        )
        .first()
    )
    return existing is not None


# ── Creation ────────────────────────────────────────────────────────────────
@dataclass
class CreateResult:
    created: bool
    reason: str | None  # None when created; 'preference_opt_out' | 'duplicate' | 'rate_limited' otherwise
    notification: Notification | None


def create_notification(
    db: Session,
    *,
    user_id: int,
    notification_type: str,
    title: str,
    body: str,
    deep_link: str | None = None,
    payload: dict | None = None,
    dedupe_key: str | None = None,
    audience: str | None = None,
    enqueue: bool = True,
) -> CreateResult:
    """Create a notification after preference + anti-spam checks.

    Returns a :class:`CreateResult`; ``created`` is False (with a reason) when
    the user opted out, the event is a duplicate, or the hourly cap kicked in.
    When created, dispatch is queued through Celery unless ``enqueue=False``.
    """
    registry_entry = _TYPE_REGISTRY.get(notification_type)
    resolved_audience = audience or (registry_entry[0] if registry_entry else Audience.CUSTOMER)
    user = db.query(User).filter(User.id == user_id).first()
    if (
        user is None
        or not getattr(user, "is_active", True)
        or bool(getattr(user, "is_deleted", False))
    ):
        return CreateResult(False, "user_inactive_or_missing", None)

    prefs = _get_preferences(db, user_id)
    if not _pref_allows_creation(notification_type, prefs):
        logger.info("notification suppressed (opt-out) user=%s type=%s", user_id, notification_type)
        return CreateResult(False, "preference_opt_out", None)

    if dedupe_key and _is_duplicated(db, user_id, dedupe_key):
        logger.info("notification suppressed (duplicate) user=%s dedupe=%s", user_id, dedupe_key)
        return CreateResult(False, "duplicate", None)

    if not _within_hourly_cap(db, user_id, notification_type):
        logger.info("notification suppressed (rate cap) user=%s type=%s", user_id, notification_type)
        return CreateResult(False, "rate_limited", None)

    notification = Notification(
        user_id=user_id,
        title=title[:255],
        body=body,
        type=notification_type,
        audience=resolved_audience,
        deep_link=deep_link[:500] if deep_link else None,
        dedupe_key=dedupe_key[:255] if dedupe_key else None,
        payload=json.dumps(payload) if payload else None,
        delivery_status=DELIVERY_STATUS_PENDING,
    )
    db.add(notification)
    db.flush()

    if enqueue:
        # Import lazily so callers without a broker can run synchronously.
        try:
            from app.services.notification_tasks import deliver_notification_task

            deliver_notification_task.delay(notification.id)
        except Exception as exc:  # noqa: BLE001 — broker issues must never break host flows
            logger.warning(
                "Could not enqueue delivery for notification %s (%s); "
                "it stays PENDING until the retry sweep picks it up",
                notification.id,
                exc,
            )
    return CreateResult(True, None, notification)


def register_device_token(
    db: Session,
    *,
    user_id: int,
    token: str,
    device_type: str = "android",
    platform: str | None = None,
    app_version: str | None = None,
) -> DeviceToken:
    """Idempotent token registration — re-owns on account switch, reacts on re-login."""
    device_token = db.query(DeviceToken).filter(DeviceToken.token == token).first()
    now = _utcnow()
    if device_token is None:
        device_token = DeviceToken(
            user_id=user_id,
            token=token,
            device_type=device_type,
            platform=platform,
            app_version=app_version,
        )
        db.add(device_token)
    else:
        device_token.user_id = user_id
        device_token.device_type = device_type
        device_token.platform = platform
        device_token.app_version = app_version
        device_token.is_active = True
        device_token.failure_count = 0
    device_token.last_used_at = now
    db.flush()
    return device_token


# ── Delivery engine ─────────────────────────────────────────────────────────
def deliver_notification(db: Session, notification_id: int) -> dict:
    """Push a pending notification to every active device of its owner.

    Creates/updates per-token :class:`NotificationDelivery` rows, deactivates
    permanently-invalid tokens, aggregates status onto the notification, and
    returns an outcome summary used by both the Celery task and retry sweeps.
    """
    notification = db.query(Notification).filter(Notification.id == notification_id).first()
    if notification is None:
        return {"status": "NOT_FOUND"}

    user_tokens = (
        db.query(DeviceToken)
        .filter(DeviceToken.user_id == notification.user_id, DeviceToken.is_active == True)  # noqa: E712
        .all()
    )
    prefs = _get_preferences(db, notification.user_id)

    if not user_tokens:
        notification.delivery_status = DELIVERY_STATUS_SKIPPED
        notification.last_error = "no active device tokens"
        notification.sent_at = notification.sent_at or _utcnow()
        db.flush()
        return {"status": DELIVERY_STATUS_SKIPPED, "delivered": 0, "failed": 0, "skipped": len(user_tokens)}

    if not prefs.push_enabled:
        # In-app copy exists, but the user silenced push.
        for t in user_tokens:
            _upsert_delivery(db, notification.id, t.id, status=DELIVERY_STATUS_SKIPPED, error="push disabled by user")
        notification.delivery_status = DELIVERY_STATUS_SKIPPED
        notification.last_error = "push disabled by user preferences"
        notification.sent_at = notification.sent_at or _utcnow()
        db.flush()
        return {"status": DELIVERY_STATUS_SKIPPED, "delivered": 0, "failed": 0, "skipped": len(user_tokens)}

    provider = get_push_service()
    payload_data = json.loads(notification.payload) if notification.payload else {}

    delivered = failed = skipped = permanent_failures = 0
    last_provider_id: str | None = None
    last_error: str | None = None

    for token_row in user_tokens:
        existing = (
            db.query(NotificationDelivery)
            .filter(
                NotificationDelivery.notification_id == notification.id,
                NotificationDelivery.device_token_id == token_row.id,
            )
            .first()
        )
        if existing is not None and existing.status == DELIVERY_STATUS_SENT:
            delivered += 1  # idempotent re-run
            continue
        if existing is not None and existing.permanent_failure:
            skipped += 1
            continue
        if existing is not None and existing.attempts >= settings.NOTIFICATION_MAX_DELIVERY_ATTEMPTS:
            skipped += 1
            continue

        result = provider.send(
            PushMessage(
                token=token_row.token,
                title=notification.title,
                body=notification.body,
                deep_link=notification.deep_link,
                data={
                    "notification_id": str(notification.id),
                    "type": notification.type,
                    **payload_data,
                },
            )
        )

        if existing is None:
            existing = NotificationDelivery(
                notification_id=notification.id,
                device_token_id=token_row.id,
                status=DELIVERY_STATUS_PENDING,
                attempts=0,
            )
            db.add(existing)

        existing.attempts = (existing.attempts or 0) + 1
        existing.attempted_at = _utcnow()

        if result.delivered:
            existing.status = DELIVERY_STATUS_SENT
            existing.provider_message_id = result.provider_message_id
            existing.error = None
            existing.permanent_failure = False
            existing.delivered_at = _utcnow()
            token_row.failure_count = 0
            token_row.last_used_at = _utcnow()
            delivered += 1
            last_provider_id = result.provider_message_id
        else:
            existing.status = DELIVERY_STATUS_FAILED
            existing.error = result.error
            existing.permanent_failure = result.permanent_failure
            last_error = result.error
            token_row.failure_count = (token_row.failure_count or 0) + 1
            if result.permanent_failure:
                # Invalid/unregistered token — stop targeting it forever.
                token_row.is_active = False
                permanent_failures += 1
            else:
                failed += 1

    notification.delivery_attempts = (notification.delivery_attempts or 0) + 1
    notification.last_attempt_at = _utcnow()
    notification.provider_message_id = last_provider_id or notification.provider_message_id

    if delivered and (failed or permanent_failures):
        notification.delivery_status = DELIVERY_STATUS_PARTIAL
    elif delivered:
        notification.delivery_status = DELIVERY_STATUS_SENT
    elif failed or permanent_failures:
        notification.delivery_status = DELIVERY_STATUS_FAILED
    else:
        notification.delivery_status = DELIVERY_STATUS_SKIPPED
    notification.last_error = last_error
    if delivered:
        notification.sent_at = notification.sent_at or _utcnow()

    db.flush()
    return {
        "status": notification.delivery_status,
        "delivered": delivered,
        "failed": failed,
        "skipped": skipped,
    }


def _upsert_delivery(
    db: Session, notification_id: int, token_id: int, *, status: str, error: str | None = None
) -> NotificationDelivery:
    delivery = (
        db.query(NotificationDelivery)
        .filter(
            NotificationDelivery.notification_id == notification_id,
            NotificationDelivery.device_token_id == token_id,
        )
        .first()
    )
    if delivery is None:
        delivery = NotificationDelivery(notification_id=notification_id, device_token_id=token_id)
        db.add(delivery)
    delivery.status = status
    delivery.error = error
    delivery.attempted_at = _utcnow()
    db.flush()
    return delivery


def retry_failed_notifications(db: Session, limit: int = 100) -> dict:
    """Sweep FAILED/PENDING notifications whose devices may accept another try."""
    candidates = (
        db.query(Notification)
        .filter(
            Notification.delivery_status.in_([DELIVERY_STATUS_FAILED, DELIVERY_STATUS_PENDING]),
            Notification.delivery_attempts < settings.NOTIFICATION_MAX_DELIVERY_ATTEMPTS,
        )
        .order_by(Notification.created_at.asc())
        .limit(limit)
        .all()
    )
    results = []
    for notification in candidates:
        results.append({"notification_id": notification.id, **deliver_notification(db, notification.id)})
    return {"retried": len(results), "results": results}


def get_delivery_status(db: Session, notification_id: int, user_id: int) -> dict | None:
    """Full per-device delivery history for one notification (owner-scoped)."""
    notification = (
        db.query(Notification)
        .filter(Notification.id == notification_id, Notification.user_id == user_id)
        .first()
    )
    if notification is None:
        return None
    deliveries = (
        db.query(NotificationDelivery)
        .filter(NotificationDelivery.notification_id == notification_id)
        .all()
    )
    return {
        "notification_id": notification.id,
        "type": notification.type,
        "delivery_status": notification.delivery_status,
        "delivery_attempts": notification.delivery_attempts,
        "provider_message_id": notification.provider_message_id,
        "last_error": notification.last_error,
        "deep_link": notification.deep_link,
        "deliveries": [
            {
                "device_token_id": d.device_token_id,
                "status": d.status,
                "attempts": d.attempts,
                "provider_message_id": d.provider_message_id,
                "error": d.error,
                "permanent_failure": d.permanent_failure,
                "attempted_at": d.attempted_at,
                "delivered_at": d.delivered_at,
            }
            for d in deliveries
        ],
    }


# ── Business-event entry points ─────────────────────────────────────────────
# These are the hooks other backend services call when a business event fires.
# Each fans out to the correct audience with sensible deep links + dedupe keys.

def notify_price_drop(db: Session, *, product_master_id: int, shop_name: str,
                      old_price: float, new_price: float) -> list[int]:
    """Fan out to every customer who saved this product (deduped per user)."""
    from app.models.saved_product import SavedProduct

    savers = db.query(SavedProduct.user_id).filter(SavedProduct.product_master_id == product_master_id).all()
    created_ids: list[int] = []
    for (user_id,) in savers:
        result = create_notification(
            db,
            user_id=user_id,
            notification_type=NotificationType.PRICE_DROP,
            title=f"Price drop at {shop_name}",
            body=f"Price fell from ₹{old_price:.0f} to ₹{new_price:.0f}",
            deep_link=f"hyperlocal://product/{product_master_id}",
            payload={"product_master_id": product_master_id, "old_price": old_price, "new_price": new_price},
            dedupe_key=f"price-drop:{product_master_id}:{user_id}",
        )
        if result.created and result.notification:
            created_ids.append(result.notification.id)
    return created_ids


def notify_product_available(db: Session, *, product_master_id: int, shop_name: str) -> list[int]:
    """Back-in-stock fan-out to customers who saved the product."""
    from app.models.saved_product import SavedProduct

    savers = db.query(SavedProduct.user_id).filter(SavedProduct.product_master_id == product_master_id).all()
    created_ids: list[int] = []
    for (user_id,) in savers:
        result = create_notification(
            db,
            user_id=user_id,
            notification_type=NotificationType.PRODUCT_AVAILABLE,
            title="Now available",
            body=f"{shop_name} just stocked an item on your list",
            deep_link=f"hyperlocal://product/{product_master_id}",
            payload={"product_master_id": product_master_id},
            dedupe_key=f"available:{product_master_id}:{user_id}",
        )
        if result.created and result.notification:
            created_ids.append(result.notification.id)
    return created_ids


def notify_inventory_update(db: Session, *, shopkeeper_user_id: int | None,
                            shop_product_id: int,
                            message: str) -> CreateResult:
    if shopkeeper_user_id is None:
        return _no_recipient()
    return create_notification(
        db,
        user_id=shopkeeper_user_id,
        notification_type=NotificationType.INVENTORY_UPDATE,
        title="Inventory updated",
        body=message,
        deep_link=f"hyperlocal://shopkeeper/inventory/{shop_product_id}",
        payload={"shop_product_id": shop_product_id},
        dedupe_key=f"inventory:{shop_product_id}",
        audience=Audience.SHOPKEEPER,
    )


def notify_offer(db: Session, *, user_id: int, offer_id: int, title: str, body: str) -> CreateResult:
    return create_notification(
        db,
        user_id=user_id,
        notification_type=NotificationType.OFFER,
        title=title,
        body=body,
        deep_link=f"hyperlocal://offers/{offer_id}",
        payload={"offer_id": offer_id},
        dedupe_key=f"offer:{offer_id}:{user_id}",
    )


def notify_shop_verification(db: Session, *, shopkeeper_user_id: int, shop_id: int,
                             decision: str, reason: str | None = None) -> CreateResult:
    approved = decision.upper() in ("VERIFY", "APPROVED", "VERIFIED")
    return create_notification(
        db,
        user_id=shopkeeper_user_id,
        notification_type=NotificationType.SHOP_VERIFICATION,
        title="Shop verified" if approved else f"Shop {decision.lower()}",
        body=(
            "Congratulations! Your shop is now live."
            if approved
            else reason or f"Your shop verification was {decision.lower()}."
        ),
        deep_link=f"hyperlocal://shopkeeper/shop/{shop_id}",
        payload={"shop_id": shop_id, "decision": decision},
        dedupe_key=f"shop-verify:{shop_id}:{decision}",
        audience=Audience.SHOPKEEPER,
    )


def notify_subscription_event(db: Session, *, user_id: int, subscription_id: int,
                              event: str, message: str) -> CreateResult:
    return create_notification(
        db,
        user_id=user_id,
        notification_type=NotificationType.SUBSCRIPTION,
        title=f"Subscription {event}",
        body=message,
        deep_link=f"hyperlocal://subscription/{subscription_id}",
        payload={"subscription_id": subscription_id, "event": event},
        dedupe_key=f"subscription:{subscription_id}:{event}",
    )


def notify_payment_event(db: Session, *, user_id: int, payment_id: int,
                         status: str, amount: float) -> CreateResult:
    return create_notification(
        db,
        user_id=user_id,
        notification_type=NotificationType.PAYMENT,
        title=f"Payment {status.lower()}",
        body=f"₹{amount:.2f} — receipt available in your history",
        deep_link=f"hyperlocal://payments/{payment_id}",
        payload={"payment_id": payment_id, "status": status, "amount": amount},
        dedupe_key=f"payment:{payment_id}:{status}",
    )


def notify_pos_sync_event(db: Session, *, shopkeeper_user_id: int, integration_id: int,
                          job_id: int, ok: bool, detail: str = "") -> CreateResult:
    return create_notification(
        db,
        user_id=shopkeeper_user_id,
        notification_type=NotificationType.POS_SYNC,
        title="POS sync finished" if ok else "POS sync failed",
        body=detail or ("All products synced." if ok else "We'll retry automatically."),
        deep_link=f"hyperlocal://shopkeeper/pos/{integration_id}",
        payload={"integration_id": integration_id, "job_id": job_id, "ok": ok},
        dedupe_key=f"pos-sync:{job_id}:{'ok' if ok else 'fail'}",
        audience=Audience.SHOPKEEPER,
    )


def broadcast_system_notification(db: Session, *, title: str, body: str,
                                  role_name: str | None = None) -> list[int]:
    """Admin/system broadcast to active users (optionally one role)."""
    query = db.query(User).filter(User.is_active == True, User.is_deleted == False)  # noqa: E712
    if role_name is not None:
        from app.models.role import Role

        role = db.query(Role).filter(Role.name == role_name).first()
        query = query.filter(User.role_id == role.id) if role else query.filter(False)
    created_ids: list[int] = []
    for user in query.all():
        result = create_notification(
            db,
            user_id=user.id,
            notification_type=NotificationType.SYSTEM,
            title=title,
            body=body,
            deep_link="hyperlocal://home",
            payload={"broadcast": True},
            audience=Audience.ADMIN,
            enqueue=False,  # caller dispatches the delivery sweep once for the batch
        )
        if result.created and result.notification:
            created_ids.append(result.notification.id)
    return created_ids



# ── Shopkeeper category entry points ─────────────────────────────────────────
# One emitter per merchant category so every backend service reports the same
# way. Each takes ``shopkeeper_user_id`` and short-circuits when the recipient
# is unknown (a shop with no resolvable owner) instead of raising.

def _no_recipient() -> CreateResult:
    return CreateResult(False, "no_recipient", None)


def notify_shop_product_event(db: Session, *, shopkeeper_user_id: int | None,
                             shop_product_id: int, event: str,
                             product_name: str = "") -> CreateResult:
    """Product added / updated / removed / discontinued."""
    if shopkeeper_user_id is None:
        return _no_recipient()
    label = product_name.strip() or "Product"
    key = event.strip().upper()
    titles = {
        "ADDED": "Product added",
        "UPDATED": "Product updated",
        "REMOVED": "Product removed",
        "DISCONTINUED": "Product discontinued",
    }
    bodies = {
        "ADDED": f"{label} is now in your catalog.",
        "UPDATED": f"{label} was updated.",
        "REMOVED": f"{label} was removed from your shop.",
        "DISCONTINUED": f"{label} is no longer available in your shop.",
    }
    return create_notification(
        db,
        user_id=shopkeeper_user_id,
        notification_type=NotificationType.PRODUCT,
        title=titles.get(key, "Product updated"),
        body=bodies.get(key, f"{label} was updated."),
        deep_link=f"hyperlocal://shopkeeper/products/{shop_product_id}",
        payload={"shop_product_id": shop_product_id, "event": key},
        dedupe_key=f"product:{shop_product_id}:{key}",
        audience=Audience.SHOPKEEPER,
    )


def notify_price_change(db: Session, *, shopkeeper_user_id: int | None,
                        shop_product_id: int, old_price: float, new_price: float,
                        product_name: str = "") -> CreateResult:
    """Price (or MRP) changed on a shop listing."""
    if shopkeeper_user_id is None:
        return _no_recipient()
    label = product_name.strip() or "Product"
    return create_notification(
        db,
        user_id=shopkeeper_user_id,
        notification_type=NotificationType.PRICING,
        title="Price update successful",
        body=f"{label}: \u20b9{old_price:.2f} \u2192 \u20b9{new_price:.2f}",
        deep_link=f"hyperlocal://shopkeeper/products/{shop_product_id}",
        payload={
            "shop_product_id": shop_product_id,
            "old_price": old_price,
            "new_price": new_price,
        },
        dedupe_key=f"price:{shop_product_id}:{new_price:.2f}",
        audience=Audience.SHOPKEEPER,
    )
def notify_import_event(db: Session, *, shopkeeper_user_id: int | None, job_id: int,
                        status: str, filename: str | None = None,
                        processed_rows: int = 0, failed_rows: int = 0) -> CreateResult:
    """Excel/CSV import finished — completed, partial or failed."""
    if shopkeeper_user_id is None:
        return _no_recipient()
    key = status.strip().upper()
    name = (filename or "your file").strip()
    if key == "COMPLETED":
        title = "Import completed"
        body = f"{name}: {processed_rows} row(s) imported."
    elif key == "PARTIAL":
        title = "Import partially completed"
        body = (
            f"{name}: {processed_rows} row(s) imported, {failed_rows} failed. "
            "Open Import history to review the failures."
        )
    elif key == "FAILED":
        title = "Import failed"
        body = f"{name} could not be processed. Open Import history for details."
    else:
        title = "Import updated"
        body = f"{name}: status is now {key}."
    return create_notification(
        db,
        user_id=shopkeeper_user_id,
        notification_type=NotificationType.IMPORT,
        title=title,
        body=body,
        deep_link=f"hyperlocal://shopkeeper/imports/{job_id}",
        payload={
            "job_id": job_id,
            "status": key,
            "processed_rows": processed_rows,
            "failed_rows": failed_rows,
        },
        dedupe_key=f"import:{job_id}:{key}",
        audience=Audience.SHOPKEEPER,
    )


def notify_shop_offer_event(db: Session, *, shopkeeper_user_id: int | None,
                            offer_id: int, event: str,
                            offer_title: str = "") -> CreateResult:
    """Shop-owned offer went live / was paused / expired / cancelled."""
    if shopkeeper_user_id is None:
        return _no_recipient()
    label = offer_title.strip() or "Your offer"
    key = event.strip().upper()
    bodies = {
        "ACTIVE": f"{label} is now live for customers.",
        "SCHEDULED": f"{label} is scheduled.",
        "PAUSED": f"{label} was paused.",
        "DISABLED": f"{label} was disabled.",
        "CANCELLED": f"{label} was cancelled.",
        "EXPIRED": f"{label} has expired.",
        "DRAFT": f"{label} was moved back to draft.",
    }
    return create_notification(
        db,
        user_id=shopkeeper_user_id,
        notification_type=NotificationType.SHOP_OFFER,
        title="Offer updated",
        body=bodies.get(key, f"{label} is now {key.lower()}."),
        deep_link=f"hyperlocal://shopkeeper/offers/{offer_id}",
        payload={"offer_id": offer_id, "event": key},
        dedupe_key=f"offer:{offer_id}:{key}",
        audience=Audience.SHOPKEEPER,
    )
def notify_account_event(db: Session, *, shopkeeper_user_id: int | None,
                         event: str, message: str) -> CreateResult:
    """Account/shop settings, profile or access-state change."""
    if shopkeeper_user_id is None:
        return _no_recipient()
    key = event.strip().upper()
    status_change = "STATUS" in key or "SUSPEND" in key or "ACCESS" in key
    return create_notification(
        db,
        user_id=shopkeeper_user_id,
        notification_type=NotificationType.ACCOUNT,
        title="Account status changed" if status_change else "Account updated",
        body=message,
        deep_link="hyperlocal://shopkeeper/account",
        payload={"event": key},
        dedupe_key=f"account:{key}",
        audience=Audience.SHOPKEEPER,
    )


def notify_support_event(db: Session, *, shopkeeper_user_id: int | None, title: str,
                         message: str, ticket_id: int | None = None) -> CreateResult:
    """Support reply / resolution notice for a shopkeeper."""
    if shopkeeper_user_id is None:
        return _no_recipient()
    return create_notification(
        db,
        user_id=shopkeeper_user_id,
        notification_type=NotificationType.SUPPORT,
        title=title,
        body=message,
        deep_link=(
            f"hyperlocal://shopkeeper/support/{ticket_id}"
            if ticket_id is not None
            else "hyperlocal://shopkeeper/support"
        ),
        payload={"ticket_id": ticket_id} if ticket_id is not None else None,
        dedupe_key=f"support:{ticket_id or 'general'}",
        audience=Audience.SHOPKEEPER,
    )