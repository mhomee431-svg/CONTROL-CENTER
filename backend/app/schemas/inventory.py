"""Inventory and Pricing Engine schemas for API serialization."""
from datetime import datetime
from typing import List, Optional
from pydantic import BaseModel, Field, ConfigDict

from app.models.product import (
    CustomerStockStatus,
    FreshnessStatus,
    InventorySource,
    OfferStatus,
    OfferType,
    StockStatus,
)


# ── Inventory ───────────────────────────────────────────────────────────────
class InventoryCreate(BaseModel):
    """Create or update inventory for a shop product."""
    shop_product_id: int
    quantity: int = Field(0, ge=0)
    reserved_quantity: int = Field(0, ge=0)
    low_stock_threshold: Optional[int] = Field(None, ge=0)
    is_available: bool = True
    source: InventorySource = InventorySource.MANUAL
    notes: Optional[str] = None
    created_by: Optional[int] = None


class InventoryUpdate(BaseModel):
    """Update inventory fields."""
    quantity: Optional[int] = Field(None, ge=0)
    reserved_quantity: Optional[int] = Field(None, ge=0)
    low_stock_threshold: Optional[int] = Field(None, ge=0)
    is_available: Optional[bool] = None
    source: Optional[InventorySource] = None
    notes: Optional[str] = None
    created_by: Optional[int] = None


class InventoryResponse(BaseModel):
    id: int
    shop_product_id: int
    quantity: int
    reserved_quantity: int
    available_quantity: int
    is_available: bool
    stock_status: StockStatus
    low_stock_threshold: Optional[int] = None
    last_updated_by: Optional[int] = None
    last_updated_source: InventorySource
    last_synced_at: Optional[datetime] = None
    freshness_status: Optional[FreshnessStatus] = None
    freshness_checked_at: Optional[datetime] = None
    created_at: datetime
    updated_at: datetime

    model_config = ConfigDict(from_attributes=True)


# ── Inventory Movement ──────────────────────────────────────────────────────
class InventoryMovementCreate(BaseModel):
    inventory_id: int
    quantity_change: int
    movement_type: str = Field(..., min_length=1, max_length=50)
    source: InventorySource = InventorySource.MANUAL
    reference_type: Optional[str] = Field(None, max_length=50)
    reference_id: Optional[int] = None
    notes: Optional[str] = None
    created_by: Optional[int] = None


class InventoryMovementResponse(BaseModel):
    id: int
    inventory_id: int
    quantity_change: int
    quantity_before: int
    quantity_after: int
    movement_type: str
    source: InventorySource
    reference_type: Optional[str] = None
    reference_id: Optional[int] = None
    notes: Optional[str] = None
    created_by: Optional[int] = None
    created_at: datetime

    model_config = ConfigDict(from_attributes=True)


# ── Inventory Adjustment ────────────────────────────────────────────────────
class InventoryAdjustmentCreate(BaseModel):
    inventory_id: int
    adjustment_type: str = Field(..., min_length=1, max_length=50)
    quantity_adjustment: int
    reason: Optional[str] = None
    approved_by: Optional[int] = None


class InventoryAdjustmentResponse(BaseModel):
    id: int
    inventory_id: int
    adjustment_type: str
    quantity_adjustment: int
    reason: Optional[str] = None
    approved_by: Optional[int] = None
    approved_at: Optional[datetime] = None
    created_at: datetime

    model_config = ConfigDict(from_attributes=True)


# ── Price History ───────────────────────────────────────────────────────────
class PriceUpdate(BaseModel):
    """Update the selling price (and optionally MRP) of a shop product."""
    new_price: float = Field(..., ge=0)
    new_mrp: Optional[float] = Field(None, ge=0)
    change_source: InventorySource = InventorySource.MANUAL
    changed_by: Optional[int] = None


class PriceHistoryResponse(BaseModel):
    id: int
    shop_product_id: int
    old_price: float
    new_price: float
    old_mrp: Optional[float] = None
    new_mrp: Optional[float] = None
    changed_by: Optional[int] = None
    change_source: InventorySource
    effective_from: datetime
    effective_to: Optional[datetime] = None
    created_at: datetime

    model_config = ConfigDict(from_attributes=True)


# ── Offers ──────────────────────────────────────────────────────────────────
class OfferConditionCreate(BaseModel):
    condition_type: str = Field(..., min_length=1, max_length=50)
    condition_value: str = Field(..., min_length=1, max_length=255)
    operator: Optional[str] = Field(None, max_length=20)


class OfferProductMapping(BaseModel):
    shop_product_id: int
    is_excluded: bool = False


class OfferCreate(BaseModel):
    shop_id: int
    title: str = Field(..., min_length=1, max_length=255)
    description: Optional[str] = None
    offer_type: OfferType
    discount_value: Optional[float] = Field(None, ge=0)
    discount_percentage: Optional[float] = Field(None, ge=0, le=100)
    promotional_price: Optional[float] = Field(None, ge=0)
    min_purchase_amount: Optional[float] = Field(None, ge=0)
    max_discount_amount: Optional[float] = Field(None, ge=0)
    buy_quantity: Optional[int] = Field(None, ge=1)
    get_quantity: Optional[int] = Field(None, ge=1)
    start_date: datetime
    end_date: datetime
    is_visible: bool = True
    terms_conditions: Optional[str] = None
    product_mappings: List[OfferProductMapping] = []
    conditions: List[OfferConditionCreate] = []


class OfferUpdate(BaseModel):
    title: Optional[str] = Field(None, min_length=1, max_length=255)
    description: Optional[str] = None
    offer_type: Optional[OfferType] = None
    discount_value: Optional[float] = Field(None, ge=0)
    discount_percentage: Optional[float] = Field(None, ge=0, le=100)
    promotional_price: Optional[float] = Field(None, ge=0)
    min_purchase_amount: Optional[float] = Field(None, ge=0)
    max_discount_amount: Optional[float] = Field(None, ge=0)
    buy_quantity: Optional[int] = Field(None, ge=1)
    get_quantity: Optional[int] = Field(None, ge=1)
    start_date: Optional[datetime] = None
    end_date: Optional[datetime] = None
    is_visible: Optional[bool] = None
    terms_conditions: Optional[str] = None
    status: Optional[OfferStatus] = None


class OfferConditionResponse(BaseModel):
    id: int
    offer_id: int
    condition_type: str
    condition_value: str
    operator: Optional[str] = None
    created_at: datetime

    model_config = ConfigDict(from_attributes=True)


class OfferProductResponse(BaseModel):
    id: int
    offer_id: int
    shop_product_id: int
    is_excluded: bool
    created_at: datetime

    model_config = ConfigDict(from_attributes=True)


class OfferResponse(BaseModel):
    id: int
    shop_id: int
    title: str
    description: Optional[str] = None
    offer_type: OfferType
    discount_value: Optional[float] = None
    discount_percentage: Optional[float] = None
    promotional_price: Optional[float] = None
    min_purchase_amount: Optional[float] = None
    max_discount_amount: Optional[float] = None
    buy_quantity: Optional[int] = None
    get_quantity: Optional[int] = None
    status: OfferStatus
    start_date: datetime
    end_date: datetime
    is_visible: bool
    terms_conditions: Optional[str] = None
    created_at: datetime
    updated_at: datetime

    model_config = ConfigDict(from_attributes=True)


class OfferDetailResponse(OfferResponse):
    """Offer with nested product mappings and conditions."""
    product_mappings: List[OfferProductResponse] = []
    conditions: List[OfferConditionResponse] = []


# ── Customer-facing inventory / freshness ───────────────────────────────────
class CustomerInventoryDetail(BaseModel):
    """Customer-facing inventory detail returned by search / product detail."""
    shop_product_id: int
    shop_id: int
    shop_name: str
    product_id: int
    product_name: str
    product_image_url: Optional[str] = None
    sku: Optional[str] = None
    price: float
    mrp: Optional[float] = None
    is_available: bool
    stock_status: CustomerStockStatus
    freshness_status: Optional[FreshnessStatus] = None
    last_updated: Optional[datetime] = None
    distance_km: float = 0.0
    shop_rating: float = 0.0
    offer_text: Optional[str] = None


class CustomerInventoryResponse(BaseModel):
    product_id: int
    items: List[CustomerInventoryDetail] = []


# ── Shop inventory ──────────────────────────────────────────────────────────
class ShopInventoryItemResponse(BaseModel):
    id: int
    shop_product_id: int
    product_id: int
    product_name: str
    sku: Optional[str] = None
    price: float
    mrp: Optional[float] = None
    quantity: int
    is_available: bool
    stock_status: StockStatus
    freshness_status: Optional[FreshnessStatus] = None
    last_updated: Optional[datetime] = None
    source: InventorySource

    model_config = ConfigDict(from_attributes=True)


class ShopInventoryResponse(BaseModel):
    shop_id: int
    items: List[ShopInventoryItemResponse] = []
