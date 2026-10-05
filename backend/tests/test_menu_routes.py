"""The menu API's shopkeeper-scoped surface, and the routes that were missing.

Two gaps this file pins, both of which were live:

  * the app calls `/shopkeeper/businesses/categories/{code}/requirements`, and a
    handler for it existed as an orphan `async def` with no decorator — so the
    route was never registered at all;
  * the menu API only existed on the customer-facing `/restaurants` router, which
    the shopkeeper app is not allowed to consume.

These are static checks rather than HTTP round-trips: the routes need a live
database to call, and the failure mode here is "the route does not exist", which
a route table answers exactly.
"""

import re
from pathlib import Path

import pytest

from app.main import app

BACKEND_DIR = Path(__file__).resolve().parents[1]


def _paths() -> set:
    return set(app.openapi().get("paths", {}))


def _source(relative: str) -> str:
    return (BACKEND_DIR / relative).read_text(encoding="utf-8")


class TestTheOrphanedRequirementsRouteIsRegistered:
    """The app calls it; it has to exist."""

    PATH = "/api/v1/shopkeeper/businesses/categories/{category_code}/requirements"

    def test_the_route_is_in_the_app(self):
        assert self.PATH in _paths()

    def test_it_offers_a_get(self):
        assert "get" in app.openapi()["paths"][self.PATH]

    def test_no_handler_in_the_module_is_left_without_a_decorator(self):
        """Catches the exact shape of the bug: an `async def` sitting where the
        previous function's body ended, which Python accepts happily and FastAPI
        never sees."""
        source = _source("app/api/routes/merchant_onboarding.py")
        orphans = re.findall(
            r"^\s*\)\s*\n(async def \w+)", source, flags=re.MULTILINE
        )
        assert not orphans, (
            "these handlers have no decorator, so their route is never "
            f"registered: {orphans}"
        )

    def test_the_sibling_category_routes_are_still_present(self):
        """The ones the wizard already depended on — a fix here must not drop
        them."""
        paths = _paths()
        for sibling in (
            "/api/v1/shopkeeper/businesses/categories/{category_code}/capabilities",
            "/api/v1/shopkeeper/businesses/categories/{category_code}/product-attributes",
            "/api/v1/shopkeeper/businesses/categories/{category_code}/fields",
        ):
            assert sibling in paths, sibling


class TestMenuRoutesLiveInTheShopkeeperNamespace:
    """The app "exclusively consumes the isolated /shopkeeper/* module".

    The customer-facing `/restaurants` router is the discovery API. A shopkeeper
    screen reaching into it would be a cross-namespace call, which the app's own
    contract test refuses — so the menu has shop-scoped routes of its own.
    """

    MENU_PATHS = (
        "/api/v1/shopkeeper/shops/{shop_id}/restaurant",
        "/api/v1/shopkeeper/shops/{shop_id}/menu",
        "/api/v1/shopkeeper/shops/{shop_id}/menu-categories",
        "/api/v1/shopkeeper/shops/{shop_id}/menu-items",
        "/api/v1/shopkeeper/shops/{shop_id}/menu-items/{item_id}",
    )

    @pytest.mark.parametrize("path", MENU_PATHS)
    def test_the_route_exists(self, path):
        assert path in _paths()

    @pytest.mark.parametrize("path", MENU_PATHS)
    def test_it_is_under_the_shopkeeper_namespace(self, path):
        assert path.startswith("/api/v1/shopkeeper/")

    def test_the_routes_are_keyed_on_shop_not_restaurant(self):
        """The app only ever holds a shop id; a restaurant-keyed route would make
        it invent one it was never given."""
        for path in self.MENU_PATHS:
            assert "{restaurant_id}" not in path

    def test_they_delegate_to_the_same_service_the_customer_api_uses(self):
        """One implementation of the ownership rules, not two that can drift."""
        source = _source("app/api/routes/shopkeeper_portal.py")
        for call in (
            "restaurant_service.get_restaurant_menu",
            "restaurant_service.create_menu_category",
            "restaurant_service.create_menu_item",
            "restaurant_service.update_menu_item",
            "restaurant_service.delete_menu_item",
            "restaurant_service.get_restaurant_by_shop",
        ):
            assert call in source, call

    def test_no_menu_route_is_reachable_without_a_profile(self):
        """A shop with no restaurant profile answers 404 rather than creating one
        the shopkeeper never asked for."""
        source = _source("app/api/routes/shopkeeper_portal.py")
        assert source.count("return _no_profile()") >= 4


def _body_of(relative: str, name: str) -> str:
    """The source of one top-level function, up to the next top-level `def`."""
    source = _source(relative)
    after = source.split(f"def {name}", 1)[1]
    # The next top-level definition ends this one; module-level `def foo(` only.
    parts = re.split(r"^def \w+", after, maxsplit=1, flags=re.MULTILINE)
    return parts[0]


class TestTheRestaurantLookup:
    def test_by_shop_route_exists_for_the_customer_side_too(self):
        assert "/api/v1/restaurants/by-shop/{shop_id}" in _paths()

    def test_it_looks_up_by_shop_and_ignores_soft_deleted_rows(self):
        block = _body_of("app/services/restaurant_service.py", "get_restaurant_by_shop")
        assert "Restaurant.shop_id == shop_id" in block
        assert "is_deleted ==" in block

    def test_it_returns_none_rather_than_creating_a_row(self):
        """Creating a restaurant profile as a side effect of a lookup would give
        a shop a profile it never set up."""
        block = _body_of("app/services/restaurant_service.py", "get_restaurant_by_shop")
        assert "db.add(" not in block
        assert "return None" in block


if __name__ == "__main__":
    raise SystemExit(pytest.main([__file__, "-v"]))
