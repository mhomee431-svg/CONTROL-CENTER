"""Shop, ShopOwner, ShopManager, ShopAddress, ShopHours, ShopHoliday, ShopDocument, ShopVerification models."""
from datetime import date, datetime, time
from sqlalchemy import (
    String, Float, Integer, DateTime, Boolean, Text, ForeignKey, Enum, Time, Date, UniqueConstraint, CheckConstraint
)
from sqlalchemy.orm import Mapped, mapped_column, relationship
from geoalchemy2 import Geography
import enum

from app.database.session import Base
from app.models.base import TimestampMixin, SoftDeleteMixin


class ShopStatus(str, enum.Enum):
    REGISTERED = "REGISTERED"
    DOCUMENTS_SUBMITTED = "DOCUMENTS_SUBMITTED"
    PENDING_VERIFICATION = "PENDING_VERIFICATION"
    VERIFIED = "VERIFIED"
    REJECTED = "REJECTED"
    SUSPENDED = "SUSPENDED"
    ACTIVE = "ACTIVE"
    CLOSED = "CLOSED"


class VerificationStatus(str, enum.Enum):
    PENDING = "PENDING"
    SUBMITTED = "SUBMITTED"
    UNDER_REVIEW = "UNDER_REVIEW"
    VERIFIED = "VERIFIED"
    REJECTED = "REJECTED"
    EXPIRED = "EXPIRED"


class ShopCategory(str, enum.Enum):
    GROCERY = "GROCERY"
    ELECTRONICS = "ELECTRONICS"
    PHARMACY = "PHARMACY"
    HARDWARE = "HARDWARE"
    FASHION = "FASHION"
    RESTAURANT = "RESTAURANT"
    BAKERY = "BAKERY"
    DAIRY = "DAIRY"
    MEAT = "MEAT"
    VEGETABLES = "VEGETABLES"
    STATIONERY = "STATIONERY"
    TOYS = "TOYS"
    BEAUTY = "BEAUTY"
    OTHER = "OTHER"


# ── Location capture metadata (Phase: Shop Location System) ──────────────────
# These enums describe the QUALITY and PROVENANCE of the coordinates stored on
# the shop, keeping them strictly separate from business verification status.
class LocationSource(str, enum.Enum):
    """How the shop location was determined."""
    GPS = "GPS"                       # device GNSS fix
    MANUAL = "MANUAL"                # shopkeeper tapped/edited the pin
    ADDRESS = "ADDRESS"              # derived from a text address lookup


class LocationType(str, enum.Enum):
    """Semantic meaning of the stored coordinates — always a customer access point."""
    SHOP_ENTRANCE = "SHOP_ENTRANCE"
    BUILDING_CENTER = "BUILDING_CENTER"
    OTHER = "OTHER"


class LocationStatus(str, enum.Enum):
    """Lifecycle of a captured location reading."""
    CAPTURED = "CAPTURED"            # freshly captured, pending review
    CONFIRMED = "CONFIRMED"          # shopkeeper confirmed the pin/accuracy
    CORRECTED = "CORRECTED"          # subsequently edited via controlled flow
    STALE = "STALE"                  # reading is older than max age


class LocationIntegrityStatus(str, enum.Enum):
    """Client-side mock-location / suspicious-fix signal (NOT tamper-proof)."""
    NORMAL = "NORMAL"
    SUSPICIOUS = "SUSPICIOUS"
    UNKNOWN = "UNKNOWN"


class Shop(Base, TimestampMixin, SoftDeleteMixin):
    __tablename__ = "shops"
    __table_args__ = (
        CheckConstraint("rating >= 0 AND rating <= 5", name="ck_shops_rating_range"),
        CheckConstraint("review_count >= 0", name="ck_shops_review_count_non_negative"),
    )

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    name: Mapped[str] = mapped_column(String(255), nullable=False, index=True)
    slug: Mapped[str | None] = mapped_column(String(280), unique=True, index=True)
    description: Mapped[str | None] = mapped_column(Text)
    tagline: Mapped[str | None] = mapped_column(String(255))
    image_url: Mapped[str | None] = mapped_column(String(500))
    cover_image_url: Mapped[str | None] = mapped_column(String(500))
    logo_url: Mapped[str | None] = mapped_column(String(500))
    phone: Mapped[str | None] = mapped_column(String(20), index=True)
    alternate_phone: Mapped[str | None] = mapped_column(String(20))
    email: Mapped[str | None] = mapped_column(String(255))
    website_url: Mapped[str | None] = mapped_column(String(500))
    whatsapp_number: Mapped[str | None] = mapped_column(String(20))
    status: Mapped[ShopStatus] = mapped_column(
        Enum(ShopStatus, name="shop_status"), nullable=False, default=ShopStatus.REGISTERED
    )
    rating: Mapped[float] = mapped_column(Float, default=0.0)
    review_count: Mapped[int] = mapped_column(Integer, default=0)
    is_verified: Mapped[bool] = mapped_column(Boolean, default=False)
    is_featured: Mapped[bool] = mapped_column(Boolean, default=False)
    is_open_24x7: Mapped[bool] = mapped_column(Boolean, default=False)
    is_accepting_orders: Mapped[bool] = mapped_column(Boolean, default=True)
    category: Mapped[ShopCategory | None] = mapped_column(
        Enum(ShopCategory, name="shop_category"), index=True
    )
    subcategories: Mapped[str | None] = mapped_column(String(500))  # JSON array of subcategories
    location: Mapped[object] = mapped_column(
        Geography(geometry_type="POINT", srid=4326, spatial_index=True), nullable=False
    )
    latitude: Mapped[float | None] = mapped_column(Float)
    longitude: Mapped[float | None] = mapped_column(Float)
    # ── Location capture metadata (Phase: Shop Location System) ────────────────
    # Accuracy of the captured fix in meters (NULL until a verified capture).
    accuracy_meters: Mapped[float | None] = mapped_column(Float, nullable=True)
    # When the location reading was captured on the device (UTC, tz-aware).
    location_captured_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    # How the coordinates were obtained: GPS / MANUAL / ADDRESS.
    location_source: Mapped[str] = mapped_column(
        String(20), nullable=False, server_default=LocationSource.GPS.value
    )
    # Semantic anchor of the pin: SHOP_ENTRANCE (preferred) / BUILDING_CENTER / OTHER.
    location_type: Mapped[str] = mapped_column(
        String(30), nullable=False, server_default=LocationType.SHOP_ENTRANCE.value
    )
    # Capture-readiness lifecycle: CAPTURED / CONFIRMED / CORRECTED / STALE.
    location_status: Mapped[str] = mapped_column(
        String(20), nullable=False, server_default=LocationStatus.CAPTURED.value
    )
    # Client-side mock-location signal — informative only, never trusted blindly.
    location_integrity_status: Mapped[str] = mapped_column(
        String(20), nullable=False, server_default=LocationIntegrityStatus.UNKNOWN.value
    )
    # Whether the shopkeeper confirmed the captured location at the access point.
    # Distinct from [is_verified], which is ADMIN business-document verification.
    location_verified: Mapped[bool] = mapped_column(Boolean, default=False)
    verified_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    last_inventory_update: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), index=True)
    rejection_reason: Mapped[str | None] = mapped_column(Text)
    suspension_reason: Mapped[str | None] = mapped_column(Text)
    suspended_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    reactivated_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    closed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    min_order_amount: Mapped[float | None] = mapped_column(Float, default=0.0)
    delivery_radius_km: Mapped[float | None] = mapped_column(Float, default=5.0)
    delivery_fee: Mapped[float | None] = mapped_column(Float, default=0.0)
    free_delivery_above: Mapped[float | None] = mapped_column(Float, default=0.0)
    is_delivery_available: Mapped[bool] = mapped_column(Boolean, default=True)
    is_pickup_available: Mapped[bool] = mapped_column(Boolean, default=True)
    gstin: Mapped[str | None] = mapped_column(String(50))
    fssai_license: Mapped[str | None] = mapped_column(String(50))
    established_year: Mapped[int | None] = mapped_column(Integer)
    created_by: Mapped[int | None] = mapped_column(ForeignKey("users.id"))

    owners = relationship("ShopOwner", back_populates="shop", cascade="all, delete-orphan")
    managers = relationship("ShopManager", back_populates="shop", cascade="all, delete-orphan")
    addresses = relationship("ShopAddress", back_populates="shop", cascade="all, delete-orphan")
    hours = relationship("ShopHour", back_populates="shop", cascade="all, delete-orphan")
    holidays = relationship("ShopHoliday", back_populates="shop", cascade="all, delete-orphan")
    documents = relationship("ShopDocument", back_populates="shop", cascade="all, delete-orphan")
    verifications = relationship("ShopVerification", back_populates="shop", cascade="all, delete-orphan")
    onboarding = relationship(
        "MerchantOnboarding", back_populates="shop", uselist=False
    )
    shop_products = relationship("ShopProduct", back_populates="shop", cascade="all, delete-orphan")
    saved_by_users = relationship("SavedShop", back_populates="shop", cascade="all, delete-orphan")
    pos_devices = relationship("POSDevice", back_populates="shop", cascade="all, delete-orphan")
    pos_sync_jobs = relationship("POSSyncJob", back_populates="shop", cascade="all, delete-orphan")
    offers = relationship("Offer", back_populates="shop", cascade="all, delete-orphan")
    subscription = relationship("Subscription", back_populates="shop", uselist=False)


class ShopOwner(Base, TimestampMixin, SoftDeleteMixin):
    __tablename__ = "shop_owners"
    __table_args__ = (
        UniqueConstraint("shop_id", "user_id", name="uq_shop_owner_shop_user"),
    )

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    shop_id: Mapped[int] = mapped_column(ForeignKey("shops.id"), index=True, nullable=False)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id"), index=True, nullable=False)
    is_primary: Mapped[bool] = mapped_column(Boolean, default=False)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)

    shop = relationship("Shop", back_populates="owners")
    user = relationship("User")


class ShopManager(Base, TimestampMixin, SoftDeleteMixin):
    __tablename__ = "shop_managers"
    __table_args__ = (
        UniqueConstraint("shop_id", "user_id", name="uq_shop_manager_shop_user"),
    )

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    shop_id: Mapped[int] = mapped_column(ForeignKey("shops.id"), index=True, nullable=False)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id"), index=True, nullable=False)
    permissions: Mapped[str | None] = mapped_column(String(500))  # JSON array of granted permissions
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)

    shop = relationship("Shop", back_populates="managers")
    user = relationship("User")


class ShopAddress(Base, TimestampMixin, SoftDeleteMixin):
    __tablename__ = "shop_addresses"

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    shop_id: Mapped[int] = mapped_column(ForeignKey("shops.id"), index=True, nullable=False)
    address_line1: Mapped[str] = mapped_column(String(255), nullable=False)
    address_line2: Mapped[str | None] = mapped_column(String(255))
    landmark: Mapped[str | None] = mapped_column(String(255))
    city: Mapped[str] = mapped_column(String(100), nullable=False, index=True)
    state: Mapped[str] = mapped_column(String(100), nullable=False)
    pincode: Mapped[str] = mapped_column(String(10), nullable=False, index=True)
    country: Mapped[str] = mapped_column(String(100), default="India")
    latitude: Mapped[float | None] = mapped_column(Float)
    longitude: Mapped[float | None] = mapped_column(Float)
    location: Mapped[object | None] = mapped_column(
        Geography(geometry_type="POINT", srid=4326, spatial_index=True),
        nullable=True,
    )
    is_primary: Mapped[bool] = mapped_column(Boolean, default=True)
    is_verified: Mapped[bool] = mapped_column(Boolean, default=False)

    shop = relationship("Shop", back_populates="addresses")


class ShopHour(Base, TimestampMixin):
    __tablename__ = "shop_hours"
    __table_args__ = (
        UniqueConstraint("shop_id", "day_of_week", name="uq_shop_hours_shop_day"),
        CheckConstraint("day_of_week >= 0 AND day_of_week <= 6", name="ck_shop_hours_day_range"),
    )

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    shop_id: Mapped[int] = mapped_column(ForeignKey("shops.id"), index=True, nullable=False)
    day_of_week: Mapped[int] = mapped_column(Integer, nullable=False)  # 0=Monday ... 6=Sunday
    open_time: Mapped[time] = mapped_column(Time, nullable=False)
    close_time: Mapped[time] = mapped_column(Time, nullable=False)
    is_closed: Mapped[bool] = mapped_column(Boolean, default=False)

    shop = relationship("Shop", back_populates="hours")


class ShopHoliday(Base, TimestampMixin):
    __tablename__ = "shop_holidays"

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    shop_id: Mapped[int] = mapped_column(ForeignKey("shops.id"), index=True, nullable=False)
    holiday_date: Mapped[date] = mapped_column(Date, nullable=False, index=True)
    reason: Mapped[str | None] = mapped_column(String(255))
    is_recurring_yearly: Mapped[bool] = mapped_column(Boolean, default=False)

    shop = relationship("Shop", back_populates="holidays")


class ShopDocument(Base, TimestampMixin, SoftDeleteMixin):
    __tablename__ = "shop_documents"

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    shop_id: Mapped[int] = mapped_column(ForeignKey("shops.id"), index=True, nullable=False)
    document_type: Mapped[str] = mapped_column(String(50), nullable=False)  # GST, License, PAN, etc.
    document_url: Mapped[str] = mapped_column(String(500), nullable=False)
    document_number: Mapped[str | None] = mapped_column(String(100))
    expires_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    is_verified: Mapped[bool] = mapped_column(Boolean, default=False)
    verified_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    verified_by: Mapped[int | None] = mapped_column(ForeignKey("users.id"))
    rejection_reason: Mapped[str | None] = mapped_column(Text)

    shop = relationship("Shop", back_populates="documents")


class ShopVerification(Base, TimestampMixin):
    __tablename__ = "shop_verifications"

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    shop_id: Mapped[int] = mapped_column(ForeignKey("shops.id"), index=True, nullable=False)
    status: Mapped[VerificationStatus] = mapped_column(
        Enum(VerificationStatus, name="verification_status"), nullable=False, default=VerificationStatus.PENDING
    )
    submitted_by: Mapped[int | None] = mapped_column(ForeignKey("users.id"))
    reviewed_by: Mapped[int | None] = mapped_column(ForeignKey("users.id"))
    review_notes: Mapped[str | None] = mapped_column(Text)
    submitted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    reviewed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    verified_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    expires_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))

    shop = relationship("Shop", back_populates="verifications")