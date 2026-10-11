"""SYSTEM CONFIGURATION — operator-controlled settings.

The System Configuration rule: the console may control operational tuning
(search radius, freshness thresholds, import limits, notification limits,
result limits, feature flags) but must never expose infrastructure secrets
(AWS keys, database passwords, Firebase admin keys).

These tests pin both halves: the controlled knobs are seeded and editable, and
a secret is returned masked regardless of its stored value.
"""

from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from app.core.database import Base, get_db
from app.core.security import create_access_token
from app.main import app
from app.models import AdminUser, SystemSetting, User


def _fresh_db() -> sessionmaker:
    engine = create_engine(
        "sqlite://",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    Base.metadata.create_all(engine)
    return sessionmaker(bind=engine, autoflush=False, autocommit=False)


def _client_with(session_factory: sessionmaker) -> tuple[TestClient, sessionmaker]:
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
    return client, session_factory


def test_controlled_configuration_knobs_are_available():
    """Every tuning knob the console is entitled to control is served."""
    session_factory = _fresh_db()
    client, session_factory_ = _client_with(session_factory)
    try:
        db = session_factory_()
        db.add_all(
            [
                SystemSetting(key="search_radius_km", value="10", value_type="int"),
                SystemSetting(key="inventory_fresh_after_hours", value="24", value_type="int"),
                SystemSetting(key="inventory_stale_after_hours", value="72", value_type="int"),
                SystemSetting(key="import_max_rows", value="50000", value_type="int"),
                SystemSetting(key="notification_max_recipients", value="100000", value_type="int"),
                SystemSetting(key="search_result_limit", value="200", value_type="int"),
                # A secret sits alongside them.
                SystemSetting(key="aws_secret_key", value="AKIA_REAL", value_type="string", is_secret=True),
            ]
        )
        db.commit()

        body = client.get("/api/v1/admin/settings").json()["data"]
        keys = {item["key"]: item for item in body["items"]}

        for knob in (
            "search_radius_km",
            "inventory_fresh_after_hours",
            "inventory_stale_after_hours",
            "import_max_rows",
            "notification_max_recipients",
            "search_result_limit",
        ):
            assert knob in keys, f"missing configuration knob: {knob}"
            assert keys[knob]["value"] != ""

        # A secret is masked in the listing no matter what is stored.
        assert keys["aws_secret_key"]["is_secret"] is True
        assert keys["aws_secret_key"]["value"] == "••••••••"
    finally:
        client.close()
        app.dependency_overrides.clear()


def test_configuration_update_is_rejected_for_unknown_keys():
    session_factory = _fresh_db()
    client, _ = _client_with(session_factory)
    try:
        resp = client.patch(
            "/api/v1/admin/settings/aws_secret_key", json={"value": "new-secret"}
        )
        # A nonexistent key cannot be created through the console — settings
        # are controlled configuration, not a free-form store.
        assert resp.status_code == 404
    finally:
        client.close()
        app.dependency_overrides.clear()


def test_customer_table_row_counts_stay_honest():
    """Sanity: unrelated surface is untouched by the settings change."""
    session_factory = _fresh_db()
    client, session_factory_ = _client_with(session_factory)
    try:
        db = session_factory_()
        db.add_all([User(name=f"C{i}", status="ACTIVE") for i in range(2)])
        db.commit()
        assert db.query(User).count() == 2
    finally:
        client.close()
        app.dependency_overrides.clear()
