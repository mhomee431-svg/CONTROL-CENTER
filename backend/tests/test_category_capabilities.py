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
    MERCHANT_CATEGORY_CAPABILITIES,
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
    assert set(MERCHANT_CATEGORY_CAPABILITIES) == {
        c.value for c in MerchantCategoryCode
    }
    assert len(MERCHANT_CATEGORY_CAPABILITIES) == 11


def test_product_categories_keep_price_stock_and_distance():
    for code in PRODUCT_CODES:
        caps = MERCHANT_CATEGORY_CAPABILITIES[code]
        assert CustomerCapability.PRODUCT_CATALOG.value in caps, code
        assert CustomerCapability.CONTACT.value in caps, code
        assert CustomerCapability.DIRECTIONS.value in caps, code


def test_restaurants_are_discovery_only():
    """No product catalogue, and therefore no stock/cart/checkout anywhere."""
    caps = MERCHANT_CATEGORY_CAPABILITIES[MerchantCategoryCode.RESTAURANTS.value]
    assert CustomerCapability.MENU.value in caps
    assert CustomerCapability.CONTACT.value in caps
    assert CustomerCapability.DIRECTIONS.value in caps
    assert CustomerCapability.PRODUCT_CATALOG.value not in caps
    # A booking/quote entry point is not part of the restaurant domain.
    assert CustomerCapability.QUOTE_REQUEST.value not in caps


def test_transport_is_a_service_domain_with_its_real_contract():
    caps = MERCHANT_CATEGORY_CAPABILITIES[MerchantCategoryCode.TRANSPORT.value]
    assert CustomerCapability.SERVICE_PROFILE.value in caps
    assert CustomerCapability.AVAILABILITY.value in caps
    # Honest only because POST /transport/quotes exists.
    assert CustomerCapability.QUOTE_REQUEST.value in caps
    assert CustomerCapability.PRODUCT_CATALOG.value not in caps


def test_personal_transport_travel_is_a_provider_profile_with_a_request_point():
    caps = MERCHANT_CATEGORY_CAPABILITIES[
        MerchantCategoryCode.PERSONAL_TRANSPORT_TRAVEL.value
    ]
    assert CustomerCapability.SERVICE_PROFILE.value in caps
    assert CustomerCapability.QUOTE_REQUEST.value in caps
    assert CustomerCapability.PRODUCT_CATALOG.value not in caps


def test_no_service_category_is_ever_given_a_product_catalog():
    for code in SERVICE_CODES:
        assert (
            CustomerCapability.PRODUCT_CATALOG.value
            not in MERCHANT_CATEGORY_CAPABILITIES[code]
        ), f"{code} must not expose product-style price/stock UI"


def test_no_capability_set_is_empty():
    for code, caps in MERCHANT_CATEGORY_CAPABILITIES.items():
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
    assert caps == MERCHANT_CATEGORY_CAPABILITIES[
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
    assert caps == MERCHANT_CATEGORY_CAPABILITIES[
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
        MERCHANT_CATEGORY_CAPABILITIES[MerchantCategoryCode.RESTAURANTS.value]
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


