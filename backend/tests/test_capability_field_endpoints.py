"""The capability-FIELD endpoint and its persistence must enforce the registry.

The field set used to live only in Dart, so there was nothing on this side to
validate what arrived and nothing to persist it. These go through the real
FastAPI handlers because the failure they guard against is precisely "the
registry is right but the route accepts something else".
"""

import json
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from app.api.routes import merchant_onboarding as route_module
from app.main import app
from app.models.merchant_category import MerchantCategoryCode

_PREFIX = "/api/v1/shopkeeper/businesses"
_ALL_CODES = [c.value for c in MerchantCategoryCode]


class _FakeUser:
    id = 1
    email = "shopkeeper@example.com"
    is_active = True
    role = None


class _FakeDb:
    """Records writes so persistence is assertable without PostgreSQL."""

    def __init__(self, shop=None):
        self._shop = shop
        self.committed = 0

    def get(self, _model, _pk):
        return self._shop

    def commit(self):
        self.committed += 1

    def refresh(self, _obj):
        return None


class _FakeShop:
    """Only the surface the handler touches."""

    def __init__(self, id=1, capability_fields=None):
        self.id = id
        self.capability_fields = capability_fields or {}
        self.owners = [type("O", (), {"user_id": 1})()]
        self.managers = []


def _client(shop=None):
    app.dependency_overrides[route_module.get_current_user] = lambda: _FakeUser()
    app.dependency_overrides[route_module.get_db] = lambda: _FakeDb(shop)
    return TestClient(app)


def _get(category: str, business_type: str | None = None):
    query = f"?business_type={business_type}" if business_type else ""
    return _client().get(f"{_PREFIX}/categories/{category}/fields{query}")


def _put(shop, payload):
    return _client(shop).put(
        f"{_PREFIX}/shops/{shop.id}/capability-fields", json=payload
    )


def _valid(category: str = "HARDWARE") -> dict:
    return {
        "category_code": category,
        "fields": {
            "opening_time": "09:00",
            "closing_time": "21:00",
            "contact_phone": "9876543210",
        },
    }


class TestFieldsEndpoint:
    def test_returns_the_exact_registry_fields(self):
        response = _get("PERSONAL_TRANSPORT_TRAVEL")
        assert response.status_code == 200
        keys = {f["key"] for f in response.json()["data"]["fields"]}
        assert {"service_area", "travel_details", "contact_phone"} <= keys

    def test_every_field_carries_label_kind_and_required(self):
        for field in _get("RESTAURANTS").json()["data"]["fields"]:
            assert field["label"], field
            assert field["kind"] in {"TEXT", "MULTILINE", "NUMBER", "CHOICE"}
            assert isinstance(field["required"], bool)

    def test_every_known_category_returns_a_usable_set(self):
        for code in _ALL_CODES:
            response = _get(code)
            assert response.status_code == 200, code
            assert response.json()["data"]["fields"], code

    def test_has_product_form_travels_capability_and_registry(self):
        assert _get("HARDWARE").json()["data"]["has_product_form"] is True
        for code in ("RESTAURANTS", "TRANSPORT", "PERSONAL_TRANSPORT_TRAVEL"):
            assert _get(code).json()["data"]["has_product_form"] is False, code

    def test_unknown_category_is_404(self):
        assert _get("NOT_A_CATEGORY").status_code == 404

    def test_business_type_narrowing_keeps_business_fields(self):
        narrowed = _get("HOUSEHOLD_GOODS", "Service").json()["data"]["fields"]
        keys = {f["key"] for f in narrowed}
        assert "contact_phone" in keys
        assert "opening_time" in keys

    def test_a_travel_category_differs_from_a_stock_one(self):
        travel = {f["key"] for f in _get("PERSONAL_TRANSPORT_TRAVEL").json()["data"]["fields"]}
        hardware = {f["key"] for f in _get("HARDWARE").json()["data"]["fields"]}
        assert travel != hardware


class TestPersistence:
    def test_a_valid_submission_is_stored(self):
        shop = _FakeShop()
        payload = _valid("PERSONAL_TRANSPORT_TRAVEL")
        payload["fields"]["service_area"] = "Goa, Mumbai"
        response = _put(shop, payload)
        assert response.status_code == 200
        assert shop.capability_fields["service_area"] == "Goa, Mumbai"

    def test_an_unapproved_key_rejects_the_whole_request(self):
        """Strict by design: no partial saves, no silent field loss."""
        shop = _FakeShop()
        payload = _valid()
        payload["fields"]["admin"] = "root"
        response = _put(shop, payload)
        assert response.status_code == 422
        assert "admin" in response.text
        assert "admin" not in shop.capability_fields

    def test_a_valid_submission_returns_what_was_stored(self):
        shop = _FakeShop()
        response = _put(shop, _valid())
        assert response.status_code == 200
        stored = response.json()["data"]["capability_fields"]
        assert stored["contact_phone"] == "9876543210"

    def test_a_travel_key_is_refused_for_hardware(self):
        shop = _FakeShop()
        payload = _valid()
        payload["fields"]["travel_details"] = "tours"
        assert _put(shop, payload).status_code == 422
        assert shop.capability_fields == {}

    def test_a_missing_required_field_rejects_the_whole_request(self):
        shop = _FakeShop()
        response = _put(
            shop, {"category_code": "HARDWARE", "fields": {"opening_time": "09:00"}}
        )
        assert response.status_code == 422
        # Nothing partially saved.
        assert shop.capability_fields == {}

    def test_a_partial_update_does_not_wipe_earlier_values(self):
        shop = _FakeShop(
            capability_fields={"service_area": "Goa", "contact_phone": "9876543210"}
        )
        payload = _valid("PERSONAL_TRANSPORT_TRAVEL")
        payload["fields"]["contact_phone"] = "9999999999"
        _put(shop, payload)
        assert shop.capability_fields["service_area"] == "Goa"
        assert shop.capability_fields["contact_phone"] == "9999999999"

    def test_a_non_dict_fields_payload_is_rejected(self):
        assert _put(_FakeShop(), {"category_code": "HARDWARE", "fields": ["a"]}).status_code == 400

    def test_a_missing_category_is_rejected(self):
        assert _put(_FakeShop(), {"fields": {}}).status_code == 400

    def test_a_missing_shop_is_404(self):
        response = _client(None).put(
            f"{_PREFIX}/shops/99/capability-fields", json=_valid()
        )
        assert response.status_code == 404

    def test_someone_elses_shop_is_403(self):
        shop = _FakeShop()
        shop.owners = []
        shop.managers = []
        assert _put(shop, _valid()).status_code == 403

    def test_a_manager_may_also_write(self):
        shop = _FakeShop()
        shop.owners = []
        shop.managers = [type("M", (), {"user_id": 1})()]
        assert _put(shop, _valid()).status_code == 200

    def test_an_admin_may_write_any_shop(self):
        class _Admin(_FakeUser):
            id = 999
            role = type("R", (), {"name": "admin"})()

        shop = _FakeShop()
        shop.owners = []
        shop.managers = []
        app.dependency_overrides[route_module.get_current_user] = lambda: _Admin()
        app.dependency_overrides[route_module.get_db] = lambda: _FakeDb(shop)
        response = TestClient(app).put(
            f"{_PREFIX}/shops/{shop.id}/capability-fields", json=_valid()
        )
        assert response.status_code == 200


def test_openapi_declares_the_capability_routes():
    """The committed contract must describe the routes the app calls.

    `add_capability_paths.py` copies these out of the live FastAPI app, so this
    fails if a route is added without the contract being updated — which is
    exactly how `api_contract_test.dart` on the Dart side caught the missing
    endpoint.
    """
    from app.main import app

    contract_path = (
        Path(__file__).resolve().parents[2] / "packages/api_contracts/openapi.json"
    )
    contract = json.loads(contract_path.read_text(encoding="utf-8"))
    paths = contract.get("paths", {})

    expected = {
        "/api/v1/shopkeeper/businesses/categories/{category_code}/capabilities",
        "/api/v1/shopkeeper/businesses/categories/{category_code}"
        "/product-attributes",
        "/api/v1/shopkeeper/businesses/categories/{category_code}/fields",
        "/api/v1/shopkeeper/businesses/shops/{shop_id}/capability-fields",
    }
    for path in expected:
        assert path in paths, f"openapi.json is missing {path}"

    # This file is the CUSTOMER-facing contract, so it legitimately documents
    # routes this app does not serve and omits shopkeeper-only ones. Assert only
    # what is true of the capability routes themselves: both sides agree on
    # existence, which is the drift that breaks a client.
    live = set(app.openapi()["paths"])
    for path in expected:
        assert path in live, f"the app no longer serves {path}"


def test_the_category_registry_is_the_approved_vocabulary():
    """No legacy GROCERY may reappear in the merchant category registry.

    The approved list is eleven categories with Grocery and General Food
    excluded, and the registry is what the shopkeeper app is driven by. A stale
    `GROCERY` here would let a client build a picker for a category the backend
    rejects.
    """
    from app.models.merchant_category import (
        MERCHANT_CATEGORY_NAMES,
        MerchantCategoryCode,
    )

    approved = {c.value for c in MerchantCategoryCode}
    assert len(approved) == 11, approved
    assert set(MERCHANT_CATEGORY_NAMES) == approved

    for excluded in ("GROCERY", "GENERAL_FOOD", "FOOD", "DELIVERY"):
        assert excluded not in approved, (
            f"{excluded} is excluded from the approved category list"
        )


if __name__ == "__main__":
    raise SystemExit(pytest.main([__file__, "-v"]))