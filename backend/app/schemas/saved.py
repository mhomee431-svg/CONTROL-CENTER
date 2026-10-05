from datetime import datetime
from typing import List
from pydantic import BaseModel


class SavedProductResponse(BaseModel):
    product_id: int
    name: str
    brand: str | None
    lowest_price: float | None
    image_url: str | None
    saved_at: datetime


class SavedShopResponse(BaseModel):
    shop_id: int
    name: str
    address: str | None
    image_url: str | None
    rating: float
    saved_at: datetime

    # ── Discovery-card fields ──────────────────────────────────────────────
    #
    # Saved Shops is a DISCOVERY surface, not a plain bookmark list, so its rows
    # carry the same fields as Nearby and Category shops: the shared customer
    # card renders distance, verification and open/closed, and it can only do
    # that if this payload supplies them.
    #
    # All four are optional with defaults because they are only known when the
    # customer's coordinates are known (distance) or the shop row has the data.
    # `is_open_now` stays None rather than False when unreported — the app
    # renders no badge for "not reported", and must never be told "Closed" by a
    # serialization default.
    distance_km: float | None = None
    is_verified: bool = False
    is_open_now: bool | None = None
    is_accepting_orders: bool | None = None


class SavedProductListResponse(BaseModel):
    items: List[SavedProductResponse] = []


class SavedShopListResponse(BaseModel):
    items: List[SavedShopResponse] = []