from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from app.core.cache import cache
from app.core.config import settings
from app.core.responses import error_response, success_response
from app.database.session import get_db
from app.models.product import Category
from app.schemas.category import CategoryResponse

router = APIRouter(prefix="/categories", tags=["categories"])

# Cache domain for category data (read-heavy, rarely-changing). Writers that
# mutate categories must call ``await cache.invalidate_domain("category")``
# (or ``invalidate("category", <id>)`` for single entities) — see
# app/core/cache.py for the full invalidation strategy.
CACHE_DOMAIN = "category"


@router.get("")
async def list_categories(db: Session = Depends(get_db)):
    """Return all product categories.

    Served from the Redis cache when warm. A Redis outage degrades to a live
    PostgreSQL query (correct, just slower) — never an error.
    """
    cached = await cache.get_json(CACHE_DOMAIN, "list")
    if cached is not None:
        return success_response(data=cached)

    categories = db.query(Category).all()
    data = [CategoryResponse.model_validate(c).model_dump() for c in categories]
    await cache.set_json(CACHE_DOMAIN, "list", data, ttl=settings.CACHE_DEFAULT_TTL)
    return success_response(data=data)


@router.get("/{category_id}")
async def get_category(category_id: int, db: Session = Depends(get_db)):
    """Return a single category by ID."""
    category = db.query(Category).filter(Category.id == category_id).first()
    if category is None:
        return error_response(message="Category not found", error_code="CATEGORY_NOT_FOUND", status_code=404)
    return success_response(data=CategoryResponse.model_validate(category).model_dump())