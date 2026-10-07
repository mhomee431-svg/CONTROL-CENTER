"""Customers and shopkeepers — listings, detail and drill-down tabs."""

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy import func, or_, select
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.core.pagination import Pagination, pagination
from app.core.responses import ok, paged
from app.core.serializers import serialise_shop, to_dict
from app.core.security import get_current_admin, require_capability
from app.models import (
    AdminUser,
    AuditLog,
    Complaint,
    ImportJob,
    PosIntegration,
    Product,
    SearchQuery,
    Shop,
    ShopInventory,
    User,
)

router = APIRouter(prefix="/admin", tags=["people"])


def _list(stmt, page: Pagination, db: Session, serialiser):
    total = db.scalar(select(func.count()).select_from(stmt.subquery())) or 0
    start, end = page.window()
    rows = db.scalars(stmt.offset(start).limit(end - start)).all()
    return ok(paged([serialiser(r) for r in rows], total))


# --- Customers -------------------------------------------------------------

CUSTOMER_FIELDS = [
    "id", "name", "phone", "email", "status", "created_at", "last_login",
    "last_active", "auth_status", "city", "state", "is_restricted",
    "search_count", "viewed_product_count", "viewed_shop_count",
    "saved_product_count", "saved_shop_count",
]


@router.get("/customers")
def list_customers(
    page: Pagination = Depends(pagination),
    status: str | None = None,
    city: str | None = None,
    db: Session = Depends(get_db),
    _: AdminUser = Depends(get_current_admin),
):
    stmt = select(User)
    if page.search:
        like = f"%{page.search}%"
        stmt = stmt.where(or_(User.name.ilike(like), User.phone.ilike(like), User.email.ilike(like)))
    if status:
        stmt = stmt.where(User.status == status)
    if city:
        stmt = stmt.where(User.city == city)
    return _list(stmt.order_by(User.id), page, db, lambda r: to_dict(r, CUSTOMER_FIELDS))


@router.get("/customers/{user_id}")
def customer_detail(
    user_id: int, db: Session = Depends(get_db), _: AdminUser = Depends(get_current_admin)
):
    user = db.get(User, user_id)
    if user is None:
        raise HTTPException(status_code=404, detail=f"Customer {user_id} not found")
    return ok(to_dict(user, CUSTOMER_FIELDS))


@router.get("/customers/{user_id}/searches")
def customer_searches(
    user_id: int,
    page: Pagination = Depends(pagination),
    db: Session = Depends(get_db),
    _: AdminUser = Depends(get_current_admin),
):
    stmt = select(SearchQuery).where(SearchQuery.user_id == user_id)
    fields = ["id", "query", "result_count", "location", "searched_at"]
    return _list(stmt.order_by(SearchQuery.id.desc()), page, db, lambda r: to_dict(r, fields))


@router.get("/customers/{user_id}/activity")
def customer_activity(
    user_id: int,
    page: Pagination = Depends(pagination),
    db: Session = Depends(get_db),
    _: AdminUser = Depends(get_current_admin),
):
    """Activity is the audit trail for this user, projected to the tab's shape."""
    stmt = select(AuditLog).where(AuditLog.entity_type == "user", AuditLog.entity_id == user_id)
    start, end = page.window()
    total = db.scalar(select(func.count()).select_from(stmt.subquery())) or 0
    rows = db.scalars(stmt.order_by(AuditLog.id.desc()).offset(start).limit(end - start)).all()
    items = [
        {
            "id": r.id,
            "activity_type": r.action,
            "description": (r.details or {}).get("description") if r.details else None,
            "entity_type": r.entity_type,
            "entity_id": r.entity_id,
            "created_at": r.created_at.isoformat() if r.created_at else None,
        }
        for r in rows
    ]
    return ok(paged(items, total))


@router.get("/customers/{user_id}/tickets")
def customer_tickets(
    user_id: int,
    page: Pagination = Depends(pagination),
    db: Session = Depends(get_db),
    _: AdminUser = Depends(get_current_admin),
):
    stmt = select(Complaint).where(
        Complaint.reporter_type == "customer", Complaint.reporter_name == str(user_id)
    )
    fields = [
        "id", "ticket_number", "complaint_type", "priority",
        "status", "description", "created_at",
    ]
    return _list(stmt.order_by(Complaint.id.desc()), page, db, lambda r: to_dict(r, fields))


class RestrictPayload(BaseModel):
    is_restricted: bool
    reason: str | None = None


@router.post("/customers/{user_id}/restrict")
def restrict_customer(
    user_id: int,
    payload: RestrictPayload,
    db: Session = Depends(get_db),
    admin: AdminUser = Depends(require_capability("customers.restrict")),
):
    user = db.get(User, user_id)
    if user is None:
        raise HTTPException(status_code=404, detail=f"Customer {user_id} not found")
    user.is_restricted = payload.is_restricted
    db.add(
        AuditLog(
            action="customer.restricted" if payload.is_restricted else "customer.unrestricted",
            entity_type="user",
            entity_id=user_id,
            user_id=admin.id,
            admin_user=admin.name or admin.username,
            details={"reason": payload.reason},
        )
    )
    db.commit()
    return ok(to_dict(user, CUSTOMER_FIELDS), message="Customer restriction updated")


class StatusPayload(BaseModel):
    status: str
    reason: str | None = None


@router.post("/users/{user_id}/status")
def set_user_status(
    user_id: int,
    payload: StatusPayload,
    db: Session = Depends(get_db),
    admin: AdminUser = Depends(require_capability("customers.status")),
):
    user = db.get(User, user_id)
    if user is None:
        raise HTTPException(status_code=404, detail=f"User {user_id} not found")
    user.status = payload.status
    db.add(
        AuditLog(
            action="user.status_changed",
            entity_type="user",
            entity_id=user_id,
            user_id=admin.id,
            admin_user=admin.name or admin.username,
            details={"status": payload.status, "reason": payload.reason},
        )
    )
    db.commit()
    return ok(to_dict(user, CUSTOMER_FIELDS), message="Status updated")


# --- Shopkeepers -----------------------------------------------------------


@router.get("/shopkeepers")
def list_shopkeepers(
    page: Pagination = Depends(pagination),
    status: str | None = None,
    db: Session = Depends(get_db),
    _: AdminUser = Depends(get_current_admin),
):
    """A shopkeeper is a user who owns at least one shop."""
    owner_ids = select(Shop.owner_id).where(Shop.owner_id.isnot(None)).distinct()
    stmt = select(User).where(User.id.in_(owner_ids))
    if page.search:
        like = f"%{page.search}%"
        stmt = stmt.where(or_(User.name.ilike(like), User.phone.ilike(like), User.email.ilike(like)))
    if status:
        stmt = stmt.where(User.status == status)
    return _list(stmt.order_by(User.id), page, db, lambda r: to_dict(r, CUSTOMER_FIELDS))


@router.get("/shopkeepers/{user_id}")
def shopkeeper_detail(
    user_id: int, db: Session = Depends(get_db), _: AdminUser = Depends(get_current_admin)
):
    user = db.get(User, user_id)
    if user is None:
        raise HTTPException(status_code=404, detail=f"Shopkeeper {user_id} not found")
    shops = db.scalars(select(Shop).where(Shop.owner_id == user_id)).all()
    payload = to_dict(user, CUSTOMER_FIELDS)
    payload["shop_ids"] = [s.id for s in shops]
    payload["shop_names"] = [s.name for s in shops]
    payload["is_profile_complete"] = user.is_profile_complete
    return ok(payload)


@router.get("/shopkeepers/{user_id}/shops")
def shopkeeper_shops(
    user_id: int,
    page: Pagination = Depends(pagination),
    db: Session = Depends(get_db),
    _: AdminUser = Depends(get_current_admin),
):
    stmt = select(Shop).where(Shop.owner_id == user_id)
    return _list(stmt.order_by(Shop.id), page, db, serialise_shop)


@router.get("/shopkeepers/{user_id}/imports")
def shopkeeper_imports(
    user_id: int,
    page: Pagination = Depends(pagination),
    db: Session = Depends(get_db),
    _: AdminUser = Depends(get_current_admin),
):
    shop_ids = [s.id for s in db.scalars(select(Shop).where(Shop.owner_id == user_id)).all()]
    stmt = select(ImportJob).where(ImportJob.shop_id.in_(shop_ids or [-1]))
    fields = [
        "id", "shop_name", "source", "status", "rows_total", "rows_processed", "created_at",
    ]
    return _list(stmt.order_by(ImportJob.id.desc()), page, db, lambda r: to_dict(r, fields))


@router.get("/shopkeepers/{user_id}/pos-integrations")
def shopkeeper_pos(
    user_id: int,
    page: Pagination = Depends(pagination),
    db: Session = Depends(get_db),
    _: AdminUser = Depends(get_current_admin),
):
    shop_ids = [s.id for s in db.scalars(select(Shop).where(Shop.owner_id == user_id)).all()]
    stmt = select(PosIntegration).where(PosIntegration.shop_id.in_(shop_ids or [-1]))
    fields = ["id", "shop_name", "provider", "status", "last_sync"]
    return _list(stmt.order_by(PosIntegration.id.desc()), page, db, lambda r: to_dict(r, fields))


@router.get("/shopkeepers/{user_id}/notifications")
def shopkeeper_notifications(
    user_id: int,
    page: Pagination = Depends(pagination),
    db: Session = Depends(get_db),
    _: AdminUser = Depends(get_current_admin),
):
    stmt = select(AuditLog).where(
        AuditLog.entity_type == "shopkeeper", AuditLog.entity_id == user_id
    )
    start, end = page.window()
    total = db.scalar(select(func.count()).select_from(stmt.subquery())) or 0
    rows = db.scalars(stmt.order_by(AuditLog.id.desc()).offset(start).limit(end - start)).all()
    items = [
        {
            "id": r.id,
            "title": r.action,
            "notification_type": (r.details or {}).get("type") if r.details else None,
            "status": "SENT",
            "sent_at": r.created_at.isoformat() if r.created_at else None,
        }
        for r in rows
    ]
    return ok(paged(items, total))


@router.get("/shopkeepers/{user_id}/tickets")
def shopkeeper_tickets(
    user_id: int,
    page: Pagination = Depends(pagination),
    db: Session = Depends(get_db),
    _: AdminUser = Depends(get_current_admin),
):
    stmt = select(Complaint).where(
        Complaint.reporter_type == "shopkeeper", Complaint.reporter_name == str(user_id)
    )
    fields = [
        "id", "ticket_number", "complaint_type", "priority",
        "status", "description", "created_at",
    ]
    return _list(stmt.order_by(Complaint.id.desc()), page, db, lambda r: to_dict(r, fields))
