from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from app.core.cache import cache
from app.core.cached_read import cached_read
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

    Read-heavy and rarely-changing, so it goes through `cached_read` rather
    than a bare get/set. At 500 concurrent customers every app launch asks for
    this list, and a plain get/set means every one of them runs the same query
    the instant the TTL lapses. `cached_read` collapses that into one query
    while the rest read from cache.

    A Redis outage degrades to a live PostgreSQL query (correct, just slower)
    -- never an error, and never a queue on a lock nobody holds.
    """

    async def _load():
        categories = db.query(Category).all()
        return [CategoryResponse.model_validate(c).model_dump() for c in categories]

    data = await cached_read(CACHE_DOMAIN, "list", _load)
    return success_response(data=data)


@router.get("/{category_id}")
async def get_category(category_id: int, db: Session = Depends(get_db)):
    """Return a single category by ID."""
    category = db.query(Category).filter(Category.id == category_id).first()
    if category is None:
        return error_response(message="Category not found", error_code="CATEGORY_NOT_FOUND", status_code=404)
    return success_response(data=CategoryResponse.model_validate(category).model_dump())