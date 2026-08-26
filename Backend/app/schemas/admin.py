"""Admin Platform schemas for API serialization — Phase 26."""
from datetime import datetime
from typing import Any, Optional
from pydantic import BaseModel, Field, ConfigDict

from app.models.admin import ApprovalStatus, ComplaintStatus
from app.models.product import ProductStatus, ShopProductStatus, StockStatus, FreshnessStatus, OfferStatus
from app.models.shop import ShopStatus, VerificationStatus
from app.models.user import UserStatus


# ── Dashboard ──────────────────────────────────────────────────────────────────
class DashboardMetrics(BaseModel):
    """Aggregated platform metrics for the admin dashboard."""
    total_customers: int = 0
    total_shops: int = 0
    active_shops: int = 0
    pending_verification: int = 0
    total_products: int = 0
    total_inventory_records: int = 0
    total_searches: int = 0
    search_success_rate: float = 0.0
    popular_categories: list[dict] = []
    active_subscriptions: int = 0
    total_subscription_revenue: float = 0.0
    pending_approvals: int = 0
    open_complaints: int = 0
    stale_inventory_count: int = 0
    products_missing_prices: int = 0
    sync_failures: int = 0


# ── Shop Management ────────────────────────────────────────────────────────────
class ShopVerificationAction(BaseModel):
    """Admin action on a shop: verify, reject, suspend, or reactivate."""
    decision: str = Field(..., pattern="^(VERIFY|REJECT|SUSPEND|REACTIVATE)$")
    reason: Optional[str] = Field(None, max_length=500)
    notes: Optional[str] = Field(None, max_length=2000)


class ShopFilterParams(BaseModel):
    """Filters for listing shops in admin panel."""
    status: Optional[ShopStatus] = None
    verification_status: Optional[VerificationStatus] = None
    category: Optional[str] = None
    city: Optional[str] = None
    state: Optional[str] = None
    is_active: Optional[bool] = None
    is_accepting_orders: Optional[bool] = None
    created_after: Optional[datetime] = None
    created_before: Optional[datetime] = None
    search: Optional[str] = Field(None, max_length=200)


# ── Product Management ────────────────────────────────────────────────────────
class ProductApprovalAction(BaseModel):
    """Admin action on a product approval request."""
    decision: str = Field(..., pattern="^(APPROVE|REJECT|NEEDS_INFO)$")
    review_notes: Optional[str] = Field(None, max_length=2000)