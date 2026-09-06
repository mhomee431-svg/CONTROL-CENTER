"""Reviews API routes — Master Spec §§19-20, 49.

Moderated, verified-customer reviews for shops and products. Customers can
create reviews, view approved reviews, and admins can moderate them.
"""

from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session

from app.core.dependencies import get_current_user, require_admin
from app.core.responses import error_response, success_response
from app.database.session import get_db
from app.models.review import Review
from app.schemas.review import (
    ReviewCreate,
    ReviewResponse,
    ReviewModeration,
)
from app.services import review_service

router = APIRouter(prefix="/reviews", tags=["reviews"])


# ── Customer-facing endpoints ──────────────────────────────────────────────
@router.get("/shop/{shop_id}")
async def get_shop_reviews(
    shop_id: int,
    page: int = Query(1, ge=1),
    page_size: int = Query(20, ge=1, le=50),
    db: Session = Depends(get_db),
):
    """Get approved reviews for a shop (paginated)."""
    reviews = review_service.get_shop_reviews(db, shop_id=shop_id, page=page, page_size=page_size)
    return success_response(data=reviews)


@router.get("/product/{product_id}")
async def get_product_reviews(
    product_id: int,
    page: int = Query(1, ge=1),
    page_size: int = Query(20, ge=1, le=50),
    db: Session = Depends(get_db),
):
    """Get approved reviews for a product (paginated)."""
    reviews = review_service.get_product_reviews(db, product_id=product_id, page=page, page_size=page_size)
    return success_response(data=reviews)


@router.post("/")
async def create_review(
    data: ReviewCreate,
    db: Session = Depends(get_db),
    current_user=Depends(get_current_user),
):
    """Submit a review for a shop or product (verified customers only)."""
    try:
        review = review_service.create_review(db, user_id=current_user.id, data=data)
        return success_response(data=review, message="Review submitted for moderation")
    except ValueError as exc:
        return error_response(message=str(exc), error_code="REVIEW_CREATE_FAILED", status_code=400)
    except Exception as exc:  # noqa: BLE001
        return error_response(message=str(exc), error_code="REVIEW_CREATE_FAILED", status_code=500)


# ── Admin moderation endpoints ──────────────────────────────────────────────
@router.get("/pending", dependencies=[Depends(require_admin)])
async def get_pending_reviews(
    page: int = Query(1, ge=1),
    page_size: int = Query(20, ge=1, le=50),
    db: Session = Depends(get_db),
):
    """Get reviews pending moderation (admin only)."""
    reviews = review_service.get_pending_reviews(db, page=page, page_size=page_size)
    return success_response(data=reviews)


@router.post("/{review_id}/moderate", dependencies=[Depends(require_admin)])
async def moderate_review(
    review_id: int,
    data: ReviewModeration,
    db: Session = Depends(get_db),
    current_user=Depends(get_current_user),
):
    """Moderate a review — approve, reject, or hide (admin only)."""
    try:
        review = review_service.moderate_review(
            db, admin_user_id=current_user.id, review_id=review_id, data=data
        )
        if review is None:
            return error_response(message="Review not found", error_code="REVIEW_NOT_FOUND", status_code=404)
        return success_response(data=review, message="Review moderated")
    except ValueError as exc:
        return error_response(message=str(exc), error_code="REVIEW_MODERATION_FAILED", status_code=400)
    except Exception as exc:  # noqa: BLE001
        return error_response(message=str(exc), error_code="REVIEW_MODERATION_FAILED", status_code=500)
