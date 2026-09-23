"""Orders schemas - Master Spec SS 30-32."""
from __future__ import annotations

from datetime import datetime
from typing import Optional

from pydantic import BaseModel, ConfigDict, Field


class OrderItemCreate(BaseModel):
    """Line item as captured by the customer cart at checkout (price snapshot)."""

    product_master_id: int = Field(..., description="Catalog product master id (snapshot at checkout)")
    product_name: str = Field(..., max_length=255)
    variant_id: Optional[int] = Field(None, description="Variant id if applicable")
    variant_name: Optional[str] = Field(None, max_length=255)
    shop_product_id: Optional[int] = Field(None, description="Shop-specific product row")
    quantity: int = Field(..., ge=1)
    price: float = Field(..., ge=0, description="Unit price snapshot")
    image_url: Optional[str] = Field(None, max_length=500)

    model_config = ConfigDict(from_attributes=True)


class OrderCreate(BaseModel):
    """A customer checkout against a single shop."""

    shop_id: int = Field(..., description="Shop the order is placed against")
    shipping_address_json: Optional[str] = Field(None, description="Snapshot of the chosen address")
    notes: Optional[str] = Field(None, max_length=2000)
    delivery_fee: float = Field(0, ge=0)
    discount_amount: float = Field(0, ge=0)
    tax_amount: float = Field(0, ge=0)
    items: list[OrderItemCreate] = Field(..., min_length=1)

    model_config = ConfigDict(from_attributes=True)

    @property
    def computed_subtotal(self) -> float:
        return sum(i.quantity * i.price for i in self.items)

    @property
    def computed_total(self) -> float:
        return round(
            self.computed_subtotal + self.delivery_fee + self.tax_amount - self.discount_amount,
            2,
        )


class OrderStatusUpdate(BaseModel):
    """Admin transition of an order to a new status."""

    status: str = Field(..., description="Target OrderStatus value")
    note: Optional[str] = Field(None, max_length=1000)
    processed_by: Optional[int] = Field(None)

    model_config = ConfigDict(from_attributes=True)


class OrderItemResponse(BaseModel):
    id: int
    order_id: int
    product_master_id: int
    product_name: str
    variant_id: Optional[int] = None
    variant_name: Optional[str] = None
    shop_product_id: Optional[int] = None
    quantity: int
    price: float
    total_price: float
    image_url: Optional[str] = None
    item_status: str

    model_config = ConfigDict(from_attributes=True)


class OrderResponse(BaseModel):
    id: int
    order_number: str
    user_id: int
    customer_id: Optional[int] = None
    shop_id: int
    status: str
    payment_method: Optional[str] = None
    payment_status: str
    currency: str
    subtotal_amount: float
    delivery_fee: float
    discount_amount: float
    tax_amount: float
    total_amount: float
    total_items: int
    notes: Optional[str] = None
    shipping_address_json: Optional[str] = None
    placed_at: Optional[datetime] = None
    confirmed_at: Optional[datetime] = None
    preparing_at: Optional[datetime] = None
    ready_at: Optional[datetime] = None
    out_for_delivery_at: Optional[datetime] = None
    delivered_at: Optional[datetime] = None
    cancelled_at: Optional[datetime] = None
    cancelled_by: Optional[int] = None
    cancel_reason: Optional[str] = None
    created_at: datetime
    updated_at: datetime
    items: list[OrderItemResponse] = []

    model_config = ConfigDict(from_attributes=True)


class OrderListResponse(BaseModel):
    orders: list[OrderResponse] = []
    total: int
    page: int
    page_size: int
    has_next: bool

    model_config = ConfigDict(from_attributes=True)
