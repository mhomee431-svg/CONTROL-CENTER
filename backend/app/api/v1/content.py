"""Content surfaces: banners, announcements, FAQs, help, promotions, messages.

Each content type is the same CRUD shape over a different table, so the routes
are generated from one description rather than written out six times.
"""

from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy import func, or_, select
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.core.pagination import Pagination, pagination
from app.core.responses import ok, paged
from app.core.serializers import to_dict
from app.core.security import get_current_admin, require_capability
from app.models import (
    AdminUser,
    Announcement,
    Banner,
    Faq,
    HelpContent,
    PromotionalCard,
    SystemMessage,
)

router = APIRouter(prefix="/admin/content", tags=["content"])

BANNER_FIELDS = [
    "id", "title", "subtitle", "image_url", "deep_link", "placement", "status",
    "sort_order", "starts_at", "ends_at", "created_at", "updated_at",
]
ANNOUNCEMENT_FIELDS = [
    "id", "title", "body", "audience", "status", "is_pinned",
    "published_at", "expires_at", "created_at", "updated_at",
]
FAQ_FIELDS = ["id", "question", "answer", "category", "audience", "status", "sort_order", "created_at", "updated_at"]
HELP_FIELDS = ["id", "title", "slug", "body", "section", "status", "sort_order", "created_at", "updated_at"]
PROMO_FIELDS = [
    "id", "title", "description", "image_url", "cta_label", "deep_link",
    "status", "starts_at", "ends_at", "created_at", "updated_at",
]
MESSAGE_FIELDS = [
    "id", "title", "body", "severity", "status", "is_active",
    "starts_at", "ends_at", "created_at", "updated_at",
]

# path -> (model, fields, searchable columns, required-for-create)
SURFACES = {
    "banners": (Banner, BANNER_FIELDS, [Banner.title, Banner.placement]),
    "announcements": (Announcement, ANNOUNCEMENT_FIELDS, [Announcement.title, Announcement.body]),
    "faqs": (Faq, FAQ_FIELDS, [Faq.question, Faq.answer, Faq.category]),
    "help": (HelpContent, HELP_FIELDS, [HelpContent.title, HelpContent.body, HelpContent.section]),
    "promotions": (PromotionalCard, PROMO_FIELDS, [PromotionalCard.title, PromotionalCard.description]),
    "system-messages": (SystemMessage, MESSAGE_FIELDS, [SystemMessage.title, SystemMessage.body]),
}


class ContentPayload(BaseModel):
    """A content row. Fields are permissive because the six surfaces differ."""

    model_config = {"extra": "allow"}


def _surface(path: str):
    entry = SURFACES.get(path)
    if entry is None:
        raise HTTPException(status_code=404, detail=f"Unknown content surface '{path}'")
    return entry


def _list_surface(path: str, page: Pagination, db: Session):
    model, fields, searchable = _surface(path)
    stmt = select(model)
    if page.search:
        like = f"%{page.search}%"
        stmt = stmt.where(or_(*[col.ilike(like) for col in searchable]))
    total = db.scalar(select(func.count()).select_from(stmt.subquery())) or 0
    start, end = page.window()
    rows = db.scalars(stmt.order_by(model.id.desc()).offset(start).limit(end - start)).all()
    return ok(paged([to_dict(r, fields) for r in rows], total))


def _detail_surface(path: str, row_id: int, db: Session):
    model, fields, _ = _surface(path)
    row = db.get(model, row_id)
    if row is None:
        raise HTTPException(status_code=404, detail=f"{path} entry {row_id} not found")
    return ok(to_dict(row, fields))


def _create_surface(path: str, payload: dict, db: Session):
    model, fields, _ = _surface(path)
    allowed = {c.name for c in model.__table__.columns}
    data = {k: v for k, v in payload.items() if k in allowed and k not in {"id", "created_at", "updated_at"}}
    row = model(**data)
    db.add(row)
    db.commit()
    db.refresh(row)
    return ok(to_dict(row, fields), message="Created")


def _update_surface(path: str, row_id: int, payload: dict, db: Session):
    model, fields, _ = _surface(path)
    row = db.get(model, row_id)
    if row is None:
        raise HTTPException(status_code=404, detail=f"{path} entry {row_id} not found")
    allowed = {c.name for c in model.__table__.columns}
    for key, value in payload.items():
        if key in allowed and key not in {"id", "created_at"}:
            setattr(row, key, value)
    db.commit()
    db.refresh(row)
    return ok(to_dict(row, fields), message="Updated")


def _delete_surface(path: str, row_id: int, db: Session):
    model, _, _ = _surface(path)
    row = db.get(model, row_id)
    if row is None:
        raise HTTPException(status_code=404, detail=f"{path} entry {row_id} not found")
    db.delete(row)
    db.commit()
    return ok(None, message="Deleted")


@router.get("/{surface}")
def list_content(
    surface: str,
    page: Pagination = Depends(pagination),
    db: Session = Depends(get_db),
    _: AdminUser = Depends(get_current_admin),
):
    return _list_surface(surface, page, db)


@router.post("/{surface}")
def create_content(
    surface: str,
    payload: dict,
    db: Session = Depends(get_db),
    admin: AdminUser = Depends(require_capability("content.manage")),
):
    return _create_surface(surface, payload, db)


@router.get("/{surface}/{row_id}")
def content_detail(
    surface: str,
    row_id: int,
    db: Session = Depends(get_db),
    _: AdminUser = Depends(get_current_admin),
):
    return _detail_surface(surface, row_id, db)


@router.patch("/{surface}/{row_id}")
def update_content(
    surface: str,
    row_id: int,
    payload: dict,
    db: Session = Depends(get_db),
    admin: AdminUser = Depends(require_capability("content.manage")),
):
    return _update_surface(surface, row_id, payload, db)


@router.put("/{surface}/{row_id}")
def replace_content(
    surface: str,
    row_id: int,
    payload: dict,
    db: Session = Depends(get_db),
    admin: AdminUser = Depends(require_capability("content.manage")),
):
    return _update_surface(surface, row_id, payload, db)


@router.delete("/{surface}/{row_id}")
def delete_content(
    surface: str,
    row_id: int,
    db: Session = Depends(get_db),
    admin: AdminUser = Depends(require_capability("content.manage")),
):
    return _delete_surface(surface, row_id, db)
