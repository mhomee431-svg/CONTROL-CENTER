from typing import List, Optional
from pydantic import BaseModel
from datetime import datetime


class SearchSuggestionSchema(BaseModel):
    text: str
    is_category: bool = False
    is_brand: bool = False


class ShopProductResultSchema(BaseModel):
    id: str
    product_id: int
    product_name: str
    product_image_url: Optional[str]
    shop_id: int
    shop_name: str
    price: float
    mrp: Optional[float] = None
    is_available: bool
    stock_status: str
    freshness_status: Optional[str] = None
    distance_km: float
    shop_rating: float
    last_updated: datetime
    offer_text: Optional[str] = None


class SearchResponse(BaseModel):
    results: List[ShopProductResultSchema]
    page: int
    limit: int
    has_more: bool
    total: int