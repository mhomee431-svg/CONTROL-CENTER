"""Reviews service — Master Spec §§19-20, 49."""

from datetime import date
from typing import Optional

from sqlalchemy import select, func
from sqlalchemy.orm import Session

from app.core.logging import get_logger
from app.models.review import Review
from app.schemas.review import ReviewCreate, ReviewModeration

logger = get_logger("app.services.reviews")


def get_shop_reviews(
    db: Session, shop_id: int, page: int = 1, page_size: int = 20
) -> dict:
    """Get approved reviews for a shop (paginated)."""
    offset = (page - 1) * page_size

    total = (
        db.execute(
            select(func.count(Review.id)).where(
                Review.shop_id == shop_id,
                Review.status == "APPROVED",
                Review.is_deleted == False,  # noqa: E712
            )
        )
        .scalar()
    )

    reviews = (
        db.execute(
            select(Review)
            .where(
                Review.shop_id == shop_id,
                Review.status == "APPROVED",
                Review.is_deleted == False,  # noqa: E712
            )
            .order_by(Review.created_at.desc())
            .offset(offset)
            .limit(page_size)
        )
        .scalars()
        .all()
    )

    return {
        "reviews": [
            {
                "id": r.id,
                "user_id": r.user_id,
                "rating": r.rating,
                "title": r.title,
                "body": r.body,
                "is_verified_purchase": r.is_verified_purchase,
                "created_at": r.created_at.isoformat(),
            }
            for r in reviews
        ],
        "total": total,
        "page": page,
        "page_size": page_size,
    }


def get_product_reviews(
    db: Session, product_id: int, page: int = 1, page_size: int = 20
) -> dict:
    """Get approved reviews for a product (paginated)."""
    offset = (page - 1) * page_size

    total = (
        db.execute(
            select(func.count(Review.id)).where(
                Review.product_master_id == product_id,
                Review.status == "APPROVED",
                Review.is_deleted == False,  # noqa: E712
            )
        )
        .scalar()
    )

    reviews = (
        db.execute(
            select(Review)
            .where(
                Review.product_master_id == product_id,
                Review.status == "APPROVED",
                Review.is_deleted == False,  # noqa: E712
            )
            .order_by(Review.created_at.desc())
            .offset(offset)
            .limit(page_size)
        )
        .scalars()
        .all()
    )

    return {
        "reviews": [
            {
                "id": r.id,
                "user_id": r.user_id,
                "rating": r.rating,
                "title": r.title,
                "body": r.body,
                "is_verified_purchase": r.is_verified_purchase,
                "created_at": r.created_at.isoformat(),
            }
            for r in reviews
        ],
        "total": total,
        "page": page,
        "page_size": page_size,
    }

def create_review(db: Session, user_id: int, data: ReviewCreate) -> Review:
    """Submit a review for a shop or product."""
    if data.shop_id is None and data.product_master_id is None:
        raise ValueError("Either shop_id or product_master_id must be provided")

    if data.shop_id:
        existing = (
            db.execute(
                select(Review).where(
                    Review.user_id == user_id,
                    Review.shop_id == data.shop_id,
                    Review.is_deleted == False,  # noqa: E712
                )
            )
            .scalars()
            .first()
        )
        if existing:
            raise ValueError("You have already reviewed this shop")

    if data.product_master_id:
        existing = (
            db.execute(
                select(Review).where(
                    Review.user_id == user_id,
                    Review.product_master_id == data.product_master_id,
                    Review.is_deleted == False,  # noqa: E712
                )
            )
            .scalars()
            .first()
        )
        if existing:
            raise ValueError("You have already reviewed this product")

    review = Review(
        user_id=user_id,
        shop_id=data.shop_id,
        product_master_id=data.product_master_id,
        rating=data.rating,
        title=data.title,
        body=data.body,
    )
    db.add(review)
    db.commit()
    db.refresh(review)
    return review


def get_pending_reviews(
    db: Session, page: int = 1, page_size: int = 20
) -> dict:
    """Get reviews pending moderation (admin only)."""
    offset = (page - 1) * page_size

    total = (
        db.execute(
            select(func.count(Review.id)).where(
                Review.status == "PENDING",
                Review.is_deleted == False,  # noqa: E712
            )
        )
        .scalar()
    )

    reviews = (
        db.execute(
            select(Review)
            .where(
                Review.status == "PENDING",
                Review.is_deleted == False,  # noqa: E712
            )
            .order_by(Review.created_at.asc())
            .offset(offset)
            .limit(page_size)
        )
        .scalars()
        .all()
    )

    return {
        "reviews": [
            {
                "id": r.id,
                "user_id": r.user_id,
                "shop_id": r.shop_id,
                "product_master_id": r.product_master_id,
                "rating": r.rating,
                "title": r.title,
                "body": r.body,
                "is_verified_purchase": r.is_verified_purchase,
                "status": r.status,
                "created_at": r.created_at.isoformat(),
            }
            for r in reviews
        ],
        "total": total,
        "page": page,
        "page_size": page_size,
    }


def moderate_review(
    db: Session, admin_user_id: int, review_id: int, data: ReviewModeration
) -> Optional[Review]:
    """Moderate a review - approve, reject, or hide (admin only)."""
    review = db.get(Review, review_id)
    if not review or review.is_deleted:
        return None

    review.status = data.status
    review.moderated_by = admin_user_id
    review.moderated_at = date.today()

    db.commit()
    db.refresh(review)
    return review
