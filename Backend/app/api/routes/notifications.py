from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from app.core.dependencies import get_current_user
from app.core.responses import error_response, success_response
from app.database.session import get_db
from app.models.notification import Notification
from app.models.user import User

router = APIRouter(prefix="/notifications", tags=["notifications"])


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
