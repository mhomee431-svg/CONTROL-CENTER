"""Category configuration — end-to-end contract for the admin panel.

Covers the spec section CATEGORY CONFIGURATION against the real router:

    manage: name, description, status, sort order,
            required fields, optional fields, feature capabilities
    "Do not implement category rules only in the frontend."

The last point is why these tests exercise the HTTP surface rather than a
frontend helper: creation, the forbidden-category rule, identifier normalisation,
feature-capability validation and partial PATCH must all hold server-side, so a
direct API call cannot store a taxonomy the console would never produce.
"""

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from app.api.v1 import catalog
from app.core.database import Base, get_db
from app.core.security import get_current_admin
from app.models import AdminUser


@pytest.fixture()
def client():
    """The catalog router on an isolated in-memory database.

    The admin dependency is overridden with an owner, so these tests exercise
    the configuration logic and not the auth stack (which has its own tests).
    """
    engine = create_engine(
        "sqlite://",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
        future=True,
    )
    TestingSession = sessionmaker(bind=engine, autoflush=False, autocommit=False, future=True)
    Base.metadata.create_all(bind=engine)

    app = FastAPI()
    app.include_router(catalog.router, prefix="/api/v1")

    def _db():
        db = TestingSession()
        try:
            yield db
        finally:
            db.close()

    def _owner() -> AdminUser:
        return AdminUser(
            id=1, username="owner", name="Owner", is_owner=True, is_active=True, permissions=[]
        )

    app.dependency_overrides[get_db] = _db
    app.dependency_overrides[get_current_admin] = _owner
    with TestClient(app) as c:
        yield c


def _create(client, **overrides):
    payload = {
        "name": "Pharmacy & Healthcare",
        "slug": "pharmacy-healthcare",
        "description": "Medicines",
        "required_fields": ["expiry_date"],
        "optional_fields": ["batch_number"],
        "feature_capabilities": ["delivery"],
    }
    payload.update(overrides)
    return client.post("/api/v1/admin/categories", json=payload)


def test_create_persists_the_full_configuration(client):
    r = _create(client, sort_order=3)
    assert r.status_code == 200, r.text
    data = r.json()["data"]
    assert data["name"] == "Pharmacy & Healthcare"
    assert data["sort_order"] == 3
    assert data["is_active"] is True
    assert data["required_fields"] == ["expiry_date"]
    assert data["optional_fields"] == ["batch_number"]
    assert data["feature_capabilities"] == ["delivery"]


def test_listing_and_detail_report_the_configuration(client):
    created = _create(client).json()["data"]
    listed = client.get("/api/v1/admin/categories").json()["data"]["items"]
    row = next(c for c in listed if c["id"] == created["id"])
    assert row["required_fields"] == ["expiry_date"]
    assert row["feature_capabilities"] == ["delivery"]

    detail = client.get(f"/api/v1/admin/categories/{created['id']}").json()["data"]
    assert detail["optional_fields"] == ["batch_number"]


def test_config_catalog_is_served_by_the_backend(client):
    r = client.get("/api/v1/admin/categories/config-catalog")
    assert r.status_code == 200, r.text
    data = r.json()["data"]
    keys = {entry["key"] for entry in data["feature_capabilities"]}
    # The vocabulary the console renders comes from here, not the frontend.
    assert {"delivery", "pickup", "installation"} <= keys
    assert data["field_presets"]


def test_static_config_catalog_route_wins_over_the_dynamic_id_route(client):
    """Registration order matters: a later static route would be read as an id.

    FastAPI matches in declaration order, so `/categories/config-catalog` must be
    declared before `/categories/{category_id}`. If the order ever inverts this
    request 422s (string parsed as an int) instead of returning the catalog.
    """
    r = client.get("/api/v1/admin/categories/config-catalog")
    assert r.status_code == 200
    assert "feature_capabilities" in r.json()["data"]


def test_forbidden_categories_are_rejected_server_side(client):
    for name in ("Grocery", "General Food", "general food essentials"):
        r = _create(client, name=name, slug="forbidden")
        assert r.status_code == 422, f"{name} should be rejected"
        # This isolated app has no app-level handler, so the detail arrives as
        # FastAPI's default `detail`; the full app reshapes it into `message`.
        body = r.json()
        reason = str(body.get("message") or body.get("detail") or "").lower()
        assert "excluded" in reason


def test_identifiers_are_normalised_and_deduplicated(client):
    r = _create(
        client,
        required_fields=["Expiry Date", "batch-number", "expiry_date"],
    )
    assert r.status_code == 200, r.text
    assert r.json()["data"]["required_fields"] == ["expiry_date", "batch_number"]


def test_malformed_identifier_is_rejected(client):
    r = _create(client, required_fields=["not a valid$field"])
    assert r.status_code == 422


def test_unknown_feature_capability_is_rejected(client):
    r = _create(client, feature_capabilities=["delivery", "teleportation"])
    assert r.status_code == 422


def test_patch_writes_only_supplied_fields(client):
    created = _create(client).json()["data"]
    cid = created["id"]

    r = client.patch(f"/api/v1/admin/categories/{cid}", json={"description": "Updated"})
    assert r.status_code == 200, r.text
    data = r.json()["data"]
    assert data["description"] == "Updated"
    # Untouched configuration survives a partial update.
    assert data["required_fields"] == ["expiry_date"]
    assert data["feature_capabilities"] == ["delivery"]


def test_patch_can_clear_a_list_explicitly(client):
    cid = _create(client).json()["data"]["id"]
    r = client.patch(f"/api/v1/admin/categories/{cid}", json={"optional_fields": []})
    assert r.status_code == 200, r.text
    assert r.json()["data"]["optional_fields"] == []


def test_patch_toggles_status_and_sort_order(client):
    cid = _create(client).json()["data"]["id"]
    r = client.patch(f"/api/v1/admin/categories/{cid}", json={"is_active": False, "sort_order": 9})
    assert r.status_code == 200, r.text
    data = r.json()["data"]
    assert data["is_active"] is False
    assert data["sort_order"] == 9


def test_patch_with_no_fields_is_rejected(client):
    cid = _create(client).json()["data"]["id"]
    r = client.patch(f"/api/v1/admin/categories/{cid}", json={})
    assert r.status_code == 422


def test_blank_name_is_rejected_on_update(client):
    cid = _create(client).json()["data"]["id"]
    r = client.patch(f"/api/v1/admin/categories/{cid}", json={"name": "   "})
    assert r.status_code == 422


def test_subcategory_flag_tracks_the_parent(client):
    parent = _create(client, name="Root A", slug="root-a").json()["data"]
    child = _create(client, name="Child", slug="child", parent_id=parent["id"]).json()["data"]
    assert child["parent_id"] == parent["id"]
    assert child["is_subcategory"] is True

    # Reparenting back to root clears the derived flag.
    moved = client.patch(
        f"/api/v1/admin/categories/{child['id']}", json={"parent_id": None}
    ).json()["data"]
    assert moved["parent_id"] is None
    assert moved["is_subcategory"] is False


def test_missing_parent_is_rejected(client):
    r = _create(client, name="Orphan", slug="orphan", parent_id=9999)
    assert r.status_code == 422


def test_a_category_cannot_parent_itself(client):
    cid = _create(client).json()["data"]["id"]
    r = client.patch(f"/api/v1/admin/categories/{cid}", json={"parent_id": cid})
    assert r.status_code == 422


def test_delete_removes_the_category(client):
    cid = _create(client).json()["data"]["id"]
    assert client.delete(f"/api/v1/admin/categories/{cid}").status_code == 200
    assert client.get(f"/api/v1/admin/categories/{cid}").status_code == 404
