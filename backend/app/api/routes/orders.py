"""Orders API routes - Master Spec ??30-32.

Customer-facing checkout/order history endpoints plus the admin status
and shop-order endpoints. Mirrors reviews.py: customer routes use
``get_current_user``; admin routes use ``dependencies=[Depends(require_admin)]``.
"""
from typing import Optional

from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session

from app.core.dependencies import get_current_user, require_admin
from app.core.responses import error_response, success_response
from app.database.session import get_db
from app.models.order import Order
from app.schemas.order import (
    OrderCreate,
    OrderListResponse,
    OrderResponse,
    OrderStatusUpdate,
)
from app.services import order_service

router = APIRouter(prefix="/orders", tags=["orders"])


def _order_out(order: Order) -> dict:
    """Serialize an Order (with nested items) to a JSON-able dict."""
    return OrderResponse.model_validate(order).model_dump(mode="json")


def _list_out(result: dict) -> dict:
    return OrderListResponse(
        orders=[OrderResponse.model_validate(o) for o in result["orders"]],
        total=result["total"],
        page=result["page"],
        page_size=result["page_size"],
        has_next=result["has_next"],
    ).model_dump(mode="json")


# --- Customer-facing endpoints -------------------------------------------------
@router.post("")
async def create_order_route(
    data: OrderCreate,
    db: Session = Depends(get_db),
    current_user=Depends(get_current_user),
):
    """Place a customer checkout order against a shop."""
    try:
        order = order_service.create_order(db=db, user_id=current_user.id, data=data)
    except ValueError as exc:
        return error_response(
            message=str(exc), error_code="ORDER_CREATE_FAILED", status_code=400
        )
    return success_response(data=_order_out(order), message="Order placed", status_code=201)


@router.get("")
async def list_orders_route(
    page: int = Query(1, ge=1),
    page_size: int = Query(20, ge=1, le=50),
    db: Session = Depends(get_db),
    current_user=Depends(get_current_user),
):
    """Paginated list of the current customer's orders."""
    result = order_service.list_customer_orders(
        db, user_id=current_user.id, page=page, page_size=page_size
    )
    return success_response(data=_list_out(result))


@router.get("/{order_id}")
async def get_order_route(
    order_id: int,
    db: Session = Depends(get_db),
    current_user=Depends(get_current_user),
):
    """Fetch one of the current customer's orders."""
    order = order_service.get_order(db, order_id=order_id, user_id=current_user.id)
    if order is None:
        return error_response(
            message="Order not found", error_code="ORDER_NOT_FOUND", status_code=404
        )
    return success_response(data=_order_out(order))


@router.post("/{order_id}/cancel")
async def cancel_order_route(
    order_id: int,
    note: Optional[str] = Query(None, max_length=1000),
    db: Session = Depends(get_db),
    current_user=Depends(get_current_user),
):
    """Cancel one of the current customer's orders."""
    existing = order_service.get_order(db, order_id=order_id, user_id=current_user.id)
    if existing is None:
        return error_response(
            message="Order not found", error_code="ORDER_NOT_FOUND", status_code=404
        )
    try:
        order = order_service.cancel_order(
            db, order_id=order_id, user_id=current_user.id, reason=note
        )
    except ValueError:
        return error_response(
            message="Order can no longer be cancelled",
            error_code="ORDER_NOT_CANCELABLE",
            status_code=409,
        )
    return success_response(data=_order_out(order), message="Order cancelled")


# --- Shopkeeper / admin endpoints ---------------------------------------------
@router.get("/shop/{shop_id}", dependencies=[Depends(require_admin)])
async def list_shop_orders_route(
    shop_id: int,
    status: Optional[str] = Query(None),
    page: int = Query(1, ge=1),
    page_size: int = Query(20, ge=1, le=50),
    db: Session = Depends(get_db),
):
    """List orders for a shop (admin only)."""
    result = order_service.list_shop_orders(
        db, shop_id=shop_id, status=status, page=page, page_size=page_size
    )
    return success_response(data=_list_out(result))


@router.post("/{order_id}/status", dependencies=[Depends(require_admin)])
async def update_order_status_route(
    order_id: int,
    data: OrderStatusUpdate,
    db: Session = Depends(get_db),
):
    """Admin transition of an order to a new status."""
    try:
        order = order_service.update_order_status(
            db,
            order_id=order_id,
            status=data.status,
            note=data.note,
            processed_by=data.processed_by,
        )
    except ValueError as exc:
        return error_response(
            message=str(exc), error_code="ORDER_STATUS_INVALID", status_code=409
        )
    if order is None:
        return error_response(
            message="Order not found", error_code="ORDER_NOT_FOUND", status_code=404
        )
    return success_response(data=_order_out(order), message="Order status updated")
