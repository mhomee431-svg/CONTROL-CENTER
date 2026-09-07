"""Shop Management System schemas for API serialization."""
from datetime import date, datetime, time
from typing import List, Optional
from pydantic import BaseModel, Field, ConfigDict

from app.models.shop import ShopCategory, ShopStatus, VerificationStatus


# ── Address ─────────────────────────────────────────────────────────────────
class ShopAddressCreate(BaseModel):
    address_line1: str = Field(..., min_length=1, max_length=255)
    address_line2: Optional[str] = Field(None, max_length=255)
    landmark: Optional[str] = Field(None, max_length=255)
    city: str = Field(..., min_length=1, max_length=100)
    state: str = Field(..., min_length=1, max_length=100)
    pincode: str = Field(..., min_length=3, max_length=10)
    country: str = Field("India", max_length=100)
    latitude: Optional[float] = Field(None, ge=-90, le=90)
    longitude: Optional[float] = Field(None, ge=-180, le=180)
    is_primary: bool = True


class ShopAddressUpdate(BaseModel):
    address_line1: Optional[str] = Field(None, min_length=1, max_length=255)
    address_line2: Optional[str] = Field(None, max_length=255)
    landmark: Optional[str] = Field(None, max_length=255)
    city: Optional[str] = Field(None, min_length=1, max_length=100)
    state: Optional[str] = Field(None, min_length=1, max_length=100)
    pincode: Optional[str] = Field(None, min_length=3, max_length=10)
    country: Optional[str] = Field(None, max_length=100)
    latitude: Optional[float] = Field(None, ge=-90, le=90)
    longitude: Optional[float] = Field(None, ge=-180, le=180)
    is_primary: Optional[bool] = None


class ShopAddressResponse(BaseModel):
    id: int
    shop_id: int
    address_line1: str
    address_line2: Optional[str] = None
    landmark: Optional[str] = None
    city: str
    state: str
    pincode: str
    country: str
    latitude: Optional[float] = None
    longitude: Optional[float] = None
    is_primary: bool
    is_verified: bool
    created_at: datetime
    updated_at: datetime

    model_config = ConfigDict(from_attributes=True)


# ── Hours ───────────────────────────────────────────────────────────────────
class ShopHourCreate(BaseModel):
    day_of_week: int = Field(..., ge=0, le=6)
    open_time: time
    close_time: time
    is_closed: bool = False


class ShopHourUpdate(BaseModel):
    open_time: Optional[time] = None
    close_time: Optional[time] = None
    is_closed: Optional[bool] = None


class ShopHourResponse(BaseModel):
    id: int
    shop_id: int
    day_of_week: int
    open_time: time
    close_time: time
    is_closed: bool
    created_at: datetime
    updated_at: datetime

    model_config = ConfigDict(from_attributes=True)


# ── Holidays ────────────────────────────────────────────────────────────────
class ShopHolidayCreate(BaseModel):
    holiday_date: date
    reason: Optional[str] = Field(None, max_length=255)
    is_recurring_yearly: bool = False


class ShopHolidayResponse(BaseModel):
    id: int
    shop_id: int
    holiday_date: date
    reason: Optional[str] = None
    is_recurring_yearly: bool
    created_at: datetime
    updated_at: datetime

    model_config = ConfigDict(from_attributes=True)


# ── Documents ───────────────────────────────────────────────────────────────
class ShopDocumentCreate(BaseModel):
    document_type: str = Field(..., min_length=1, max_length=50)
    document_url: str = Field(..., min_length=1, max_length=500)
    document_number: Optional[str] = Field(None, max_length=100)
    expires_at: Optional[datetime] = None


class ShopDocumentResponse(BaseModel):
    id: int
    shop_id: int
    document_type: str
    document_url: str
    document_number: Optional[str] = None
    expires_at: Optional[datetime] = None
    is_verified: bool
    verified_at: Optional[datetime] = None
    verified_by: Optional[int] = None
    rejection_reason: Optional[str] = None
    created_at: datetime
    updated_at: datetime

    model_config = ConfigDict(from_attributes=True)


# ── Owners ──────────────────────────────────────────────────────────────────
class ShopOwnerResponse(BaseModel):
    id: int
    shop_id: int
    user_id: int
    is_primary: bool
    is_active: bool
    created_at: datetime

    model_config = ConfigDict(from_attributes=True)


# ── Managers ────────────────────────────────────────────────────────────────
class ShopManagerCreate(BaseModel):
    user_id: int
    permissions: Optional[List[str]] = None


class ShopManagerResponse(BaseModel):
    id: int
    shop_id: int
    user_id: int
    permissions: Optional[str] = None
    is_active: bool
    created_at: datetime
    updated_at: datetime

    model_config = ConfigDict(from_attributes=True)


# ── Verification ────────────────────────────────────────────────────────────
class ShopVerificationResponse(BaseModel):
    id: int
    shop_id: int
    status: VerificationStatus
    submitted_by: Optional[int] = None
    reviewed_by: Optional[int] = None
    review_notes: Optional[str] = None
    submitted_at: Optional[datetime] = None
    reviewed_at: Optional[datetime] = None
    verified_at: Optional[datetime] = None
    expires_at: Optional[datetime] = None
    created_at: datetime
    updated_at: datetime

    model_config = ConfigDict(from_attributes=True)


# ── Shop ────────────────────────────────────────────────────────────────────
class ShopCreate(BaseModel):
    name: str = Field(..., min_length=1, max_length=255)
    slug: Optional[str] = Field(None, min_length=1, max_length=280)
    description: Optional[str] = None
    tagline: Optional[str] = Field(None, max_length=255)
    image_url: Optional[str] = Field(None, max_length=500)
    cover_image_url: Optional[str] = Field(None, max_length=500)
    logo_url: Optional[str] = Field(None, max_length=500)
    phone: Optional[str] = Field(None, max_length=20)
    alternate_phone: Optional[str] = Field(None, max_length=20)
    email: Optional[str] = Field(None, max_length=255)
    website_url: Optional[str] = Field(None, max_length=500)
    whatsapp_number: Optional[str] = Field(None, max_length=20)
    category: Optional[ShopCategory] = None
    subcategories: Optional[List[str]] = None
    latitude: float = Field(..., ge=-90, le=90)
    longitude: float = Field(..., ge=-180, le=180)
    is_open_24x7: bool = False
    is_accepting_orders: bool = True
    min_order_amount: Optional[float] = Field(None, ge=0)
    delivery_radius_km: Optional[float] = Field(None, ge=0, le=100)
    delivery_fee: Optional[float] = Field(None, ge=0)
    free_delivery_above: Optional[float] = Field(None, ge=0)
    is_delivery_available: bool = True
    is_pickup_available: bool = True
    gstin: Optional[str] = Field(None, max_length=50)
    fssai_license: Optional[str] = Field(None, max_length=50)
    established_year: Optional[int] = Field(None, ge=1900, le=2100)
    address: ShopAddressCreate
    hours: Optional[List[ShopHourCreate]] = None


class ShopUpdate(BaseModel):
    name: Optional[str] = Field(None, min_length=1, max_length=255)
    slug: Optional[str] = Field(None, min_length=1, max_length=280)
    description: Optional[str] = None
    tagline: Optional[str] = Field(None, max_length=255)
    image_url: Optional[str] = Field(None, max_length=500)
    cover_image_url: Optional[str] = Field(None, max_length=500)
    logo_url: Optional[str] = Field(None, max_length=500)
    phone: Optional[str] = Field(None, max_length=20)
    alternate_phone: Optional[str] = Field(None, max_length=20)
    email: Optional[str] = Field(None, max_length=255)
    website_url: Optional[str] = Field(None, max_length=500)
    whatsapp_number: Optional[str] = Field(None, max_length=20)
    category: Optional[ShopCategory] = None
    subcategories: Optional[List[str]] = None
    latitude: Optional[float] = Field(None, ge=-90, le=90)
    longitude: Optional[float] = Field(None, ge=-180, le=180)
    is_open_24x7: Optional[bool] = None
    is_accepting_orders: Optional[bool] = None
    min_order_amount: Optional[float] = Field(None, ge=0)
    delivery_radius_km: Optional[float] = Field(None, ge=0, le=100)
    delivery_fee: Optional[float] = Field(None, ge=0)
    free_delivery_above: Optional[float] = Field(None, ge=0)
    is_delivery_available: Optional[bool] = None
    is_pickup_available: Optional[bool] = None
    gstin: Optional[str] = Field(None, max_length=50)
    fssai_license: Optional[str] = Field(None, max_length=50)
    established_year: Optional[int] = Field(None, ge=1900, le=2100)


class ShopResponse(BaseModel):
    id: int
    name: str
    slug: Optional[str] = None
    description: Optional[str] = None
    tagline: Optional[str] = None
    image_url: Optional[str] = None
    cover_image_url: Optional[str] = None
    logo_url: Optional[str] = None
    phone: Optional[str] = None
    alternate_phone: Optional[str] = None
    email: Optional[str] = None
    website_url: Optional[str] = None
    whatsapp_number: Optional[str] = None
    status: ShopStatus
    rating: float
    review_count: int
    is_verified: bool
    is_featured: bool
    is_open_24x7: bool
    is_accepting_orders: bool
    category: Optional[ShopCategory] = None
    subcategories: Optional[str] = None
    latitude: Optional[float] = None
    longitude: Optional[float] = None
    verified_at: Optional[datetime] = None
    rejection_reason: Optional[str] = None
    suspension_reason: Optional[str] = None
    suspended_at: Optional[datetime] = None
    reactivated_at: Optional[datetime] = None
    closed_at: Optional[datetime] = None
    min_order_amount: Optional[float] = None
    delivery_radius_km: Optional[float] = None
    delivery_fee: Optional[float] = None
    free_delivery_above: Optional[float] = None
    is_delivery_available: bool
    is_pickup_available: bool
    gstin: Optional[str] = None
    fssai_license: Optional[str] = None
    established_year: Optional[int] = None
    created_at: datetime
    updated_at: datetime

    model_config = ConfigDict(from_attributes=True)


class ShopDetailResponse(ShopResponse):
    """Full shop profile with nested relationships."""
    addresses: List[ShopAddressResponse] = []
    hours: List[ShopHourResponse] = []
    holidays: List[ShopHolidayResponse] = []
    documents: List[ShopDocumentResponse] = []
    owners: List[ShopOwnerResponse] = []
    managers: List[ShopManagerResponse] = []
    verifications: List[ShopVerificationResponse] = []


class ShopPublicResponse(BaseModel):
    """Customer-facing shop profile (only visible/verified info)."""
    id: int
    name: str
    slug: Optional[str] = None
    description: Optional[str] = None
    tagline: Optional[str] = None
    image_url: Optional[str] = None
    cover_image_url: Optional[str] = None
    logo_url: Optional[str] = None
    phone: Optional[str] = None
    whatsapp_number: Optional[str] = None
    rating: float
    review_count: int
    is_verified: bool
    is_featured: bool
    is_open_24x7: bool
    is_accepting_orders: bool
    category: Optional[ShopCategory] = None
    subcategories: Optional[str] = None
    latitude: Optional[float] = None
    longitude: Optional[float] = None
    min_order_amount: Optional[float] = None
    delivery_radius_km: Optional[float] = None
    delivery_fee: Optional[float] = None
    free_delivery_above: Optional[float] = None
    is_delivery_available: bool
    is_pickup_available: bool
    established_year: Optional[int] = None
    addresses: List[ShopAddressResponse] = []
    hours: List[ShopHourResponse] = []
    holidays: List[ShopHolidayResponse] = []
    is_open_now: bool = False
    distance_km: Optional[float] = None
    created_at: datetime
    updated_at: datetime

    model_config = ConfigDict(from_attributes=True)


class NearbyShopResponse(BaseModel):
    id: int
    name: str
    image_url: Optional[str] = None
    distance_km: float
    rating: float
    is_verified: bool
    category: Optional[ShopCategory] = None
    is_open_now: bool = False


class ShopProductSummarySchema(BaseModel):
    product_id: int
    name: str
    image_url: Optional[str] = None
    price: float
    is_available: bool
    stock_status: str


# ── Admin verification ──────────────────────────────────────────────────────
class ShopVerificationReview(BaseModel):
    decision: str = Field(..., pattern="^(APPROVE|REJECT|SUSPEND|REACTIVATE)$")
    review_notes: Optional[str] = None


class ShopStatusUpdate(BaseModel):
    status: ShopStatus
    reason: Optional[str] = None