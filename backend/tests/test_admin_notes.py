"""Administrative notes — end-to-end contract for the admin panel.

The notes grid lets an operator attach a memo to a shop/user/product/category/
setting, or leave it free-standing. Two rules the UI depends on are enforced
here rather than in the browser:

  * `entity_type` and `entity_id` travel together or not at all — a note is
    never stored with half a reference.
  * the response exposes `author` (the stored column), which is the exact field
    the grid renders; the frontend interface mirrors it.

Creation, edit and delete are all audited, so the governance trail is complete.
"""

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient
from sqlalchemy import create_engine, select
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from app.api.v1 import offers_audit
from app.core.database import Base, get_db
from app.core.security import get_current_admin
from app.models import AdminUser, AuditLog


@pytest.fixture()
def ctx():
    """The offers/audit router on an in-memory DB, plus the session factory.

    The session factory is yielded so tests can assert directly on the audit
    trail the routes wrote.
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
    app.include_router(offers_audit.router, prefix="/api/v1")

    def _db():
        db = TestingSession()
        try:
            yield db
        finally:
            db.close()

    admin = AdminUser(
        id=1,
        username="owner",
        name="Owner Name",
        is_owner=True,
        is_active=True,
        permissions=[],
    )

    app.dependency_overrides[get_db] = _db
    app.dependency_overrides[get_current_admin] = lambda: admin
    with TestClient(app) as client:
        yield client, TestingSession


def test_create_free_standing_note_is_allowed(ctx):
    """A general memo (no entity) must succeed — the UI offers 'None'."""
    client, _ = ctx
    r = client.post("/api/v1/admin/notes", json={"note": "Platform-wide reminder"})
    assert r.status_code == 200, r.text
    data = r.json()["data"]
    assert data["note"] == "Platform-wide reminder"
    assert data["entity_type"] is None
    assert data["entity_id"] is None
    assert data["author"] == "Owner Name"


def test_create_note_with_entity_records_the_full_pair(ctx):
    client, _ = ctx
    r = client.post(
        "/api/v1/admin/notes",
        json={"note": "Follow up on pricing", "entity_type": "SHOP", "entity_id": 7},
    )
    assert r.status_code == 200, r.text
    data = r.json()["data"]
    assert data["entity_type"] == "SHOP"
    assert data["entity_id"] == 7


def test_half_a_reference_is_rejected(ctx):
    """Type without id (and id without type) must not be stored."""
    client, _ = ctx
    only_type = client.post(
        "/api/v1/admin/notes", json={"note": "x", "entity_type": "SHOP"}
    )
    assert only_type.status_code == 422

    only_id = client.post("/api/v1/admin/notes", json={"note": "x", "entity_id": 3})
    assert only_id.status_code == 422


def test_blank_note_body_is_rejected(ctx):
    client, _ = ctx
    assert client.post("/api/v1/admin/notes", json={"note": "   "}).status_code == 422


def test_response_exposes_the_author_field_the_grid_renders(ctx):
    client, _ = ctx
    created = client.post("/api/v1/admin/notes", json={"note": "Check"}).json()["data"]
    assert "author" in created
    # The frontend interface mirrors the wire shape, so no alias field is needed.
    assert "created_by" not in created


def test_listing_reports_total_and_items(ctx):
    client, _ = ctx
    client.post("/api/v1/admin/notes", json={"note": "First"})
    client.post("/api/v1/admin/notes", json={"note": "Second"})
    body = client.get("/api/v1/admin/notes").json()["data"]
    assert body["total"] == 2
    assert len(body["items"]) == 2
    # Newest first, so the operator sees the most recent annotation on top.
    assert body["items"][0]["note"] == "Second"


def test_listing_filters_by_entity(ctx):
    client, _ = ctx
    client.post("/api/v1/admin/notes", json={"note": "General"})
    client.post(
        "/api/v1/admin/notes", json={"note": "On shop", "entity_type": "SHOP", "entity_id": 4}
    )
    body = client.get(
        "/api/v1/admin/notes", params={"entity_type": "SHOP", "entity_id": 4}
    ).json()["data"]
    assert body["total"] == 1
    assert body["items"][0]["note"] == "On shop"


def test_update_writes_only_supplied_fields(ctx):
    client, _ = ctx
    created = client.post(
        "/api/v1/admin/notes",
        json={"note": "Original", "entity_type": "USER", "entity_id": 9},
    ).json()["data"]

    r = client.patch(f"/api/v1/admin/notes/{created['id']}", json={"note": "Revised"})
    assert r.status_code == 200, r.text
    data = r.json()["data"]
    assert data["note"] == "Revised"
    # The entity pair is untouched by a body that did not mention it.
    assert data["entity_type"] == "USER"
    assert data["entity_id"] == 9


def test_update_can_detach_a_note_from_its_entity(ctx):
    client, _ = ctx
    created = client.post(
        "/api/v1/admin/notes",
        json={"note": "Attached", "entity_type": "PRODUCT", "entity_id": 2},
    ).json()["data"]

    r = client.patch(
        f"/api/v1/admin/notes/{created['id']}",
        json={"entity_type": None, "entity_id": None},
    )
    assert r.status_code == 200, r.text
    data = r.json()["data"]
    assert data["entity_type"] is None
    assert data["entity_id"] is None


def test_update_rejects_half_a_reference(ctx):
    """A PATCH that would leave the note half-referenced is refused."""
    client, _ = ctx
    created = client.post("/api/v1/admin/notes", json={"note": "Plain"}).json()["data"]
    r = client.patch(
        f"/api/v1/admin/notes/{created['id']}", json={"entity_type": "SETTING"}
    )
    assert r.status_code == 422


def test_update_with_no_fields_is_rejected(ctx):
    client, _ = ctx
    created = client.post("/api/v1/admin/notes", json={"note": "Plain"}).json()["data"]
    r = client.patch(f"/api/v1/admin/notes/{created['id']}", json={})
    assert r.status_code == 422


def test_update_of_missing_note_is_404(ctx):
    client, _ = ctx
    assert client.patch("/api/v1/admin/notes/9999", json={"note": "x"}).status_code == 404


def test_delete_of_missing_note_is_404(ctx):
    client, _ = ctx
    assert client.delete("/api/v1/admin/notes/9999").status_code == 404


def test_delete_removes_the_note(ctx):
    client, _ = ctx
    created = client.post("/api/v1/admin/notes", json={"note": "Temporary"}).json()["data"]
    assert client.delete(f"/api/v1/admin/notes/{created['id']}").status_code == 200
    assert client.get("/api/v1/admin/notes").json()["data"]["total"] == 0


def test_delete_of_missing_note_is_404(ctx):
    client, _ = ctx
    assert client.delete("/api/v1/admin/notes/9999").status_code == 404


def test_creation_edit_and_delete_are_all_audited(ctx):
    """The governance trail must cover the whole note lifecycle."""
    client, Session = ctx
    created = client.post("/api/v1/admin/notes", json={"note": "Tracked"}).json()["data"]
    client.patch(f"/api/v1/admin/notes/{created['id']}", json={"note": "Tracked v2"})
    client.delete(f"/api/v1/admin/notes/{created['id']}")

    db = Session()
    try:
        actions = [
            row.action
            for row in db.scalars(
                select(AuditLog).where(AuditLog.entity_type == "note").order_by(AuditLog.id)
            ).all()
        ]
    finally:
        db.close()
    assert actions == ["note.created", "note.updated", "note.deleted"]
