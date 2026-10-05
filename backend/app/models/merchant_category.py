"""Merchant Category configuration models.

Centralized category configuration for the tiered merchant onboarding system.
Supports 11 merchant categories with configurable verification requirements.
"""
from sqlalchemy import String, Boolean, Integer, Text, ForeignKey, Enum
from sqlalchemy.orm import Mapped, mapped_column, relationship
import enum

from app.database.session import Base
from app.models.base import TimestampMixin


class MerchantCategoryCode(str, enum.Enum):
    """Category codes for all 11 merchant categories."""
    PHARMACY_HEALTHCARE = "PHARMACY_HEALTHCARE"
    BEAUTY_PERSONAL_CARE = "BEAUTY_PERSONAL_CARE"
    FURNITURE_HOME_CARE = "FURNITURE_HOME_CARE"
    HOUSEHOLD_GOODS = "HOUSEHOLD_GOODS"
    SPORTS_FITNESS_OUTDOOR = "SPORTS_FITNESS_OUTDOOR"
    BOOKS_MEDIA_STATIONERY = "BOOKS_MEDIA_STATIONERY"
    AUTOMOTIVE_PARTS_TOOLS = "AUTOMOTIVE_PARTS_TOOLS"
    HARDWARE = "HARDWARE"
    RESTAURANTS = "RESTAURANTS"
    TRANSPORT = "TRANSPORT"
    PERSONAL_TRANSPORT_TRAVEL = "PERSONAL_TRANSPORT_TRAVEL"


# ── Canonical category registry (SINGLE SOURCE OF TRUTH) ──────────────────────
# Codes live in ``MerchantCategoryCode`` (above). The human-readable display names
# live HERE so every consumer — seed data, request validators, db_seed, the test
# suite and the OpenAPI contract — derives from this ONE dict instead of re-typing
# the 11-item list. Grocery / General Food are deliberately absent.
MERCHANT_CATEGORY_NAMES: dict[str, str] = {
    MerchantCategoryCode.PHARMACY_HEALTHCARE.value: "Pharmacy & Healthcare",
    MerchantCategoryCode.BEAUTY_PERSONAL_CARE.value: "Beauty & Personal Care",
    MerchantCategoryCode.FURNITURE_HOME_CARE.value: "Furniture & Home Care",
    MerchantCategoryCode.HOUSEHOLD_GOODS.value: "Household Goods",
    MerchantCategoryCode.SPORTS_FITNESS_OUTDOOR.value: "Sports, Fitness & Outdoor",
    MerchantCategoryCode.BOOKS_MEDIA_STATIONERY.value: "Books, Media & Stationery",
    MerchantCategoryCode.AUTOMOTIVE_PARTS_TOOLS.value: "Automotive Parts & Tools",
    MerchantCategoryCode.HARDWARE.value: "Hardware",
    MerchantCategoryCode.RESTAURANTS.value: "Restaurants",
    MerchantCategoryCode.TRANSPORT.value: "Transport",
    MerchantCategoryCode.PERSONAL_TRANSPORT_TRAVEL.value: "Personal Transport / Personal Travel",
}

# Ordered canonical (code, display-name) pairs preserving the spec numbering.
MERCHANT_CATEGORIES: list[tuple[str, str]] = [
    (code, name) for code, name in MERCHANT_CATEGORY_NAMES.items()
]


# ── Category capability model (SINGLE SOURCE OF TRUTH) ───────────────────────
# What a business category can actually DO. The registration wizard and the
# data-entry forms are rendered FROM this: the app is told which capabilities
# apply and shows exactly those fields, rather than showing one giant form and
# hiding what does not apply.
#
# It lives beside the codes and names above for the same reason: a rule that
# exists in two places is a rule that eventually disagrees with itself.
# Grocery / General Food remain absent.
class CategoryCapability(str, enum.Enum):
    """Data-entry capabilities a business category can be granted."""

    PRODUCT_CATALOG = "PRODUCT_CATALOG"
    INVENTORY = "INVENTORY"
    PRICE = "PRICE"
    BARCODE = "BARCODE"
    OFFERS = "OFFERS"
    OPERATING_HOURS = "OPERATING_HOURS"
    SERVICES = "SERVICES"
    BOOKING = "BOOKING"
    CONTACT = "CONTACT"
    LOCATION = "LOCATION"
    IMPORT = "IMPORT"
    POS = "POS"
    DOCUMENTS = "DOCUMENTS"
    CATEGORY_SPECIFIC_DATA = "CATEGORY_SPECIFIC_DATA"


# Capabilities every business has whatever its category: you can always be
# contacted, and a shop that cannot state its location cannot be found. These
# are never stripped, which is what makes business-type narrowing safe.
_ALWAYS: tuple[CategoryCapability, ...] = (
    CategoryCapability.CONTACT,
    CategoryCapability.LOCATION,
)

_CATALOG: tuple[CategoryCapability, ...] = (
    CategoryCapability.PRODUCT_CATALOG,
    CategoryCapability.INVENTORY,
    CategoryCapability.PRICE,
    CategoryCapability.BARCODE,
    CategoryCapability.OFFERS,
    CategoryCapability.OPERATING_HOURS,
    CategoryCapability.IMPORT,
)

# Per-category capability sets, mirroring how each trade actually operates.
# A restaurant is not a product catalogue with a food SKU: it sells services,
# takes bookings and publishes a menu. A pharmacy is the opposite. Forcing one
# shape onto every category is what makes a capability model pointless.
MERCHANT_CATEGORY_CAPABILITIES: dict[str, tuple[CategoryCapability, ...]] = {
    MerchantCategoryCode.PHARMACY_HEALTHCARE.value: (
        *_CATALOG,
        CategoryCapability.POS,
        CategoryCapability.DOCUMENTS,  # drug licence
    ),
    MerchantCategoryCode.BEAUTY_PERSONAL_CARE.value: (
        *_CATALOG,
        CategoryCapability.SERVICES,
        CategoryCapability.BOOKING,
        CategoryCapability.POS,
    ),
    MerchantCategoryCode.FURNITURE_HOME_CARE.value: (
        *_CATALOG,
        # Bulky goods: installation and delivery are services, but a till sale
        # is not how furniture is bought, so POS is left out.
        CategoryCapability.SERVICES,
    ),
    MerchantCategoryCode.HOUSEHOLD_GOODS.value: (*_CATALOG, CategoryCapability.POS),
    MerchantCategoryCode.SPORTS_FITNESS_OUTDOOR.value: (
        *_CATALOG,
        CategoryCapability.SERVICES,  # coaching / fitting
        CategoryCapability.POS,
    ),
    MerchantCategoryCode.BOOKS_MEDIA_STATIONERY.value: (
        *_CATALOG,
        CategoryCapability.POS,
    ),
    MerchantCategoryCode.AUTOMOTIVE_PARTS_TOOLS.value: (
        *_CATALOG,
        CategoryCapability.SERVICES,  # fitting / installation
    ),
    MerchantCategoryCode.HARDWARE.value: (
        *_CATALOG,
        CategoryCapability.SERVICES,
    ),
    # Service-led categories: no product catalogue, no stock ledger.
    MerchantCategoryCode.RESTAURANTS.value: (
        CategoryCapability.PRICE,
        CategoryCapability.OFFERS,
        CategoryCapability.OPERATING_HOURS,
        CategoryCapability.SERVICES,
        CategoryCapability.BOOKING,
        CategoryCapability.POS,
        CategoryCapability.DOCUMENTS,  # FSSAI
        CategoryCapability.CATEGORY_SPECIFIC_DATA,  # menu
    ),
    MerchantCategoryCode.TRANSPORT.value: (
        CategoryCapability.PRICE,
        CategoryCapability.OFFERS,
        CategoryCapability.OPERATING_HOURS,
        CategoryCapability.SERVICES,
        CategoryCapability.BOOKING,
        CategoryCapability.DOCUMENTS,
        CategoryCapability.CATEGORY_SPECIFIC_DATA,  # routes / fares
    ),
    # Personal transport / personal travel — a travel agency, tour operator or
    # event-transport arranger, NOT a vehicle fleet.
    #
    # BOOKING and PRICE are deliberately absent even though the sibling
    # TRANSPORT entry grants them. Everything the transport models offer is bound
    # to a vehicle: `transport_bookings.vehicle_id -> vehicles.id`,
    # `vehicle_availability.vehicle_id`, `transport_services.provider_id ->
    # transport_providers.id`, and `trip_details` is a driver/odometer trip log
    # rather than an itinerary. A travel agency has no fleet row to attach those
    # to, so granting the capabilities would render booking and pricing screens
    # that have nothing behind them.
    #
    # This is the spec's rule applied literally: "Only render these when backend
    # capability exists." Re-add BOOKING and PRICE in the same commit that adds
    # a travel booking / package model, and the screens become honest.
    MerchantCategoryCode.PERSONAL_TRANSPORT_TRAVEL.value: (
        CategoryCapability.OFFERS,
        CategoryCapability.OPERATING_HOURS,
        CategoryCapability.SERVICES,
        CategoryCapability.DOCUMENTS,
        # Descriptive profile text only ("services you arrange", "travel details").
        # These land in `shops.capability_fields`, a real column — they describe
        # the business rather than pretending to be a package catalogue or an
        # availability schedule, neither of which the schema models.
        CategoryCapability.CATEGORY_SPECIFIC_DATA,
    ),
}

# Business type is the SECOND axis: it says HOW the category trades, and can
# narrow what applies. Narrowing only ever removes stock-shaped capabilities —
# a service-only type has no catalogue to fill, but still needs contact and
# location, which `resolve_capabilities` re-applies.
_SERVING_ONLY: tuple[CategoryCapability, ...] = (
    CategoryCapability.PRODUCT_CATALOG,
    CategoryCapability.INVENTORY,
    CategoryCapability.BARCODE,
    CategoryCapability.IMPORT,
    CategoryCapability.POS,
)

BUSINESS_TYPE_NARROWING: dict[str, tuple[CategoryCapability, ...]] = {
    "Service": _SERVING_ONLY,
    "Wholesale": (),  # trades the same catalogue, at volume
    "Retail": (),
    "Retail + Wholesale": (),
    "Other": (),  # unknown shape — stay permissive rather than hide features
}

# The exact vocabulary the wizard offers, so the client validates against the
# server instead of guessing, and a typo here fails the suite rather than
# silently dropping a narrowing rule.
BUSINESS_TYPES: tuple[str, ...] = tuple(BUSINESS_TYPE_NARROWING)


def is_known_business_type(value: str | None) -> bool:
    """Whether ``value`` is one of the five types this platform defines.

    An empty / missing value is allowed: the type is optional, and a shop that
    never chose one simply gets no narrowing rather than an error at creation.

    Everything else is checked rather than stored, because a value outside this
    tuple cannot match a narrowing rule. It would pass through
    ``resolve_capabilities`` as "unknown, stay permissive" — which looks correct
    and is indistinguishable from the type genuinely being Service. A silent
    permissive fallback on a typo is how a Service shop ends up shown a stock
    ledger, so the typo is refused at the edge instead.
    """
    text = str(value or "").strip()
    return text == "" or text in BUSINESS_TYPES


def resolve_capabilities(
    category_code: str, business_type: str | None = None
) -> tuple[CategoryCapability, ...] | None:
    """Capabilities for ``category_code``, narrowed by ``business_type``.

    Returns ``None`` for an unknown category — the caller answers 404, matching
    how an unknown category is treated everywhere else. An unknown or missing
    business type is permissive (no narrowing), because wrongly hiding a
    capability locks a shopkeeper out of something they may be entitled to,
    whereas wrongly showing one surfaces the moment they submit.

    Order is deterministic so the client renders a stable list without
    re-sorting.
    """
    base = MERCHANT_CATEGORY_CAPABILITIES.get(str(category_code or "").upper())
    if base is None:
        return None

    removed = set(BUSINESS_TYPE_NARROWING.get((business_type or "").strip(), ()))
    resolved = [c for c in base if c not in removed]
    for capability in _ALWAYS:
        if capability not in resolved:
            resolved.append(capability)
    return tuple(resolved)


def capabilities_for_category(
    category_code: str, business_type: str | None = None
) -> dict | None:
    """UI contract for the data-entry forms of one category.

    The app renders exactly this — it never decides for itself which fields a
    category has, because a client-side rule that disagrees with the server
    shows a shopkeeper a form the backend will reject.
    """
    resolved = resolve_capabilities(category_code, business_type)
    if resolved is None:
        return None
    return {
        "category_code": str(category_code).upper(),
        "business_type": (business_type or None),
        "capabilities": [c.value for c in resolved],
    }


class MerchantCategory(Base, TimestampMixin):
    """Centralized merchant category configuration.

    Each category defines what verification requirements apply to merchants
    registering under that category.
    """
    __tablename__ = "merchant_categories"

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    code: Mapped[str] = mapped_column(
        String(50), unique=True, nullable=False, index=True
    )
    name: Mapped[str] = mapped_column(String(100), nullable=False)
    description: Mapped[str | None] = mapped_column(Text)
    is_active: Mapped[bool] = mapped_column(
        Boolean, nullable=False, default=True, server_default="true"
    )
    sort_order: Mapped[int] = mapped_column(Integer, default=0, server_default="0")

    # Relationships
    requirements = relationship(
        "MerchantVerificationRequirement",
        back_populates="category",
        cascade="all, delete-orphan",
    )


class VerificationMethod(str, enum.Enum):
    """How a requirement can be verified."""
    PHONE_OTP = "PHONE_OTP"
    GSTIN_VERIFY = "GSTIN_VERIFY"
    UDYAM_VERIFY = "UDYAM_VERIFY"
    BANK_PENNY_DROP = "BANK_PENNY_DROP"
    DRUG_LICENSE_VERIFY = "DRUG_LICENSE_VERIFY"
    FSSAI_LICENSE_VERIFY = "FSSAI_LICENSE_VERIFY"
    DRIVING_LICENSE_VERIFY = "DRIVING_LICENSE_VERIFY"
    VEHICLE_RC_VERIFY = "VEHICLE_RC_VERIFY"
    ADMIN_REVIEW = "ADMIN_REVIEW"


class MerchantVerificationRequirement(Base, TimestampMixin):
    """Category-specific verification requirement configuration.

    Defines what documents/verifications are required for each category.
    This allows adding new categories/requirements without code changes.
    """
    __tablename__ = "merchant_verification_requirements"

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    category_id: Mapped[int] = mapped_column(
        ForeignKey("merchant_categories.id", ondelete="CASCADE"),
        index=True,
        nullable=False,
    )
    requirement_code: Mapped[str] = mapped_column(String(50), nullable=False)
    requirement_name: Mapped[str] = mapped_column(String(100), nullable=False)
    description: Mapped[str | None] = mapped_column(Text)
    is_required: Mapped[bool] = mapped_column(
        Boolean, nullable=False, default=True, server_default="true"
    )
    verification_method: Mapped[str] = mapped_column(String(50), nullable=False)
    requires_admin_review: Mapped[bool] = mapped_column(
        Boolean, nullable=False, default=False, server_default="false"
    )
    is_active: Mapped[bool] = mapped_column(
        Boolean, nullable=False, default=True, server_default="true"
    )
    sort_order: Mapped[int] = mapped_column(Integer, default=0, server_default="0")

    # Relationships
    category = relationship("MerchantCategory", back_populates="requirements")
