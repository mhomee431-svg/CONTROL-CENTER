"""Offer Management sections.

The Offer Management console resolves its five tabs (Active / Scheduled /
Expired / Disabled / Review) server-side via `?section=...`. These tests pin
the contract that keeps each tab's total honest: every section is a real
predicate over stored columns, never a client-side slice of another tab.
"""

from datetime import datetime, timedelta, timezone

from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import Session, sessionmaker
from sqlalchemy.pool import StaticPool

from app.core.database import Base, get_db
from app.core.security import create_access_token
from app.main import app
from app.models import AdminUser, Offer, Shop, User


def _now() -> datetime:
    return datetime.now(timezone.utc)


def _fresh_db() -> sessionmaker:
    engine = create_engine(
        "sqlite://",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    Base.metadata.create_all(engine)
    return sessionmaker(bind=engine, autoflush=False, autocommit=False)


def _client_with(session_factory: sessionmaker) -> tuple[TestClient, Session]:
    """A TestClient wired to an in-memory database with an owner token."""
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


def test_offers_sections_partition_by_status_and_window():
    """Each section returns exactly the offers its predicate describes."""
    session_factory = _fresh_db()
    client, db = _client_with(session_factory)
    try:
        owner = User(name="Owner", status="ACTIVE")
        db.add(owner)
        db.commit()
        shop = Shop(name="Shop A", owner_id=owner.id, status="ACTIVE")
        db.add(shop)
        db.commit()

        past, future = _now() - timedelta(days=1), _now() + timedelta(days=1)
        offers = [
            # Running now: ACTIVE and already started.
            Offer(shop_id=shop.id, title="Live", status="ACTIVE",
                  starts_at=past, ends_at=future,
                  valid_from=past, valid_until=future),
            # Queued: starts in the future regardless of status label.
            Offer(shop_id=shop.id, title="Queued", status="ACTIVE",
                  starts_at=future, ends_at=future + timedelta(days=5),
                  valid_from=future, valid_until=future + timedelta(days=5)),
            # Ended by wall clock.
            Offer(shop_id=shop.id, title="Ended", status="ACTIVE",
                  starts_at=past, ends_at=past,
                  valid_from=past, valid_until=past),
            # Taken down by a human.
            Offer(shop_id=shop.id, title="Pulled", status="CANCELLED",
                  starts_at=past, ends_at=future,
                  valid_from=past, valid_until=future),
            # Held for an operator decision.
            Offer(shop_id=shop.id, title="Held", status="PAUSED",
                  starts_at=past, ends_at=future,
                  valid_from=past, valid_until=future),
        ]
        db.add_all(offers)
        db.commit()

        def titles(section: str) -> list[str]:
            body = client.get(
                "/api/v1/admin/offers", params={"section": section}
            ).json()["data"]
            return sorted(item["title"] for item in body["items"])

        assert titles("active") == ["Live"]
        assert titles("scheduled") == ["Queued"]
        assert titles("expired") == ["Ended"]
        assert titles("disabled") == ["Pulled"]
        assert titles("review") == ["Held"]

        # No section leaks rows into another: 5 offers, 5 disjoint sections.
        total = client.get("/api/v1/admin/offers").json()["data"]["total"]
        assert total == 5
    finally:
        client.close()
        app.dependency_overrides.clear()



def test_offers_section_total_respects_filter_and_paging():
    """The paged total counts only the section asked for, not the whole table."""
    session_factory = _fresh_db()
    client, db = _client_with(session_factory)
    try:
        owner = User(name="Owner", status="ACTIVE")
        db.add(owner)
        db.commit()
        shop = Shop(name="Shop A", owner_id=owner.id, status="ACTIVE")
        db.add(shop)
        db.commit()

        past, future = _now() - timedelta(days=1), _now() + timedelta(days=1)
        for i in range(3):
            db.add(Offer(shop_id=shop.id, title=f"Live {i}", status="ACTIVE",
                         starts_at=past, ends_at=future,
                         valid_from=past, valid_until=future))
        db.add(Offer(shop_id=shop.id, title="Held", status="PAUSED",
                     starts_at=past, ends_at=future,
                     valid_from=past, valid_until=future))
        db.commit()

        # Page size 2 must still report total 3 — the true section count.
        body = client.get(
            "/api/v1/admin/offers",
            params={"section": "active", "limit": 2, "offset": 0},
        ).json()["data"]
        assert body["total"] == 3
        assert len(body["items"]) == 2

        # `status` stays an exact override and wins over `section`.
        by_status = client.get(
            "/api/v1/admin/offers", params={"status": "PAUSED"}
        ).json()["data"]
        assert by_status["total"] == 1
        assert by_status["items"][0]["title"] == "Held"
    finally:
        client.close()
        app.dependency_overrides.clear()


def test_disable_offer_is_audited_status_change():
    """PATCH {status: CANCELLED} lands the new status and writes an audit row."""
    session_factory = _fresh_db()
    client, db = _client_with(session_factory)
    try:
        owner = User(name="Owner", status="ACTIVE")
        db.add(owner)
        db.commit()
        shop = Shop(name="Shop A", owner_id=owner.id, status="ACTIVE")
        db.add(shop)
        db.commit()
        past, future = _now() - timedelta(days=1), _now() + timedelta(days=1)
        offer = Offer(shop_id=shop.id, title="Live", status="ACTIVE",
                      starts_at=past, ends_at=future,
                      valid_from=past, valid_until=future)
        db.add(offer)
        db.commit()
        offer_id = offer.id

        resp = client.patch(
            f"/api/v1/admin/offers/{offer_id}/status", json={"status": "CANCELLED"}
        )
        assert resp.status_code == 200
        assert resp.json()["data"]["status"] == "CANCELLED"

        # It moved out of Active and into Disabled.
        active = client.get(
            "/api/v1/admin/offers", params={"section": "active"}
        ).json()["data"]
        assert active["total"] == 0
        disabled = client.get(
            "/api/v1/admin/offers", params={"section": "disabled"}
        ).json()["data"]
        assert disabled["total"] == 1

        # The trail the console's Audit action reads.
        trail = client.get(
            "/api/v1/admin/audit-logs",
            params={"entity_type": "offer", "entity_id": offer_id},
        ).json()["data"]
        assert trail["total"] >= 1
        assert trail["items"][0]["action"] == "offer.status_changed"
    finally:
        client.close()
        app.dependency_overrides.clear()
