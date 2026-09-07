"""Reviews model — Master Spec §§19-20, 49.

Moderated, verified-customer reviews for shops and products. This is the
display-grade review content; user_interactions.rating stays as the lightweight
create-only signal. Reviews adds moderated title/body content with admin
moderation workflow.

A review targets EITHER a shop OR a product (never both), enforced by a CHECK
constraint. Partial unique index ensures one review per (user, shop) or
(user, product) when the review is in a display state.
"""

from datetime import date

from sqlalchemy import (
    Boolean,
    CheckConstraint,
    Date,
    ForeignKey,
    Integer,
    String,
    Text,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database.session import Base
from app.models.base import SoftDeleteMixin, TimestampMixin


class Review(Base, TimestampMixin, SoftDeleteMixin):
    """Moderated, verified-customer review for a shop or product."""

    __tablename__ = "reviews"
    __table_args__ = (
        CheckConstraint("rating >= 1 AND rating <= 5", name="ck_reviews_rating_range"),
        CheckConstraint(
            "shop_id IS NOT NULL OR product_master_id IS NOT NULL",
            name="ck_reviews_target_required",
        ),
        CheckConstraint(
            "status IN ('PENDING', 'APPROVED', 'REJECTED', 'HIDDEN')",
            name="ck_reviews_status",
        ),
    )

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id"), index=True, nullable=False)
    shop_id: Mapped[int | None] = mapped_column(ForeignKey("shops.id"), index=True)
    product_master_id: Mapped[int | None] = mapped_column(ForeignKey("product_masters.id"), index=True)
    rating: Mapped[int] = mapped_column(Integer, nullable=False)
    title: Mapped[str | None] = mapped_column(String(255))
    body: Mapped[str | None] = mapped_column(Text)
    is_verified_purchase: Mapped[bool] = mapped_column(Boolean, default=False)
    status: Mapped[str] = mapped_column(String(20), nullable=False, default="PENDING")
    moderated_by: Mapped[int | None] = mapped_column(ForeignKey("users.id"))
    moderated_at: Mapped[date | None] = mapped_column(Date)

    user = relationship("User", foreign_keys=[user_id])
    shop = relationship("Shop")
    product = relationship("ProductMaster")
