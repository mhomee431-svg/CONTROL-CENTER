"""SQLAlchemy models.

Field names mirror the TypeScript interfaces in
`src/core/types/admin.ts` exactly, because the frontend renders those shapes
directly. Where the frontend tolerates a field being absent, the column is
nullable so the API can honestly report "not supplied by the backend" rather
than fabricate a value.
"""

from datetime import datetime, timezone

from sqlalchemy import (
    Boolean,
    Column,
    DateTime,
    Float,
    ForeignKey,
    Integer,
    JSON,
    String,
    Text,
)
from sqlalchemy.orm import relationship

from app.core.database import Base


def _now() -> datetime:
    return datetime.now(timezone.utc)


class TimestampMixin:
    created_at = Column(DateTime(timezone=True), default=_now)
    updated_at = Column(DateTime(timezone=True), default=_now, onupdate=_now)


class AdminUser(Base, TimestampMixin):
    """An operator of the control center, with its capability grants."""

    __tablename__ = "admin_users"

    id = Column(Integer, primary_key=True)
    username = Column(String(64), unique=True, nullable=False, index=True)
    name = Column(String(128))
    email = Column(String(255))
    hashed_password = Column(String(255), nullable=False)
    role_name = Column(String(64), default="Support Admin")
    level = Column(String(16), default="SUB")  # SUPER | SUB
    is_owner = Column(Boolean, default=False)
    is_active = Column(Boolean, default=True)
    last_login = Column(DateTime(timezone=True))
    permissions = Column(JSON, default=list)


class RevokedAdminToken(Base):
    """Server-side denylist for signed-out or exchanged access tokens."""

    __tablename__ = "revoked_admin_tokens"
    jti = Column(String(32), primary_key=True)
    expires_at = Column(DateTime(timezone=True), nullable=False)


class User(Base, TimestampMixin):
    """A customer of the platform."""

    __tablename__ = "users"

    id = Column(Integer, primary_key=True)
    name = Column(String(128))
    phone = Column(String(32))
    email = Column(String(255))
    status = Column(String(32), default="ACTIVE")
    last_login = Column(DateTime(timezone=True))
    last_active = Column(DateTime(timezone=True))
    auth_status = Column(String(32), default="VERIFIED")
    city = Column(String(64))
    state = Column(String(64))
    is_profile_complete = Column(Boolean, default=True)
    is_restricted = Column(Boolean, default=False)
    search_count = Column(Integer, default=0)
    viewed_product_count = Column(Integer, default=0)
    viewed_shop_count = Column(Integer, default=0)
    saved_product_count = Column(Integer, default=0)
    saved_shop_count = Column(Integer, default=0)


class Shop(Base, TimestampMixin):
    """A business (merchant storefront).

    One row backs the whole business drill-down. Sub-resources (documents,
    pricing, inventory, offers, audit) are separate tables so each tab reads
    its own contract.
    """

    __tablename__ = "shops"

    id = Column(Integer, primary_key=True)
    name = Column(String(160), nullable=False)
    owner_id = Column(Integer, ForeignKey("users.id"))
    category_id = Column(Integer, ForeignKey("categories.id"))
    category = Column(String(96))
    subcategory = Column(String(96))
    business_type = Column(String(32))

    # Location
    address = Column(String(255))
    locality = Column(String(96))
    city = Column(String(64))
    state = Column(String(64))
    pincode = Column(String(12))
    latitude = Column(Float)
    longitude = Column(Float)

    # Contact
    phone = Column(String(32))
    alt_phone = Column(String(32))
    email = Column(String(255))
    website = Column(String(255))

    # Presentation / registration
    logo_url = Column(String(512))
    description = Column(Text)
    registration_number = Column(String(64))
    gst_number = Column(String(32))

    # State
    status = Column(String(32), default="PENDING")
    verification_status = Column(String(32), default="PENDING")
    verified_at = Column(DateTime(timezone=True))
    verified_by = Column(String(128))
    rejection_reason = Column(Text)

    # Operating hours: a weekday map. Stored as JSON so a closed day can be
    # null rather than an absent key.
    operating_hours = Column(JSON)

    # Denormalised rollups the listing reads directly.
    product_count = Column(Integer, default=0)
    inventory_count = Column(Integer, default=0)
    inventory_freshness = Column(String(32))
    last_inventory_update = Column(DateTime(timezone=True))

    owner = relationship("User", foreign_keys=[owner_id])
    documents = relationship("ShopDocument", back_populates="shop", cascade="all, delete-orphan")
    prices = relationship("ShopPricing", back_populates="shop", cascade="all, delete-orphan")
    inventory = relationship("ShopInventory", back_populates="shop", cascade="all, delete-orphan")
    offers = relationship("Offer", back_populates="shop", cascade="all, delete-orphan")


class Category(Base, TimestampMixin):
    __tablename__ = "categories"

    id = Column(Integer, primary_key=True)
    name = Column(String(96), nullable=False)
    slug = Column(String(96))
    description = Column(Text)
    icon_url = Column(String(512))
    parent_id = Column(Integer, ForeignKey("categories.id"))
    sort_order = Column(Integer, default=0)
    is_active = Column(Boolean, default=True)
    is_subcategory = Column(Boolean, default=False)


class Brand(Base, TimestampMixin):
    __tablename__ = "brands"

    id = Column(Integer, primary_key=True)
    name = Column(String(96), nullable=False)
    slug = Column(String(96))
    description = Column(Text)
    logo_url = Column(String(512))
    is_active = Column(Boolean, default=True)
    product_count = Column(Integer, default=0)


class Product(Base, TimestampMixin):
    __tablename__ = "products"

    id = Column(Integer, primary_key=True)
    name = Column(String(200), nullable=False)
    brand_id = Column(Integer, ForeignKey("brands.id"))
    brand_name = Column(String(96))
    category_id = Column(Integer, ForeignKey("categories.id"))
    category_name = Column(String(96))
    subcategory_id = Column(Integer)
    barcode = Column(String(64))
    status = Column(String(32), default="DRAFT")
    shop_count = Column(Integer, default=0)
    image_url = Column(String(512))
    images = Column(JSON)
    description = Column(Text)
    mrp = Column(Float)
    unit = Column(String(32))

    variants = relationship("ProductVariant", back_populates="product", cascade="all, delete-orphan")


class ProductVariant(Base, TimestampMixin):
    __tablename__ = "product_variants"

    id = Column(Integer, primary_key=True)
    product_id = Column(Integer, ForeignKey("products.id"))
    name = Column(String(128))
    variant_name = Column(String(128))
    sku = Column(String(64))
    barcode = Column(String(64))
    mrp = Column(Float)
    price = Column(Float)
    unit = Column(String(32))
    status = Column(String(32), default="ACTIVE")
    image_url = Column(String(512))

    product = relationship("Product", back_populates="variants")


class ShopInventory(Base, TimestampMixin):
    """One product's stock inside one shop."""

    __tablename__ = "shop_inventory"

    id = Column(Integer, primary_key=True)
    shop_id = Column(Integer, ForeignKey("shops.id"), nullable=False)
    product_id = Column(Integer, ForeignKey("products.id"))
    product_name = Column(String(200))
    quantity = Column(Integer, default=0)
    price = Column(Float)
    mrp = Column(Float)
    stock_status = Column(String(32), default="IN_STOCK")
    freshness_status = Column(String(32))
    availability = Column(String(32))
    last_updated = Column(DateTime(timezone=True))
    last_updated_source = Column(String(64))
    stale_hours = Column(Float)
    sync_source = Column(String(64))
    sync_status = Column(String(32))
    sync_error = Column(Text)

    shop = relationship("Shop", back_populates="inventory")


class InventoryHistory(Base, TimestampMixin):
    __tablename__ = "inventory_history"

    id = Column(Integer, primary_key=True)
    shop_product_id = Column(Integer, ForeignKey("shop_inventory.id"), nullable=False)
    change_type = Column(String(48))
    old_value = Column(String(255))
    new_value = Column(String(255))
    source = Column(String(64))
    changed_by = Column(String(128))


class ShopDocument(Base, TimestampMixin):
    __tablename__ = "shop_documents"

    id = Column(Integer, primary_key=True)
    shop_id = Column(Integer, ForeignKey("shops.id"), nullable=False)
    doc_type = Column(String(64))
    title = Column(String(200))
    file_name = Column(String(255))
    file_url = Column(String(512))
    status = Column(String(32), default="PENDING")
    uploaded_at = Column(DateTime(timezone=True))
    expires_at = Column(DateTime(timezone=True))
    verified_at = Column(DateTime(timezone=True))

    shop = relationship("Shop", back_populates="documents")


class ShopPricing(Base, TimestampMixin):
    __tablename__ = "shop_pricing"

    id = Column(Integer, primary_key=True)
    shop_id = Column(Integer, ForeignKey("shops.id"), nullable=False)
    product_id = Column(Integer, ForeignKey("products.id"))
    product_name = Column(String(200))
    sku = Column(String(64))
    barcode = Column(String(64))
    price = Column(Float)
    mrp = Column(Float)
    currency = Column(String(8), default="INR")

    shop = relationship("Shop", back_populates="prices")


class Offer(Base, TimestampMixin):
    __tablename__ = "offers"

    id = Column(Integer, primary_key=True)
    shop_id = Column(Integer, ForeignKey("shops.id"))
    title = Column(String(200), nullable=False)
    discount_type = Column(String(32), default="PERCENT")
    discount_value = Column(Float, default=0)
    status = Column(String(32), default="ACTIVE")
    starts_at = Column(DateTime(timezone=True))
    ends_at = Column(DateTime(timezone=True))
    valid_from = Column(DateTime(timezone=True))
    valid_until = Column(DateTime(timezone=True))

    shop = relationship("Shop", back_populates="offers")


class AuditLog(Base, TimestampMixin):
    """Append-only governance trail.

    The History tab filters this by entity_type/entity_id, so both are indexed.
    """

    __tablename__ = "audit_logs"

    id = Column(Integer, primary_key=True)
    action = Column(String(96), nullable=False)
    entity_type = Column(String(64), index=True)
    entity_id = Column(Integer, index=True)
    user_id = Column(Integer)
    admin_user = Column(String(128))
    ip_address = Column(String(64))
    details = Column(JSON)


class Complaint(Base, TimestampMixin):
    __tablename__ = "complaints"

    id = Column(Integer, primary_key=True)
    ticket_number = Column(String(32))
    reporter_type = Column(String(32))
    reporter_name = Column(String(128))
    complaint_type = Column(String(64))
    priority = Column(String(16), default="MEDIUM")
    status = Column(String(32), default="OPEN")
    description = Column(Text)
    resolution = Column(Text)


class Subscription(Base, TimestampMixin):
    __tablename__ = "subscriptions"

    id = Column(Integer, primary_key=True)
    shop_id = Column(Integer, ForeignKey("shops.id"))
    shop_name = Column(String(160))
    plan_name = Column(String(96))
    status = Column(String(32), default="ACTIVE")
    amount = Column(Float, default=0)
    currency = Column(String(8), default="INR")
    started_at = Column(DateTime(timezone=True))
    expires_at = Column(DateTime(timezone=True))


class Payment(Base, TimestampMixin):
    __tablename__ = "payments"

    id = Column(Integer, primary_key=True)
    subscription_id = Column(Integer, ForeignKey("subscriptions.id"))
    shop_name = Column(String(160))
    amount = Column(Float, default=0)
    currency = Column(String(8), default="INR")
    status = Column(String(32), default="SUCCESS")
    method = Column(String(32))
    reference = Column(String(96))
    paid_at = Column(DateTime(timezone=True))


class NotificationCampaign(Base, TimestampMixin):
    __tablename__ = "notification_campaigns"

    id = Column(Integer, primary_key=True)
    title = Column(String(200), nullable=False)
    body = Column(Text)
    notification_type = Column(String(64))
    audience = Column(String(32), default="all")
    status = Column(String(32), default="DRAFT")
    deep_link = Column(String(255))
    entity_id = Column(String(64))
    recipients_total = Column(Integer, default=0)
    recipients_sent = Column(Integer, default=0)
    recipients_failed = Column(Integer, default=0)
    sent_by = Column(String(128))
    sent_at = Column(DateTime(timezone=True))


class Banner(Base, TimestampMixin):
    __tablename__ = "banners"

    id = Column(Integer, primary_key=True)
    title = Column(String(200), nullable=False)
    subtitle = Column(String(255))
    image_url = Column(String(512))
    deep_link = Column(String(255))
    placement = Column(String(64))
    status = Column(String(32), default="DRAFT")
    sort_order = Column(Integer, default=0)
    starts_at = Column(DateTime(timezone=True))
    ends_at = Column(DateTime(timezone=True))


class Announcement(Base, TimestampMixin):
    __tablename__ = "announcements"

    id = Column(Integer, primary_key=True)
    title = Column(String(200), nullable=False)
    body = Column(Text, nullable=False)
    audience = Column(String(32), default="all")
    status = Column(String(32), default="DRAFT")
    is_pinned = Column(Boolean, default=False)
    published_at = Column(DateTime(timezone=True))
    expires_at = Column(DateTime(timezone=True))


class Faq(Base, TimestampMixin):
    __tablename__ = "faqs"

    id = Column(Integer, primary_key=True)
    question = Column(Text, nullable=False)
    answer = Column(Text, nullable=False)
    category = Column(String(64))
    audience = Column(String(32), default="all")
    status = Column(String(32), default="PUBLISHED")
    sort_order = Column(Integer, default=0)


class HelpContent(Base, TimestampMixin):
    __tablename__ = "help_content"

    id = Column(Integer, primary_key=True)
    title = Column(String(200), nullable=False)
    slug = Column(String(128))
    body = Column(Text, nullable=False)
    section = Column(String(64))
    status = Column(String(32), default="PUBLISHED")
    sort_order = Column(Integer, default=0)


class PromotionalCard(Base, TimestampMixin):
    __tablename__ = "promotional_cards"

    id = Column(Integer, primary_key=True)
    title = Column(String(200), nullable=False)
    description = Column(Text)
    image_url = Column(String(512))
    cta_label = Column(String(64))
    deep_link = Column(String(255))
    status = Column(String(32), default="DRAFT")
    starts_at = Column(DateTime(timezone=True))
    ends_at = Column(DateTime(timezone=True))


class SystemMessage(Base, TimestampMixin):
    __tablename__ = "system_messages"

    id = Column(Integer, primary_key=True)
    title = Column(String(200), nullable=False)
    body = Column(Text, nullable=False)
    severity = Column(String(32), default="INFO")
    status = Column(String(32), default="DRAFT")
    is_active = Column(Boolean, default=True)
    starts_at = Column(DateTime(timezone=True))
    ends_at = Column(DateTime(timezone=True))


class PosIntegration(Base, TimestampMixin):
    __tablename__ = "pos_integrations"

    id = Column(Integer, primary_key=True)
    shop_id = Column(Integer, ForeignKey("shops.id"))
    shop_name = Column(String(160))
    provider = Column(String(64))
    status = Column(String(32), default="CONNECTED")
    last_sync = Column(DateTime(timezone=True))
    external_ref = Column(String(128))


class PosSyncRun(Base, TimestampMixin):
    __tablename__ = "pos_sync_runs"

    id = Column(Integer, primary_key=True)
    integration_id = Column(Integer, ForeignKey("pos_integrations.id"), nullable=False)
    status = Column(String(32), default="SUCCESS")
    rows_synced = Column(Integer, default=0)
    message = Column(Text)


class ImportJob(Base, TimestampMixin):
    __tablename__ = "import_jobs"

    id = Column(Integer, primary_key=True)
    shop_id = Column(Integer, ForeignKey("shops.id"))
    shop_name = Column(String(160))
    source = Column(String(64))
    filename = Column(String(255))
    status = Column(String(32), default="COMPLETED")
    rows_total = Column(Integer, default=0)
    rows_processed = Column(Integer, default=0)
    rows_failed = Column(Integer, default=0)


class ImportError(Base, TimestampMixin):
    __tablename__ = "import_errors"

    id = Column(Integer, primary_key=True)
    import_id = Column(Integer, ForeignKey("import_jobs.id"), nullable=False)
    row_number = Column(Integer)
    column_name = Column(String(96))
    message = Column(Text)
    raw_value = Column(String(255))


class FeatureFlag(Base, TimestampMixin):
    __tablename__ = "feature_flags"

    name = Column(String(96), primary_key=True)
    is_enabled = Column(Boolean, default=False)
    rollout_percentage = Column(Integer, default=0)
    scope = Column(String(32), default="GLOBAL")
    description = Column(Text)


class SystemSetting(Base, TimestampMixin):
    __tablename__ = "system_settings"

    key = Column(String(128), primary_key=True)
    value = Column(String(512))
    value_type = Column(String(16), default="string")
    description = Column(Text)
    is_secret = Column(Boolean, default=False)


class AdminNote(Base, TimestampMixin):
    __tablename__ = "admin_notes"

    id = Column(Integer, primary_key=True)
    entity_type = Column(String(64))
    entity_id = Column(Integer)
    note = Column(Text, nullable=False)
    author = Column(String(128))


class SearchQuery(Base, TimestampMixin):
    """A customer search, for the search-quality surfaces."""

    __tablename__ = "search_queries"

    id = Column(Integer, primary_key=True)
    user_id = Column(Integer, ForeignKey("users.id"))
    query = Column(String(255))
    result_count = Column(Integer, default=0)
    location = Column(String(96))
    searched_at = Column(DateTime(timezone=True))


class OperationalEvent(Base):
    """Persisted, non-sensitive events consumed by the admin live feed."""

    __tablename__ = "operational_events"

    id = Column(Integer, primary_key=True)
    type = Column(String(48), nullable=False, index=True)
    title = Column(String(200), nullable=False)
    created_at = Column(DateTime(timezone=True), nullable=False, default=_now, index=True)
