"""Orders service - Master Spec ??30-32.

An order is the immutable header for a customer purchase from a single shop.
Line-item prices/names are trusted snapshots from the cart (the service never
re-reads live catalog prices), so a later price change can never mutate a
placed order.
"""
from __future__ import annotations

import secrets
from datetime import datetime
from typing import Optional

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.core.logging import get_logger
from app.models.order import Order, OrderItem, OrderStatus
from app.schemas.order import OrderCreate

logger = get_logger("app.services.orders")


# Timestamp fields stamped when an order enters each status.
_STATUS_STAMPS = {
    "CONFIRMED": "confirmed_at",
    "PREPARING": "preparing_at",
    "READY_FOR_PICKUP": "ready_at",
    "OUT_FOR_DELIVERY": "out_for_delivery_at",
    "DELIVERED": "delivered_at",
    "CANCELLED": "cancelled_at",
    "FAILED": "failed_at",
}

# Allowed forward transitions: current_status -> {allowed next statuses}.
_VALID_STATUS_TRANSITIONS: dict[str, set[str]] = {
    "PENDING": {"CONFIRMED", "CANCELLED", "FAILED"},
    "CONFIRMED": {"PREPARING", "CANCELLED"},
    "PREPARING": {"READY_FOR_PICKUP", "CANCELLED"},
    "READY_FOR_PICKUP": {"OUT_FOR_DELIVERY", "CANCELLED"},
    "OUT_FOR_DELIVERY": {"DELIVERED"},
    "DELIVERED": {"REFUNDED"},
    "CANCELLED": set(),
    "REFUNDED": set(),
    "FAILED": set(),
}


def _now() -> datetime:
    return datetime.now()


def _order_number(db: Session) -> str:
    """Generate a unique, human-friendly order number with a collision retry."""
    prefix = _now().strftime("%Y%m%d")
    for _ in range(5):
        number = f"ORD-{prefix}-{secrets.token_hex(4)}"
        exists = db.execute(select(func.count()).where(Order.order_number == number)).scalar() or 0
        if not exists:
            return number
    return f"ORD-{prefix}-{secrets.token_hex(6)}"


def create_order(db: Session, user_id: int, data: OrderCreate) -> Order:
    """Persist a customer checkout as an immutable order with snapshot line items."""
    subtotal = round(sum(i.quantity * i.price for i in data.items), 2)
    total = round(subtotal + data.delivery_fee + data.tax_amount - data.discount_amount, 2)
    if total < 0:
        raise ValueError("Computed order total must be non-negative")

    order = Order(
        order_number=_order_number(db),
        user_id=user_id,
        customer_id=None,
        shop_id=data.shop_id,
        subtotal_amount=subtotal,
        delivery_fee=data.delivery_fee,
        discount_amount=data.discount_amount,
        tax_amount=data.tax_amount,
        total_amount=total,
        total_items=sum(i.quantity for i in data.items),
        notes=data.notes,
        shipping_address_json=data.shipping_address_json,
        status=OrderStatus.PENDING.value,
        placed_at=_now(),
    )
    db.add(order)
    db.flush()  # assign order.id so line items can reference it

    for item in data.items:
        line_total = round(item.quantity * item.price, 2)
        db.add(
            OrderItem(
                order_id=order.id,
                product_master_id=item.product_master_id,
                product_name=item.product_name,
                variant_id=item.variant_id,
                variant_name=item.variant_name,
                shop_product_id=item.shop_product_id,
                quantity=item.quantity,
                price=item.price,
                total_price=line_total,
                image_url=item.image_url,
            )
        )

    db.commit()
    db.refresh(order)
    return order


def list_customer_orders(
    db: Session, user_id: int, page: int = 1, page_size: int = 20
) -> dict:
    """Paginated list of the customer's own orders, newest first."""
    offset = (page - 1) * page_size
    total = (
        db.execute(
            select(func.count()).where(
                Order.user_id == user_id,
                Order.is_deleted == False,  # noqa: E712
            )
        ).scalar()
        or 0
    )
    rows = (
        db.execute(
            select(Order)
            .where(
                Order.user_id == user_id,
                Order.is_deleted == False,  # noqa: E712
            )
            .order_by(Order.created_at.desc())
            .offset(offset)
            .limit(page_size)
        )
        .scalars()
        .unique()
        .all()
    )
    return {
        "orders": rows,
        "total": total,
        "page": page,
        "page_size": page_size,
        "has_next": len(rows) == page_size,
    }


def get_order(db: Session, order_id: int, user_id: int) -> Optional[Order]:
    """Fetch a single order owned by the given user (None if missing/other)."""
    order = db.get(Order, order_id)
    if order is None or order.is_deleted or order.user_id != user_id:
        return None
    return order


def cancel_order(
    db: Session, order_id: int, user_id: int, reason: Optional[str] = None
) -> Order:
    """Cancel a cancellable order owned by the user; refunds a paid order."""
    order = get_order(db, order_id, user_id)
    if order is None:
        raise ValueError("Order not found")
    if not order.is_cancellable:
        raise ValueError("Order can no longer be cancelled")
    order.status = OrderStatus.CANCELLED.value
    order.cancelled_at = _now()
    order.cancel_reason = reason
    if order.payment_status == "PAID":
        order.payment_status = "REFUNDED"
    db.commit()
    db.refresh(order)
    return order


def update_order_status(
    db: Session,
    order_id: int,
    status: str,
    note: Optional[str] = None,
    processed_by: Optional[int] = None,
) -> Optional[Order]:
    """Admin-driven status transition with forward-only transition guard."""
    order = db.get(Order, order_id)
    if order is None or order.is_deleted:
        return None
    current = order.status
    allowed = _VALID_STATUS_TRANSITIONS.get(current, set())
    if status not in allowed:
        raise ValueError(f"Cannot transition order from {current} to {status}")
    order.status = status
    stamp = _STATUS_STAMPS.get(status)
    if stamp:
        setattr(order, stamp, _now())
    if status == "CANCELLED" and processed_by is not None:
        order.cancelled_by = processed_by
        order.cancel_reason = note or order.cancel_reason
    db.commit()
    db.refresh(order)
    return order


def list_shop_orders(
    db: Session,
    shop_id: int,
    status: Optional[str] = None,
    page: int = 1,
    page_size: int = 20,
) -> dict:
    """Paginated orders for a shop, optionally filtered by status."""
    stmt = select(Order).where(
        Order.shop_id == shop_id,
        Order.is_deleted == False,  # noqa: E712
    )
    if status:
        stmt = stmt.where(Order.status == status)
    offset = (page - 1) * page_size
    total = (
        db.execute(
            select(func.count()).where(
                Order.shop_id == shop_id,
                Order.is_deleted == False,  # noqa: E712
            )
        ).scalar()
        or 0
    )
    rows = (
        db.execute(
            stmt.order_by(Order.created_at.desc()).offset(offset).limit(page_size)
        )
        .scalars()
        .unique()
        .all()
    )
    return {
        "orders": rows,
        "total": total,
        "page": page,
        "page_size": page_size,
        "has_next": len(rows) == page_size,
    }
