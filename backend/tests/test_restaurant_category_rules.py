"""The RESTAURANTS category spec, pinned.

The spec's binding instruction is negative and therefore easy to satisfy by
accident and break without noticing:

    "Do NOT automatically convert this category into: Food delivery, Cart,
     Checkout, Delivery tracking, Delivery rider management."

Nothing here asserts that a restaurant *works* -- that is covered by the API and
schema suites. What these tests hold is the set of things the platform must
never quietly turn a restaurant into, plus the one capability the spec makes
conditional on backend support.

The conditional is "If backend supports offerings/menu: show appropriate
management UI." The backend does support it (tables plus a full write API), so
that support is pinned here -- it is the premise of the conditional, and losing
it silently would leave the spec's condition untrue without anyone noticing.
"""

import re
from pathlib import Path

import pytest
from sqlalchemy import CheckConstraint, UniqueConstraint

from app.models import merchant_category, product_attributes
from app.models.merchant_category import (
    CategoryCapability,
    MERCHANT_CATEGORY_NAMES,
    MerchantCategoryCode,
)
from app.models.restaurant import Restaurant, RestaurantMenuCategory, RestaurantMenuItem
from app.services.capability_field_specs import capability_fields_for

BACKEND_DIR = Path(__file__).resolve().parents[1]

# Words that would mean the platform had grown a delivery business. `orders`
# and `order_items` are deliberately NOT here: they are the generic customer
# purchase flow every shop may use, not a food-delivery pipeline.
_DELIVERY_WORDS = ("delivery", "rider", "dispatch", "cart", "checkout")


def _capabilities() -> set:
    resolved = merchant_category.capabilities_for_category("RESTAURANTS")
    return set(resolved.get("capabilities", ()))


def _tables() -> dict:
    """Every declared tablename mapped to the file that declares it."""
    found = {}
    for path in (BACKEND_DIR / "app" / "models").glob("*.py"):
        for match in re.finditer(
            r'__tablename__\s*=\s*"([^"]+)"', path.read_text(encoding="utf-8")
        ):
            found[match.group(1)] = path.name
    return found


class TestRestaurantsIsARealBusiness:
    """'Restaurants are valid HyperLocal businesses.'"""

    def test_restaurants_is_in_the_registry(self):
        assert MerchantCategoryCode.RESTAURANTS.value == "RESTAURANTS"
        assert MERCHANT_CATEGORY_NAMES["RESTAURANTS"] == "Restaurants"

    def test_the_registry_still_holds_all_eleven_categories(self):
        assert len(list(MerchantCategoryCode)) == 11

    def test_it_is_not_excluded_the_way_grocery_and_food_are(self):
        """Grocery / General Food are absent from the registry on purpose.

        That exclusion must not spread: a restaurant is a first-class category,
        not a near-miss filtered out with the delivery-adjacent ones.
        """
        names = " ".join(MERCHANT_CATEGORY_NAMES.values()).lower()
        assert "restaurant" in names
        assert "grocery" not in names
        assert "general food" not in names


class TestNoAutomaticConversion:
    """The spec's explicit prohibition, one clause at a time."""

    def test_no_grocery_food_or_delivery_category_exists_to_convert_into(self):
        """There is no delivery category the restaurant could be swapped for."""
        codes = [c.value for c in MerchantCategoryCode]
        for banned in ("GROCERY", "FOOD", "DELIVERY"):
            assert not any(banned in c for c in codes), banned

    def test_the_schema_has_no_delivery_rider_dispatch_cart_or_checkout_table(self):
        offenders = [
            f"{table} ({where})"
            for table, where in _tables().items()
            if any(word in table for word in _DELIVERY_WORDS)
        ]
        assert not offenders, f"delivery-shaped tables appeared: {offenders}"

    def test_a_restaurant_carries_no_stock_catalogue(self):
        """'Do not force standard shop inventory fields where they do not make
        sense.'"""
        assert not product_attributes.product_attributes_for("RESTAURANTS")

    @pytest.mark.parametrize(
        "capability",
        [
            CategoryCapability.PRODUCT_CATALOG,
            CategoryCapability.INVENTORY,
            CategoryCapability.BARCODE,
            CategoryCapability.IMPORT,
        ],
    )
    def test_no_stock_shaped_capability_is_granted(self, capability):
        """Capability grants are how the UI decides what to show, so a stock
        capability here is what would put an inventory form in front of a
        restaurant."""
        assert capability.value not in _capabilities()

    def test_menu_items_have_no_stock_column(self):
        """A menu item is a display row, not a SKU."""
        columns = {c.name for c in RestaurantMenuItem.__table__.columns}
        for stock_column in ("quantity", "stock", "stock_quantity", "inventory"):
            assert stock_column not in columns, stock_column

    def test_the_delivery_columns_are_never_prefilled_at_creation(self):
        """`shops` carries delivery_* columns, so the risk is not their existence
        but a restaurant being handed values it never chose.

        The columns are shared by every shop; what must not happen is a value
        being invented for this category.
        """
        source = (
            BACKEND_DIR / "app" / "api" / "routes" / "shopkeeper_auth.py"
        ).read_text(encoding="utf-8")
        for column in (
            "delivery_fee=",
            "delivery_radius_km=",
            "free_delivery_above=",
            "is_delivery_available=",
            "min_order_amount=",
        ):
            assert column not in source, (
                f"{column} is assigned during shop creation; a restaurant would be "
                "pre-filled with delivery settings it never chose"
            )
class TestRestaurantProfileShape:
    """'Restaurant profile may include: ...' -- every listed item has a home."""

    def test_the_service_capabilities_are_granted(self):
        granted = _capabilities()
        for capability in (
            CategoryCapability.PRICE,
            CategoryCapability.OFFERS,
            CategoryCapability.OPERATING_HOURS,
            CategoryCapability.SERVICES,
            CategoryCapability.CONTACT,
            CategoryCapability.LOCATION,
            CategoryCapability.DOCUMENTS,
        ):
            assert capability.value in granted, capability

    def test_operating_hours_are_collected(self):
        keys = {f.key for f in capability_fields_for("RESTAURANTS")}
        assert {"opening_time", "closing_time", "closed_on"} <= keys

    def test_contact_and_services_are_collected(self):
        keys = {f.key for f in capability_fields_for("RESTAURANTS")}
        assert {"contact_phone", "service_summary"} <= keys

    def test_a_description_field_exists_on_the_shop(self):
        from app.models.shop import Shop

        assert "description" in {c.name for c in Shop.__table__.columns}

    def test_owner_and_manager_are_modelled_separately(self):
        """The spec lists "Owner/Manager" as one line, but the schema models two
        relationships -- a shop can have more than one manager."""
        assert "shop_owners" in _tables()
        assert "shop_managers" in _tables()

    def test_address_and_location_are_modelled(self):
        assert "shop_addresses" in _tables()
        from app.models.shop import Shop

        columns = {c.name for c in Shop.__table__.columns}
        assert {"latitude", "longitude"} <= columns


class TestOfferingsMenuSupport:
    """The spec's one conditional: 'If backend supports offerings/menu'."""

    def test_the_backend_really_does_support_a_menu(self):
        """The premise of the conditional. If this stops being true the spec's
        'if' clause changes behaviour, and that must not happen silently."""
        tables = _tables()
        assert "restaurants" in tables
        assert "restaurant_menu_categories" in tables
        assert "restaurant_menu_items" in tables

    def test_the_menu_is_writable_not_just_displayable(self):
        """'show appropriate management UI' implies managing, so a read-only menu
        route would not satisfy the spec."""
        source = (
            BACKEND_DIR / "app" / "api" / "routes" / "restaurant.py"
        ).read_text(encoding="utf-8")
        for method, path in (
            ("post", "/{restaurant_id}/menu-categories"),
            ("post", "/{restaurant_id}/menu-items"),
            ("put", "/{restaurant_id}/menu-items/{item_id}"),
            ("delete", "/{restaurant_id}/menu-items/{item_id}"),
        ):
            assert f'@router.{method}("{path}")' in source, f"{method} {path}"

    def test_menu_items_are_grouped_under_categories(self):
        assert RestaurantMenuCategory.items.property.mapper.class_ is RestaurantMenuItem
        assert Restaurant.menu_items.property.mapper.class_ is RestaurantMenuItem

    def test_the_menu_carries_a_display_price_and_diet_flags(self):
        columns = {c.name for c in RestaurantMenuItem.__table__.columns}
        assert {"name", "description", "price", "veg", "spicy"} <= columns

    def test_a_menu_item_price_cannot_go_negative(self):
        # Filtered to CheckConstraint first: a table also carries PK and FK
        # constraints, and those have no `sqltext`.
        checks = [
            str(c.sqltext)
            for c in RestaurantMenuItem.__table__.constraints
            if isinstance(c, CheckConstraint)
        ]
        assert any("price >= 0" in check for check in checks), checks

    def test_the_restaurant_profile_is_one_to_one_with_a_shop(self):
        uniques = [
            c
            for c in Restaurant.__table__.constraints
            if isinstance(c, UniqueConstraint)
        ]
        named = {c.name for c in uniques}
        assert "uq_restaurants_shop_id" in named, named
        assert any("shop_id" in {col.name for col in c.columns} for c in uniques)


if __name__ == "__main__":
    raise SystemExit(pytest.main([__file__, "-v"]))