from datetime import datetime
from typing import List, Optional

from pydantic import BaseModel


# ── V2 Search Schemas ──────────────────────────────────────────────────────
class SearchResultSchema(BaseModel):
    """Single search result (product×shop match)."""
    id: str
    product_id: int
    product_name: str
    brand_name: Optional[str] = None
    category_name: Optional[str] = None
    variant_name: Optional[str] = None
    product_image_url: Optional[str] = None
    shop_id: int
    shop_name: str
    shop_rating: float = 0.0
    shop_review_count: int = 0
    price: Optional[float] = None
    mrp: Optional[float] = None
    is_available: bool = False
    stock_status: Optional[str] = None
    freshness_status: Optional[str] = None
    last_inventory_update: Optional[datetime] = None
    distance_km: Optional[float] = None
    relevance_score: Optional[float] = None
    offer_text: Optional[str] = None


class SearchResponse(BaseModel):
    """Paginated response for product discovery."""
    results: List[SearchResultSchema] = []
    page: int = 1
    limit: int = 20
    has_more: bool = False
    total: int = 0
    sort: str = "relevance"


class SuggestionSchema(BaseModel):
    text: str
    type: str = "product"  # product | brand | category
    is_category: bool = False
    is_brand: bool = False


class NearbyShopResponseSchema(BaseModel):
    shop_id: int
    shop_name: str
    category: Optional[str] = None
    rating: float = 0.0
    review_count: int = 0
    is_accepting_orders: bool = True
    distance_km: float
    latitude: Optional[float] = None
    longitude: Optional[float] = None
    image_url: Optional[str] = None


class NearbyShopsResponse(BaseModel):
    shops: List[NearbyShopResponseSchema] = []
    page: int = 1
    limit: int = 20
    has_more: bool = False
    total: int = 0


class PopularSearchSchema(BaseModel):
    query: str
    search_count: int = 0
    result_count: Optional[int] = None
    last_searched_at: Optional[datetime] = None


class SearchHistorySchema(BaseModel):
    id: int
    query: str
    result_count: Optional[int] = None
    is_successful: bool = True
    searched_at: datetime


class BarcodeResultSchema(BaseModel):
    shop_product_id: int
    product_id: int
    product_name: str
    brand_name: Optional[str] = None
    category_name: Optional[str] = None
    price: Optional[float] = None
    mrp: Optional[float] = None
    is_available: bool = False
    stock_status: Optional[str] = None
    freshness_status: Optional[str] = None
    # When the shop last reported this item's stock. Drives the customer-facing
    # freshness wording so a scanned product is dated exactly like a typed one.
    last_inventory_update: Optional[datetime] = None
    shop_id: int
    shop_name: str
    distance_km: Optional[float] = None
    shop_rating: float = 0.0


# ── Legacy V1 (kept for backward compatibility) ────────────────────────────
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