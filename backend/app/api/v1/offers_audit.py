"""Offers, audit trail and admin notes."""

from datetime import date, datetime, time, timezone

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel
from sqlalchemy import String, func, or_, select
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


# Result values a caller may filter on. The stored `details` blob reports the
# outcome under several keys ("result", "status", "outcome"); this maps the
# operator-facing filter value to every key it might appear under so the filter
# is truthful regardless of which writer produced the row.
_AUDIT_RESULT_KEYS = ("result", "outcome", "status", "state")

# Severity values the console offers. Only critical/destructive actions are
# escalated; everything else is informational.
_AUDIT_SEVERITY_RANK = {
    "INFO": 0,
    "NOTICE": 1,
    "WARNING": 2,
    "CRITICAL": 3,
}

# Action-name fragments that mark a destructive / high-impact event. Used to
# derive severity when the backend never stored one explicitly.
_HIGH_IMPACT_ACTION_MARKERS = (
    "delete",
    "archive",
    "suspend",
    "reject",
    "ban",
    "revoke",
    "purge",
    "wipe",
    "reset",
    "deactivate",
    "disable",
)


def derive_severity(action: str, details: dict | None) -> str:
    """Resolve the severity of an audit event.

    Prefers an explicit `severity` on the stored details; otherwise derives it
    from the action name so a destructive event is never silently reported as
    informational. `CRITICAL` is reserved for hard deletion and revocation.
    """
    if details:
        explicit = details.get("severity")
        if isinstance(explicit, str) and explicit.strip():
            return explicit.strip().upper()
    lowered = (action or "").lower()
    if any(marker in lowered for marker in ("delete", "purge", "wipe", "revoke", "reset")):
        return "CRITICAL"
    if any(marker in lowered for marker in _HIGH_IMPACT_ACTION_MARKERS):
        return "WARNING"
    return "INFO"


def derive_result(details: dict | None) -> str:
    """Resolve the outcome reported inside the stored details blob.

    Returns "SUCCESS" when the writer recorded no explicit failure, because an
    audit row is only ever written for an action the server carried out.
    """
    if details:
        for key in _AUDIT_RESULT_KEYS:
            value = details.get(key)
            if isinstance(value, str) and value.strip():
                return value.strip().upper()
    return "SUCCESS"


def _parse_day(value: str, *, end_of_day: bool) -> datetime:
    """Parse a `YYYY-MM-DD` (or full ISO) date bound into a UTC datetime."""
    try:
        parsed = date.fromisoformat(value) if len(value) == 10 else datetime.fromisoformat(value).date()
    except ValueError:
        raise HTTPException(status_code=422, detail=f"Invalid date filter: {value}")
    boundary = time.max if end_of_day else time.min
    return datetime.combine(parsed, boundary, tzinfo=timezone.utc)


@router.get("/audit-logs")
def list_audit_logs(
    page: Pagination = Depends(pagination),
    entity_type: str | None = None,
    entity_id: int | None = None,
    action: str | None = None,
    status: str | None = Query(None, description="Outcome filter: SUCCESS | FAILED | PARTIAL"),
    severity: str | None = Query(None, description="Severity filter: INFO | WARNING | CRITICAL"),
    date_from: str | None = Query(None, description="Inclusive lower bound (YYYY-MM-DD)"),
    date_to: str | None = Query(None, description="Inclusive upper bound (YYYY-MM-DD)"),
    db: Session = Depends(get_db),
    _: AdminUser = Depends(get_current_admin),
):
    """Append-only trail.

    The business drill-down filters this by `entity_type=shop&entity_id=<id>`,
    which is what makes the History tab meaningful. The Audit Log Center adds
    the operator-facing filters named in the spec: admin action, entity type,
    date range, status and severity — plus a free-text search that also matches
    a bare entity id, so an operator can paste `42` and find every event on
    record 42 across entity types.

    Outcome and severity live inside the `details` JSON blob rather than in
    dedicated columns, so those two filters are applied in Python after the
    database has already narrowed the set by the indexed columns. The date,
    entity and action filters stay in SQL so paging and totals remain correct.
    """
    stmt = select(AuditLog)
    if entity_type:
        stmt = stmt.where(AuditLog.entity_type == entity_type)
    if entity_id is not None:
        stmt = stmt.where(AuditLog.entity_id == entity_id)
    if action:
        stmt = stmt.where(AuditLog.action == action)
    if date_from:
        stmt = stmt.where(AuditLog.created_at >= _parse_day(date_from, end_of_day=False))
    if date_to:
        stmt = stmt.where(AuditLog.created_at <= _parse_day(date_to, end_of_day=True))
    if page.search:
        like = f"%{page.search}%"
        clauses = [
            AuditLog.action.ilike(like),
            AuditLog.admin_user.ilike(like),
            AuditLog.entity_type.ilike(like),
            AuditLog.entity_id.cast(String).ilike(like),
            AuditLog.ip_address.ilike(like),
        ]
        stmt = stmt.where(or_(*clauses))

    rows = db.scalars(
        stmt.order_by(AuditLog.created_at.desc(), AuditLog.id.desc())
    ).all()

    # Post-filter the JSON-backed fields so "severity" and "status" can be
    # filtered without a schema migration, then page the surviving rows.
    if severity:
        wanted = severity.strip().upper()
        rows = [r for r in rows if derive_severity(r.action, r.details) == wanted]
    if status:
        wanted = status.strip().upper()
        rows = [r for r in rows if derive_result(r.details) == wanted]

    total = len(rows)
    start, end = page.window()
    window = rows[start:end]
    fields = [
        "id", "action", "entity_type", "entity_id", "user_id",
        "admin_user", "ip_address", "details", "created_at",
    ]
    items = []
    for r in window:
        row = to_dict(r, fields)
        # The derived values are first-class on the payload so the console does
        # not have to re-derive them, and so a filter and a badge can never
        # disagree about what the row says.
        row["result"] = derive_result(r.details)
        row["severity"] = derive_severity(r.action, r.details)
        details = r.details or {}
        for key in ("reason", "justification", "request_id", "correlation_id", "before", "after"):
            if key in details:
                row[key] = details[key]
        items.append(row)
    return ok(paged(items, total))


@router.get("/actions")
def list_actions(db: Session = Depends(get_db), _: AdminUser = Depends(get_current_admin)):
    """Distinct action names, for the audit filter dropdown."""
    rows = db.execute(select(AuditLog.action).distinct().order_by(AuditLog.action)).scalars().all()
    return ok({"items": list(rows)})


@router.get("/audit-logs/{log_id}")
def audit_log_detail(
    log_id: int, db: Session = Depends(get_db), _: AdminUser = Depends(get_current_admin)
):
    """One audit entry, with its derived result/severity and full details."""
    log = db.get(AuditLog, log_id)
    if log is None:
        raise HTTPException(status_code=404, detail=f"Audit log {log_id} not found")
    fields = [
        "id", "action", "entity_type", "entity_id", "user_id",
        "admin_user", "ip_address", "details", "created_at",
    ]
    row = to_dict(log, fields)
    row["result"] = derive_result(log.details)
    row["severity"] = derive_severity(log.action, log.details)
    details = log.details or {}
    for key in ("reason", "justification", "request_id", "correlation_id", "before", "after"):
        if key in details:
            row[key] = details[key]
    return ok(row)


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


class NoteUpdate(BaseModel):
    note: str | None = None
    entity_type: str | None = None
    entity_id: int | None = None


@router.patch("/notes/{note_id}")
def update_note(
    note_id: int,
    payload: NoteUpdate,
    db: Session = Depends(get_db),
    admin: AdminUser = Depends(require_capability("settings.manage")),
):
    """Edit an administrative note. Only supplied fields are written."""
    note = db.get(AdminNote, note_id)
    if note is None:
        raise HTTPException(status_code=404, detail=f"Note {note_id} not found")
    if payload.note is not None:
        note.note = payload.note
    if payload.entity_type is not None:
        note.entity_type = payload.entity_type
    if payload.entity_id is not None:
        note.entity_id = payload.entity_id
    db.add(
        AuditLog(
            action="note.updated",
            entity_type="note",
            entity_id=note_id,
            user_id=admin.id,
            admin_user=admin.name or admin.username,
            details={"note_id": note_id},
        )
    )
    db.commit()
    db.refresh(note)
    fields = ["id", "entity_type", "entity_id", "note", "author", "created_at"]
    return ok(to_dict(note, fields), message="Note updated")


@router.delete("/notes/{note_id}")
def delete_note(
    note_id: int,
    db: Session = Depends(get_db),
    admin: AdminUser = Depends(require_capability("settings.manage")),
):
    """Remove an administrative note. Deletion is audited."""
    note = db.get(AdminNote, note_id)
    if note is None:
        raise HTTPException(status_code=404, detail=f"Note {note_id} not found")
    db.delete(note)
    db.add(
        AuditLog(
            action="note.deleted",
            entity_type="note",
            entity_id=note_id,
            user_id=admin.id,
            admin_user=admin.name or admin.username,
            details={"note_id": note_id},
        )
    )
    db.commit()
    return ok({"deleted": note_id}, message="Note deleted")
