"""The capability endpoint must answer from the registry, not from a copy.

A unit test on `resolve_capabilities` proves the rule is right; it does not
prove the ROUTE ships it. These go through the real FastAPI handler, because the
failure this guards against is exactly "the resolver works but the endpoint
returns something else" — which no registry-only test can see.
"""

from fastapi.testclient import TestClient

from app.api.routes import merchant_onboarding as route_module
from app.main import app
from app.models import merchant_category


class _FakeUser:
    """Only the fields the dependency chain touches."""

    id = 1
    email = "shopkeeper@example.com"
    is_active = True


def _client() -> TestClient:
    """A client whose category listing comes from the REGISTRY, not the database.

    The handler's only database use is reading the `merchant_categories` rows
    (active flag, sort order, description). That is presentation metadata, not
    the rule under test, and depending on a live PostgreSQL here would make this
    suite hang wherever the database is down — turning a fast contract test into
    an infrastructure dependency. The capability rule itself is pure and is
    exercised for real.
    """
    app.dependency_overrides[route_module.get_current_user] = lambda: _FakeUser()
    app.dependency_overrides[route_module.get_db] = lambda: _FakeDb()
    return TestClient(app)


def _fake_category(code: str, index: int):
    """One row as the `merchant_categories` table would hold it."""

    class _Row:
        def __init__(self):
            self.code = code
            self.name = merchant_category.MERCHANT_CATEGORY_NAMES[code]
            self.description = f"{self.name} business"
            self.sort_order = index + 1
            self.is_active = True

    return _Row()


class _FakeDb:
    """Minimal query chain serving the registry as if it were the table.

    `order_by` is included because the real service applies one; without it the
    fake would diverge from the code path and the test would pass for the wrong
    reason.
    """

    def query(self, *_a, **_k):
        return self

    def filter(self, *_a, **_k):
        return self

    def order_by(self, *_a, **_k):
        return self

    def all(self):
        return [
            _fake_category(code, i)
            for i, (code, _name) in enumerate(merchant_category.MERCHANT_CATEGORIES)
        ]

    def first(self):
        return _fake_category("RESTAURANTS", 0)


def _auth():
    return {"Authorization": "Bearer test-token"}


class TestCategoriesEndpoint:
    def test_every_category_ships_its_capabilities(self):
        response = _client().get(
            "/api/v1/shopkeeper/businesses/categories", headers=_auth()
        )
        assert response.status_code == 200
        payload = response.json()
        assert "data" in payload, response.text
        categories = payload["data"]["categories"]

        # Every category must carry a non-empty capability list, or the wizard
        # has nothing to render fields from.
        for category in categories:
            assert category.get("capabilities"), (
                f"{category.get('code')} returned no capabilities — the form "
                "would render with no fields and no explanation"
            )

    def test_business_types_are_published_alongside(self):
        response = _client().get(
            "/api/v1/shopkeeper/businesses/categories", headers=_auth()
        )
        assert response.json()["data"]["business_types"], (
            "the client needs the server's business-type vocabulary"
        )

    def test_no_forbidden_category_is_listed(self):
        response = _client().get(
            "/api/v1/shopkeeper/businesses/categories", headers=_auth()
        )
        for category in response.json()["data"]["categories"]:
            code = category["code"]
            for word in ("GROCERY", "FOOD", "DELIVERY"):
                assert word not in code, f"{code} is not an approved category"

class TestCapabilitiesEndpoint:
    def test_resolves_for_a_known_category(self):
        response = _client().get(
            "/api/v1/shopkeeper/businesses/categories/RESTAURANTS/capabilities",
            headers=_auth(),
        )
        assert response.status_code == 200
        data = response.json()["data"]
        assert data["category_code"] == "RESTAURANTS"
        assert "SERVICES" in data["capabilities"]
        assert "INVENTORY" not in data["capabilities"]

    def test_business_type_narrows_the_answer(self):
        client = _client()
        base = client.get(
            "/api/v1/shopkeeper/businesses/categories/HOUSEHOLD_GOODS/capabilities",
            headers=_auth(),
        ).json()["data"]["capabilities"]
        service = client.get(
            "/api/v1/shopkeeper/businesses/categories/HOUSEHOLD_GOODS/capabilities"
            "?business_type=Service",
            headers=_auth(),
        ).json()["data"]["capabilities"]

        assert "INVENTORY" in base
        assert "INVENTORY" not in service
        # Contact and location must survive narrowing, or the business becomes
        # unusable — the invariant the whole narrowing table rests on.
        assert "CONTACT" in service
        assert "LOCATION" in service

    def test_unknown_category_is_404_not_empty(self):
        # An empty list would render a blank form that looks valid; a 404 tells
        # the client the category is genuinely unavailable.
        response = _client().get(
            "/api/v1/shopkeeper/businesses/categories/NOT_A_CATEGORY/capabilities",
            headers=_auth(),
        )
        assert response.status_code == 404, response.text
        # The error envelope is top-level (`error_code` is a sibling of
        # `message`), with `data` null — reading it from inside `data` would
        # pass vacuously on None.
        assert response.json()["error_code"] == "CATEGORY_NOT_FOUND", response.text
        assert response.json()["data"] is None

    def test_requires_authentication(self):
        response = TestClient(app).get(
            "/api/v1/shopkeeper/businesses/categories/RESTAURANTS/capabilities"
        )
        assert response.status_code in (401, 403)
