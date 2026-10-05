"""The product-attributes endpoint must ship the real registry per category.

The category-vs-product-category distinction only pays off if the route actually
returns different attribute lists for different categories. A unit test on the
registry cannot see a route that returns one hardcoded list for everything, so
these go through the real FastAPI handler.
"""

from fastapi.testclient import TestClient

from app.api.routes import merchant_onboarding as route_module
from app.main import app
from app.models import merchant_category, product_attributes

_PREFIX = "/api/v1/shopkeeper/businesses"


class _FakeUser:
    id = 1
    email = "shopkeeper@example.com"
    is_active = True


def _client() -> TestClient:
    app.dependency_overrides[route_module.get_current_user] = lambda: _FakeUser()
    return TestClient(app)


def _get(category: str):
    return _client().get(f"{_PREFIX}/categories/{category}/product-attributes")


def _keys(payload: dict) -> set[str]:
    return {a["key"] for a in payload["data"]["attributes"]}


class TestStockCategories:
    def test_pharmacy_returns_only_the_stock_attributes(self):
        # The spec's product list for pharmacy: name, brand, variant, barcode,
        # category/subcategory, price, MRP, availability, quantity, image. No
        # regulatory field, because none is defined.
        response = _get("PHARMACY_HEALTHCARE")
        assert response.status_code == 200
        keys = _keys(response.json())
        assert "name" in keys
        assert "price" in keys
        assert "quantity" in keys
        assert not any("regulat" in k or "licen" in k for k in keys)

    def test_the_route_ships_no_regulatory_field_to_anyone(self):
        for code in (c.value for c in merchant_category.MerchantCategoryCode):
            for attr in _get(code).json()["data"]["attributes"]:
                assert "regulat" not in attr["key"], f"{code}.{attr['key']}"
                assert "licen" not in attr["key"], f"{code}.{attr['key']}"

    def test_furniture_omits_barcode_but_keeps_quantity(self):
        # The spec says "Quantity where applicable" for this category, and a
        # furniture shop really does stock fifty identical chairs. Barcode stays
        # out: a sofa has no scannable EAN.
        keys = _keys(_get("FURNITURE_HOME_CARE").json())
        assert "barcode" not in keys
        assert "quantity" in keys
        assert "price" in keys

    def test_the_route_ships_the_furniture_fields_separately(self):
        # Not one "Material / colour / size" box: a shopkeeper cannot filter by
        # material when material and colour share a single string.
        keys = _keys(_get("FURNITURE_HOME_CARE").json())
        for key in ("dimensions", "material", "colour", "assembly_service"):
            assert key in keys, key

    def test_books_offers_an_optional_isbn(self):
        payload = _get("BOOKS_MEDIA_STATIONERY").json()
        isbn = [a for a in payload["data"]["attributes"] if a["key"] == "barcode"]
        assert isbn
        assert isbn[0]["required"] is False

    def test_hardware_serves_its_optional_fields_and_no_hardcoded_taxonomy(self):
        """The spec's hardware rules at the HTTP boundary.

        "Only show attributes supplied by backend capability definitions" is what
        this asserts end to end: the route ships the backend's optional fields and
        ships no choice list that would let the client impose its own taxonomy.
        """
        response = _get("HARDWARE")
        assert response.status_code == 200
        by_key = {a["key"]: a for a in response.json()["data"]["attributes"]}

        for optional in ("size", "material", "base_unit", "specification"):
            assert optional in by_key, optional
            assert by_key[optional]["required"] is False, optional

        for core in (
            "name", "brand", "category", "variant",
            "barcode", "price", "availability", "quantity", "image",
        ):
            assert core in by_key, core

        # A choice list is the one place the client could impose a taxonomy; only
        # the yes/no availability flag legitimately carries one.
        for key, attr in by_key.items():
            if key != "availability":
                assert attr["choices"] == [], key

        # "Plumbing-related hardware where categorized by backend": the grouping
        # rides on a catalog-backed subcategory rather than on choices shipped
        # here, so this build cannot claim to know what counts as plumbing.
        assert by_key["subcategory"]["catalog_backed"] is True
        assert by_key["subcategory"]["choices"] == []

    def test_two_categories_really_do_differ(self):
        """The whole point: one uniform list would fail this."""
        assert _keys(_get("PHARMACY_HEALTHCARE").json()) != _keys(
            _get("HARDWARE").json()
        )


class TestServiceCategories:
    def test_restaurant_has_no_product_form(self):
        payload = _get("RESTAURANTS").json()
        assert payload["data"]["attributes"] == []
        assert payload["data"]["has_product_form"] is False

    def test_transport_and_travel_have_no_product_form(self):
        for code in ("TRANSPORT", "PERSONAL_TRANSPORT_TRAVEL"):
            payload = _get(code).json()
            assert payload["data"]["attributes"] == [], code

    def test_an_empty_form_is_200_not_an_error(self):
        """No product form is a valid answer, not a failure."""
        assert _get("RESTAURANTS").status_code == 200


class TestContract:
    def test_has_product_form_is_accurate(self):
        for code in (c.value for c in merchant_category.MerchantCategoryCode):
            payload = _get(code).json()["data"]
            assert payload["has_product_form"] == bool(payload["attributes"]), code

    def test_lowercase_category_is_accepted(self):
        assert _get("pharmacy_healthcare").status_code == 200

    def test_unknown_category_is_404(self):
        response = _get("NOT_A_CATEGORY")
        assert response.status_code == 404

    def test_every_attribute_carries_a_usable_label_and_kind(self):
        for code in (c.value for c in merchant_category.MerchantCategoryCode):
            for attr in _get(code).json()["data"]["attributes"]:
                assert attr["label"], f"{code}.{attr['key']} has no label"
                assert attr["kind"] in {"TEXT", "MULTILINE", "NUMBER", "CHOICE"}

    def test_choices_are_present_only_for_choice_attributes(self):
        for code in (c.value for c in merchant_category.MerchantCategoryCode):
            for attr in _get(code).json()["data"]["attributes"]:
                assert bool(attr["choices"]) == (attr["kind"] == "CHOICE"), (
                    f"{code}.{attr['key']}"
                )

    def test_route_serves_exactly_the_registry(self):
        """Guards against the route drifting from the source of truth."""
        for code in (c.value for c in merchant_category.MerchantCategoryCode):
            served = _get(code).json()["data"]["attributes"]
            expected = [
                s.as_dict() for s in product_attributes.product_attributes_for(code)
            ]
            assert served == expected, code


if __name__ == "__main__":
    raise SystemExit(pytest.main([__file__, "-v"]))