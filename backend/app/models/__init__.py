"""SQLAlchemy models.

Field names mirror the TypeScript interfaces in
`src/core/types/admin.ts` exactly, because the frontend renders those shapes
directly. Where the frontend tolerates a field being absent, the column is
nullable so the API can honestly report "not supplied by the backend" rather
than fabricate a value.
"""

from datetime import datetime, timezone
from typing import Any, Optional

from sqlalchemy import (
    Boolean,
    DateTime,
    Float,
    ForeignKey,
    Integer,
    JSON,
    String,
    Text,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.database import Base


def _now() -> datetime:
    return datetime.now(timezone.utc)


class TimestampMixin:
    """Created/updated timestamps shared by most tables.

    Typed with `Mapped[...]` so a static checker sees `created_at` as a
    `datetime`, not a `Column`. Legacy `Column(...)` declarations leave the
    instance attribute typed as the descriptor, which is why reading one in a
    boolean context (e.g. `admin.created_at or default`) was reported as a type
    error even though it works at runtime.
    """

    created_at: Mapped[Optional[datetime]] = mapped_column(
        DateTime(timezone=True), default=_now
    )
    updated_at: Mapped[Optional[datetime]] = mapped_column(
        DateTime(timezone=True), default=_now, onupdate=_now
    )


class AdminUser(Base, TimestampMixin):
    """An operator of the control center, with its capability grants.

    Declared with SQLAlchemy 2.0 typed mapping so instance attributes carry
    their real Python types (`is_active` is a `bool`, `id` an `int`). That is
    what lets the admin-user management routes assign to these fields and read
    them in conditionals without tripping the type checker.
    """

    __tablename__ = "admin_users"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    username: Mapped[str] = mapped_column(String(64), unique=True, nullable=False, index=True)
    name: Mapped[Optional[str]] = mapped_column(String(128))
    email: Mapped[Optional[str]] = mapped_column(String(255))
    hashed_password: Mapped[str] = mapped_column(String(255), nullable=False)
    role_name: Mapped[Optional[str]] = mapped_column(String(64), default="Support Admin")
    level: Mapped[Optional[str]] = mapped_column(String(16), default="SUB")  # SUPER | SUB
    is_owner: Mapped[Optional[bool]] = mapped_column(Boolean, default=False)
    is_active: Mapped[Optional[bool]] = mapped_column(Boolean, default=True)
    last_login: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True))
    permissions: Mapped[Optional[list[Any]]] = mapped_column(JSON, default=list)


class RevokedAdminToken(Base):
    """Server-side denylist for signed-out or exchanged access tokens.

    `jti` also holds synthetic `cutoff:<admin_id>:<epoch>` markers written when
    an administrator's access is reset; the auth layer interprets those as
    "every token issued at or before this instant is revoked".
    """

    __tablename__ = "revoked_admin_tokens"
    jti: Mapped[str] = mapped_column(String(64), primary_key=True)
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)


class User(Base, TimestampMixin):
    """A customer of the platform."""

    __tablename__ = "users"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    name: Mapped[Optional[str]] = mapped_column(String(128))
    phone: Mapped[Optional[str]] = mapped_column(String(32))
    email: Mapped[Optional[str]] = mapped_column(String(255))
    status: Mapped[Optional[str]] = mapped_column(String(32), default="ACTIVE")
    last_login: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True))
    last_active: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True))
    auth_status: Mapped[Optional[str]] = mapped_column(String(32), default="VERIFIED")
    city: Mapped[Optional[str]] = mapped_column(String(64))
    state: Mapped[Optional[str]] = mapped_column(String(64))
    is_profile_complete: Mapped[Optional[bool]] = mapped_column(Boolean, default=True)
    is_restricted: Mapped[Optional[bool]] = mapped_column(Boolean, default=False)
    search_count: Mapped[Optional[int]] = mapped_column(Integer, default=0)
    viewed_product_count: Mapped[Optional[int]] = mapped_column(Integer, default=0)
    viewed_shop_count: Mapped[Optional[int]] = mapped_column(Integer, default=0)
    saved_product_count: Mapped[Optional[int]] = mapped_column(Integer, default=0)
    saved_shop_count: Mapped[Optional[int]] = mapped_column(Integer, default=0)


class Shop(Base, TimestampMixin):
    """A business (merchant storefront).

    One row backs the whole business drill-down. Sub-resources (documents,
    pricing, inventory, offers, audit) are separate tables so each tab reads
    its own contract.
    """

    __tablename__ = "shops"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    name: Mapped[str] = mapped_column(String(160), nullable=False)
    owner_id: Mapped[Optional[int]] = mapped_column(Integer, ForeignKey("users.id"))
    category_id: Mapped[Optional[int]] = mapped_column(Integer, ForeignKey("categories.id"))
    category: Mapped[Optional[str]] = mapped_column(String(96))
    subcategory: Mapped[Optional[str]] = mapped_column(String(96))
    business_type: Mapped[Optional[str]] = mapped_column(String(32))

    # Location
    address: Mapped[Optional[str]] = mapped_column(String(255))
    locality: Mapped[Optional[str]] = mapped_column(String(96))
    city: Mapped[Optional[str]] = mapped_column(String(64))
    state: Mapped[Optional[str]] = mapped_column(String(64))
    pincode: Mapped[Optional[str]] = mapped_column(String(12))
    latitude: Mapped[Optional[float]] = mapped_column(Float)
    longitude: Mapped[Optional[float]] = mapped_column(Float)

    # Contact
    phone: Mapped[Optional[str]] = mapped_column(String(32))
    alt_phone: Mapped[Optional[str]] = mapped_column(String(32))
    email: Mapped[Optional[str]] = mapped_column(String(255))
    website: Mapped[Optional[str]] = mapped_column(String(255))

    # Presentation / registration
    logo_url: Mapped[Optional[str]] = mapped_column(String(512))
    description: Mapped[Optional[str]] = mapped_column(Text)
    registration_number: Mapped[Optional[str]] = mapped_column(String(64))
    gst_number: Mapped[Optional[str]] = mapped_column(String(32))

    # State
    status: Mapped[Optional[str]] = mapped_column(String(32), default="PENDING")
    verification_status: Mapped[Optional[str]] = mapped_column(String(32), default="PENDING")
    verified_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True))
    verified_by: Mapped[Optional[str]] = mapped_column(String(128))
    rejection_reason: Mapped[Optional[str]] = mapped_column(Text)

    # Operating hours: a weekday map. Stored as JSON so a closed day can be
    # null rather than an absent key.
    operating_hours: Mapped[Optional[dict[str, Any]]] = mapped_column(JSON)

    # Denormalised rollups the listing reads directly.
    product_count: Mapped[Optional[int]] = mapped_column(Integer, default=0)
    inventory_count: Mapped[Optional[int]] = mapped_column(Integer, default=0)
    inventory_freshness: Mapped[Optional[str]] = mapped_column(String(32))
    last_inventory_update: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True))

    owner: Mapped[Optional["User"]] = relationship("User", foreign_keys=[owner_id])
    documents: Mapped[list["ShopDocument"]] = relationship(
        "ShopDocument", back_populates="shop", cascade="all, delete-orphan"
    )
    prices: Mapped[list["ShopPricing"]] = relationship(
        "ShopPricing", back_populates="shop", cascade="all, delete-orphan"
    )
    inventory: Mapped[list["ShopInventory"]] = relationship(
        "ShopInventory", back_populates="shop", cascade="all, delete-orphan"
    )
    offers: Mapped[list["Offer"]] = relationship(
        "Offer", back_populates="shop", cascade="all, delete-orphan"
    )


class Category(Base, TimestampMixin):
    __tablename__ = "categories"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    name: Mapped[str] = mapped_column(String(96), nullable=False)
    slug: Mapped[Optional[str]] = mapped_column(String(96))
    description: Mapped[Optional[str]] = mapped_column(Text)
    icon_url: Mapped[Optional[str]] = mapped_column(String(512))
    parent_id: Mapped[Optional[int]] = mapped_column(Integer, ForeignKey("categories.id"))
    sort_order: Mapped[Optional[int]] = mapped_column(Integer, default=0)
    is_active: Mapped[Optional[bool]] = mapped_column(Boolean, default=True)
    is_subcategory: Mapped[Optional[bool]] = mapped_column(Boolean, default=False)
    # Category configuration beyond identity (Section: CATEGORY CONFIGURATION).
    # Stored server-side on purpose — the spec forbids implementing category
    # rules only in the frontend. JSON lists of field names / feature keys.
    required_fields: Mapped[Optional[list[Any]]] = mapped_column(JSON, default=list)
    optional_fields: Mapped[Optional[list[Any]]] = mapped_column(JSON, default=list)
    feature_capabilities: Mapped[Optional[list[Any]]] = mapped_column(JSON, default=list)


class Brand(Base, TimestampMixin):
    __tablename__ = "brands"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    name: Mapped[str] = mapped_column(String(96), nullable=False)
    slug: Mapped[Optional[str]] = mapped_column(String(96))
    description: Mapped[Optional[str]] = mapped_column(Text)
    logo_url: Mapped[Optional[str]] = mapped_column(String(512))
    is_active: Mapped[Optional[bool]] = mapped_column(Boolean, default=True)
    product_count: Mapped[Optional[int]] = mapped_column(Integer, default=0)


class Product(Base, TimestampMixin):
    __tablename__ = "products"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    name: Mapped[str] = mapped_column(String(200), nullable=False)
    brand_id: Mapped[Optional[int]] = mapped_column(Integer, ForeignKey("brands.id"))
    brand_name: Mapped[Optional[str]] = mapped_column(String(96))
    category_id: Mapped[Optional[int]] = mapped_column(Integer, ForeignKey("categories.id"))
    category_name: Mapped[Optional[str]] = mapped_column(String(96))
    subcategory_id: Mapped[Optional[int]] = mapped_column(Integer)
    barcode: Mapped[Optional[str]] = mapped_column(String(64))
    status: Mapped[Optional[str]] = mapped_column(String(32), default="DRAFT")
    shop_count: Mapped[Optional[int]] = mapped_column(Integer, default=0)
    image_url: Mapped[Optional[str]] = mapped_column(String(512))
    images: Mapped[Optional[list[Any]]] = mapped_column(JSON)
    description: Mapped[Optional[str]] = mapped_column(Text)
    mrp: Mapped[Optional[float]] = mapped_column(Float)
    unit: Mapped[Optional[str]] = mapped_column(String(32))

    variants: Mapped[list["ProductVariant"]] = relationship(
        "ProductVariant", back_populates="product", cascade="all, delete-orphan"
    )


class ProductVariant(Base, TimestampMixin):
    __tablename__ = "product_variants"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    product_id: Mapped[Optional[int]] = mapped_column(Integer, ForeignKey("products.id"))
    name: Mapped[Optional[str]] = mapped_column(String(128))
    variant_name: Mapped[Optional[str]] = mapped_column(String(128))
    sku: Mapped[Optional[str]] = mapped_column(String(64))
    barcode: Mapped[Optional[str]] = mapped_column(String(64))
    mrp: Mapped[Optional[float]] = mapped_column(Float)
    price: Mapped[Optional[float]] = mapped_column(Float)
    unit: Mapped[Optional[str]] = mapped_column(String(32))
    status: Mapped[Optional[str]] = mapped_column(String(32), default="ACTIVE")
    image_url: Mapped[Optional[str]] = mapped_column(String(512))

    product: Mapped[Optional["Product"]] = relationship("Product", back_populates="variants")


class ShopInventory(Base, TimestampMixin):
    """One product's stock inside one shop."""

    __tablename__ = "shop_inventory"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    shop_id: Mapped[int] = mapped_column(Integer, ForeignKey("shops.id"), nullable=False)
    product_id: Mapped[Optional[int]] = mapped_column(Integer, ForeignKey("products.id"))
    product_name: Mapped[Optional[str]] = mapped_column(String(200))
    quantity: Mapped[Optional[int]] = mapped_column(Integer, default=0)
    price: Mapped[Optional[float]] = mapped_column(Float)
    mrp: Mapped[Optional[float]] = mapped_column(Float)
    stock_status: Mapped[Optional[str]] = mapped_column(String(32), default="IN_STOCK")
    freshness_status: Mapped[Optional[str]] = mapped_column(String(32))
    availability: Mapped[Optional[str]] = mapped_column(String(32))
    last_updated: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True))
    last_updated_source: Mapped[Optional[str]] = mapped_column(String(64))
    stale_hours: Mapped[Optional[float]] = mapped_column(Float)
    sync_source: Mapped[Optional[str]] = mapped_column(String(64))
    sync_status: Mapped[Optional[str]] = mapped_column(String(32))
    sync_error: Mapped[Optional[str]] = mapped_column(Text)

    shop: Mapped[Optional["Shop"]] = relationship("Shop", back_populates="inventory")


class InventoryHistory(Base, TimestampMixin):
    __tablename__ = "inventory_history"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    shop_product_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("shop_inventory.id"), nullable=False
    )
    change_type: Mapped[Optional[str]] = mapped_column(String(48))
    old_value: Mapped[Optional[str]] = mapped_column(String(255))
    new_value: Mapped[Optional[str]] = mapped_column(String(255))
    source: Mapped[Optional[str]] = mapped_column(String(64))
    changed_by: Mapped[Optional[str]] = mapped_column(String(128))


class ShopDocument(Base, TimestampMixin):
    __tablename__ = "shop_documents"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    shop_id: Mapped[int] = mapped_column(Integer, ForeignKey("shops.id"), nullable=False)
    doc_type: Mapped[Optional[str]] = mapped_column(String(64))
    title: Mapped[Optional[str]] = mapped_column(String(200))
    file_name: Mapped[Optional[str]] = mapped_column(String(255))
    file_url: Mapped[Optional[str]] = mapped_column(String(512))
    status: Mapped[Optional[str]] = mapped_column(String(32), default="PENDING")
    uploaded_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True))
    expires_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True))
    verified_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True))

    shop: Mapped[Optional["Shop"]] = relationship("Shop", back_populates="documents")


class ShopPricing(Base, TimestampMixin):
    __tablename__ = "shop_pricing"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    shop_id: Mapped[int] = mapped_column(Integer, ForeignKey("shops.id"), nullable=False)
    product_id: Mapped[Optional[int]] = mapped_column(Integer, ForeignKey("products.id"))
    product_name: Mapped[Optional[str]] = mapped_column(String(200))
    sku: Mapped[Optional[str]] = mapped_column(String(64))
    barcode: Mapped[Optional[str]] = mapped_column(String(64))
    price: Mapped[Optional[float]] = mapped_column(Float)
    mrp: Mapped[Optional[float]] = mapped_column(Float)
    currency: Mapped[Optional[str]] = mapped_column(String(8), default="INR")

    shop: Mapped[Optional["Shop"]] = relationship("Shop", back_populates="prices")


class Offer(Base, TimestampMixin):
    __tablename__ = "offers"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    shop_id: Mapped[Optional[int]] = mapped_column(Integer, ForeignKey("shops.id"))
    title: Mapped[str] = mapped_column(String(200), nullable=False)
    discount_type: Mapped[Optional[str]] = mapped_column(String(32), default="PERCENT")
    discount_value: Mapped[Optional[float]] = mapped_column(Float, default=0)
    status: Mapped[Optional[str]] = mapped_column(String(32), default="ACTIVE")
    starts_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True))
    ends_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True))
    valid_from: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True))
    valid_until: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True))

    shop: Mapped[Optional["Shop"]] = relationship("Shop", back_populates="offers")


class AuditLog(Base, TimestampMixin):
    """Append-only governance trail.

    The History tab filters this by entity_type/entity_id, so both are indexed.
    """

    __tablename__ = "audit_logs"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    action: Mapped[str] = mapped_column(String(96), nullable=False)
    entity_type: Mapped[Optional[str]] = mapped_column(String(64), index=True)
    entity_id: Mapped[Optional[int]] = mapped_column(Integer, index=True)
    user_id: Mapped[Optional[int]] = mapped_column(Integer)
    admin_user: Mapped[Optional[str]] = mapped_column(String(128))
    ip_address: Mapped[Optional[str]] = mapped_column(String(64))
    details: Mapped[Optional[dict[str, Any]]] = mapped_column(JSON)


class Complaint(Base, TimestampMixin):
    __tablename__ = "complaints"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    ticket_number: Mapped[Optional[str]] = mapped_column(String(32))
    reporter_type: Mapped[Optional[str]] = mapped_column(String(32))
    reporter_name: Mapped[Optional[str]] = mapped_column(String(128))
    complaint_type: Mapped[Optional[str]] = mapped_column(String(64))
    priority: Mapped[Optional[str]] = mapped_column(String(16), default="MEDIUM")
    status: Mapped[Optional[str]] = mapped_column(String(32), default="OPEN")
    description: Mapped[Optional[str]] = mapped_column(Text)
    resolution: Mapped[Optional[str]] = mapped_column(Text)


class Subscription(Base, TimestampMixin):
    __tablename__ = "subscriptions"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    shop_id: Mapped[Optional[int]] = mapped_column(Integer, ForeignKey("shops.id"))
    shop_name: Mapped[Optional[str]] = mapped_column(String(160))
    plan_name: Mapped[Optional[str]] = mapped_column(String(96))
    status: Mapped[Optional[str]] = mapped_column(String(32), default="ACTIVE")
    amount: Mapped[Optional[float]] = mapped_column(Float, default=0)
    currency: Mapped[Optional[str]] = mapped_column(String(8), default="INR")
    started_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True))
    expires_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True))


class Payment(Base, TimestampMixin):
    __tablename__ = "payments"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    subscription_id: Mapped[Optional[int]] = mapped_column(Integer, ForeignKey("subscriptions.id"))
    shop_name: Mapped[Optional[str]] = mapped_column(String(160))
    amount: Mapped[Optional[float]] = mapped_column(Float, default=0)
    currency: Mapped[Optional[str]] = mapped_column(String(8), default="INR")
    status: Mapped[Optional[str]] = mapped_column(String(32), default="SUCCESS")
    method: Mapped[Optional[str]] = mapped_column(String(32))
    reference: Mapped[Optional[str]] = mapped_column(String(96))
    paid_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True))


class NotificationCampaign(Base, TimestampMixin):
    __tablename__ = "notification_campaigns"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    title: Mapped[str] = mapped_column(String(200), nullable=False)
    body: Mapped[Optional[str]] = mapped_column(Text)
    notification_type: Mapped[Optional[str]] = mapped_column(String(64))
    audience: Mapped[Optional[str]] = mapped_column(String(32), default="all")
    status: Mapped[Optional[str]] = mapped_column(String(32), default="DRAFT")
    deep_link: Mapped[Optional[str]] = mapped_column(String(255))
    entity_id: Mapped[Optional[str]] = mapped_column(String(64))
    recipients_total: Mapped[Optional[int]] = mapped_column(Integer, default=0)
    recipients_sent: Mapped[Optional[int]] = mapped_column(Integer, default=0)
    recipients_failed: Mapped[Optional[int]] = mapped_column(Integer, default=0)
    sent_by: Mapped[Optional[str]] = mapped_column(String(128))
    sent_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True))


class Banner(Base, TimestampMixin):
    __tablename__ = "banners"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    title: Mapped[str] = mapped_column(String(200), nullable=False)
    subtitle: Mapped[Optional[str]] = mapped_column(String(255))
    image_url: Mapped[Optional[str]] = mapped_column(String(512))
    deep_link: Mapped[Optional[str]] = mapped_column(String(255))
    placement: Mapped[Optional[str]] = mapped_column(String(64))
    status: Mapped[Optional[str]] = mapped_column(String(32), default="DRAFT")
    sort_order: Mapped[Optional[int]] = mapped_column(Integer, default=0)
    starts_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True))
    ends_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True))


class Announcement(Base, TimestampMixin):
    __tablename__ = "announcements"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    title: Mapped[str] = mapped_column(String(200), nullable=False)
    body: Mapped[str] = mapped_column(Text, nullable=False)
    audience: Mapped[Optional[str]] = mapped_column(String(32), default="all")
    status: Mapped[Optional[str]] = mapped_column(String(32), default="DRAFT")
    is_pinned: Mapped[Optional[bool]] = mapped_column(Boolean, default=False)
    published_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True))
    expires_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True))


class Faq(Base, TimestampMixin):
    __tablename__ = "faqs"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    question: Mapped[str] = mapped_column(Text, nullable=False)
    answer: Mapped[str] = mapped_column(Text, nullable=False)
    category: Mapped[Optional[str]] = mapped_column(String(64))
    audience: Mapped[Optional[str]] = mapped_column(String(32), default="all")
    status: Mapped[Optional[str]] = mapped_column(String(32), default="PUBLISHED")
    sort_order: Mapped[Optional[int]] = mapped_column(Integer, default=0)


class HelpContent(Base, TimestampMixin):
    __tablename__ = "help_content"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    title: Mapped[str] = mapped_column(String(200), nullable=False)
    slug: Mapped[Optional[str]] = mapped_column(String(128))
    body: Mapped[str] = mapped_column(Text, nullable=False)
    section: Mapped[Optional[str]] = mapped_column(String(64))
    status: Mapped[Optional[str]] = mapped_column(String(32), default="PUBLISHED")
    sort_order: Mapped[Optional[int]] = mapped_column(Integer, default=0)


class PromotionalCard(Base, TimestampMixin):
    __tablename__ = "promotional_cards"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    title: Mapped[str] = mapped_column(String(200), nullable=False)
    description: Mapped[Optional[str]] = mapped_column(Text)
    image_url: Mapped[Optional[str]] = mapped_column(String(512))
    cta_label: Mapped[Optional[str]] = mapped_column(String(64))
    deep_link: Mapped[Optional[str]] = mapped_column(String(255))
    status: Mapped[Optional[str]] = mapped_column(String(32), default="DRAFT")
    starts_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True))
    ends_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True))


class SystemMessage(Base, TimestampMixin):
    __tablename__ = "system_messages"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    title: Mapped[str] = mapped_column(String(200), nullable=False)
    body: Mapped[str] = mapped_column(Text, nullable=False)
    severity: Mapped[Optional[str]] = mapped_column(String(32), default="INFO")
    status: Mapped[Optional[str]] = mapped_column(String(32), default="DRAFT")
    is_active: Mapped[Optional[bool]] = mapped_column(Boolean, default=True)
    starts_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True))
    ends_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True))


class PosIntegration(Base, TimestampMixin):
    __tablename__ = "pos_integrations"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    shop_id: Mapped[Optional[int]] = mapped_column(Integer, ForeignKey("shops.id"))
    shop_name: Mapped[Optional[str]] = mapped_column(String(160))
    provider: Mapped[Optional[str]] = mapped_column(String(64))
    status: Mapped[Optional[str]] = mapped_column(String(32), default="CONNECTED")
    last_sync: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True))
    external_ref: Mapped[Optional[str]] = mapped_column(String(128))


class PosSyncRun(Base, TimestampMixin):
    __tablename__ = "pos_sync_runs"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    integration_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("pos_integrations.id"), nullable=False
    )
    status: Mapped[Optional[str]] = mapped_column(String(32), default="SUCCESS")
    rows_synced: Mapped[Optional[int]] = mapped_column(Integer, default=0)
    message: Mapped[Optional[str]] = mapped_column(Text)


class ImportJob(Base, TimestampMixin):
    __tablename__ = "import_jobs"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    shop_id: Mapped[Optional[int]] = mapped_column(Integer, ForeignKey("shops.id"))
    shop_name: Mapped[Optional[str]] = mapped_column(String(160))
    source: Mapped[Optional[str]] = mapped_column(String(64))
    filename: Mapped[Optional[str]] = mapped_column(String(255))
    status: Mapped[Optional[str]] = mapped_column(String(32), default="COMPLETED")
    rows_total: Mapped[Optional[int]] = mapped_column(Integer, default=0)
    rows_processed: Mapped[Optional[int]] = mapped_column(Integer, default=0)
    rows_failed: Mapped[Optional[int]] = mapped_column(Integer, default=0)


class ImportError(Base, TimestampMixin):
    __tablename__ = "import_errors"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    import_id: Mapped[int] = mapped_column(Integer, ForeignKey("import_jobs.id"), nullable=False)
    row_number: Mapped[Optional[int]] = mapped_column(Integer)
    column_name: Mapped[Optional[str]] = mapped_column(String(96))
    message: Mapped[Optional[str]] = mapped_column(Text)
    raw_value: Mapped[Optional[str]] = mapped_column(String(255))


class FeatureFlag(Base, TimestampMixin):
    __tablename__ = "feature_flags"

    name: Mapped[str] = mapped_column(String(96), primary_key=True)
    is_enabled: Mapped[Optional[bool]] = mapped_column(Boolean, default=False)
    rollout_percentage: Mapped[Optional[int]] = mapped_column(Integer, default=0)
    scope: Mapped[Optional[str]] = mapped_column(String(32), default="GLOBAL")
    description: Mapped[Optional[str]] = mapped_column(Text)
    # Which environment the flag applies to (DEVELOPMENT / STAGING / PRODUCTION).
    # Nullable so a pre-existing row is reported as "not set" rather than being
    # silently defaulted to production.
    environment: Mapped[Optional[str]] = mapped_column(String(32))
    # Who last changed the flag, resolved from the audit trail on read when this
    # column is null. Denormalised here so the console can render it without a
    # join, but it is not the source of truth — the audit log is.
    changed_by: Mapped[Optional[str]] = mapped_column(String(128))


class SystemSetting(Base, TimestampMixin):
    __tablename__ = "system_settings"

    key: Mapped[str] = mapped_column(String(128), primary_key=True)
    value: Mapped[Optional[str]] = mapped_column(String(512))
    value_type: Mapped[Optional[str]] = mapped_column(String(16), default="string")
    description: Mapped[Optional[str]] = mapped_column(Text)
    is_secret: Mapped[Optional[bool]] = mapped_column(Boolean, default=False)


class AdminNote(Base, TimestampMixin):
    __tablename__ = "admin_notes"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    entity_type: Mapped[Optional[str]] = mapped_column(String(64))
    entity_id: Mapped[Optional[int]] = mapped_column(Integer)
    note: Mapped[str] = mapped_column(Text, nullable=False)
    author: Mapped[Optional[str]] = mapped_column(String(128))


class SearchQuery(Base, TimestampMixin):
    """A customer search, for the search-quality surfaces."""

    __tablename__ = "search_queries"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    user_id: Mapped[Optional[int]] = mapped_column(Integer, ForeignKey("users.id"))
    query: Mapped[Optional[str]] = mapped_column(String(255))
    result_count: Mapped[Optional[int]] = mapped_column(Integer, default=0)
    location: Mapped[Optional[str]] = mapped_column(String(96))
    searched_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True))


class OperationalEvent(Base):
    """Persisted, non-sensitive events consumed by the admin live feed."""

    __tablename__ = "operational_events"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    type: Mapped[str] = mapped_column(String(48), nullable=False, index=True)
    title: Mapped[str] = mapped_column(String(200), nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, default=_now, index=True
    )
