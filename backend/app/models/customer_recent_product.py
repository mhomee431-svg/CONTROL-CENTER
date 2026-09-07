"""Customer recently-viewed products (upsert by customer + product master)."""

from datetime import datetime

from sqlalchemy import (
    DateTime,
    ForeignKey,
    Index,
    Integer,
    UniqueConstraint,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database.session import Base
from app.models.base import TimestampMixin


class CustomerRecentProduct(Base, TimestampMixin):
    """Tracks per-customer recently-viewed products.

    One row per (customer, product_master); each view increments ``view_count``
    and bumps ``last_viewed_at`` (application-side UPSERT on the UNIQUE key).
    ``variant_id`` / ``shop_product_id`` preserve the last-viewed context when
    the customer drilled into a specific variant at a specific shop.
    """

    __tablename__ = "customer_recent_products"
    __table_args__ = (
        UniqueConstraint(
            "customer_id", "product_master_id",
            name="uq_customer_recent_customer_product",
        ),
        Index("ix_customer_recent_customer_last_viewed", "customer_id", "last_viewed_at"),
    )

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    customer_id: Mapped[int] = mapped_column(
        ForeignKey("customers.id", ondelete="CASCADE"), index=True, nullable=False
    )
    product_master_id: Mapped[int] = mapped_column(
        ForeignKey("product_masters.id", ondelete="CASCADE"), index=True, nullable=False
    )
    variant_id: Mapped[int | None] = mapped_column(
        ForeignKey("product_variants.id", ondelete="SET NULL"), index=True
    )
    shop_product_id: Mapped[int | None] = mapped_column(
        ForeignKey("shop_products.id", ondelete="SET NULL"), index=True
    )
    first_viewed_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default="now()"
    )
    last_viewed_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default="now()"
    )
    view_count: Mapped[int] = mapped_column(
        Integer, nullable=False, default=1, server_default="1"
    )

    customer = relationship("Customer", back_populates="recent_products")
    product_master = relationship("ProductMaster")
    variant = relationship("ProductVariant")