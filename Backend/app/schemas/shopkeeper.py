"""Phase 22/23 — Pydantic schemas for the Shopkeeper App API."""

from datetime import datetime

from pydantic import BaseModel, Field


# ── Auth ─────────────────────────────────────────────────────────────────
class ShopkeeperSendOTPRequest(BaseModel):
    phone_number: str = Field(..., min_length=10, max_length=15)


class ShopkeeperRegisterRequest(BaseModel):
    """First-time shopkeeper registration (phone + OTP + display name)."""

    phone_number: str = Field(..., min_length=10, max_length=15)
    otp: str = Field(..., min_length=4, max_length=8)
    name: str = Field(..., min_length=1, max_length=100)
    email: str | None = Field(None, max_length=255)
    device_id: str | None = Field(None, description="Stable device identifier")
    device_name: str | None = None
    device_type: str | None = Field(None, description="android, ios, web")
    platform: str | None = None
    app_version: str | None = None


class ShopkeeperLoginRequest(BaseModel):
    """OTP login for an EXISTING account (any role) via the Shopkeeper App."""

    phone_number: str = Field(..., min_length=10, max_length=15)
    otp: str = Field(..., min_length=4, max_length=8)
    device_id: str | None = None
    device_name: str | None = None
    device_type: str | None = None
    platform: str | None = None
    app_version: str | None = None


class ShopkeeperRefreshRequest(BaseModel):
    refresh_token: str
    device_id: str | None = None


class ShopkeeperLogoutRequest(BaseModel):
    session_id: str | None = None
    revoke_all: bool = False


# ── Shop registration / profile / settings ───────────────────────────────
class ShopAddressInput(BaseModel):
    address_line1: str = Field(..., min_length=1, max_length=255)
    address_line2: str | None = Field(None, max_length=255)
    landmark: str | None = Field(None, max_length=255)
    city: str = Field(..., min_length=1, max_length=100)
    state: str = Field(..., min_length=1, max_length=100)
    pincode: str = Field(..., min_length=3, max_length=10)
    country: str | None = Field("India", max_length=100)


class ShopkeeperShopCreate(BaseModel):
    name: str = Field(..., min_length=1, max_length=255)
    description: str | None = None
    tagline: str | None = Field(None, max_length=255)
    category: str | None = Field(None, max_length=50)
    phone: str | None = Field(None, max_length=20)
    whatsapp_number: str | None = Field(None, max_length=20)
    email: str | None = Field(None, max_length=255)
    image_url: str | None = Field(None, max_length=500)
    latitude: float = Field(..., ge=-90, le=90)
    longitude: float = Field(..., ge=-180, le=180)
    gstin: str | None = Field(None, max_length=50)
    address: ShopAddressInput


class ShopkeeperProfileUpdate(BaseModel):
    """Editable shop profile fields (whitelist enforced in service)."""

    name: str | None = Field(None, min_length=1, max_length=255)
    description: str | None = None
    tagline: str | None = Field(None, max_length=255)
    phone: str | None = Field(None, max_length=20)
    alternate_phone: str | None = Field(None, max_length=20)
    whatsapp_number: str | None = Field(None, max_length=20)
    email: str | None = Field(None, max_length=255)
    website_url: str | None = Field(None, max_length=500)
    image_url: str | None = Field(None, max_length=500)
    logo_url: str | None = Field(None, max_length=500)
    # Phase 7 — signed-upload integration: pass the server-minted object key
    # returned by POST /media/confirm. Validated (category + ownership +
    # existence) and converted to a durable s3:// storage reference.
    image_key: str | None = Field(None, max_length=512)
    logo_key: str | None = Field(None, max_length=512)


class ShopkeeperSettingsUpdate(BaseModel):
    """Operational settings toggles for a shop."""

    is_accepting_orders: bool | None = None
    is_delivery_available: bool | None = None
    is_pickup_available: bool | None = None
    is_open_24x7: bool | None = None
    min_order_amount: float | None = Field(None, ge=0)
    delivery_radius_km: float | None = Field(None, ge=0, le=100)
    delivery_fee: float | None = Field(None, ge=0)
    free_delivery_above: float | None = Field(None, ge=0)


# ── Products ─────────────────────────────────────────────────────────────
class ShopkeeperProductCreate(BaseModel):
    name: str = Field(..., min_length=1, max_length=255)
    description: str | None = None
    brand_name: str | None = Field(None, max_length=120)
    unit: str | None = Field(None, max_length=50)
    price: float = Field(..., ge=0)
    mrp: float | None = Field(None, ge=0)
    sku: str | None = Field(None, max_length=100)
    quantity: int = Field(0, ge=0)
    low_stock_threshold: int = Field(5, ge=0)
    is_available: bool = True
    publish: bool = Field(False, description="Publish immediately (APPROVED) vs keep as DRAFT")
    # Phase 7 — PRODUCT_IMAGE object key from POST /media/confirm.
    image_key: str | None = Field(None, max_length=512)


class ShopkeeperProductUpdate(BaseModel):
    price: float | None = Field(None, ge=0)
    mrp: float | None = Field(None, ge=0)
    quantity: int | None = Field(None, ge=0)
    low_stock_threshold: int | None = Field(None, ge=0)
    is_available: bool | None = None
    is_featured: bool | None = None
    status: str | None = Field(None, max_length=30)
    # Phase 7 — replace the product image with a confirmed PRODUCT_IMAGE key.
    image_key: str | None = Field(None, max_length=512)


# ── Phase 23 — Inventory management ──────────────────────────────────────
class ShopkeeperAddFromMaster(BaseModel):
    """Add an EXISTING product-master record (optionally a variant) to a shop.

    Shopkeepers must select from the platform catalog — arbitrary duplicate
    product-master creation is not allowed through this endpoint.
    """

    product_master_id: int
    variant_id: int | None = None
    price: float = Field(..., ge=0, description="Shop selling price")
    mrp: float | None = Field(None, ge=0)
    sku: str | None = Field(None, max_length=100)
    quantity: int = Field(0, ge=0)
    low_stock_threshold: int = Field(5, ge=0)
    is_available: bool = True


class ShopkeeperStockAdjustment(BaseModel):
    """Delta stock adjustment with audit trail (type + reason)."""

    adjustment_type: str = Field("CORRECTION", max_length=50)
    quantity_adjustment: int = Field(
        ..., description="Delta units (+restock / -damage); result must stay >= 0"
    )
    reason: str | None = Field(None, max_length=255)


class ShopkeeperBulkOperation(BaseModel):
    """Bulk operations foundation: apply one change to many shop products."""

    operation: str = Field(..., description="price_update | stock_set | availability")
    shop_product_ids: list[int] = Field(..., min_length=1, max_length=200)
    price: float | None = Field(None, ge=0)
    mrp: float | None = Field(None, ge=0)
    quantity: int | None = Field(None, ge=0)
    is_available: bool | None = None


class ShopkeeperOfferAssign(BaseModel):
    """Assign (create + link) an offer to selected shop products."""

    title: str = Field(..., min_length=1, max_length=255)
    offer_type: str = Field(..., max_length=40)
    discount_value: float | None = Field(None, ge=0)
    discount_percentage: float | None = Field(None, gt=0, le=100)
    start_date: datetime
    end_date: datetime
    shop_product_ids: list[int] = Field(..., min_length=1, max_length=200)
    terms_conditions: str | None = None
