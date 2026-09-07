"""Customer favorites (polymorphic: product / shop / brand / category / shop-product)."""

from datetime import datetime

from sqlalchemy import (
    CheckConstraint,
    DateTime,
    ForeignKey,
    Index,
    Integer,
    JSON,
    String,
    UniqueConstraint,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database.session import Base
from app.models.base import TimestampMixin

FAVORITE_ITEM_TYPES = ("PRODUCT", "SHOP", "BRAND", "CATEGORY", "SHOP_PRODUCT")


class CustomerFavorite(Base, TimestampMixin):
    """A customer's favourite item, polymorphic via ``item_type`` + ``item_id``.

    ``item_id`` deliberately has no FK: one table serves every entity kind and
    survives a referenced row's deletion (soft deletes are used system-wide).
    Query by (customer_id, item_type) for a feed; the UNIQUE constraint keeps
    one favourite per (customer, item).
    """

    __tablename__ = "customer_favorites"
    __table_args__ = (
        UniqueConstraint(
            "customer_id", "item_type", "item_id",
            name="uq_customer_favorite_customer_item",
        ),
        CheckConstraint(
            "item_type IN ('PRODUCT','SHOP','BRAND','CATEGORY','SHOP_PRODUCT')",
            name="ck_customer_favorites_item_type",
        ),
        Index("ix_customer_favorites_customer_created", "customer_id", "created_at"),
        Index("ix_customer_favorites_item", "item_type", "item_id"),
    )

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    customer_id: Mapped[int] = mapped_column(
        ForeignKey("customers.id", ondelete="CASCADE"), nullable=False, index=True
    )
    item_type: Mapped[str] = mapped_column(String(30), nullable=False)
    item_id: Mapped[int] = mapped_column(Integer, nullable=False)
    metadata_json: Mapped[dict | None] = mapped_column(JSON)

    customer = relationship("Customer", back_populates="favorites")