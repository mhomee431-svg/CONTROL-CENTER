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


# ── Customer-facing capability vocabulary (SINGLE SOURCE OF TRUTH) ────────────
# WHAT A CUSTOMER MAY BE SHOWN, derived from the business's category.
#
# This module already owns the 11 category codes and their display names, so the
# capability map lives HERE rather than as `if category == ...` branches spread
# over the API and the Flutter app. A category added later, or a capability added
# to an existing one, is then a one-line change that no app release has to
# repeat.
#
# WHY A CAPABILITY LIST AND NOT "IS_PRODUCT" / "IS_SERVICE"
# --------------------------------------------------------
# A boolean forces every consumer to invent the rest. "Not a product shop" says
# nothing about whether a menu, a contacting action or a quote form should be
# shown, so each screen ends up guessing, and the guesses disagree. A capability
# list states exactly what exists, and a screen renders what it is given —
# nothing more. That is the whole point: a restaurant must never inherit a
# product grid, and a transport provider must never inherit a price/stock card.
class CustomerCapability(str, enum.Enum):
    """One thing a category may expose to the customer."""

    # Price + stock + distance listings (the platform's core domain).
    PRODUCT_CATALOG = "product_catalog"
    # Display-only restaurant menu. Never stock, never cart, never checkout.
    MENU = "menu"
    # Service details: a provider's offerings, fleet, or comparable.
    SERVICE_PROFILE = "service_profile"
    # Availability information (vehicle counts, availability windows).
    AVAILABILITY = "availability"
    # The customer may REQUEST a quote/booking. Deliberately only for categories
    # whose backend contract actually exists, so the button cannot lead to a
    # request that was never implemented.
    QUOTE_REQUEST = "quote_request"
    CONTACT = "contact"
    DIRECTIONS = "directions"
    RATINGS = "ratings"
    OFFERS = "offers"


# A physical product business: the classic discovery flow.
_PRODUCT_SHOP_CAPABILITIES: tuple[str, ...] = (
    CustomerCapability.PRODUCT_CATALOG.value,
    CustomerCapability.AVAILABILITY.value,
    CustomerCapability.CONTACT.value,
    CustomerCapability.DIRECTIONS.value,
    CustomerCapability.RATINGS.value,
    CustomerCapability.OFFERS.value,
)

# Restaurants: discovery-only (Master Spec §27, Rule 4). A menu with DISPLAY
# prices is the whole surface — no PRODUCT_CATALOG, and therefore no price/stock
# grid, no cart, no delivery, no checkout.
_RESTAURANT_CAPABILITIES: tuple[str, ...] = (
    CustomerCapability.MENU.value,
    CustomerCapability.CONTACT.value,
    CustomerCapability.DIRECTIONS.value,
    CustomerCapability.RATINGS.value,
    CustomerCapability.OFFERS.value,
)

# Transport: a SERVICE domain (Master Spec §28). ``quote_request`` is honest here
# only because ``/transport/quotes`` exists; the app never invents a booking
# flow that the backend cannot serve.
_TRANSPORT_CAPABILITIES: tuple[str, ...] = (
    CustomerCapability.SERVICE_PROFILE.value,
    CustomerCapability.AVAILABILITY.value,
    CustomerCapability.QUOTE_REQUEST.value,
    CustomerCapability.CONTACT.value,
    CustomerCapability.DIRECTIONS.value,
    CustomerCapability.RATINGS.value,
)

# Personal transport / travel: a travel agency or provider profile with a
# request entry point (Master Spec §29).
_TRAVEL_CAPABILITIES: tuple[str, ...] = (
    CustomerCapability.SERVICE_PROFILE.value,
    CustomerCapability.QUOTE_REQUEST.value,
    CustomerCapability.CONTACT.value,
    CustomerCapability.DIRECTIONS.value,
    CustomerCapability.RATINGS.value,
)

MERCHANT_CATEGORY_CAPABILITIES: dict[str, tuple[str, ...]] = {
    MerchantCategoryCode.PHARMACY_HEALTHCARE.value: _PRODUCT_SHOP_CAPABILITIES,
    MerchantCategoryCode.BEAUTY_PERSONAL_CARE.value: _PRODUCT_SHOP_CAPABILITIES,
    MerchantCategoryCode.FURNITURE_HOME_CARE.value: _PRODUCT_SHOP_CAPABILITIES,
    MerchantCategoryCode.HOUSEHOLD_GOODS.value: _PRODUCT_SHOP_CAPABILITIES,
    MerchantCategoryCode.SPORTS_FITNESS_OUTDOOR.value: _PRODUCT_SHOP_CAPABILITIES,
    MerchantCategoryCode.BOOKS_MEDIA_STATIONERY.value: _PRODUCT_SHOP_CAPABILITIES,
    MerchantCategoryCode.AUTOMOTIVE_PARTS_TOOLS.value: _PRODUCT_SHOP_CAPABILITIES,
    MerchantCategoryCode.HARDWARE.value: _PRODUCT_SHOP_CAPABILITIES,
    MerchantCategoryCode.RESTAURANTS.value: _RESTAURANT_CAPABILITIES,
    MerchantCategoryCode.TRANSPORT.value: _TRANSPORT_CAPABILITIES,
    MerchantCategoryCode.PERSONAL_TRANSPORT_TRAVEL.value: _TRAVEL_CAPABILITIES,
}

# Coverage guards. A category missing from the map would silently render as the
# product default (or as nothing at all), which is exactly the drift this
# registry exists to prevent — so it fails at import instead of in production.
assert set(MERCHANT_CATEGORY_CAPABILITIES) == {c.value for c in MerchantCategoryCode}, (
    "MERCHANT_CATEGORY_CAPABILITIES must cover exactly the 11 MerchantCategoryCode values"
)
assert CustomerCapability.PRODUCT_CATALOG.value not in _RESTAURANT_CAPABILITIES, (
    "a restaurant must never be given a product catalog: a price/stock grid is the "
    "first step toward cart/checkout/delivery, which Rule 4 forbids"
)
assert CustomerCapability.PRODUCT_CATALOG.value not in _TRANSPORT_CAPABILITIES
assert CustomerCapability.PRODUCT_CATALOG.value not in _TRAVEL_CAPABILITIES, (
    "service categories must not be given product-style price/stock UI"
)

# Legacy shops predate merchant onboarding and carry only the older
# ``shops.category`` enum. Only RESTAURANT differs from the product default, and
# it is unambiguous there, so the legacy bridge stays a single entry rather than
# a second full copy of the table.
LEGACY_SHOP_CATEGORY_CAPABILITIES: dict[str, tuple[str, ...]] = {
    "RESTAURANT": _RESTAURANT_CAPABILITIES,
}

# The fallback for a shop with no category signal at all. The platform's core
# promise is product discovery and a physical shop is the overwhelming common
# case, so this is the product set — NOT an empty one, which would leave a shop
# showing nothing at all.
DEFAULT_SHOP_CAPABILITIES: tuple[str, ...] = _PRODUCT_SHOP_CAPABILITIES

# A shop whose free-form ``business_type`` says "Service" but whose category is
# unknown. It gets the service profile — deliberately WITHOUT ``quote_request``:
# a request/booking entry point is only offered when a provider record exists
# behind it (transport / personal travel), and offering one for a generic
# service business would be faking a booking contract.
SERVICE_BUSINESS_CAPABILITIES: tuple[str, ...] = (
    CustomerCapability.SERVICE_PROFILE.value,
    CustomerCapability.AVAILABILITY.value,
    CustomerCapability.CONTACT.value,
    CustomerCapability.DIRECTIONS.value,
    CustomerCapability.RATINGS.value,
    CustomerCapability.OFFERS.value,
)


def capabilities_for_merchant_category(code: str | None) -> tuple[str, ...]:
    """Capabilities for a canonical merchant-category code, or the default."""
    if not code:
        return DEFAULT_SHOP_CAPABILITIES
    return MERCHANT_CATEGORY_CAPABILITIES.get(
        code.strip().upper(), DEFAULT_SHOP_CAPABILITIES
    )


def resolve_customer_capabilities(
    *,
    merchant_category_code: str | None = None,
    legacy_shop_category: str | None = None,
    business_type: str | None = None,
) -> tuple[str, ...]:
    """What a customer may be shown for one business.

    The resolution ORDER is the contract, not an implementation detail:

    1. the merchant-onboarding category code — the authoritative record, which
       covers all 11 approved categories;
    2. the legacy ``shops.category`` enum, for shops that predate onboarding —
       only RESTAURANT is unambiguous there, so everything else keeps the default
       rather than guessing between the four codes that collapse onto "OTHER";
    3. ``business_type == "Service"`` — the only signal a service business whose
       category is unrecognised can give;
    4. the product default.

    Pure and total: every combination of inputs returns a non-empty tuple, so no
    caller has to decide what "no capabilities" should look like on screen.
    """
    if merchant_category_code:
        resolved = MERCHANT_CATEGORY_CAPABILITIES.get(
            merchant_category_code.strip().upper()
        )
        if resolved:
            return resolved

    if legacy_shop_category:
        resolved = LEGACY_SHOP_CATEGORY_CAPABILITIES.get(
            legacy_shop_category.strip().upper()
        )
        if resolved:
            return resolved

    if business_type and business_type.strip().lower() == "service":
        return SERVICE_BUSINESS_CAPABILITIES

    return DEFAULT_SHOP_CAPABILITIES


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
