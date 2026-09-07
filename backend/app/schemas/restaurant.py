"""Restaurant Discovery schemas — Master Spec §27 (Rule 4: discovery-only domain)."""


from datetime import datetime

from pydantic import BaseModel, Field, ConfigDict


# ── Restaurant ──────────────────────────────────────────────────────────────
class RestaurantCreate(BaseModel):
    shop_id: int = Field(..., description="Existing shop ID (must be RESTAURANT category)")
    cuisine_types: list[str] | None = None
    dining_available: bool = True
    takeaway_available: bool = True
    avg_cost_for_two: float | None = Field(None, ge=0)
    veg_only: bool = False
    licence_fssai: str | None = Field(None, max_length=50)


class RestaurantUpdate(BaseModel):
    cuisine_types: list[str] | None = None
    dining_available: bool | None = None
    takeaway_available: bool | None = None
    avg_cost_for_two: float | None = Field(None, ge=0)
    veg_only: bool | None = None
    licence_fssai: str | None = Field(None, max_length=50)


class RestaurantResponse(BaseModel):
    id: int
    shop_id: int
    cuisine_types: list[str] | None = None
    dining_available: bool
    takeaway_available: bool
    avg_cost_for_two: float | None = None
    is_open_now_calc: bool
    rating: float = 0.0
    review_count: int = 0
    veg_only: bool
    licence_fssai: str | None = None
    created_at: datetime
    updated_at: datetime

    model_config = ConfigDict(from_attributes=True)


class RestaurantListResponse(BaseModel):
    id: int
    shop_id: int
    name: str
    cuisine_types: list[str] | None = None
    dining_available: bool
    takeaway_available: bool
    avg_cost_for_two: float | None = None
    rating: float = 0.0
    review_count: int = 0
    veg_only: bool
    distance_km: float | None = None

    model_config = ConfigDict(from_attributes=True)


class RestaurantDetailResponse(BaseModel):
    id: int
    shop_id: int
    name: str
    description: str | None = None
    cuisine_types: list[str] | None = None
    dining_available: bool
    takeaway_available: bool
    avg_cost_for_two: float | None = None
    rating: float = 0.0
    review_count: int = 0
    veg_only: bool
    licence_fssai: str | None = None
    phone: str | None = None
    address: str | None = None
    latitude: float | None = None
    longitude: float | None = None
    distance_km: float | None = None
    menu_categories: list["RestaurantMenuCategoryResponse"] = []

    model_config = ConfigDict(from_attributes=True)


# ── Menu Categories ────────────────────────────────────────────────────────
class RestaurantMenuCategoryCreate(BaseModel):
    name: str = Field(..., min_length=1, max_length=120)
    description: str | None = None
    sort_order: int = 0


class RestaurantMenuCategoryResponse(BaseModel):
    id: int
    restaurant_id: int
    name: str
    description: str | None = None
    sort_order: int
    is_active: bool
    items: list["RestaurantMenuItemResponse"] = []
    created_at: datetime
    updated_at: datetime

    model_config = ConfigDict(from_attributes=True)


# ── Menu Items ─────────────────────────────────────────────────────────────
class RestaurantMenuItemCreate(BaseModel):
    name: str = Field(..., min_length=1, max_length=255)
    description: str | None = None
    price: float | None = Field(None, ge=0)
    menu_category_id: int | None = None
    veg: bool = False
    spicy: bool = False
    is_available_today: bool = True
    sort_order: int = 0


class RestaurantMenuItemResponse(BaseModel):
    id: int
    restaurant_id: int
    menu_category_id: int | None = None
    name: str
    description: str | None = None
    price: float | None = None
    veg: bool
    spicy: bool
    is_available_today: bool
    sort_order: int
    is_active: bool
    created_at: datetime
    updated_at: datetime

    model_config = ConfigDict(from_attributes=True)


