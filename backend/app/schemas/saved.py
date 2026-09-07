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


class SavedProductListResponse(BaseModel):
    items: List[SavedProductResponse] = []


class SavedShopListResponse(BaseModel):
    items: List[SavedShopResponse] = []