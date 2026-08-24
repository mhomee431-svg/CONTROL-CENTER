from datetime import datetime, timezone

from fastapi import APIRouter, Depends
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session

from app.core.dependencies import get_current_user
from app.core.responses import error_response, success_response
from app.database.session import get_db
from app.models.notification import DeviceToken, Notification, NotificationPreference
from app.models.user import User

router = APIRouter(prefix="/notifications", tags=["notifications"])


class NotificationPreferencesPayload(BaseModel):
    """Per-customer delivery preferences (API_CONTRACT §21.4)."""

    push_enabled: bool = True
    email_enabled: bool = True
    sms_enabled: bool = False
    price_alerts: bool = True
    availability_alerts: bool = True
    promotional: bool = False
    deal_alerts: bool = True


class DeviceTokenPayload(BaseModel):
    """Push registration payload (API_CONTRACT §21.6)."""

    token: str = Field(..., min_length=1, max_length=500)
    device_type: str = Field("android", pattern="^(android|ios|web)$")
    platform: str | None = Field(None, description="FCM or APNS")
    app_version: str | None = Field(None, max_length=20)


@router.get("")
async def list_notifications(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Return all notifications for the current user."""
    notifications = (
        db.query(Notification)
        .filter(Notification.user_id == current_user.id)
        .order_by(Notification.created_at.desc())
        .all()
    )
    unread_count = sum(1 for n in notifications if not n.is_read)
    return success_response(
        data={
            "notifications": [
                {
                    "id": n.id,
                    "title": n.title,
                    "body": n.body,
                    "type": n.type,
                    "is_read": n.is_read,
                    "payload": n.payload,
                    "created_at": n.created_at,
                }
                for n in notifications
            ],
            "unread_count": unread_count,
        }
    )


@router.put("/{notification_id}/read")
async def mark_notification_read(
    notification_id: int,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Mark a single notification as read."""
    notification = (
        db.query(Notification)
        .filter(Notification.id == notification_id, Notification.user_id == current_user.id)
        .first()
    )
    if notification is None:
        return error_response(message="Notification not found", error_code="NOTIFICATION_NOT_FOUND", status_code=404)

    notification.is_read = True
    db.add(notification)
    db.commit()
    return success_response(data=None, message="Notification marked as read")


@router.put("/read-all")
async def mark_all_notifications_read(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Mark all notifications for the current user as read."""
    db.query(Notification).filter(Notification.user_id == current_user.id).update(
        {Notification.is_read: True}
    )
    db.commit()
    return success_response(data=None, message="All notifications marked as read")


# ── Preferences (API_CONTRACT §21.4/21.5) ──────────────────────────────────
def _get_or_create_preferences(db: Session, user_id: int) -> NotificationPreference:
    prefs = (
        db.query(NotificationPreference)
        .filter(NotificationPreference.user_id == user_id)
        .first()
    )
    if prefs is None:
        prefs = NotificationPreference(user_id=user_id)
        db.add(prefs)
        db.flush()
    return prefs


def _prefs_payload(prefs: NotificationPreference) -> dict:
    return {
        "push_enabled": prefs.push_enabled,
        "email_enabled": prefs.email_enabled,
        "sms_enabled": prefs.sms_enabled,
        "price_alerts": prefs.price_alerts,
        "availability_alerts": prefs.availability_alerts,
        "promotional": prefs.promotional,
        "deal_alerts": prefs.deal_alerts,
    }


@router.get("/preferences")
async def get_notification_preferences(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Return the current user's notification delivery preferences."""
    prefs = _get_or_create_preferences(db, current_user.id)
    db.commit()
    return success_response(data=_prefs_payload(prefs))


@router.put("/preferences")
async def update_notification_preferences(
    payload: NotificationPreferencesPayload,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Create or update the current user's notification delivery preferences."""
    prefs = _get_or_create_preferences(db, current_user.id)
    prefs.push_enabled = payload.push_enabled
    prefs.email_enabled = payload.email_enabled
    prefs.sms_enabled = payload.sms_enabled
    prefs.price_alerts = payload.price_alerts
    prefs.availability_alerts = payload.availability_alerts
    prefs.promotional = payload.promotional
    prefs.deal_alerts = payload.deal_alerts
    db.add(prefs)
    db.commit()
    return success_response(data=_prefs_payload(prefs), message="Preferences updated")


# ── Device push tokens (API_CONTRACT §21.6) ────────────────────────────────
@router.post("/device-token")
async def register_device_token(
    payload: DeviceTokenPayload,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Register (or reactivate) a push device token for the current user."""
    device_token = (
        db.query(DeviceToken).filter(DeviceToken.token == payload.token).first()
    )
    now = datetime.now(timezone.utc)
    if device_token is None:
        device_token = DeviceToken(
            user_id=current_user.id,
            token=payload.token,
            device_type=payload.device_type,
            platform=payload.platform,
            app_version=payload.app_version,
        )
        db.add(device_token)
    else:
        # Re-own the token if it moved accounts, and reactivate it.
        device_token.user_id = current_user.id
        device_token.device_type = payload.device_type
        device_token.platform = payload.platform
        device_token.app_version = payload.app_version
        device_token.is_active = True
        device_token.last_used_at = now
    db.commit()
    return success_response(data={"registered": True}, message="Device token registered")


@router.delete("/device-token/{token}")
async def unregister_device_token(
    token: str,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Deactivate a push device token (e.g. on logout)."""
    device_token = (
        db.query(DeviceToken)
        .filter(DeviceToken.token == token, DeviceToken.user_id == current_user.id)
        .first()
    )
    if device_token is None:
        return error_response(
            message="Device token not found",
            error_code="DEVICE_TOKEN_NOT_FOUND",
            status_code=404,
        )
    device_token.is_active = False
    device_token.last_used_at = datetime.now(timezone.utc)
    db.commit()
    return success_response(data={"unregistered": True}, message="Device token removed")
