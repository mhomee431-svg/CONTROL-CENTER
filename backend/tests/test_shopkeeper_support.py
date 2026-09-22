"""Shopkeeper support tickets — real intake, scoping and tracking.

The shopkeeper app's *Report an issue* / *Contact support* screens file a ticket
instead of copying text into an e-mail. Those tickets are stored in the
platform's EXISTING ``complaints`` table (the same queue ``/admin/complaints``
triages), so these tests cover the whole loop against a REAL database:

  * the taxonomy the app is allowed to send, and the rejection of anything else
  * ticket creation (subject derivation, description composition, audit trail)
  * reporter scoping — one merchant can never read another merchant's tickets
  * the HTTP surface (auth required, 201/422/404/403 shape)
  * the resolution notice an admin's status change produces

Runs against an in-memory SQLite database plus a FastAPI TestClient, so the
authorization boundary is exercised for real rather than mocked.
"""

import os
import sys
from datetime import datetime, timezone
from pathlib import Path

BACKEND_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BACKEND_DIR))

os.environ.setdefault("ENVIRONMENT", "test")
os.environ.setdefault("HYPERLOCAL_ENV", "test")

import pytest  # noqa: E402
from sqlalchemy import create_engine  # noqa: E402
from sqlalchemy.orm import sessionmaker  # noqa: E402

from app.core.config import settings  # noqa: E402

settings.RATE_LIMIT_ENABLED = False

from app.core.exceptions import (  # noqa: E402
    ForbiddenError,
    NotFoundError,
    ValidationError,
)
from app.models.admin import (  # noqa: E402
    AdminAction,
    AdminNote,
    AuditLog,
    Complaint,
    ComplaintStatus,
)
from app.models.base import Base  # noqa: E402
from app.models.notification import (  # noqa: E402
    DeviceToken,
    Notification,
    NotificationDelivery,
    NotificationPreference,
)
from app.models.role import Permission, Role, role_permissions  # noqa: E402
from app.models.session import AuthSession, TokenBlacklist  # noqa: E402
from app.models.shop import Shop, ShopManager, ShopOwner  # noqa: E402
from app.models.user import User  # noqa: E402
from app.services import support_service  # noqa: E402

# Adapt PostGIS Geography columns for plain SQLite (shared, idempotent helper).
from tests.geo_compat import strip_geo_columns  # noqa: E402

strip_geo_columns()


def _portable_timestamp_defaults():
    """Replace literal ``now()`` server defaults so SQLite stores timestamps."""
    from sqlalchemy import ColumnDefault

    def _now(ctx=None):
        return datetime.now(timezone.utc)

    for table in Base.metadata.tables.values():
        for col in table.columns:
            sd = getattr(col, "server_default", None)
            sd_arg = getattr(sd, "arg", None)
            if sd_arg == "now()":
                if col.default is None:
                    col.default = ColumnDefault(_now)
                col.server_default = None
            ou = getattr(col, "onupdate", None)
            if ou is not None and getattr(ou, "arg", None) == "now()":
                col.onupdate = ColumnDefault(_now, for_update=True)


_portable_timestamp_defaults()

TABLES = [
    Role.__table__,
    Permission.__table__,
    role_permissions,
    User.__table__,
    Shop.__table__,
    ShopOwner.__table__,
    ShopManager.__table__,
    Complaint.__table__,
    AdminAction.__table__,
    AdminNote.__table__,
    AuditLog.__table__,
    Notification.__table__,
    NotificationPreference.__table__,
    DeviceToken.__table__,
    NotificationDelivery.__table__,
    AuthSession.__table__,
    TokenBlacklist.__table__,
]

API_PREFIX = settings.API_PREFIX
TICKETS_PATH = f"{API_PREFIX}/shopkeeper/support/tickets"


@pytest.fixture()
def db():
    from sqlalchemy.pool import StaticPool

    engine = create_engine(
        "sqlite://",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    strip_geo_columns()
    Base.metadata.create_all(engine, tables=TABLES)
    session = sessionmaker(bind=engine)()
    yield session
    session.close()
    engine.dispose()


@pytest.fixture()
def dispatch_log(monkeypatch):
    """Capture Celery .delay calls so tests never need a broker."""
    from app.services.notification_tasks import deliver_notification_task

    log: list[int] = []
    monkeypatch.setattr(
        deliver_notification_task, "delay", lambda nid: log.append(nid)
    )
    return log


@pytest.fixture()
def client(db):
    from fastapi.testclient import TestClient

    from app.database.session import get_db
    from app.main import app

    # Snapshot the app's current overrides so teardown RESTORES other modules'
    # wiring instead of clearing it — several modules install theirs at import
    # time, and a blanket clear() would make them fall through to the real
    # PostgreSQL engine on the next test.
    previous_overrides = dict(app.dependency_overrides)
    app.dependency_overrides[get_db] = lambda: db
    try:
        yield TestClient(app)
    finally:
        app.dependency_overrides.clear()
        app.dependency_overrides.update(previous_overrides)


_counter = {"n": 0}


def _next_id() -> int:
    _counter["n"] += 1
    return _counter["n"]


def make_role(db, name="shopkeeper"):
    role = db.query(Role).filter(Role.name == name).first()
    if role is None:
        role = Role(name=name, description=name)
        db.add(role)
        db.flush()
    return role


def make_user(db, role_name="shopkeeper", name=None):
    from app.models.user import UserStatus

    n = _next_id()
    user = User(
        phone_number=f"+9199000{n:05d}",
        name=name or f"Shopkeeper {n}",
        email=f"keeper{n}@example.com",
        role_id=make_role(db, role_name).id,
        status=UserStatus.ACTIVE,
        is_active=True,
    )
    db.add(user)
    db.flush()
    return user


def make_shop(db, name=None):
    from app.models.shop import ShopStatus

    n = _next_id()
    shop = Shop(
        name=name or f"Shop {n}",
        description=f"desc {n}",
        status=ShopStatus.ACTIVE,
        latitude=25.59,
        longitude=85.13,
    )
    db.add(shop)
    db.flush()
    return shop


def own(db, user, shop, is_primary=True):
    """Links *user* as an active owner of *shop* (what `resolve_shop_access` reads)."""
    db.add(
        ShopOwner(
            shop_id=shop.id,
            user_id=user.id,
            is_primary=is_primary,
            is_active=True,
        )
    )
    db.flush()
    return shop



def headers_for(user):
    from app.core.security import create_access_token

    token, _ = create_access_token(subject=str(user.id))
    return {"Authorization": f"Bearer {token}"}


# ── Taxonomy ──────────────────────────────────────────────────────────────
class TestTaxonomy:
    """The app may only file tickets the backend can triage and filter on."""

    # The exact codes the Flutter `IssueCategory` enum sends. Pinned here so a
    # rename on either side fails a test instead of silently storing free text.
    APP_CODES = {
        "APP_PRODUCTS",
        "APP_INVENTORY",
        "APP_OFFERS",
        "APP_POS",
        "APP_PAYMENTS",
        "APP_ACCOUNT",
        "APP_OTHER",
    }

    def test_app_issue_codes_match_the_client_contract(self):
        assert set(support_service.CATEGORIES) == self.APP_CODES

    @pytest.mark.parametrize("code", sorted(APP_CODES))
    def test_every_app_code_is_accepted(self, code):
        assert support_service.normalize_category(code) == code

    def test_codes_are_case_insensitive_and_trimmed(self):
        assert support_service.normalize_category("  app_products ") == "APP_PRODUCTS"

    def test_unknown_category_is_rejected_with_the_allowed_list(self):
        with pytest.raises(ValidationError) as err:
            support_service.normalize_category("SHOP_ISSUE")
        # A customer-complaint code is NOT a shopkeeper app issue.
        assert err.value.status_code == 422
        assert "APP_PRODUCTS" in err.value.data["allowed_categories"]

    def test_empty_category_is_rejected(self):
        with pytest.raises(ValidationError):
            support_service.normalize_category("   ")

    def test_priority_defaults_to_medium(self):
        assert support_service.normalize_priority(None) == "MEDIUM"
        assert support_service.normalize_priority("  ") == "MEDIUM"

    def test_priority_is_upper_cased(self):
        assert support_service.normalize_priority("high") == "HIGH"

    def test_unknown_priority_is_rejected(self):
        with pytest.raises(ValidationError):
            support_service.normalize_priority("BLOCKER")

    def test_every_backend_status_has_app_wording(self):
        """A status added to the enum must not render as `None` in the app."""
        for status in ComplaintStatus:
            assert support_service.STATUS_LABELS.get(status)


# ── Creation ──────────────────────────────────────────────────────────────
class TestCreateTicket:
    def test_files_an_open_ticket_with_a_reference(self, db):
        user = make_user(db)
        shop = own(db, user, make_shop(db))

        ticket = support_service.create_ticket(
            db,
            user=user,
            category="APP_PRODUCTS",
            description="A price saved as the old value after I tapped Save.",
            priority="HIGH",
            shop_id=shop.id,
        )

        assert ticket["id"] > 0
        assert ticket["reference"] == f"HL-{ticket['id']}"
        assert ticket["status"] == ComplaintStatus.OPEN.value
        assert ticket["status_label"] == "Submitted"
        assert ticket["priority"] == "HIGH"
        assert ticket["category"] == "APP_PRODUCTS"
        assert ticket["category_label"] == "Products & catalogue"
        assert ticket["shop_id"] == shop.id
        assert ticket["shop_name"] == shop.name
        # Nothing resolved yet — the app must not invent a resolution.
        assert ticket["resolution_notes"] is None
        assert ticket["resolved_at"] is None

    def test_subject_is_derived_from_the_first_line_when_absent(self, db):
        user = make_user(db)
        support_service.create_ticket(
            db,
            user=user,
            category="APP_POS",
            description="Sync failed twice.\nThen the job disappeared.",
        )
        assert db.query(Complaint).one().subject == (
            "[POS / billing sync] Sync failed twice."
        )

    def test_explicit_subject_is_kept_but_capped(self, db):
        user = make_user(db)
        support_service.create_ticket(
            db,
            user=user,
            category="APP_OTHER",
            description="Something else entirely broke today.",
            subject="x" * 400,
        )
        assert len(db.query(Complaint).one().subject) == 255

    def test_steps_and_client_context_are_preserved_for_triage(self, db):
        user = make_user(db)
        support_service.create_ticket(
            db,
            user=user,
            category="APP_INVENTORY",
            description="Stock did not update.",
            steps="1. Open Products\n2. Change quantity",
            app_version="1.0.0 (12)",
        )
        body = db.query(Complaint).one().description
        assert "Stock did not update." in body
        assert "Steps to reproduce:\n1. Open Products" in body
        assert "App: 1.0.0 (12)" in body

    def test_short_description_is_rejected(self, db):
        user = make_user(db)
        with pytest.raises(ValidationError):
            support_service.create_ticket(
                db, user=user, category="APP_OTHER", description="broken"
            )
        assert db.query(Complaint).count() == 0

    def test_a_foreign_shop_cannot_be_attached(self, db):
        """IDOR guard: the shop must be one the caller owns or manages."""
        user = make_user(db)
        stranger_shop = make_shop(db)  # created but NOT owned by `user`

        with pytest.raises(ForbiddenError):
            support_service.create_ticket(
                db,
                user=user,
                category="APP_OTHER",
                description="Trying to file against someone else's shop.",
                shop_id=stranger_shop.id,
            )

    def test_filing_a_ticket_is_written_to_the_audit_trail(self, db):
        user = make_user(db)
        ticket = support_service.create_ticket(
            db, user=user, category="APP_ACCOUNT", description="Sign-in failed."
        )
        rows = db.query(AuditLog).filter(
            AuditLog.entity_type == "SUPPORT_TICKET"
        ).all()
        assert len(rows) == 1
        assert rows[0].entity_id == ticket["id"]
        assert rows[0].user_id == user.id


# ── Scoping & tracking ────────────────────────────────────────────────────
class TestMyTickets:
    def test_a_shopkeeper_only_sees_their_own_tickets(self, db):
        mine = make_user(db)
        theirs = make_user(db)
        support_service.create_ticket(
            db, user=mine, category="APP_PRODUCTS", description="My own problem."
        )
        support_service.create_ticket(
            db, user=theirs, category="APP_ACCOUNT", description="Their problem."
        )

        tickets, total = support_service.list_my_tickets(db, user=mine)

        assert total == 1
        assert len(tickets) == 1
        assert tickets[0]["category"] == "APP_PRODUCTS"

    def test_newest_ticket_comes_first(self, db):
        user = make_user(db)
        first = support_service.create_ticket(
            db, user=user, category="APP_OTHER", description="First reported."
        )
        second = support_service.create_ticket(
            db, user=user, category="APP_OTHER", description="Second reported."
        )

        tickets, _ = support_service.list_my_tickets(db, user=user)

        assert [t["id"] for t in tickets] == [second["id"], first["id"]]

    def test_status_filter_uses_the_backend_vocabulary(self, db):
        user = make_user(db)
        support_service.create_ticket(
            db, user=user, category="APP_OTHER", description="Still open here."
        )
        resolved = support_service.create_ticket(
            db, user=user, category="APP_OTHER", description="Already resolved."
        )
        row = db.query(Complaint).filter(Complaint.id == resolved["id"]).one()
        row.status = ComplaintStatus.RESOLVED
        db.flush()

        open_only, total = support_service.list_my_tickets(db, user=user, status="open")

        assert total == 1
        assert open_only[0]["status"] == "OPEN"

    def test_unknown_status_filter_is_rejected(self, db):
        user = make_user(db)
        with pytest.raises(ValidationError) as err:
            support_service.list_my_tickets(db, user=user, status="PENDING")
        assert "OPEN" in err.value.data["allowed_statuses"]

    def test_reading_a_ticket_returns_the_tracked_state(self, db):
        user = make_user(db)
        ticket = support_service.create_ticket(
            db, user=user, category="APP_PAYMENTS", description="Card was charged."
        )
        row = db.query(Complaint).filter(Complaint.id == ticket["id"]).one()
        row.status = ComplaintStatus.IN_PROGRESS
        db.flush()

        read = support_service.get_ticket(db, user=user, ticket_id=ticket["id"])

        assert read["status"] == "IN_PROGRESS"
        assert read["status_label"] == "In progress"

    def test_resolution_notes_are_exposed_to_the_reporter(self, db):
        user = make_user(db)
        ticket = support_service.create_ticket(
            db, user=user, category="APP_POS", description="Sync job vanished."
        )
        row = db.query(Complaint).filter(Complaint.id == ticket["id"]).one()
        row.status = ComplaintStatus.RESOLVED
        row.resolution_notes = "Fixed in build 42."
        row.resolved_at = datetime.now(timezone.utc)
        db.flush()

        read = support_service.get_ticket(db, user=user, ticket_id=ticket["id"])

        assert read["status"] == "RESOLVED"
        assert read["resolution_notes"] == "Fixed in build 42."
        assert read["resolved_at"] is not None

    def test_another_reporters_ticket_is_not_found(self, db):
        """Same 404 as a missing ticket — ticket ids are not enumerable."""
        mine = make_user(db)
        theirs = make_user(db)
        ticket = support_service.create_ticket(
            db, user=theirs, category="APP_OTHER", description="Not yours to read."
        )

        with pytest.raises(NotFoundError):
            support_service.get_ticket(db, user=mine, ticket_id=ticket["id"])

    def test_missing_ticket_is_not_found(self, db):
        user = make_user(db)
        with pytest.raises(NotFoundError):
            support_service.get_ticket(db, user=user, ticket_id=999999)


# ── HTTP surface ──────────────────────────────────────────────────────────
class TestTicketRoutes:
    def test_filing_requires_a_session(self, client):
        response = client.post(
            TICKETS_PATH,
            json={"category": "APP_OTHER", "description": "No token here."},
        )
        assert response.status_code == 401

    def test_filing_returns_the_tracked_ticket(self, client, db):
        user = make_user(db)
        shop = own(db, user, make_shop(db))

        response = client.post(
            TICKETS_PATH,
            headers=headers_for(user),
            json={
                "category": "APP_INVENTORY",
                "priority": "HIGH",
                "description": "Stock did not update after I saved it.",
                "steps": "1. Open Products\n2. Change quantity",
                "app_version": "1.0.0 (12)",
                "shop_id": shop.id,
            },
        )

        assert response.status_code == 201
        body = response.json()
        assert body["success"] is True
        data = body["data"]
        assert data["status"] == "OPEN"
        assert data["status_label"] == "Submitted"
        assert data["reference"] == f"HL-{data['id']}"
        assert data["shop_name"] == shop.name

    def test_a_too_short_description_is_a_422(self, client, db):
        user = make_user(db)
        response = client.post(
            TICKETS_PATH,
            headers=headers_for(user),
            json={"category": "APP_OTHER", "description": "nope"},
        )
        assert response.status_code == 422

    def test_an_unknown_category_is_a_422(self, client, db):
        user = make_user(db)
        response = client.post(
            TICKETS_PATH,
            headers=headers_for(user),
            json={
                "category": "FAKE_PRODUCT",
                "description": "A customer complaint code is not an app issue.",
            },
        )
        assert response.status_code == 422
        assert response.json()["error_code"] == "VALIDATION_ERROR"

    def test_a_foreign_shop_is_a_403(self, client, db):
        user = make_user(db)
        stranger_shop = make_shop(db)
        response = client.post(
            TICKETS_PATH,
            headers=headers_for(user),
            json={
                "category": "APP_OTHER",
                "description": "Filing against a shop I do not manage.",
                "shop_id": stranger_shop.id,
            },
        )
        assert response.status_code == 403

    def test_listing_shows_only_the_callers_tickets(self, client, db):
        mine = make_user(db)
        theirs = make_user(db)
        support_service.create_ticket(
            db, user=mine, category="APP_PRODUCTS", description="Visible to me."
        )
        support_service.create_ticket(
            db, user=theirs, category="APP_ACCOUNT", description="Hidden from me."
        )

        response = client.get(TICKETS_PATH, headers=headers_for(mine))

        assert response.status_code == 200
        data = response.json()["data"]
        assert data["total"] == 1
        assert data["tickets"][0]["description"].startswith("Visible to me.")

    def test_an_empty_history_is_a_200_with_no_tickets(self, client, db):
        """No tickets is NOT an error — the screen shows an empty state."""
        user = make_user(db)
        response = client.get(TICKETS_PATH, headers=headers_for(user))
        assert response.status_code == 200
        assert response.json()["data"] == {"tickets": [], "count": 0, "total": 0}

    def test_reading_another_reporters_ticket_is_a_404(self, client, db):
        mine = make_user(db)
        theirs = make_user(db)
        ticket = support_service.create_ticket(
            db, user=theirs, category="APP_OTHER", description="Private report."
        )

        response = client.get(
            f"{TICKETS_PATH}/{ticket['id']}", headers=headers_for(mine)
        )

        assert response.status_code == 404

    def test_reading_my_own_ticket_is_a_200(self, client, db):
        user = make_user(db)
        ticket = support_service.create_ticket(
            db, user=user, category="APP_OFFERS", description="Discount vanished."
        )

        response = client.get(
            f"{TICKETS_PATH}/{ticket['id']}", headers=headers_for(user)
        )

        assert response.status_code == 200
        assert response.json()["data"]["id"] == ticket["id"]


# ── The loop closes: an admin's status change reaches the reporter ────────
class TestResolutionNotice:
    def test_resolving_an_app_ticket_notifies_the_reporter(self, db, dispatch_log):
        from app.services import admin_service

        shopkeeper = make_user(db)
        admin = make_user(db, role_name="admin")
        ticket = support_service.create_ticket(
            db, user=shopkeeper, category="APP_POS", description="Sync is broken."
        )

        admin_service.update_complaint(
            db,
            admin_user=admin,
            complaint_id=ticket["id"],
            updates={"status": "RESOLVED", "resolution_notes": "Fixed in build 42."},
        )

        notes = (
            db.query(Notification)
            .filter(Notification.user_id == shopkeeper.id)
            .all()
        )
        assert len(notes) == 1
        note = notes[0]
        assert note.deep_link == f"hyperlocal://shopkeeper/support/{ticket['id']}"
        assert "Fixed in build 42." in note.body
        assert f"HL-{ticket['id']}" in note.title

    def test_a_customer_complaint_sends_no_shopkeeper_notice(self, db, dispatch_log):
        """The same table carries customer complaints; they must stay silent."""
        from app.services import admin_service

        reporter = make_user(db)
        admin = make_user(db, role_name="admin")
        complaint = Complaint(
            complainant_user_id=reporter.id,
            complaint_type="WRONG_PRICE",
            subject="Price mismatch",
            description="The shelf price says 20.",
            status=ComplaintStatus.OPEN,
            priority="MEDIUM",
        )
        db.add(complaint)
        db.flush()

        admin_service.update_complaint(
            db,
            admin_user=admin,
            complaint_id=complaint.id,
            updates={"status": "RESOLVED", "resolution_notes": "Shop corrected it."},
        )

        assert db.query(Notification).count() == 0

    def test_a_priority_only_edit_sends_no_notice(self, db, dispatch_log):
        from app.services import admin_service

        shopkeeper = make_user(db)
        admin = make_user(db, role_name="admin")
        ticket = support_service.create_ticket(
            db, user=shopkeeper, category="APP_PRODUCTS", description="Price is wrong."
        )

        admin_service.update_complaint(
            db,
            admin_user=admin,
            complaint_id=ticket["id"],
            updates={"priority": "URGENT"},
        )

        assert db.query(Notification).count() == 0


# ── Report payloads survive the input-sanitization middleware ─────────────
class TestReportPayloadSafety:
    """A merchant's own words must reach the triage queue.

    `InputSanitizationMiddleware` scans every JSON body, and its SQL rules used
    to match bare keywords: the report below ("Stock did not update") was
    answered with 400 INVALID_INPUT, so the most common verb in a bug report
    made the feature unusable. These tests pin BOTH halves of the fix — ordinary
    prose is accepted, and real injection shapes are still rejected.
    """

    ORDINARY_REPORTS = [
        "Stock did not update after I saved it.",
        "I tried to update the price and nothing happened.",
        "Cannot delete this product from the list.",
        "Please create the offer again, it failed.",
        "The POS backup did not run last night.",
        "There is a delay before the sync finishes.",
        "Can you restore my previous prices?",
        "The connection= timed out while saving.",
    ]

    INJECTION_SHAPES = [
        "SELECT * FROM users",
        "1 UNION SELECT password FROM users",
        "UPDATE shops SET name='x'",
        "DELETE FROM shops WHERE id=1",
        "DROP TABLE users",
        "a; DROP TABLE users",
        "admin' OR 1=1 --",
        "<script>alert(1)</script>",
        "<img src=x onerror=alert(1)>",
        "WAITFOR DELAY 0:0:5",
    ]

    @pytest.mark.parametrize("text", ORDINARY_REPORTS)
    def test_an_ordinary_report_is_accepted(self, client, db, text):
        user = make_user(db)
        response = client.post(
            TICKETS_PATH,
            headers=headers_for(user),
            json={"category": "APP_OTHER", "description": text},
        )
        assert response.status_code == 201, response.json()

    @pytest.mark.parametrize("payload", INJECTION_SHAPES)
    def test_an_injection_shaped_report_is_rejected(self, client, db, payload):
        user = make_user(db)
        response = client.post(
            TICKETS_PATH,
            headers=headers_for(user),
            json={"category": "APP_OTHER", "description": payload},
        )
        assert response.status_code == 400
        assert response.json()["error_code"] == "INVALID_INPUT"


# ── Screenshot evidence (Phase 7 media pipeline) ──────────────────────────
def _support_key(user, name="screenshot.png", prefix="support"):
    """A server-minted key shape: ``{prefix}/{scope}/{YYYY}/{MM}/{uuid8}_{name}``."""
    return f"{prefix}/{user.id}/2026/09/ab12cd34_{name}"


class FakeMediaClient:
    """Marker object: ``media_service._is_s3`` treats a provider with a
    ``.client`` (and no ``upload_dir``) as S3."""


class FakeMediaProvider:
    """In-memory stand-in for the S3 provider (no boto3, no network).

    Implements only the surface ``attach_media`` / ``resolve_media_url`` touch,
    so the tests drive the REAL key validation, authorization, HEAD and
    serialization code rather than a stubbed-out version of them.
    """

    def __init__(self):
        self.bucket = "test-bucket"
        self.client = FakeMediaClient()
        self.objects: dict[str, dict] = {}

    def put(self, key, *, size=2048, content_type="image/png"):
        """Simulate a completed upload of one object."""
        self.objects[key] = {"size": size, "content_type": content_type}

    async def create_signed_upload(self, key, content_type, max_bytes, expires_in=None):
        return {
            "mode": "post",
            "url": "https://s3.test/",
            "fields": {"key": key},
            "key": key,
            "expires_in": expires_in or 600,
            "content_type": content_type,
            "max_bytes": max_bytes,
        }

    async def get_object_head(self, key):
        return self.objects.get(key)

    async def get_file_url(self, key):
        return f"https://s3.test/{self.bucket}/{key}?sig=read"

    def presign_get_sync(self, key):
        return f"https://s3.test/{self.bucket}/{key}?sig=serialize"


@pytest.fixture()
def fake_media(monkeypatch):
    """Serve media calls from memory — no AWS credentials, no network."""
    from app.services import media_service

    provider = FakeMediaProvider()
    monkeypatch.setattr(media_service, "get_storage", lambda: provider)
    return provider


class TestScreenshotAttachment:
    """*Report an issue* can attach one screenshot as evidence.

    The key must come from the signed-upload flow, and the backend re-checks its
    shape, its category and its owner, then HEADs the object — all before the
    ticket row is written. These tests pin exactly what a client could otherwise
    attempt: borrowing another reporter's key, passing off a catalog image as
    evidence, or referencing an object that was never uploaded.
    """

    def test_a_screenshot_is_stored_and_returned_with_a_read_url(
        self, client, db, fake_media
    ):
        user = make_user(db)
        key = _support_key(user, name="checkout.png")
        fake_media.put(key, size=2048, content_type="image/png")

        response = client.post(
            TICKETS_PATH,
            headers=headers_for(user),
            json={
                "category": "APP_POS",
                "description": "The billing pane went blank after I tapped sync.",
                "attachment_key": key,
            },
        )

        assert response.status_code == 201, response.text
        attachment = response.json()["data"]["attachment"]
        assert attachment["key"] == key
        assert attachment["url"].startswith("https://s3.test/")
        # Server-observed metadata, never what the client claimed.
        assert attachment["content_type"] == "image/png"
        assert attachment["size_bytes"] == 2048
        # The readable name survives the uuid prefix the server mints.
        assert attachment["filename"] == "checkout.png"

        stored = (
            db.query(Complaint)
            .filter(Complaint.complainant_user_id == user.id)
            .one()
        )
        assert stored.attachment_key == key
        assert stored.attachment_meta["filename"] == "checkout.png"

    def test_a_ticket_without_a_screenshot_has_no_attachment(self, client, db):
        user = make_user(db)
        response = client.post(
            TICKETS_PATH,
            headers=headers_for(user),
            json={"category": "APP_OTHER", "description": "Nothing to attach here."},
        )
        assert response.status_code == 201
        assert response.json()["data"]["attachment"] is None

    def test_another_reporters_screenshot_cannot_be_attached(
        self, client, db, fake_media
    ):
        owner = make_user(db)
        stranger = make_user(db)
        key = _support_key(owner)
        fake_media.put(key)

        response = client.post(
            TICKETS_PATH,
            headers=headers_for(stranger),
            json={
                "category": "APP_OTHER",
                "description": "Trying to attach an upload that is not mine.",
                "attachment_key": key,
            },
        )

        assert response.status_code == 403
        assert db.query(Complaint).count() == 0  # nothing half-filed

    def test_a_catalog_image_cannot_be_borrowed_as_evidence(
        self, client, db, fake_media
    ):
        user = make_user(db)
        shop = own(db, user, make_shop(db))
        key = f"products/{shop.id}/2026/09/ab12cd34_photo.png"
        fake_media.put(key)

        response = client.post(
            TICKETS_PATH,
            headers=headers_for(user),
            json={
                "category": "APP_PRODUCTS",
                "description": "A product photo is not support evidence.",
                "attachment_key": key,
            },
        )

        assert response.status_code == 422
        assert response.json()["error_code"] == "VALIDATION_ERROR"
        assert db.query(Complaint).count() == 0

    def test_a_key_that_was_never_uploaded_is_rejected(self, client, db, fake_media):
        user = make_user(db)
        response = client.post(
            TICKETS_PATH,
            headers=headers_for(user),
            json={
                "category": "APP_OTHER",
                "description": "This key points at nothing at all.",
                "attachment_key": _support_key(user, name="ghost.png"),
            },
        )
        assert response.status_code == 404
        assert db.query(Complaint).count() == 0

    def test_a_malformed_key_is_rejected(self, client, db, fake_media):
        user = make_user(db)
        response = client.post(
            TICKETS_PATH,
            headers=headers_for(user),
            json={
                "category": "APP_OTHER",
                "description": "A key outside the server-minted shape.",
                "attachment_key": "support/../..//etc/passwd.jpg",
            },
        )
        assert response.status_code == 422
        assert db.query(Complaint).count() == 0

    def test_the_evidence_is_recorded_in_the_audit_trail(self, client, db, fake_media):
        user = make_user(db)
        key = _support_key(user)
        fake_media.put(key)

        response = client.post(
            TICKETS_PATH,
            headers=headers_for(user),
            json={
                "category": "APP_INVENTORY",
                "description": "Stock count screen, screenshot attached.",
                "attachment_key": key,
            },
        )
        assert response.status_code == 201

        rows = (
            db.query(AuditLog).filter(AuditLog.entity_type == "SUPPORT_TICKET").all()
        )
        assert len(rows) == 1
        assert rows[0].new_values["has_attachment"] is True

    def test_the_read_url_is_minted_at_read_time(self, client, db, fake_media):
        """Only the KEY is persisted; each read re-presigns, so a stored ticket
        can never hand out a URL that has already expired."""
        user = make_user(db)
        key = _support_key(user)
        fake_media.put(key)

        created = client.post(
            TICKETS_PATH,
            headers=headers_for(user),
            json={
                "category": "APP_ACCOUNT",
                "description": "Sign-in loop, screenshot attached.",
                "attachment_key": key,
            },
        ).json()["data"]

        fetched = client.get(
            f"{TICKETS_PATH}/{created['id']}", headers=headers_for(user)
        )
        assert fetched.status_code == 200
        attachment = fetched.json()["data"]["attachment"]
        assert attachment["key"] == key
        assert attachment["url"].startswith("https://s3.test/")

        stored = db.query(Complaint).filter(Complaint.id == created["id"]).one()
        assert stored.attachment_key == key
        assert "https://" not in stored.attachment_key

    def test_the_listing_carries_the_attachment_too(self, client, db, fake_media):
        """`My tickets` shows which reports have evidence without a second call."""
        user = make_user(db)
        key = _support_key(user)
        fake_media.put(key)
        client.post(
            TICKETS_PATH,
            headers=headers_for(user),
            json={
                "category": "APP_OTHER",
                "description": "Filed with a screenshot, then listed.",
                "attachment_key": key,
            },
        )

        listed = client.get(TICKETS_PATH, headers=headers_for(user))
        assert listed.status_code == 200
        tickets = listed.json()["data"]["tickets"]
        assert len(tickets) == 1
        assert tickets[0]["attachment"]["key"] == key






