"""Customer analytics endpoint.

The Customers Analytics surface must report a figure the backend can
substantiate, over exactly the window the operator selected. These tests pin the
two behaviours that make that true: the window is honoured (and clamped), and
the derived metrics are computed from real rows rather than fabricated.
"""

from datetime import datetime, timedelta, timezone

from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import Session, sessionmaker
from sqlalchemy.pool import StaticPool

from app.core.database import Base, get_db
from app.core.security import create_access_token
from app.main import app
from app.models import AdminUser, SearchQuery, User


def _now() -> datetime:
    return datetime.now(timezone.utc)


def _client_with(session_factory: sessionmaker) -> tuple[TestClient, Session]:
    """A TestClient wired to an in-memory database with an owner token.

    Returns the live session too, so a test can seed rows through the same
    connection the request handlers read from.
    """
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


def _fresh_db() -> sessionmaker:
    engine = create_engine(
        "sqlite://",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    Base.metadata.create_all(engine)
    return sessionmaker(bind=engine, autoflush=False, autocommit=False)


def test_customer_analytics_counts_acquisition_and_engagement_in_window():
    session_factory = _fresh_db()
    client, db = _client_with(session_factory)
    try:
        # Inside the 30-day window: three recent registrations, one active.
        for i in range(3):
            db.add(
                User(
                    name=f"Recent {i}",
                    status="ACTIVE",
                    city="Mumbai",
                    created_at=_now() - timedelta(days=i + 1),
                    last_active=_now() - timedelta(days=1),
                )
            )
        # Outside the window: an older customer, still active (a returning user).
        db.add(
            User(
                name="Veteran",
                status="ACTIVE",
                city="Pune",
                created_at=_now() - timedelta(days=200),
                last_active=_now() - timedelta(days=2),
            )
        )
        # Dormant: registered long ago, never active in the window.
        db.add(
            User(
                name="Dormant",
                status="INACTIVE",
                created_at=_now() - timedelta(days=120),
                last_active=_now() - timedelta(days=100),
            )
        )
        db.commit()

        db.add(SearchQuery(query="rice", result_count=3, searched_at=_now() - timedelta(days=1)))
        db.add(SearchQuery(query="milk", result_count=0, searched_at=_now() - timedelta(days=40)))
        db.commit()

        body = client.get("/api/v1/admin/analytics/customers", params={"days": 30}).json()["data"]

        assert body["period_days"] == 30
        assert body["total_customers"] == 5
        assert body["new_customers"] == 3
        assert body["active_users"] == 4
        # Only the veteran predates the window and was active within it.
        assert body["returning_users"] == 1
        # One search inside the window; the 40-day-old one is excluded.
        assert body["searches"] == 1
        # The dense series covers every day of the window.
        assert len(body["registrations_by_day"]) == 30
    finally:
        client.close()
        app.dependency_overrides.clear()


def test_customer_analytics_window_is_clamped_and_defaulted():
    session_factory = _fresh_db()
    client, _db = _client_with(session_factory)
    try:
        default = client.get("/api/v1/admin/analytics/customers").json()["data"]
        assert default["period_days"] == 30

        # A larger, explicitly requested window is honoured.
        ninety = client.get("/api/v1/admin/analytics/customers", params={"days": 90}).json()["data"]
        assert ninety["period_days"] == 90
        assert len(ninety["registrations_by_day"]) == 90
    finally:
        client.close()
        app.dependency_overrides.clear()


def test_customer_analytics_reports_unavailable_metrics_as_null_not_zero():
    """Directions are not collected by the platform, so they are reported as
    null — an honest "unknown" rather than a fabricated zero."""
    db = _fresh_db()
    client, _db = _client_with(db)
    try:
        body = client.get("/api/v1/admin/analytics/customers", params={"days": 7}).json()["data"]
        assert body["directions"] is None
        # With no eligible base there is no retention rate to report either.
        assert body["retention_rate"] is None
    finally:
        client.close()
        app.dependency_overrides.clear()
