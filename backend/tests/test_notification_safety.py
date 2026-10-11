"""Notification Center — server-side safety, targeting and scheduling.

NOTIFICATION SAFETY contract:
    validate → notification type · entity ID · supported route

The composer validates a deep link in the browser, but the backend is the
authoritative gate. These tests pin that contract: an unvalidated or
unroutable deep link must be rejected before a campaign row is written, and the
targeting/scheduling dimensions the console exposes must be genuinely honoured
by the API rather than displayed and ignored.
"""

from datetime import datetime, timedelta, timezone

from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import Session, sessionmaker
from sqlalchemy.pool import StaticPool

from app.core.database import Base, get_db
from app.core.notification_safety import (
    build_deep_link,
    is_supported_route,
    resolve_deep_link,
    validate_entity_id,
    validate_explicit_url,
    validate_notification_payload,
)
from app.core.security import create_access_token
from app.main import app
from app.models import AdminUser, NotificationCampaign, Shop, User


def _fresh_db() -> sessionmaker:
    engine = create_engine(
        "sqlite://",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    Base.metadata.create_all(engine)
    return sessionmaker(bind=engine, autoflush=False, autocommit=False)


def _client_with(session_factory: sessionmaker) -> tuple[TestClient, Session]:
    db = session_factory()
    owner = AdminUser(
        username="owner",
        name="Platform Owner",
        hashed_password="x",
        role_name="Platform Owner",
        level="SUPER",
        is_owner=True,
        permissions=[],
    )
    db.add(owner)
    db.commit()
    token = create_access_token(owner.id, {"purpose": "admin_access"})

    def _override():
        yield db

    app.dependency_overrides[get_db] = _override
    client = TestClient(app)
    client.headers.update({"Authorization": f"Bearer {token}"})
    return client, db


# --------------------------------------------------------------------------- #
# Notification type · entity ID · supported route
# --------------------------------------------------------------------------- #


def test_unknown_notification_type_is_rejected():
    result = validate_notification_payload("NOT_A_TYPE", "all")
    assert result.valid is False
    assert result.code == "UNKNOWN_NOTIFICATION_TYPE"


def test_entity_contract_is_enforced_per_type():
    # A no-entity type must not carry an id...
    assert validate_entity_id("ADMIN_BROADCAST", "123").valid is False
    # ...an entity-bound type must have one...
    assert validate_entity_id("PRODUCT_ALERT", None).code == "ENTITY_REQUIRED"
    # ...and it must be numeric.
    assert validate_entity_id("PRODUCT_ALERT", "abc").code == "INVALID_NUMERIC_ENTITY"


def test_deep_link_must_map_to_a_supported_route():
    assert is_supported_route("/products/12") is True
    assert is_supported_route("/secret") is False
    assert is_supported_route("/customers/../brands") is False

    assert build_deep_link("PRODUCT_ALERT", "7") == "/products/7"
    assert build_deep_link("ADMIN_BROADCAST", None) is None


def test_explicit_url_rejects_external_and_protocol_relative():
    for url in ("https://evil.com", "javascript:alert(1)", "//evil.com/path"):
        assert validate_explicit_url(url).valid is False
    assert validate_explicit_url("/products/12?tab=pricing").valid is True


def test_explicit_url_wins_and_is_not_trusted():
    """An explicitly supplied link is validated directly, never accepted."""
    bad = resolve_deep_link("PRODUCT_ALERT", "7", "https://evil.com")
    assert bad.valid is False
    assert bad.code == "EXTERNAL_URL_BLOCKED"

    good = resolve_deep_link("PRODUCT_ALERT", "7", "/products/7")
    assert good.valid is True
    assert good.path == "/products/7"


# --------------------------------------------------------------------------- #
# The send endpoint is the authoritative gate
# --------------------------------------------------------------------------- #


def test_send_rejects_unvalidated_deep_link():
    session_factory = _fresh_db()
    client, _ = _client_with(session_factory)
    try:
        resp = client.post(
            "/api/v1/admin/notifications/send",
            json={
                "title": "Bad",
                "body": "Nope",
                "notification_type": "PRODUCT_ALERT",
                "audience": "all",
                "entity_id": "7",
                "deep_link": "https://evil.com",
            },
        )
        assert resp.status_code == 422
        assert resp.json()["data"]["code"] == "EXTERNAL_URL_BLOCKED"
    finally:
        client.close()
        app.dependency_overrides.clear()


def test_send_rejects_entity_type_mismatch():
    session_factory = _fresh_db()
    client, _ = _client_with(session_factory)
    try:
        resp = client.post(
            "/api/v1/admin/notifications/send",
            json={
                "title": "Bad",
                "body": "Missing id",
                "notification_type": "PRODUCT_ALERT",
                "audience": "all",
            },
        )
        assert resp.status_code == 422
        assert resp.json()["data"]["code"] == "ENTITY_REQUIRED"
    finally:
        client.close()
        app.dependency_overrides.clear()


def test_send_derives_link_and_records_recipients():
    session_factory = _fresh_db()
    client, db = _client_with(session_factory)
    try:
        db.add_all([User(name=f"U{i}", status="ACTIVE") for i in range(4)])
        db.commit()

        resp = client.post(
            "/api/v1/admin/notifications/send",
            json={
                "title": "Product drop",
                "body": "New in your area",
                "notification_type": "PRODUCT_ALERT",
                "audience": "all",
                "entity_id": "7",
            },
        )
        assert resp.status_code == 200
        data = resp.json()["data"]
        assert data["deep_link"] == "/products/7"
        assert data["status"] == "SENT"
        assert data["recipients_total"] == 4
        assert data["recipients_sent"] == 4
    finally:
        client.close()
        app.dependency_overrides.clear()


# --------------------------------------------------------------------------- #
# Scheduling
# --------------------------------------------------------------------------- #


def test_scheduling_queues_without_reporting_delivery():
    session_factory = _fresh_db()
    client, db = _client_with(session_factory)
    try:
        db.add_all([User(name=f"U{i}", status="ACTIVE") for i in range(3)])
        db.commit()
        future = (datetime.now(timezone.utc) + timedelta(days=1)).isoformat()

        resp = client.post(
            "/api/v1/admin/notifications/send",
            json={
                "title": "Later",
                "body": "Queued",
                "notification_type": "ADMIN_BROADCAST",
                "audience": "all",
                "scheduled_at": future,
            },
        )
        assert resp.status_code == 200
        data = resp.json()["data"]
        assert data["status"] == "SCHEDULED"
        # Nothing has gone out, so no delivery count is fabricated.
        assert data["recipients_sent"] is None
        assert data["sent_at"] is None
        assert data["scheduled_at"] is not None
    finally:
        client.close()
        app.dependency_overrides.clear()


def test_scheduling_in_the_past_is_rejected():
    session_factory = _fresh_db()
    client, _ = _client_with(session_factory)
    try:
        past = (datetime.now(timezone.utc) - timedelta(hours=1)).isoformat()
        resp = client.post(
            "/api/v1/admin/notifications/send",
            json={
                "title": "Too late",
                "body": "Bad",
                "notification_type": "ADMIN_BROADCAST",
                "audience": "all",
                "scheduled_at": past,
            },
        )
        assert resp.status_code == 422
        assert resp.json()["data"]["code"] == "SCHEDULE_IN_PAST"
    finally:
        client.close()
        app.dependency_overrides.clear()


# --------------------------------------------------------------------------- #
# Targeting
# --------------------------------------------------------------------------- #


def test_audience_scope_selects_the_right_subjects():
    session_factory = _fresh_db()
    client, db = _client_with(session_factory)
    try:
        owner = User(name="Owner", status="ACTIVE")
        db.add(owner)
        db.commit()
        shop = Shop(name="Shop A", owner_id=owner.id, status="ACTIVE")
        db.add(shop)
        db.add_all([User(name=f"C{i}", status="ACTIVE") for i in range(3)])
        db.commit()

        shopkeepers = client.post(
            "/api/v1/admin/notifications/send",
            json={
                "title": "To shops",
                "body": "x",
                "notification_type": "ADMIN_BROADCAST",
                "audience": "shopkeeper",
            },
        ).json()["data"]
        assert shopkeepers["recipients_total"] == 1

        customers = client.post(
            "/api/v1/admin/notifications/send",
            json={
                "title": "To customers",
                "body": "x",
                "notification_type": "ADMIN_BROADCAST",
                "audience": "customer",
            },
        ).json()["data"]
        assert customers["recipients_total"] == 3
    finally:
        client.close()
        app.dependency_overrides.clear()


def test_draft_persists_partial_work_without_dispatching():
    session_factory = _fresh_db()
    client, _ = _client_with(session_factory)
    try:
        resp = client.post(
            "/api/v1/admin/notifications/drafts",
            json={
                "title": "Half-written",
                "body": "",
                "notification_type": "PROMOTION",
                "audience": "customer",
                "metadata": {"campaign": "spring"},
            },
        )
        assert resp.status_code == 200
        data = resp.json()["data"]
        assert data["status"] == "DRAFT"
        assert data["recipients_sent"] is None
        assert data["metadata_json"] == {"campaign": "spring"}
    finally:
        client.close()
        app.dependency_overrides.clear()


def test_draft_still_rejects_an_unsafe_deep_link():
    session_factory = _fresh_db()
    client, _ = _client_with(session_factory)
    try:
        resp = client.post(
            "/api/v1/admin/notifications/drafts",
            json={
                "title": "Draft",
                "body": "x",
                "notification_type": "PROMOTION",
                "audience": "all",
                "deep_link": "//evil.com",
            },
        )
        assert resp.status_code == 422
        assert resp.json()["data"]["code"] == "PROTOCOL_RELATIVE_BLOCKED"
    finally:
        client.close()
        app.dependency_overrides.clear()


def test_campaign_list_filters_by_status():
    session_factory = _fresh_db()
    client, db = _client_with(session_factory)
    try:
        db.add_all(
            [
                NotificationCampaign(title="A", body="b", notification_type="PROMOTION",
                                     audience="all", status="SENT"),
                NotificationCampaign(title="B", body="b", notification_type="PROMOTION",
                                     audience="all", status="SCHEDULED"),
                NotificationCampaign(title="C", body="b", notification_type="PROMOTION",
                                     audience="all", status="FAILED"),
            ]
        )
        db.commit()

        scheduled = client.get(
            "/api/v1/admin/notifications/campaigns", params={"status": "SCHEDULED"}
        ).json()["data"]
        assert scheduled["total"] == 1
        assert scheduled["items"][0]["title"] == "B"
    finally:
        client.close()
        app.dependency_overrides.clear()
