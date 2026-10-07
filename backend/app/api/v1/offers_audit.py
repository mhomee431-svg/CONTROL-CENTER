"""Offers, audit trail and admin notes."""

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy import func, or_, select
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.core.pagination import Pagination, pagination
from app.core.responses import ok, paged
from app.core.serializers import to_dict
from app.core.security import get_current_admin, require_capability
from app.models import AdminNote, AdminUser, AuditLog, Offer

router = APIRouter(prefix="/admin", tags=["offers-audit"])

OFFER_FIELDS = [
    "id", "shop_id", "title", "discount_type", "discount_value", "status",
    "starts_at", "ends_at", "valid_from", "valid_until", "created_at",
]


# --- Offers ----------------------------------------------------------------


@router.get("/offers")
def list_offers(
    page: Pagination = Depends(pagination),
    shop_id: int | None = None,
    status: str | None = None,
    db: Session = Depends(get_db),
    _: AdminUser = Depends(get_current_admin),
):
    stmt = select(Offer)
    if shop_id is not None:
        stmt = stmt.where(Offer.shop_id == shop_id)
    if status:
        stmt = stmt.where(Offer.status == status)
    if page.search:
        like = f"%{page.search}%"
        stmt = stmt.where(or_(Offer.title.ilike(like), Offer.discount_type.ilike(like)))
    total = db.scalar(select(func.count()).select_from(stmt.subquery())) or 0
    start, end = page.window()
    rows = db.scalars(stmt.order_by(Offer.id.desc()).offset(start).limit(end - start)).all()
    items = []
    for r in rows:
        row = to_dict(r, OFFER_FIELDS)
        row["shop_name"] = r.shop.name if r.shop else None
        items.append(row)
    return ok(paged(items, total))


class OfferStatusUpdate(BaseModel):
    status: str


@router.patch("/offers/{offer_id}/status")
def update_offer_status(
    offer_id: int,
    payload: OfferStatusUpdate,
    db: Session = Depends(get_db),
    admin: AdminUser = Depends(require_capability("offers.update")),
):
    offer = db.get(Offer, offer_id)
    if offer is None:
        raise HTTPException(status_code=404, detail=f"Offer {offer_id} not found")
    offer.status = payload.status
    db.add(
        AuditLog(
            action="offer.status_changed",
            entity_type="offer",
            entity_id=offer_id,
            user_id=admin.id,
            admin_user=admin.name or admin.username,
            details={"status": payload.status},
        )
    )
    db.commit()
    return ok(to_dict(offer, OFFER_FIELDS), message="Offer status updated")


# --- Audit trail (the business History tab) --------------------------------


@router.get("/audit-logs")
def list_audit_logs(
    page: Pagination = Depends(pagination),
    entity_type: str | None = None,
    entity_id: int | None = None,
    action: str | None = None,
    db: Session = Depends(get_db),
    _: AdminUser = Depends(get_current_admin),
):
    """Append-only trail.

    The business drill-down filters this by `entity_type=shop&entity_id=<id>`,
    which is what makes the History tab meaningful.
    """
    stmt = select(AuditLog)
    if entity_type:
        stmt = stmt.where(AuditLog.entity_type == entity_type)
    if entity_id is not None:
        stmt = stmt.where(AuditLog.entity_id == entity_id)
    if action:
        stmt = stmt.where(AuditLog.action == action)
    if page.search:
        like = f"%{page.search}%"
        stmt = stmt.where(or_(AuditLog.action.ilike(like), AuditLog.admin_user.ilike(like)))
    total = db.scalar(select(func.count()).select_from(stmt.subquery())) or 0
    start, end = page.window()
    rows = db.scalars(
        stmt.order_by(AuditLog.created_at.desc(), AuditLog.id.desc()).offset(start).limit(end - start)
    ).all()
    fields = [
        "id", "action", "entity_type", "entity_id", "user_id",
        "admin_user", "ip_address", "details", "created_at",
    ]
    return ok(paged([to_dict(r, fields) for r in rows], total))


@router.get("/actions")
def list_actions(db: Session = Depends(get_db), _: AdminUser = Depends(get_current_admin)):
    """Distinct action names, for the audit filter dropdown."""
    rows = db.execute(select(AuditLog.action).distinct().order_by(AuditLog.action)).scalars().all()
    return ok({"items": list(rows)})


# --- Admin notes -----------------------------------------------------------


class NoteCreate(BaseModel):
    entity_type: str
    entity_id: int
    note: str


@router.get("/notes")
def list_notes(
    page: Pagination = Depends(pagination),
    entity_type: str | None = None,
    entity_id: int | None = None,
    db: Session = Depends(get_db),
    _: AdminUser = Depends(get_current_admin),
):
    stmt = select(AdminNote)
    if entity_type:
        stmt = stmt.where(AdminNote.entity_type == entity_type)
    if entity_id is not None:
        stmt = stmt.where(AdminNote.entity_id == entity_id)
    total = db.scalar(select(func.count()).select_from(stmt.subquery())) or 0
    start, end = page.window()
    rows = db.scalars(stmt.order_by(AdminNote.id.desc()).offset(start).limit(end - start)).all()
    fields = ["id", "entity_type", "entity_id", "note", "author", "created_at"]
    return ok(paged([to_dict(r, fields) for r in rows], total))


@router.post("/notes")
def create_note(
    payload: NoteCreate,
    db: Session = Depends(get_db),
    admin: AdminUser = Depends(get_current_admin),
):
    note = AdminNote(
        entity_type=payload.entity_type,
        entity_id=payload.entity_id,
        note=payload.note,
        author=admin.name or admin.username,
    )
    db.add(note)
    db.commit()
    db.refresh(note)
    fields = ["id", "entity_type", "entity_id", "note", "author", "created_at"]
    return ok(to_dict(note, fields), message="Note added")
