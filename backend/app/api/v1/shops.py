"""Shops (businesses) — listing, detail, and every drill-down tab.

Each tab on the business detail page reads its own route. A route that is not
implemented here returns 404, which `fetchList` on the frontend reports as
"not published on this deployment" rather than as an empty list — so an
unimplemented tab is honest rather than silently blank.
"""

from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel, field_validator
from sqlalchemy import func, or_, select, String
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.core.pagination import Pagination, pagination
from app.core.responses import ok, paged
from app.core.security import get_current_admin, require_capability
from app.core.serializers import iso, serialise_shop, to_dict
from app.models import (
    AdminUser,
    AuditLog,
    Offer,
    Product,
    Shop,
    ShopDocument,
    ShopInventory,
    ShopPricing,
)

router = APIRouter(prefix="/admin/shops", tags=["shops"])

# The five stages of one verification workflow. "Approved" is the operator's
# word for the backend's VERIFIED, so both spellings are accepted on the way in
# and normalised to the stored value.
VERIFICATION_STAGES = (
    "PENDING",
    "UNDER_REVIEW",
    "VERIFIED",
    "REJECTED",
    "NEEDS_CORRECTION",
)

# Triage decisions the reviewer can record, mapped to the stored stage. The
# frontend posts the operator-facing verb; the backend owns the mapping so the
# two can never disagree about what "Request Correction" means.
DECISION_TO_STAGE = {
    "VERIFY": "VERIFIED",
    "APPROVE": "VERIFIED",
    "VERIFIED": "VERIFIED",
    "REJECT": "REJECTED",
    "REJECTED": "REJECTED",
    "REQUEST_CORRECTION": "NEEDS_CORRECTION",
    "NEEDS_CORRECTION": "NEEDS_CORRECTION",
    "ON_HOLD": "UNDER_REVIEW",
    "HOLD": "UNDER_REVIEW",
    "UNDER_REVIEW": "UNDER_REVIEW",
}

# Every triage ruling must say why: the merchant is told, and the Previous
# decisions table renders Admin + Time + Reason + Action for each entry.
# Approve included — "verified, no comment" is not an auditable decision.
REASON_REQUIRED = {"VERIFIED", "REJECTED", "NEEDS_CORRECTION", "UNDER_REVIEW"}


def _record_audit(
    db: Session, admin: AdminUser, action: str, entity_id: int, details: dict | None = None
) -> None:
    """Every mutation lands in the trail the History tab reads."""
    db.add(
        AuditLog(
            action=action,
            entity_type="shop",
            entity_id=entity_id,
            user_id=admin.id,
            admin_user=admin.name or admin.username,
            details=details or {},
        )
    )


def _get_shop_or_404(db: Session, shop_id: int) -> Shop:
    shop = db.get(Shop, shop_id)
    if shop is None:
        raise HTTPException(status_code=404, detail=f"Business {shop_id} not found")
    return shop


def _parse_bound(value: str, *, end_of_day: bool) -> datetime:
    """Parse an ISO date/datetime filter bound.

    A bare `YYYY-MM-DD` from a date input means the whole day, so the upper
    bound is pushed to 23:59:59 — otherwise "submitted up to today" would
    exclude everything submitted today. Full timestamps are respected as-is.
    """
    try:
        parsed = datetime.fromisoformat(value)
    except ValueError:
        raise HTTPException(status_code=422, detail=f"Invalid date filter: {value}")
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    if end_of_day and len(value) == 10:
        parsed = parsed.replace(hour=23, minute=59, second=59, microsecond=999999)
    return parsed


@router.get("")
def list_shops(
    page: Pagination = Depends(pagination),
    status_filter: str | None = Query(None, alias="status"),
    verification_status: str | None = Query(None),
    category: str | None = Query(None),
    city: str | None = Query(None),
    state: str | None = Query(None),
    reviewer: str | None = Query(None),
    created_from: str | None = Query(None),
    created_to: str | None = Query(None),
    business_type: str | None = Query(None),
    db: Session = Depends(get_db),
    _: AdminUser = Depends(get_current_admin),
):
    """Shop listing, and the single read behind the verification queue.

    Every filter the queue offers is honoured here rather than in the client:
    filtering after paging would show a page of 25 then hide nine of them, and
    the total would count rows the operator never asked for.
    """
    stmt = select(Shop)
    if page.search:
        like = f"%{page.search}%"
        stmt = stmt.where(
            or_(
                Shop.name.ilike(like),
                Shop.city.ilike(like),
                Shop.state.ilike(like),
                Shop.category.ilike(like),
                Shop.owner_id.cast(String).ilike(like),
            )
        )
    if status_filter:
        stmt = stmt.where(Shop.status == status_filter)
    if verification_status:
        stmt = stmt.where(Shop.verification_status == verification_status)
    if category:
        stmt = stmt.where(Shop.category == category)
    if city:
        stmt = stmt.where(Shop.city == city)
    if state:
        stmt = stmt.where(Shop.state == state)
    if business_type:
        stmt = stmt.where(Shop.business_type == business_type)
    # The reviewer filter matches the operator named on the last decision. An
    # unassigned case has no reviewer, so it is correctly absent from every
    # reviewer's results rather than silently appearing under all of them.
    if reviewer:
        stmt = stmt.where(Shop.verified_by == reviewer)
    if created_from:
        stmt = stmt.where(Shop.created_at >= _parse_bound(created_from, end_of_day=False))
    if created_to:
        stmt = stmt.where(Shop.created_at <= _parse_bound(created_to, end_of_day=True))

    total = db.scalar(select(func.count()).select_from(stmt.subquery())) or 0
    start, end = page.window()
    rows = db.scalars(stmt.order_by(Shop.id).offset(start).limit(end - start)).all()
    return ok(paged([serialise_shop(r) for r in rows], total))


@router.get("/bulk")
def bulk_preview(db: Session = Depends(get_db), _: AdminUser = Depends(get_current_admin)):
    """Actions the multi-shop governance surface supports.

    Declared before `/{shop_id}` so "bulk" is never parsed as an id.
    """
    return ok({"supported_actions": ["approve", "reject", "suspend", "reactivate", "archive"]})


class BulkShopDecision(BaseModel):
    """One audited VERIFY or SUSPEND applied to every selected shop."""

    shop_ids: list[int]
    decision: str
    reason: str | None = None

    @field_validator("decision")
    @classmethod
    def normalise_decision(cls, value: str) -> str:
        upper = (value or "").strip().upper()
        if upper not in ("VERIFY", "SUSPEND"):
            raise ValueError(f"Unknown bulk decision '{value}'. Expected VERIFY or SUSPEND.")
        return upper


@router.post("/bulk")
def bulk_decide_shops(
    payload: BulkShopDecision,
    db: Session = Depends(get_db),
    admin: AdminUser = Depends(require_capability("shops.verify")),
):
    """Apply one audited VERIFY or SUSPEND to every selected shop.

    VERIFY marks each shop VERIFIED and activates it; SUSPEND marks each shop
    SUSPENDED. The posted reason is mandatory and recorded on every audit row,
    exactly like the single-shop decision surface. Missing ids fail loudly so
    an operator never believes unselected or deleted shops were decided.
    """
    reason = (payload.reason or "").strip()
    if not payload.shop_ids:
        raise HTTPException(status_code=422, detail="Select at least one shop")
    if not reason:
        raise HTTPException(status_code=422, detail="A reason is required for a bulk shop decision")

    now = datetime.now(timezone.utc)
    admin_name = admin.name or admin.username
    updated = 0
    for shop_id in payload.shop_ids:
        shop = _get_shop_or_404(db, shop_id)
        previous = shop.verification_status
        if payload.decision == "VERIFY":
            shop.verification_status = "VERIFIED"
            shop.verified_at = now
            shop.verified_by = admin_name
            shop.rejection_reason = None
            if shop.status == "PENDING":
                shop.status = "ACTIVE"
            audit_action = "shop.verification.verified"
        else:
            shop.status = "SUSPENDED"
            audit_action = "shop.suspend"
        _record_audit(
            db,
            admin,
            audit_action,
            shop_id,
            {
                "from": previous,
                "to": shop.verification_status,
                "status": shop.status,
                "decision": payload.decision,
                "reason": reason,
            },
        )
        updated += 1
    db.commit()
    return ok({"updated": updated}, message=f"Bulk {payload.decision} applied to {updated} shops")


@router.get("/verification/summary")
def verification_summary(
    db: Session = Depends(get_db), _: AdminUser = Depends(get_current_admin)
):
    """Counts per verification stage, for the queue's tab badges.

    One grouped query rather than five list requests: the badges have to agree
    with the lists, and computing them from the same table is what guarantees
    that. Stages with no rows are reported as 0 rather than omitted, so the tab
    always has a number to render.

    Declared before `/{shop_id}` so "verification" is never parsed as an id.
    """
    rows = db.execute(
        select(Shop.verification_status, func.count()).group_by(Shop.verification_status)
    ).all()
    counts = {status: 0 for status in VERIFICATION_STAGES}
    for status, count in rows:
        counts[status or "PENDING"] = count
    counts["total"] = sum(counts[s] for s in VERIFICATION_STAGES)
    return ok({"counts": counts, "stages": list(VERIFICATION_STAGES)})


@router.get("/{shop_id}")
def shop_detail(
    shop_id: int, db: Session = Depends(get_db), _: AdminUser = Depends(get_current_admin)
):
    return ok(serialise_shop(_get_shop_or_404(db, shop_id)))


# --- Drill-down tabs -------------------------------------------------------


@router.get("/{shop_id}/documents")
def shop_documents(
    shop_id: int,
    page: Pagination = Depends(pagination),
    db: Session = Depends(get_db),
    _: AdminUser = Depends(get_current_admin),
):
    _get_shop_or_404(db, shop_id)
    stmt = select(ShopDocument).where(ShopDocument.shop_id == shop_id)
    if page.search:
        like = f"%{page.search}%"
        stmt = stmt.where(
            or_(ShopDocument.title.ilike(like), ShopDocument.file_name.ilike(like))
        )
    total = db.scalar(select(func.count()).select_from(stmt.subquery())) or 0
    start, end = page.window()
    rows = db.scalars(stmt.order_by(ShopDocument.id).offset(start).limit(end - start)).all()
    fields = [
        "id", "doc_type", "title", "file_name", "file_url",
        "status", "uploaded_at", "expires_at", "verified_at",
    ]
    return ok(paged([to_dict(r, fields) for r in rows], total))


@router.get("/{shop_id}/pricing")
def shop_pricing(
    shop_id: int,
    page: Pagination = Depends(pagination),
    db: Session = Depends(get_db),
    _: AdminUser = Depends(get_current_admin),
):
    _get_shop_or_404(db, shop_id)
    stmt = select(ShopPricing).where(ShopPricing.shop_id == shop_id)
    if page.search:
        like = f"%{page.search}%"
        stmt = stmt.where(
            or_(ShopPricing.product_name.ilike(like), ShopPricing.barcode.ilike(like))
        )
    total = db.scalar(select(func.count()).select_from(stmt.subquery())) or 0
    start, end = page.window()
    rows = db.scalars(stmt.order_by(ShopPricing.id).offset(start).limit(end - start)).all()
    fields = ["id", "product_name", "sku", "barcode", "price", "mrp", "currency", "updated_at"]
    return ok(paged([to_dict(r, fields) for r in rows], total))


@router.get("/{shop_id}/hours")
def shop_hours(shop_id: int, db: Session = Depends(get_db), _: AdminUser = Depends(get_current_admin)):
    shop = _get_shop_or_404(db, shop_id)
    return ok({"operating_hours": shop.operating_hours or {}})


class VerificationDecision(BaseModel):
    """One triage ruling.

    `decision` is the operator-facing verb the UI posts (VERIFY / REJECT /
    REQUEST_CORRECTION / ON_HOLD) or the stored stage itself; both are accepted
    and normalised through DECISION_TO_STAGE. The reason is optional at the
    schema level because Approve needs none, but it is enforced below for the
    decisions that must tell the merchant why.
    """

    decision: str
    reason: str | None = None

    @field_validator("decision")
    @classmethod
    def _known_decision(cls, value: str) -> str:
        if value.strip().upper() not in DECISION_TO_STAGE:
            raise ValueError(
                f"Unknown decision '{value}'. Expected one of: "
                + ", ".join(sorted(DECISION_TO_STAGE))
            )
        return value.strip().upper()


@router.get("/{shop_id}/verification")
def shop_verification(
    shop_id: int, db: Session = Depends(get_db), _: AdminUser = Depends(get_current_admin)
):
    shop = _get_shop_or_404(db, shop_id)
    return ok(
        {
            "verification_status": shop.verification_status,
            "verified_at": iso(shop.verified_at),
            "verified_by": shop.verified_by,
            "rejection_reason": shop.rejection_reason,
        }
    )


@router.post("/{shop_id}/verification")
def decide_verification(
    shop_id: int,
    payload: VerificationDecision,
    db: Session = Depends(get_db),
    admin: AdminUser = Depends(require_capability("shops.verify")),
):
    """Record a triage decision and log it.

    Every ruling — approve, reject, request correction, hold — lands on this one
    endpoint so the queue, the detail page and the History tab can never
    disagree about what was decided. The stored stage is the normalised value,
    and the operator's own verb plus the reason are kept in the audit trail the
    Decisions tab reads back.
    """
    shop = _get_shop_or_404(db, shop_id)
    stage = DECISION_TO_STAGE[payload.decision]
    reason = (payload.reason or "").strip() or None

    # A rejection or a correction request is only actionable if it says why.
    # Approve and Hold included: every row in Previous decisions renders
    # Admin + Time + Reason + Action.
    if stage in REASON_REQUIRED and not reason:
        raise HTTPException(
            status_code=422,
            detail=f"A reason is required to set a case to {stage}",
        )

    previous = shop.verification_status
    shop.verification_status = stage

    # One audit action per operator verb: a hold stays visible as a hold in the
    # Previous decisions table rather than dissolving into "under review".
    audit_action = (
        "shop.verification.hold"
        if payload.decision in ("ON_HOLD", "HOLD")
        else f"shop.verification.{stage.lower()}"
    )

    if stage == "VERIFIED":
        shop.verified_at = datetime.now(timezone.utc)
        shop.verified_by = admin.name or admin.username
        shop.rejection_reason = None
        # Approving a pending business also activates it.
        if shop.status == "PENDING":
            shop.status = "ACTIVE"
    elif stage in REASON_REQUIRED:
        # The merchant is shown this text, so it is the operator's, not a default.
        shop.rejection_reason = reason
    elif stage == "UNDER_REVIEW":
        # Held or picked up: the case is now owned by whoever touched it last.
        shop.verified_by = admin.name or admin.username
        shop.verified_at = datetime.now(timezone.utc)

    _record_audit(
        db,
        admin,
        audit_action,
        shop_id,
        {
            "from": previous,
            "to": stage,
            "decision": payload.decision,
            "reason": reason,
        },
    )
    db.commit()
    return ok(serialise_shop(shop), message=f"Verification set to {stage}")


@router.get("/{shop_id}/verification/history")
def shop_verification_history(
    shop_id: int,
    page: Pagination = Depends(pagination),
    db: Session = Depends(get_db),
    _: AdminUser = Depends(get_current_admin),
):
    """Every decision recorded on one case, newest first.

    This is the same append-only trail the History tab reads, narrowed to the
    verification events and shaped for the Decisions table (admin, time,
    reason, action) so the detail page does not have to filter client-side.
    """
    _get_shop_or_404(db, shop_id)
    stmt = select(AuditLog).where(
        AuditLog.entity_type == "shop",
        AuditLog.entity_id == shop_id,
        AuditLog.action.like("shop.verification.%"),
    )
    total = db.scalar(select(func.count()).select_from(stmt.subquery())) or 0
    start, end = page.window()
    rows = db.scalars(
        stmt.order_by(AuditLog.created_at.desc(), AuditLog.id.desc())
        .offset(start)
        .limit(end - start)
    ).all()
    items = []
    for r in rows:
        details = r.details or {}
        items.append(
            {
                "id": r.id,
                "admin_user": r.admin_user,
                "created_at": iso(r.created_at),
                "reason": details.get("reason"),
                "action": r.action,
                "from": details.get("from"),
                "to": details.get("to"),
                "decision": details.get("decision"),
            }
        )
    return ok(paged(items, total))


class ReviewerAssignment(BaseModel):
    """Assign or clear the reviewer holding a case."""

    reviewer: str | None = None
    reason: str | None = None


@router.post("/{shop_id}/verification/assign")
def assign_reviewer(
    shop_id: int,
    payload: ReviewerAssignment,
    db: Session = Depends(get_db),
    admin: AdminUser = Depends(require_capability("shops.verify")),
):
    """Put a case in a named reviewer's hands, or take it off them.

    Assignment moves the case to UNDER_REVIEW without deciding it: the queue's
    "Under Review" tab is exactly the set of cases someone has picked up. A
    null reviewer releases it back to the unassigned pool.
    """
    shop = _get_shop_or_404(db, shop_id)
    previous = shop.verified_by
    shop.verified_by = payload.reviewer or None
    if shop.verified_by and shop.verification_status == "PENDING":
        shop.verification_status = "UNDER_REVIEW"
    _record_audit(
        db,
        admin,
        "shop.verification.assigned" if shop.verified_by else "shop.verification.unassigned",
        shop_id,
        {"from": previous, "to": shop.verified_by, "reason": payload.reason},
    )
    db.commit()
    return ok(
        serialise_shop(shop),
        message=f"Case assigned to {shop.verified_by}" if shop.verified_by else "Case unassigned",
    )


class ShopUpdate(BaseModel):
    """Partial update. Only supplied fields are written."""

    name: str | None = None
    category: str | None = None
    subcategory: str | None = None
    business_type: str | None = None
    address: str | None = None
    locality: str | None = None
    city: str | None = None
    state: str | None = None
    pincode: str | None = None
    phone: str | None = None
    alt_phone: str | None = None
    email: str | None = None
    website: str | None = None
    description: str | None = None
    registration_number: str | None = None
    gst_number: str | None = None
    status: str | None = None
    operating_hours: dict | None = None


@router.patch("/{shop_id}")
def update_shop(
    shop_id: int,
    payload: ShopUpdate,
    db: Session = Depends(get_db),
    admin: AdminUser = Depends(require_capability("shops.update")),
):
    shop = _get_shop_or_404(db, shop_id)
    changes = payload.model_dump(exclude_unset=True)
    for field, value in changes.items():
        setattr(shop, field, value)
    _record_audit(db, admin, "shop.updated", shop_id, {"fields": list(changes)})
    db.commit()
    db.refresh(shop)
    return ok(serialise_shop(shop), message="Business updated")
