"""Model exports - import all models so SQLAlchemy metadata is complete."""
# Base & Mixins
from app.models.base import Base, TimestampMixin, SoftDeleteMixin, AuditMixin

# RBAC
from app.models.role import Role, Permission, role_permissions

# Users & Customers
from app.models.user import User, UserStatus
from app.models.customer import Customer, CustomerAddress

# Sessions
from app.models.session import AuthSession, TokenBlacklist

# Shops
from app.models.shop import (
    Shop,
    ShopStatus,
    ShopCategory,
    ShopOwner,
    ShopManager,
    ShopAddress,
    ShopHour,
    ShopHoliday,
    ShopDocument,
    ShopVerification,
    VerificationStatus,
)

# Products
from app.models.product import (
    Category,
    Brand,
    ProductMaster,
    ProductStatus,
    ProductVariant,
    ProductImage,
    ProductAttribute,
    ProductAttributeValue,
    ProductIdentifier,
    IdentifierType,
    BarcodeRelationship,
    ShopProduct,
    ShopProductStatus,
    StockStatus,
    CustomerStockStatus,
    FreshnessStatus,
    InventorySource,
    Inventory,
    InventoryMovement,
    InventoryAdjustment,
    PriceHistory,
    Offer,
    OfferStatus,
    OfferType,
    OfferProduct,
    OfferCondition,
)

# Search
from app.models.search import (
    SearchHistory,
    SearchEvent,
    PopularSearch,
    BarcodeScan,
    SearchIndex,
    SearchIndexEntityType,
    SearchIndexSync,
    SearchIndexSyncStatus,
)

# POS
from app.models.pos import (
    POSIntegration,
    POSIntegrationStatus,
    POSDevice,
    POSSyncJob,
    POSSyncStatus,
    POSSyncLog,
    POSProductMapping,
)

# Notifications
from app.models.notification import (
    DeviceToken,
    Notification,
    NotificationDelivery,
    NotificationPreference,
)

# Admin
from app.models.admin import (
    AdminAction,
    AdminNote,
    ProductApproval,
    ApprovalStatus,
    Report,
    Complaint,
    ComplaintStatus,
    AuditLog,
)

# Analytics
from app.models.analytics import ProductView, ShopView, ProductClick, InventoryEvent, SystemMetric

# System
from app.models.system import SystemSetting, FeatureFlag

# Subscriptions
from app.models.subscription import (
    Subscription,
    SubscriptionStatus,
    BillingCycle,
    SubscriptionPlan,
    Payment,
    PaymentEvent,
)

# Saved
from app.models.saved_product import SavedProduct
from app.models.saved_shop import SavedShop

# Phase 24 — Inventory intake jobs
from app.models.inventory_import import (
    ImportJobStatus,
    InventoryImportJob,
    InventoryImportRow,
)