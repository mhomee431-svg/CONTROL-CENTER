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
class ProductAdminUpdate(BaseModel):
    """Admin edit of a product (authorized fields)."""
    name: Optional[str] = Field(None, min_length=1, max_length=255)
    description: Optional[str] = None
    short_description: Optional[str] = Field(None, max_length=500)
    category_id: Optional[int] = None
    subcategory_id: Optional[int] = None
    brand_id: Optional[int] = None
    is_active: Optional[bool] = None
    status: Optional[ProductStatus] = None


class ProductAdminAction(BaseModel):
    """Bulk or single product action: approve, reject, archive, activate."""
    action: str = Field(..., pattern="^(APPROVE|REJECT|ARCHIVE|ACTIVATE)$")
    product_ids: list[int] = Field(..., min_length=1)
    reason: Optional[str] = Field(None, max_length=500)


# ── Inventory Monitoring ───────────────────────────────────────────────────────
class InventoryIssueFilter(BaseModel):
    """Filters for inventory monitoring views."""
    stale_threshold_hours: int = Field(48, ge=1, le=720)
    shop_id: Optional[int] = None
    category_id: Optional[int] = None
    only_missing_price: bool = False
    only_availability_anomaly: bool = False
    only_sync_failure: bool = False
    limit: int = Field(50, ge=1, le=500)
    offset: int = Field(0, ge=0)


class StaleInventoryItem(BaseModel):
    """A single stale inventory record with context."""
    shop_product_id: int
    product_name: str
    shop_name: str
    shop_id: int
    quantity: int
    stock_status: str
    freshness_status: Optional[str] = None
    last_updated: Optional[datetime] = None
    last_updated_source: Optional[str] = None
    stale_hours: Optional[int] = None


class InventoryAnomalyItem(BaseModel):
    """An inventory anomaly record."""
    shop_product_id: int
    product_name: str
    shop_name: str
    shop_id: int
    anomaly_type: str  # MISSING_PRICE, AVAILABILITY_ANOMALY, SYNC_FAILURE
    detail: str


# ── Reports ───────────────────────────────────────────────────────────────────
class ReportGenerateRequest(BaseModel):
    """Request to generate a report."""
    report_type: str = Field(..., pattern="^(SEARCH|INVENTORY|SHOPS|PRODUCTS|USERS|REVENUE)$")
    report_name: str = Field(..., min_length=1, max_length=255)
    date_from: Optional[datetime] = None
    date_to: Optional[datetime] = None
    filters: Optional[dict] = None


class ReportResponse(BaseModel):
    id: int
    report_type: str
    report_name: str
    parameters_json: Optional[dict] = None
    generated_by: Optional[int] = None
    file_url: Optional[str] = None
    status: str

# ── Audit Log ─────────────────────────────────────────────────────────────────
class AuditLogFilter(BaseModel):
    """Filters for audit log listing."""
    action: Optional[str] = None
    entity_type: Optional[str] = None
    entity_id: Optional[int] = None
    user_id: Optional[int] = None
    date_from: Optional[datetime] = None
    date_to: Optional[datetime] = None
    search: Optional[str] = Field(None, max_length=200)
    limit: int = Field(50, ge=1, le=500)
    offset: int = Field(0, ge=0)


# ── Admin Actions ─────────────────────────────────────────────────────────────
class AdminActionFilter(BaseModel):
    """Filters for admin action listing."""
    action_type: Optional[str] = None
    target_type: Optional[str] = None
    target_id: Optional[int] = None
    admin_user_id: Optional[int] = None
    date_from: Optional[datetime] = None
    date_to: Optional[datetime] = None
    limit: int = Field(50, ge=1, le=500)
    offset: int = Field(0, ge=0)


# ── Admin Notes ────────────────────────────────────────────────────────────────
class AdminNoteCreate(BaseModel):
    """Create an internal admin note."""
    entity_type: str = Field(..., pattern="^(SHOP|USER|PRODUCT)$")
    entity_id: int = Field(..., ge=1)
    note: str = Field(..., min_length=1, max_length=5000)
    is_private: bool = True


class AdminNoteUpdate(BaseModel):
    """Update an admin note."""
    note: Optional[str] = Field(None, min_length=1, max_length=5000)
    is_private: Optional[bool] = None


# ── Bulk Operations ────────────────────────────────────────────────────────────
class BulkShopAction(BaseModel):
    """Bulk action on multiple shops."""
    action: str = Field(..., pattern="^(VERIFY|REJECT|SUSPEND|REACTIVATE|DELETE)$")
    shop_ids: list[int] = Field(..., min_length=1, max_length=100)
    reason: Optional[str] = Field(None, max_length=500)


class BulkUserAction(BaseModel):
    """Bulk action on multiple users."""
    action: str = Field(..., pattern="^(SUSPEND|BAN|ACTIVATE)$")
    user_ids: list[int] = Field(..., min_length=1, max_length=100)
    reason: Optional[str] = Field(None, max_length=500)


# ── Categories / Brands ────────────────────────────────────────────────────────
class CategoryAdminCreate(BaseModel):
    name: str = Field(..., min_length=1, max_length=100)
    slug: str = Field(..., min_length=1, max_length=120)
    description: Optional[str] = None
    icon_url: Optional[str] = None
    parent_id: Optional[int] = None
    sort_order: int = 0
    is_active: bool = True
    is_subcategory: bool = False


class CategoryAdminUpdate(BaseModel):
    name: Optional[str] = Field(None, min_length=1, max_length=100)
    slug: Optional[str] = Field(None, min_length=1, max_length=120)
    description: Optional[str] = None
    icon_url: Optional[str] = None
    parent_id: Optional[int] = None
    sort_order: Optional[int] = None
    is_active: Optional[bool] = None
    is_subcategory: Optional[bool] = None


class BrandAdminCreate(BaseModel):
    name: str = Field(..., min_length=1, max_length=120)
    slug: str = Field(..., min_length=1, max_length=140)
    description: Optional[str] = None
    logo_url: Optional[str] = None
    is_active: bool = True


class BrandAdminUpdate(BaseModel):
    name: Optional[str] = Field(None, min_length=1, max_length=120)
    slug: Optional[str] = Field(None, min_length=1, max_length=140)
    description: Optional[str] = None
    logo_url: Optional[str] = None
    is_active: Optional[bool] = None


# ── Subscription / Payment admin ───────────────────────────────────────────────
class SubscriptionAdminUpdate(BaseModel):
    status: Optional[str] = None
    is_auto_renew: Optional[bool] = None
    cancel_at_period_end: Optional[bool] = None
    plan_id: Optional[int] = None


class PaymentFilter(BaseModel):
    status: Optional[str] = None
    payment_provider: Optional[str] = None
    payment_method: Optional[str] = None
    date_from: Optional[datetime] = None
    date_to: Optional[datetime] = None
    subscription_id: Optional[int] = None
    limit: int = Field(50, ge=1, le=500)
    offset: int = Field(0, ge=0)


# ── Notification admin ─────────────────────────────────────────────────────────
class AdminNotificationCreate(BaseModel):
    """Create a platform-wide or targeted notification."""
    title: str = Field(..., min_length=1, max_length=255)
    body: str = Field(..., min_length=1, max_length=2000)
    notification_type: str = Field(..., pattern="^(ADMIN_BROADCAST|TARGETED)$")
    target_user_ids: Optional[list[int]] = None
    target_role: Optional[str] = None


# ── Paginated response envelope ────────────────────────────────────────────────
def paginate(items: list[Any], total: int, limit: int, offset: int) -> dict:
    """Standard pagination payload used across all list endpoints."""
    return {"items": items, "total": total, "limit": limit, "offset": offset}
    started_at: Optional[datetime] = None
    completed_at: Optional[datetime] = None
    error_message: Optional[str] = None
    created_at: datetime

    model_config = ConfigDict(from_attributes=True)


# ── Complaints ────────────────────────────────────────────────────────────────
class ComplaintUpdate(BaseModel):
    """Admin update to a complaint."""
    status: Optional[ComplaintStatus] = None
    priority: Optional[str] = Field(None, pattern="^(LOW|MEDIUM|HIGH|URGENT)$")
    assigned_to: Optional[int] = None
    resolution_notes: Optional[str] = Field(None, max_length=5000)
    created_before: Optional[datetime] = None
    search: Optional[str] = Field(None, max_length=200)


# ── Product Management ────────────────────────────────────────────────────────
class ProductApprovalAction(BaseModel):
    """Admin action on a product approval request."""
    decision: str = Field(..., pattern="^(APPROVE|REJECT|NEEDS_INFO)$")
    review_notes: Optional[str] = Field(None, max_length=2000)