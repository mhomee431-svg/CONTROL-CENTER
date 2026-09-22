"""Shopkeeper supplementary routes: documents, hours, holidays, notifications.

Fills the remaining gaps in the shopkeeper management surface so owners can
run their entire business from the app.
"""

from datetime import date as ddate, time as dtime
import json

from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session

from app.core.dependencies import get_current_user
from app.core.responses import error_response, success_response
from app.database.session import get_db
from app.models.notification import Notification
from app.models.shop import ShopDocument, ShopHoliday, ShopHour
from app.models.user import User
from app.services import shopkeeper_service

router = APIRouter(prefix="/shopkeeper", tags=["shopkeeper-management"])


def _resolve(shop_id: int, current_user: User, db: Session):
    return shopkeeper_service.resolve_shop_access(db, current_user, shop_id)


# ── Documents ────────────────────────────────────────────────────────────────
@router.get("/shops/{shop_id}/documents")
async def list_documents(
    shop_id: int,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """List all verification documents for a shop."""
    access = _resolve(shop_id, current_user, db)
    access.require("documents", "read")
    docs = (
        db.query(ShopDocument)
        .filter(ShopDocument.shop_id == shop_id, ShopDocument.is_deleted == False)  # noqa: E712
        .order_by(ShopDocument.created_at.desc())
        .all()
    )
    return success_response(data={"documents": [
        {
            "id": d.id,
            "document_type": d.document_type,
            "document_number": d.document_number,
            "document_url": d.document_url,
            "expires_at": d.expires_at.isoformat() if d.expires_at else None,
            "is_verified": d.is_verified,
            "verified_at": d.verified_at.isoformat() if d.verified_at else None,
            "rejection_reason": d.rejection_reason,
            "created_at": d.created_at.isoformat(),
        }
        for d in docs
    ], "count": len(docs)})


@router.post("/shops/{shop_id}/documents", status_code=201)
async def upload_document(
    shop_id: int,
    document_type: str = Query(..., max_length=50),
    document_number: str | None = Query(None, max_length=100),
    document_url: str = Query(..., max_length=500),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Upload a verification document reference for a shop."""
    access = _resolve(shop_id, current_user, db)
    access.require("documents", "create")
    doc = ShopDocument(
        shop_id=shop_id,
        document_type=document_type,
        document_number=document_number,
        document_url=document_url,
    )
    db.add(doc)
    db.commit()
    db.refresh(doc)
    return success_response(
        data={"id": doc.id, "document_type": doc.document_type, "is_verified": doc.is_verified},
        message="Document uploaded",
        status_code=201,
    )


@router.delete("/shops/{shop_id}/documents/{document_id}")
async def delete_document(
    shop_id: int,
    document_id: int,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Soft-delete a document."""
    access = _resolve(shop_id, current_user, db)
    access.require("documents", "delete")
    doc = (
        db.query(ShopDocument)
        .filter(ShopDocument.id == document_id, ShopDocument.shop_id == shop_id)
        .first()
    )
    if not doc:
        return error_response(message="Document not found", error_code="NOT_FOUND", status_code=404)
    doc.is_deleted = True
    db.commit()
    return success_response(message="Document deleted")
# -- Hours ---------------------------------------------------------------------
@router.get("/shops/{shop_id}/hours")
async def get_hours(
    shop_id: int,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Get business hours for all days of the week."""
    access = _resolve(shop_id, current_user, db)
    access.require("shop", "read")
    hours = (
        db.query(ShopHour)
        .filter(ShopHour.shop_id == shop_id)
        .order_by(ShopHour.day_of_week)
        .all()
    )
    return success_response(data={"hours": [
        {
            "id": h.id,
            "day_of_week": h.day_of_week,
            "open_time": str(h.open_time) if h.open_time else None,
            "close_time": str(h.close_time) if h.close_time else None,
            "is_closed": h.is_closed,
        }
        for h in hours
    ]})


@router.put("/shops/{shop_id}/hours")
async def update_hours(
    shop_id: int,
    hours: list[dict],
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Update business hours. Accepts a list of {day_of_week, open_time, close_time, is_closed}."""
    access = _resolve(shop_id, current_user, db)
    access.require("shop", "update")
    updated = []
    for entry in hours:
        day = entry.get("day_of_week")
        if day is None or not (0 <= day <= 6):
            continue
        existing = (
            db.query(ShopHour)
            .filter(ShopHour.shop_id == shop_id, ShopHour.day_of_week == day)
            .first()
        )
        is_closed = entry.get("is_closed", False)
        open_time = None
        close_time = None
        if not is_closed:
            try:
                ot = entry.get("open_time", "09:00")
                ct = entry.get("close_time", "21:00")
                open_time = dtime.fromisoformat(ot) if isinstance(ot, str) else ot
                close_time = dtime.fromisoformat(ct) if isinstance(ct, str) else ct
            except (ValueError, TypeError):
                return error_response(
                    message=f"Invalid time format for day {day}. Use HH:MM",
                    error_code="INVALID_TIME",
                    status_code=400,
                )
        if existing:
            existing.open_time = open_time
            existing.close_time = close_time
            existing.is_closed = is_closed
        else:
            db.add(ShopHour(
                shop_id=shop_id,
                day_of_week=day,
                open_time=open_time,
                close_time=close_time,
                is_closed=is_closed,
            ))
        updated.append(day)
    db.commit()
    return success_response(message=f"Updated hours for {len(updated)} days", data={"updated_days": updated})

# -- Holidays ------------------------------------------------------------------
@router.get("/shops/{shop_id}/holidays")
async def get_holidays(
    shop_id: int,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Get scheduled holidays for a shop."""
    access = _resolve(shop_id, current_user, db)
    access.require("shop", "read")
    holidays = (
        db.query(ShopHoliday)
        .filter(ShopHoliday.shop_id == shop_id)
        .order_by(ShopHoliday.holiday_date)
        .all()
    )
    return success_response(data={"holidays": [
        {
            "id": h.id,
            "holiday_date": str(h.holiday_date),
            "reason": h.reason,
            "is_recurring_yearly": h.is_recurring_yearly,
        }
        for h in holidays
    ]})


@router.post("/shops/{shop_id}/holidays", status_code=201)
async def add_holiday(
    shop_id: int,
    holiday_date: str = Query(...),
    reason: str | None = Query(None, max_length=255),
    is_recurring_yearly: bool = Query(False),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Add a holiday for a shop."""
    access = _resolve(shop_id, current_user, db)
    access.require("shop", "update")
    try:
        hdate = ddate.fromisoformat(holiday_date)
    except ValueError:
        return error_response(message="Invalid date format. Use YYYY-MM-DD", error_code="INVALID_DATE", status_code=400)
    holiday = ShopHoliday(
        shop_id=shop_id,
        holiday_date=hdate,
        reason=reason,
        is_recurring_yearly=is_recurring_yearly,
    )
    db.add(holiday)
    db.commit()
    db.refresh(holiday)
    return success_response(
        data={"id": holiday.id, "holiday_date": str(holiday.holiday_date)},
        message="Holiday added",
        status_code=201,
    )


@router.delete("/shops/{shop_id}/holidays/{holiday_id}")
async def delete_holiday(
    shop_id: int,
    holiday_id: int,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Delete a holiday."""
    access = _resolve(shop_id, current_user, db)
    access.require("shop", "update")
    holiday = (
        db.query(ShopHoliday)
        .filter(ShopHoliday.id == holiday_id, ShopHoliday.shop_id == shop_id)
        .first()
    )
    if not holiday:
        return error_response(message="Holiday not found", error_code="NOT_FOUND", status_code=404)
    db.delete(holiday)
    db.commit()
    return success_response(message="Holiday deleted")

# -- Shop-level notifications -------------------------------------------------
@router.get("/shops/{shop_id}/notifications")
async def get_shop_notifications(
    shop_id: int,
    unread_only: bool = Query(False),
    limit: int = Query(20, ge=1, le=100),
    offset: int = Query(0, ge=0),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Get notifications relevant to this shop owners/managers.

    Paginated (``limit`` / ``offset``) like every other list this app reads:
    the response carries ``total`` so the client can tell whether another page
    exists instead of guessing from a short page.

    ``unread`` is counted across the WHOLE shop-scoped set, not just the
    returned page — a page-scoped count would make the badge shrink as the
    shopkeeper pages deeper, and a page with no unread rows would report zero
    even while earlier pages were still unread.
    """
    access = _resolve(shop_id, current_user, db)
    access.require("notifications", "read")
    shop = access.shop
    user_ids = [shop.created_by] if shop.created_by else []
    for owner in shop.owners:
        if owner.user_id and owner.user_id not in user_ids:
            user_ids.append(owner.user_id)
    for manager in shop.managers:
        if manager.user_id and manager.user_id not in user_ids:
            user_ids.append(manager.user_id)
    if not user_ids:
        return success_response(
            data={"notifications": [], "count": 0, "total": 0, "unread": 0}
        )
    base = db.query(Notification).filter(Notification.user_id.in_(user_ids))
    if unread_only:
        base = base.filter(Notification.is_read == False)  # noqa: E712
    total = base.count()
    # Badge count: every unread notification in scope, independent of the page.
    unread = (
        db.query(Notification)
        .filter(
            Notification.user_id.in_(user_ids),
            Notification.is_read == False,  # noqa: E712
        )
        .count()
    )
    notifications = (
        base.order_by(Notification.created_at.desc())
        .offset(offset)
        .limit(limit)
        .all()
    )
    return success_response(data={
        "notifications": [
            {
                "id": n.id,
                "title": n.title,
                "body": n.body,
                "type": n.type,
                "is_read": n.is_read,
                "created_at": n.created_at.isoformat(),
                # The app routes a tap from these: without the deep link the
                # client can only fall back to the notification type, and
                # without the payload it can never validate an id before
                # navigating on it.
                "deep_link": n.deep_link,
                "payload": json.loads(n.payload) if n.payload else None,
            }
            for n in notifications
        ],
        "count": len(notifications),
        "total": total,
        "unread": unread,
    })


@router.put("/notifications/{notification_id}/read")
async def mark_notification_read(
    notification_id: int,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Mark a notification as read."""
    notif = db.get(Notification, notification_id)
    if not notif or notif.user_id != current_user.id:
        return error_response(message="Notification not found", error_code="NOT_FOUND", status_code=404)
    notif.is_read = True
    db.commit()
    return success_response(message="Marked as read")


@router.put("/notifications/read-all")
async def mark_all_notifications_read(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Mark every notification owned by the current user as read."""
    db.query(Notification).filter(Notification.user_id == current_user.id).update(
        {"is_read": True}, synchronize_session=False
    )
    db.commit()
    return success_response(message="All notifications marked as read")
