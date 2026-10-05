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


# The two vocabularies below are distinct on purpose and deliberately do
# NOT share a name with the data-entry table above: one says what a
# CATEGORY MAY DO in this app, the other says what a CUSTOMER MAY BE SHOWN
# for a category. Sharing a name let the second shadow the first.
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

MERCHANT_CATEGORY_CUSTOMER_CAPABILITIES: dict[str, tuple[str, ...]] = {
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
assert set(MERCHANT_CATEGORY_CUSTOMER_CAPABILITIES) == {c.value for c in MerchantCategoryCode}, (
    "MERCHANT_CATEGORY_CUSTOMER_CAPABILITIES must cover exactly the 11 MerchantCategoryCode values"
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
    return MERCHANT_CATEGORY_CUSTOMER_CAPABILITIES.get(
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
        resolved = MERCHANT_CATEGORY_CUSTOMER_CAPABILITIES.get(
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
