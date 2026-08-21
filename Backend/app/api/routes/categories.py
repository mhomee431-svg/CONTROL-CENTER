from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from app.core.responses import error_response, success_response
from app.database.session import get_db
from app.models.product import Category
from app.schemas.category import CategoryResponse

router = APIRouter(prefix="/categories", tags=["categories"])


@router.get("")
async def list_categories(db: Session = Depends(get_db)):
    """Return all product categories."""
    categories = db.query(Category).all()
    return success_response(data=[CategoryResponse.model_validate(c).model_dump() for c in categories])


@router.get("/{category_id}")
async def get_category(category_id: int, db: Session = Depends(get_db)):
    """Return a single category by ID."""
    category = db.query(Category).filter(Category.id == category_id).first()
    if category is None:
        return error_response(message="Category not found", error_code="CATEGORY_NOT_FOUND", status_code=404)
    return success_response(data=CategoryResponse.model_validate(category).model_dump())