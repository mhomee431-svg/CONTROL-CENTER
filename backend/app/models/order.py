"""Orders ? customer cart/checkout/payment flow (Master Spec ??30-32).

An [Order] is the immutable header for a customer's purchase from a single
shop; [OrderItem] rows are the line items. Prices/names are snapshotted at
checkout time, so later catalog or price changes can NEVER mutate a
completed order. The customer-facing cart carries the snapshotted unit
price (read from the live catalog at add-to-cart time); the service trusts
it rather than re-reading a live price ? this keeps an order stable even
if the shop changes a price between checkout and payment settlement.

Follows the Review model convention: string status columns with CHECK
constraints (portable across PostgreSQL/SQLite), TimestampMixin +
SoftDeleteMixin, FK to users/customers/shops.
"""

from __future__ import annotations

import enum
from datetime import datetime

from sqlalchemy import (
    CheckConstraint,
    DateTime,
    ForeignKey,
    Integer,
    Numeric,
    String,
    Text,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database.session import Base
from app.models.base import SoftDeleteMixin, TimestampMixin


class OrderStatus(str, enum.Enum):
    """Customer-visible order lifecycle states."""

    PENDING = "PENDING"
    CONFIRMED = "CONFIRMED"
    PREPARING = "PREPARING"
    READY_FOR_PICKUP = "READY_FOR_PICKUP"
    OUT_FOR_DELIVERY = "OUT_FOR_DELIVERY"
    DELIVERED = "DELIVERED"
    CANCELLED = "CANCELLED"
    REFUNDED = "REFUNDED"
    FAILED = "FAILED"


class OrderItemStatus(str, enum.Enum):
    """Per-line-item status - a single order may carry mixed item states."""

    PENDING = "PENDING"
    CONFIRMED = "CONFIRMED"
    PREPARING = "PREPARING"
    READY = "READY"
    CANCELLED = "CANCELLED"


# CHECK constraint value lists, kept in sync with the enums above.
_ORDER_STATUSES = ", ".join(f"'{s.value}'" for s in OrderStatus)
_ITEM_STATUSES = ", ".join(f"'{s.value}'" for s in OrderItemStatus)
_PAYMENT_STATUSES = "'PENDING','PAID','FAILED','REFUNDED','PARTIALLY_REFUNDED'"


class Order(Base, TimestampMixin, SoftDeleteMixin):
    """Purchase header for a customer checkout against a single shop."""

    __tablename__ = "orders"
    __table_args__ = (
        CheckConstraint(f"status IN ({_ORDER_STATUSES})", name="ck_orders_status"),
        CheckConstraint(
            f"payment_status IN ({_PAYMENT_STATUSES})", name="ck_orders_payment_status"
        ),
        CheckConstraint("total_amount >= 0", name="ck_orders_total_non_negative"),
        CheckConstraint("subtotal_amount >= 0", name="ck_orders_subtotal_non_negative"),
        CheckConstraint("total_items >= 1", name="ck_orders_total_items_positive"),
    )

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    order_number: Mapped[str] = mapped_column(String(32), unique=True, index=True, nullable=False)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id"), nullable=False, index=True)
    customer_id: Mapped[int | None] = mapped_column(ForeignKey("customers.id"), index=True)
    shop_id: Mapped[int] = mapped_column(ForeignKey("shops.id"), nullable=False, index=True)
    # Shipping address snapshot (JSON text) - orders are immutable history,
    # so they do NOT FK to customer_addresses: deleting an address must never
    # void a placed order (mirrors CustomerFavorite.item_id policy).
    shipping_address_json: Mapped[str | None] = mapped_column(Text)

    status: Mapped[str] = mapped_column(
        String(20),
        nullable=False,
        default=OrderStatus.PENDING.value,
        server_default="PENDING",
    )
    payment_method: Mapped[str | None] = mapped_column(String(30))
    payment_status: Mapped[str] = mapped_column(
        String(20), nullable=False, default="PENDING", server_default="PENDING"
    )
    currency: Mapped[str] = mapped_column(String(3), nullable=False, default="INR", server_default="INR")

    subtotal_amount: Mapped[float] = mapped_column(Numeric(12, 2), nullable=False, default=0)
    delivery_fee: Mapped[float] = mapped_column(Numeric(12, 2), nullable=False, default=0)
    discount_amount: Mapped[float] = mapped_column(Numeric(12, 2), nullable=False, default=0)
    tax_amount: Mapped[float] = mapped_column(Numeric(12, 2), nullable=False, default=0)
    total_amount: Mapped[float] = mapped_column(Numeric(12, 2), nullable=False, default=0)
    total_items: Mapped[int] = mapped_column(Integer, nullable=False, default=0)

    notes: Mapped[str | None] = mapped_column(Text)

    placed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    confirmed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    preparing_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    ready_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    out_for_delivery_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    delivered_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    cancelled_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    cancelled_by: Mapped[int | None] = mapped_column(ForeignKey("users.id"))
    cancel_reason: Mapped[str | None] = mapped_column(Text)
    failed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    failure_reason: Mapped[str | None] = mapped_column(Text)

    # `cancelled_by` is a second FK to users.id, so the join path must be
    # pinned explicitly or SQLAlchemy cannot resolve the relationship.
    user = relationship("User", foreign_keys=[user_id])
    customer = relationship("Customer")
    shop = relationship("Shop")
    items = relationship("OrderItem", back_populates="order", cascade="all, delete-orphan")

    @property
    def is_cancellable(self) -> bool:
        """A customer may only cancel orders not yet in fulfilment."""
        return self.status in (
            OrderStatus.PENDING.value,
            OrderStatus.CONFIRMED.value,
            OrderStatus.PREPARING.value,
        )


class OrderItem(Base, TimestampMixin):
    """A single line item on an order. Price/name are checkout-time snapshots."""

    __tablename__ = "order_items"
    __table_args__ = (
        CheckConstraint("quantity >= 1", name="ck_order_items_quantity_positive"),
        CheckConstraint("price >= 0", name="ck_order_items_price_non_negative"),
        CheckConstraint("total_price >= 0", name="ck_order_items_total_non_negative"),
        CheckConstraint(f"item_status IN ({_ITEM_STATUSES})", name="ck_order_items_status"),
    )

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    order_id: Mapped[int] = mapped_column(
        ForeignKey("orders.id", ondelete="CASCADE"), nullable=False, index=True
    )
    # Catalog references are plain integers (no FK) so catalog deletes never
    # invalidate order history - mirrors CustomerFavorite.item_id policy.
    product_master_id: Mapped[int] = mapped_column(Integer, nullable=False, index=True)
    product_name: Mapped[str] = mapped_column(String(255), nullable=False)
    variant_id: Mapped[int | None] = mapped_column(Integer, index=True)
    variant_name: Mapped[str | None] = mapped_column(String(255))
    shop_product_id: Mapped[int | None] = mapped_column(Integer, index=True)
    quantity: Mapped[int] = mapped_column(Integer, nullable=False, default=1)
    price: Mapped[float] = mapped_column(Numeric(12, 2), nullable=False)
    total_price: Mapped[float] = mapped_column(Numeric(12, 2), nullable=False)
    image_url: Mapped[str | None] = mapped_column(String(500))
    item_status: Mapped[str] = mapped_column(
        String(20),
        nullable=False,
        default=OrderItemStatus.PENDING.value,
        server_default="PENDING",
    )

    order = relationship("Order", back_populates="items")


