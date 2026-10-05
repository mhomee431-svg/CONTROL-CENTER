"""CATEGORY CAPABILITY MODEL — the Category + Business Type -> Capabilities rule.

The spec this implements is that data-entry fields must be capability-driven:
the app renders the form the backend describes rather than one giant form, and
it must not invent category rules the backend does not support. That only holds
if the rule lives in exactly one place, so these tests read the registry itself
and pin the properties the client relies on.

The properties that matter, and why each is a bug if it breaks:

  * every category resolves — a missing entry means the shopkeeper cannot
    register at all, and the client gets a 404 instead of a form
  * CONTACT and LOCATION always survive narrowing — a business that cannot be
    contacted or found is not usable, so narrowing may never remove them
  * a service-led category is NOT a stock ledger — if RESTAURANTS ever gained
    INVENTORY, the app would show a stock screen a restaurant has no use for
  * narrowing only ever removes — it must never ADD a capability the category
    did not have, or "Service" could silently grant POS to a category that
    never had it
"""

from app.models.merchant_category import (
    BUSINESS_TYPES,
    BUSINESS_TYPE_NARROWING,
    MERCHANT_CATEGORIES,
    MERCHANT_CATEGORY_CAPABILITIES,
    MERCHANT_CATEGORY_NAMES,
    CategoryCapability,
    capabilities_for_category,
    resolve_capabilities,
)

# Categories that trade in services/menus/bookings rather than stocked SKUs.
SERVICE_LED = {
    "RESTAURANTS",
    "TRANSPORT",
    "PERSONAL_TRANSPORT_TRAVEL",
}


class TestRegistryCoverage:
    def test_every_approved_category_has_capabilities(self):
        for code, _name in MERCHANT_CATEGORIES:
            assert code in MERCHANT_CATEGORY_CAPABILITIES, (
                f"{code} is an approved category but has no capability set — "
                "the app would receive a 404 instead of a form"
            )

    def test_no_capability_set_exists_for_an_unapproved_category(self):
        # A capability entry for a category the registry does not list is dead
        # configuration nobody will ever exercise.
        approved = {code for code, _ in MERCHANT_CATEGORIES}
        assert set(MERCHANT_CATEGORY_CAPABILITIES) == approved

    def test_no_forbidden_food_category_appears(self):
        for code in MERCHANT_CATEGORY_CAPABILITIES:
            for word in ("GROCERY", "FOOD", "DELIVERY", "SUPERMARKET"):
                assert word not in code, f"{code} is not an approved category"

    def test_every_capability_entry_is_non_empty(self):
        for code, caps in MERCHANT_CATEGORY_CAPABILITIES.items():
            assert caps, f"{code} resolved to no capabilities at all"


class TestResolution:
    def test_known_category_resolves(self):
        resolved = resolve_capabilities("PHARMACY_HEALTHCARE")
        assert resolved is not None
        assert CategoryCapability.PRODUCT_CATALOG in resolved
        assert CategoryCapability.INVENTORY in resolved

    def test_category_code_is_case_insensitive(self):
        assert resolve_capabilities("pharmacy_healthcare") == resolve_capabilities(
            "PHARMACY_HEALTHCARE"
        )

    def test_unknown_category_returns_none(self):
        # None is what makes the route answer 404; returning an empty set would
        # render an empty form with no explanation.
        assert resolve_capabilities("NOT_A_CATEGORY") is None
        assert resolve_capabilities("") is None
        assert resolve_capabilities(None) is None

    def test_service_led_categories_have_no_stock_ledger(self):
        for code in SERVICE_LED:
            resolved = resolve_capabilities(code)
            assert CategoryCapability.PRODUCT_CATALOG not in resolved, (
                f"{code} sells services, not stocked SKUs — a product catalogue "
                "would make the app show a screen the category cannot use"
            )
            assert CategoryCapability.INVENTORY not in resolved, (
                f"{code} has no stock ledger to maintain"
            )
            # BOOKING is asserted per category, not for every service-led one.
            # It used to be a blanket expectation, which quietly assumed that
            # "sells services" implies "can be booked". Personal transport /
            # personal travel breaks that: every booking model in the schema is
            # chained to a `vehicles` row, and a travel agency has no fleet, so
            # granting it there would render a booking screen that cannot book.
            if code == "PERSONAL_TRANSPORT_TRAVEL":
                assert CategoryCapability.BOOKING not in resolved, (
                    "a travel agency has no vehicle to attach a booking to; the "
                    "capability must stay off until a travel booking model exists"
                )
            else:
                assert CategoryCapability.BOOKING in resolved, (
                    f"{code} is backed by transport_bookings"
                )
            assert CategoryCapability.SERVICES in resolved

    def test_stock_categories_keep_their_catalogue(self):
        for code in ("PHARMACY_HEALTHCARE", "HOUSEHOLD_GOODS", "HARDWARE"):
            resolved = resolve_capabilities(code)
            assert CategoryCapability.PRODUCT_CATALOG in resolved
            assert CategoryCapability.INVENTORY in resolved


class TestBusinessTypeNarrowing:
    def test_service_type_drops_stock_capabilities(self):
        resolved = resolve_capabilities("HOUSEHOLD_GOODS", "Service")
        assert CategoryCapability.PRODUCT_CATALOG not in resolved
        assert CategoryCapability.INVENTORY not in resolved
        assert CategoryCapability.BARCODE not in resolved
        assert CategoryCapability.POS not in resolved

    def test_narrowing_never_removes_contact_or_location(self):
        # The safety invariant. Narrowing may hide stock features but must never
        # leave a business unfindable or uncontactable.
        for code, _ in MERCHANT_CATEGORIES:
            for business_type in BUSINESS_TYPES:
                resolved = resolve_capabilities(code, business_type)
                assert resolved is not None
                assert CategoryCapability.CONTACT in resolved, (
                    f"{code}/{business_type} lost CONTACT"
                )
                assert CategoryCapability.LOCATION in resolved, (
                    f"{code}/{business_type} lost LOCATION"
                )

    def test_narrowing_only_removes_and_never_adds(self):
        # Otherwise "Service" could silently grant a capability the category never
        # had, and the client would render a screen the backend refuses.
        for code, _caps in MERCHANT_CATEGORIES:
            base = set(resolve_capabilities(code) or ())
            for business_type in BUSINESS_TYPES:
                narrowed = set(resolve_capabilities(code, business_type) or ())
                unexpected = narrowed - base
                assert unexpected <= {
                    CategoryCapability.CONTACT,
                    CategoryCapability.LOCATION,
                }, (
                    f"{code}/{business_type} gained {unexpected} — narrowing "
                    "may only remove stock-shaped capabilities"
                )

    def test_retail_and_wholesale_do_not_narrow(self):
        for code, _ in MERCHANT_CATEGORIES:
            for business_type in ("Retail", "Wholesale", "Retail + Wholesale"):
                assert (
                    resolve_capabilities(code, business_type)
                    == resolve_capabilities(code)
                )

    def test_unknown_business_type_is_permissive(self):
        # Wrongly hiding a capability locks a shopkeeper out of something they
        # may be entitled to; wrongly showing one surfaces on submit. The
        # permissive failure is the safer one.
        assert resolve_capabilities("HOUSEHOLD_GOODS", "Something Else") == (
            resolve_capabilities("HOUSEHOLD_GOODS")
        )
        assert resolve_capabilities("HOUSEHOLD_GOODS", None) == (
            resolve_capabilities("HOUSEHOLD_GOODS")
        )

    def test_resolution_is_deterministic(self):
        # The client renders the list in the order it arrives; unstable order
        # would make the form reshuffle between rebuilds.
        first = resolve_capabilities("PHARMACY_HEALTHCARE", "Retail")
        for _ in range(5):
            assert resolve_capabilities("PHARMACY_HEALTHCARE", "Retail") == first

    def test_no_capability_is_duplicated(self):
        for code, _ in MERCHANT_CATEGORIES:
            for business_type in BUSINESS_TYPES:
                resolved = resolve_capabilities(code, business_type)
                assert len(resolved) == len(set(resolved)), (
                    f"{code}/{business_type} produced a duplicate capability"
                )


class TestVocabulary:
    def test_business_types_match_the_wizard_options(self):
        assert set(BUSINESS_TYPES) == set(BUSINESS_TYPE_NARROWING)

    def test_business_types_are_non_empty_and_unique(self):
        assert BUSINESS_TYPES
        assert len(set(BUSINESS_TYPES)) == len(BUSINESS_TYPES)

    def test_capability_names_are_stable_strings(self):
        # They cross the wire; a rename here is a client-visible break.
        for capability in CategoryCapability:
            assert capability.value.isupper()
            assert " " not in capability.value


class TestUiContract:
    def test_contract_shape(self):
        data = capabilities_for_category("RESTAURANTS", "Service")
        assert data is not None
        assert data["category_code"] == "RESTAURANTS"
        assert data["business_type"] == "Service"
        assert isinstance(data["capabilities"], list)
        assert all(isinstance(c, str) for c in data["capabilities"])

    def test_unknown_category_yields_no_contract(self):
        assert capabilities_for_category("NOPE") is None

    def test_contract_capabilities_match_the_resolver(self):
        for code, _ in MERCHANT_CATEGORIES:
            for business_type in (None, *BUSINESS_TYPES):
                data = capabilities_for_category(code, business_type)
                expected = [c.value for c in resolve_capabilities(code, business_type)]
                assert data["capabilities"] == expected

    def test_every_category_has_a_display_name(self):
        for code, name in MERCHANT_CATEGORIES:
            assert MERCHANT_CATEGORY_NAMES[code] == name


"""Category-capability model — Master Spec §86-§89.

Restaurants are discovery-only, Transport and Personal Transport / Travel are
service domains, and a physical product business is the price/stock case. These
tests pin that mapping so a later edit cannot quietly hand a restaurant a product
catalogue (the first step toward cart / checkout / delivery) or hand a service
business a product-style price/stock surface.

They also pin the RESOLUTION ORDER, because that is what keeps a legacy shop row —
which has no merchant-onboarding record — from rendering as the wrong kind of
business.
"""

import asyncio
import json
import os
import sys
from datetime import datetime, timezone
from pathlib import Path
from unittest.mock import MagicMock, patch

BACKEND_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BACKEND_DIR))

os.environ.setdefault("ENVIRONMENT", "test")
os.environ.setdefault("HYPERLOCAL_ENV", "test")

from app.core.config import settings  # noqa: E402

settings.RATE_LIMIT_ENABLED = False

from app.models.merchant_category import (  # noqa: E402
    CustomerCapability,
    DEFAULT_SHOP_CAPABILITIES,
    LEGACY_SHOP_CATEGORY_CAPABILITIES,
    MERCHANT_CATEGORY_CUSTOMER_CAPABILITIES,
    MerchantCategoryCode,
    resolve_customer_capabilities,
)

PRODUCT_CODES = {
    MerchantCategoryCode.PHARMACY_HEALTHCARE.value,
    MerchantCategoryCode.BEAUTY_PERSONAL_CARE.value,
    MerchantCategoryCode.FURNITURE_HOME_CARE.value,
    MerchantCategoryCode.HOUSEHOLD_GOODS.value,
    MerchantCategoryCode.SPORTS_FITNESS_OUTDOOR.value,
    MerchantCategoryCode.BOOKS_MEDIA_STATIONERY.value,
    MerchantCategoryCode.AUTOMOTIVE_PARTS_TOOLS.value,
    MerchantCategoryCode.HARDWARE.value,
}
SERVICE_CODES = {
    MerchantCategoryCode.TRANSPORT.value,
    MerchantCategoryCode.PERSONAL_TRANSPORT_TRAVEL.value,
}


# ── The registry itself ─────────────────────────────────────────────────────
def test_registry_covers_exactly_the_11_approved_categories():
    assert set(MERCHANT_CATEGORY_CUSTOMER_CAPABILITIES) == {
        c.value for c in MerchantCategoryCode
    }
    assert len(MERCHANT_CATEGORY_CUSTOMER_CAPABILITIES) == 11


def test_product_categories_keep_price_stock_and_distance():
    for code in PRODUCT_CODES:
        caps = MERCHANT_CATEGORY_CUSTOMER_CAPABILITIES[code]
        assert CustomerCapability.PRODUCT_CATALOG.value in caps, code
        assert CustomerCapability.CONTACT.value in caps, code
        assert CustomerCapability.DIRECTIONS.value in caps, code


def test_restaurants_are_discovery_only():
    """No product catalogue, and therefore no stock/cart/checkout anywhere."""
    caps = MERCHANT_CATEGORY_CUSTOMER_CAPABILITIES[MerchantCategoryCode.RESTAURANTS.value]
    assert CustomerCapability.MENU.value in caps
    assert CustomerCapability.CONTACT.value in caps
    assert CustomerCapability.DIRECTIONS.value in caps
    assert CustomerCapability.PRODUCT_CATALOG.value not in caps
    # A booking/quote entry point is not part of the restaurant domain.
    assert CustomerCapability.QUOTE_REQUEST.value not in caps


def test_transport_is_a_service_domain_with_its_real_contract():
    caps = MERCHANT_CATEGORY_CUSTOMER_CAPABILITIES[MerchantCategoryCode.TRANSPORT.value]
    assert CustomerCapability.SERVICE_PROFILE.value in caps
    assert CustomerCapability.AVAILABILITY.value in caps
    # Honest only because POST /transport/quotes exists.
    assert CustomerCapability.QUOTE_REQUEST.value in caps
    assert CustomerCapability.PRODUCT_CATALOG.value not in caps


def test_personal_transport_travel_is_a_provider_profile_with_a_request_point():
    caps = MERCHANT_CATEGORY_CUSTOMER_CAPABILITIES[
        MerchantCategoryCode.PERSONAL_TRANSPORT_TRAVEL.value
    ]
    assert CustomerCapability.SERVICE_PROFILE.value in caps
    assert CustomerCapability.QUOTE_REQUEST.value in caps
    assert CustomerCapability.PRODUCT_CATALOG.value not in caps


def test_no_service_category_is_ever_given_a_product_catalog():
    for code in SERVICE_CODES:
        assert (
            CustomerCapability.PRODUCT_CATALOG.value
            not in MERCHANT_CATEGORY_CUSTOMER_CAPABILITIES[code]
        ), f"{code} must not expose product-style price/stock UI"


def test_no_capability_set_is_empty():
    for code, caps in MERCHANT_CATEGORY_CUSTOMER_CAPABILITIES.items():
        assert caps, f"{code} resolved to no capabilities at all"


# ── Resolution order ────────────────────────────────────────────────────────
def test_merchant_category_code_is_authoritative():
    caps = resolve_customer_capabilities(
        merchant_category_code=MerchantCategoryCode.RESTAURANTS.value,
        # A conflicting legacy signal must not win: the onboarding record knows
        # better than the compatibility column written alongside it.
        legacy_shop_category="PHARMACY",
        business_type="Retail",
    )
    assert CustomerCapability.MENU.value in caps
    assert CustomerCapability.PRODUCT_CATALOG.value not in caps


def test_legacy_restaurant_category_still_resolves_to_the_restaurant_set():
    caps = resolve_customer_capabilities(legacy_shop_category="restaurant")
    assert caps == MERCHANT_CATEGORY_CUSTOMER_CAPABILITIES[
        MerchantCategoryCode.RESTAURANTS.value
    ]
    assert set(LEGACY_SHOP_CATEGORY_CAPABILITIES) == {"RESTAURANT"}


def test_legacy_non_restaurant_category_keeps_the_product_default():
    # The legacy enum collapses four approved categories onto "OTHER", so a
    # legacy row must NOT be guessed into one of them.
    assert resolve_customer_capabilities(legacy_shop_category="OTHER") == (
        DEFAULT_SHOP_CAPABILITIES
    )
    assert resolve_customer_capabilities(legacy_shop_category="HARDWARE") == (
        DEFAULT_SHOP_CAPABILITIES
    )


def test_service_business_type_is_never_offered_a_quote_request():
    """A generic service shop has no provider record behind a booking form."""
    caps = resolve_customer_capabilities(business_type="Service")
    assert CustomerCapability.SERVICE_PROFILE.value in caps
    assert CustomerCapability.PRODUCT_CATALOG.value not in caps
    assert CustomerCapability.QUOTE_REQUEST.value not in caps


def test_lowercase_and_whitespace_are_tolerated():
    caps = resolve_customer_capabilities(merchant_category_code="  transport ")
    assert caps == MERCHANT_CATEGORY_CUSTOMER_CAPABILITIES[
        MerchantCategoryCode.TRANSPORT.value
    ]


def test_unknown_code_falls_back_to_product_rather_than_nothing():
    assert resolve_customer_capabilities(
        merchant_category_code="NOT_A_CATEGORY"
    ) == (DEFAULT_SHOP_CAPABILITIES)
    assert resolve_customer_capabilities() == (DEFAULT_SHOP_CAPABILITIES)


# ── The customer-facing shop payload ────────────────────────────────────────
def _shop_row(category=None, business_type=None):
    """A real Shop row: the route serializes it through a pydantic schema."""
    from app.models.shop import Shop, ShopStatus

    shop = Shop()
    shop.id = 7
    shop.name = "Annapurna Restaurant"
    shop.slug = "annapurna"
    shop.phone = "+919876543210"
    shop.alternate_phone = None
    shop.email = None
    shop.description = "Home style meals."
    shop.tagline = None
    shop.image_url = None
    shop.cover_image_url = None
    shop.logo_url = None
    shop.rating = 4.4
    shop.review_count = 120
    shop.is_verified = True
    shop.is_featured = False
    shop.is_open_24x7 = False
    shop.is_accepting_orders = True
    shop.subcategories = None
    shop.latitude = 28.7150
    shop.longitude = 77.1150
    shop.min_order_amount = None
    shop.delivery_radius_km = None
    shop.delivery_fee = None
    shop.free_delivery_above = None
    shop.is_delivery_available = False
    shop.is_pickup_available = False
    shop.established_year = None
    shop.status = ShopStatus.ACTIVE
    shop.category = category
    shop.business_type = business_type
    shop.created_at = datetime.now(timezone.utc)
    shop.updated_at = datetime.now(timezone.utc)
    return shop


def _shop_payload(shop, onboarding_rows):
    """Run the customer detail route and decode its `data` payload.

    Only the shop lookup and the two display helpers are patched; the capability
    block is produced by the REAL service, so this covers the resolution path
    (onboarding query -> registry -> payload) rather than a mock of it.

    The db double answers per MODEL rather than per query: the route also loads
    the shop's products, so a single blanket `.all()` would feed onboarding rows
    to the product loop (and vice versa).
    """
    from app.api.routes import shops as shops_routes
    from app.models.merchant_onboarding import MerchantOnboarding

    class _OnboardingRow:
        def __init__(self, shop_id, category_code):
            self.shop_id = shop_id
            self.category_code = category_code

    db = MagicMock()

    def _query(model):
        result = MagicMock()
        if model is MerchantOnboarding:
            result.filter.return_value.all.return_value = [
                _OnboardingRow(shop_id, code) for shop_id, code in onboarding_rows
            ]
        else:
            result.filter.return_value.all.return_value = []
            result.filter.return_value.first.return_value = None
        return result

    db.query.side_effect = _query

    with (
        patch.object(shops_routes.shop_service, "get_shop_detail", return_value=shop),
        patch.object(shops_routes.shop_service, "is_shop_open", return_value=True),
        patch.object(
            shops_routes.shop_service, "parse_subcategories", return_value=[]
        ),
    ):
        response = asyncio.run(
            shops_routes.get_shop(shop_id=7, latitude=None, longitude=None, db=db)
        )
    return json.loads(bytes(response.body))["data"]


def test_customer_shop_payload_carries_capabilities_and_business_category():
    from app.models.shop import ShopCategory

    payload = _shop_payload(
        _shop_row(category=ShopCategory.RESTAURANT),
        onboarding_rows=[(7, MerchantCategoryCode.RESTAURANTS.value)],
    )
    assert payload["business_category_code"] == "RESTAURANTS"
    assert payload["business_category_name"] == "Restaurants"
    assert CustomerCapability.MENU.value in payload["capabilities"]
    assert CustomerCapability.PRODUCT_CATALOG.value not in payload["capabilities"]


def test_customer_shop_payload_falls_back_to_the_legacy_category():
    from app.models.shop import ShopCategory

    payload = _shop_payload(
        _shop_row(category=ShopCategory.RESTAURANT),
        onboarding_rows=[],  # a shop that predates merchant onboarding
    )
    assert payload["business_category_code"] is None
    assert payload["capabilities"] == list(
        MERCHANT_CATEGORY_CUSTOMER_CAPABILITIES[MerchantCategoryCode.RESTAURANTS.value]
    )


def test_a_product_shop_payload_keeps_its_catalog_capability():
    from app.models.shop import ShopCategory

    payload = _shop_payload(
        _shop_row(category=ShopCategory.HARDWARE),
        onboarding_rows=[(7, MerchantCategoryCode.HARDWARE.value)],
    )
    assert CustomerCapability.PRODUCT_CATALOG.value in payload["capabilities"]
    assert payload["business_category_name"] == "Hardware"


def test_a_missing_onboarding_table_degrades_instead_of_failing_the_read():
    """A shop profile must not 500 because an optional table is absent.

    The onboarding record is the authoritative category signal, but it is a LATER
    addition: a deployment with a stale migration, a partially applied schema, or
    a test fixture that creates only the tables it exercises, will not have the
    table at all. The capability block then resolves from the legacy
    ``shops.category`` / ``business_type`` instead — which is exactly the answer
    such a deployment can give.
    """
    from sqlalchemy.exc import OperationalError

    from app.api.routes import shops as shops_routes
    from app.models.merchant_onboarding import MerchantOnboarding
    from app.models.shop import ShopCategory

    shop = _shop_row(category=ShopCategory.RESTAURANT)

    class _NoSuchTableDB:
        def query(self, model):
            if model is MerchantOnboarding:
                raise OperationalError(
                    "SELECT merchant_onboardings",
                    {},
                    Exception("no such table: merchant_onboardings"),
                )
            result = MagicMock()
            result.filter.return_value.all.return_value = []
            result.filter.return_value.first.return_value = None
            return result

    with (
        patch.object(shops_routes.shop_service, "get_shop_detail", return_value=shop),
        patch.object(shops_routes.shop_service, "is_shop_open", return_value=True),
        patch.object(
            shops_routes.shop_service, "parse_subcategories", return_value=[]
        ),
    ):
        response = asyncio.run(
            shops_routes.get_shop(
                shop_id=7,
                latitude=None,
                longitude=None,
                db=_NoSuchTableDB(),
            )
        )

    payload = json.loads(bytes(response.body))["data"]
    # Degraded, not broken: the legacy category still identifies the business.
    assert payload["business_category_code"] is None
    assert CustomerCapability.MENU.value in payload["capabilities"]
    assert CustomerCapability.PRODUCT_CATALOG.value not in payload["capabilities"]


def test_a_service_shop_payload_exposes_business_type():
    payload = _shop_payload(
        _shop_row(category=None, business_type="Service"),
        onboarding_rows=[],
    )
    assert payload["business_type"] == "Service"
    assert CustomerCapability.SERVICE_PROFILE.value in payload["capabilities"]
    assert CustomerCapability.PRODUCT_CATALOG.value not in payload["capabilities"]


