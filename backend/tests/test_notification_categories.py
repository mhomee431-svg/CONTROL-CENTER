"""Notification categories — shopkeeper operational taxonomy tests.

Covers the merchant categories layered on top of the Phase 27 types:

  Products, Pricing, Imports, Offers, Account, Support

plus the Inventory low-stock emitter that already existed but had no call site.

Runs against a real in-memory SQLite database so preference gating, dedupe,
hourly caps and audience resolution are exercised for real — not mocked.
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

from app.models.base import Base  # noqa: E402
from app.services import notification_service as ns  # noqa: E402
from app.services.push_service import MockPushProvider, set_push_service  # noqa: E402

UTC = timezone.utc


def _portable_timestamp_defaults():
    """Replace literal "now()" server defaults with Python-side callables.

    SQLite has no ``now()``; the production schema relies on server defaults
    that the portable test engine cannot evaluate.
    """
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
            elif isinstance(sd_arg, str) and sd_arg.lower() == "false":
                if col.default is None and (
                    getattr(getattr(col.type, "python_type", None), "__name__", "") == "bool"
                ):
                    col.default = ColumnDefault(False)
                col.server_default = None


_portable_timestamp_defaults()


from app.models.notification import (  # noqa: E402
    DeviceToken,
    Notification,
    NotificationDelivery,
    NotificationPreference,
)
from app.models.role import Permission, Role, role_permissions  # noqa: E402
from app.models.user import User  # noqa: E402

TABLES = [
    Role.__table__,
    Permission.__table__,
    role_permissions,
    User.__table__,
    Notification.__table__,
    NotificationPreference.__table__,
    DeviceToken.__table__,
    NotificationDelivery.__table__,
]


@pytest.fixture()
def db():
    from sqlalchemy.pool import StaticPool

    engine = create_engine(
        "sqlite://",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    Base.metadata.create_all(engine, tables=TABLES)
    SessionLocal = sessionmaker(bind=engine)
    session = SessionLocal()
    yield session
    session.close()
    engine.dispose()


@pytest.fixture()
def dispatch_log(monkeypatch):
    """Capture Celery .delay calls so tests never need a broker."""
    from app.services.notification_tasks import deliver_notification_task

    log: list[int] = []
    monkeypatch.setattr(deliver_notification_task, "delay", lambda nid: log.append(nid))
    return log


@pytest.fixture()
def provider():
    mock = MockPushProvider()
    set_push_service(mock)
    yield mock
    set_push_service(MockPushProvider())


_counter = {"n": 0}


def _next_id():
    _counter["n"] += 1
    return _counter["n"]


def make_role(db, name="shopkeeper"):
    role = db.query(Role).filter(Role.name == name).first()
    if role is None:
        role = Role(name=name, description=name)
        db.add(role)
        db.flush()
    return role


def make_user(db, role_name="shopkeeper"):
    n = _next_id()
    role = make_role(db, role_name)
    user = User(
        phone_number=f"+9198765{n:05d}",
        name=f"Shopkeeper {n}",
        role_id=role.id,
        status="ACTIVE",
        is_active=True,
    )
    db.add(user)
    db.flush()
    return user


def types_for(db):
    return [row.type for row in db.query(Notification).all()]
# ── Registry ───────────────────────────────────────────────────────────────

class TestCategoryRegistry:
    """Every merchant category the Alerts filter groups must be a real type."""

    CATEGORIES = {
        "Inventory": ns.NotificationType.INVENTORY_UPDATE,
        "Products": ns.NotificationType.PRODUCT,
        "Pricing": ns.NotificationType.PRICING,
        "Offers": ns.NotificationType.SHOP_OFFER,
        "Imports": ns.NotificationType.IMPORT,
        "POS": ns.NotificationType.POS_SYNC,
        "Account": ns.NotificationType.ACCOUNT,
        "System": ns.NotificationType.SYSTEM,
        "Support": ns.NotificationType.SUPPORT,
    }

    def test_all_nine_categories_are_registered(self):
        for label, ntype in self.CATEGORIES.items():
            assert ntype in ns._TYPE_REGISTRY, f"{label} ({ntype}) unregistered"

    def test_operational_categories_survive_a_marketing_opt_out(self):
        prefs = NotificationPreference(
            user_id=1,
            price_alerts=False,
            availability_alerts=False,
            deal_alerts=False,
            promotional=False,
        )
        for ntype in (
            ns.NotificationType.PRODUCT,
            ns.NotificationType.PRICING,
            ns.NotificationType.IMPORT,
            ns.NotificationType.SHOP_OFFER,
            ns.NotificationType.ACCOUNT,
            ns.NotificationType.SUPPORT,
            ns.NotificationType.INVENTORY_UPDATE,
        ):
            assert ns._pref_allows_creation(ntype, prefs) is True

    def test_shopkeeper_categories_target_the_shopkeeper_audience(self):
        for ntype in (
            ns.NotificationType.PRODUCT,
            ns.NotificationType.PRICING,
            ns.NotificationType.IMPORT,
            ns.NotificationType.SHOP_OFFER,
            ns.NotificationType.ACCOUNT,
            ns.NotificationType.SUPPORT,
        ):
            assert ns._TYPE_REGISTRY[ntype][0] == ns.Audience.SHOPKEEPER

    def test_operational_categories_are_transactional(self):
        """Receipts are never throttled by the hourly marketing cap."""
        for ntype in (
            ns.NotificationType.PRODUCT,
            ns.NotificationType.PRICING,
            ns.NotificationType.IMPORT,
            ns.NotificationType.SHOP_OFFER,
            ns.NotificationType.ACCOUNT,
            ns.NotificationType.SUPPORT,
        ):
            assert ns._TYPE_REGISTRY[ntype][2] is True
# ── Emitters ───────────────────────────────────────────────────────────────

class TestCategoryEmitters:
    def test_products_emitter(self, db, dispatch_log):
        user = make_user(db)
        result = ns.notify_shop_product_event(
            db,
            shopkeeper_user_id=user.id,
            shop_product_id=42,
            event="ADDED",
            product_name="Amul Milk",
        )
        assert result.created is True
        note = result.notification
        assert note.type == ns.NotificationType.PRODUCT
        assert note.audience == ns.Audience.SHOPKEEPER
        assert "Amul Milk" in note.body
        assert note.deep_link == "hyperlocal://shopkeeper/products/42"

    def test_products_emitter_has_distinct_copy_per_event(self, db, dispatch_log):
        user = make_user(db)
        titles = set()
        for event in ("ADDED", "UPDATED", "REMOVED", "DISCONTINUED"):
            result = ns.notify_shop_product_event(
                db,
                shopkeeper_user_id=user.id,
                shop_product_id=1,
                event=event,
                product_name="Rice",
            )
            assert result.created is True
            titles.add(result.notification.title)
        assert len(titles) == 4

    def test_pricing_emitter_formats_the_delta(self, db, dispatch_log):
        user = make_user(db)
        result = ns.notify_price_change(
            db,
            shopkeeper_user_id=user.id,
            shop_product_id=7,
            old_price=100.0,
            new_price=85.5,
            product_name="Amul Milk",
        )
        note = result.notification
        assert note.type == ns.NotificationType.PRICING
        assert note.title == "Price update successful"
        assert "100.00" in note.body and "85.50" in note.body

    @pytest.mark.parametrize(
        ("status", "expected_title"),
        [
            ("COMPLETED", "Import completed"),
            ("PARTIAL", "Import partially completed"),
            ("FAILED", "Import failed"),
        ],
    )
    def test_import_emitter_titles(self, db, dispatch_log, status, expected_title):
        user = make_user(db)
        result = ns.notify_import_event(
            db,
            shopkeeper_user_id=user.id,
            job_id=9,
            status=status,
            filename="stock.xlsx",
            processed_rows=482,
            failed_rows=18,
        )
        note = result.notification
        assert note.type == ns.NotificationType.IMPORT
        assert note.title == expected_title
        assert "stock.xlsx" in note.body

    def test_offers_emitter(self, db, dispatch_log):
        user = make_user(db)
        result = ns.notify_shop_offer_event(
            db,
            shopkeeper_user_id=user.id,
            offer_id=3,
            event="ACTIVE",
            offer_title="Diwali Sale",
        )
        note = result.notification
        assert note.type == ns.NotificationType.SHOP_OFFER
        assert "Diwali Sale" in note.body
        assert note.deep_link == "hyperlocal://shopkeeper/offers/3"

    def test_account_emitter_labels_access_changes(self, db, dispatch_log):
        user = make_user(db)
        routine = ns.notify_account_event(
            db,
            shopkeeper_user_id=user.id,
            event="PROFILE_UPDATED",
            message="Profile saved.",
        )
        assert routine.notification.title == "Account updated"
        restricted = ns.notify_account_event(
            db,
            shopkeeper_user_id=user.id,
            event="ACCESS_STATUS_CHANGED",
            message="Access restricted.",
        )
        assert restricted.notification.title == "Account status changed"

    def test_support_emitter(self, db, dispatch_log):
        user = make_user(db)
        result = ns.notify_support_event(
            db,
            shopkeeper_user_id=user.id,
            title="Support replied",
            message="Re: payout delay",
            ticket_id=55,
        )
        note = result.notification
        assert note.type == ns.NotificationType.SUPPORT
        assert note.deep_link == "hyperlocal://shopkeeper/support/55"

    def test_support_emitter_without_ticket_still_has_a_link(self, db, dispatch_log):
        user = make_user(db)
        result = ns.notify_support_event(
            db,
            shopkeeper_user_id=user.id,
            title="Support notice",
            message="We are looking into it.",
        )
        assert result.notification.deep_link == "hyperlocal://shopkeeper/support"

    def test_inventory_low_stock_emitter(self, db, dispatch_log):
        user = make_user(db)
        result = ns.notify_inventory_update(
            db,
            shopkeeper_user_id=user.id,
            shop_product_id=11,
            message="Amul Milk is low on stock — 2 left.",
        )
        note = result.notification
        assert note.type == ns.NotificationType.INVENTORY_UPDATE
        assert note.audience == ns.Audience.SHOPKEEPER
        assert "low on stock" in note.body
# ── Recipient safety ───────────────────────────────────────────────────────

class TestRecipientSafety:
    def test_unknown_recipient_is_a_no_op(self, db, dispatch_log):
        calls = (
            lambda: ns.notify_shop_product_event(
                db, shopkeeper_user_id=None, shop_product_id=1, event="ADDED"
            ),
            lambda: ns.notify_price_change(
                db, shopkeeper_user_id=None, shop_product_id=1,
                old_price=1.0, new_price=2.0,
            ),
            lambda: ns.notify_import_event(
                db, shopkeeper_user_id=None, job_id=1, status="COMPLETED"
            ),
            lambda: ns.notify_shop_offer_event(
                db, shopkeeper_user_id=None, offer_id=1, event="ACTIVE"
            ),
            lambda: ns.notify_account_event(
                db, shopkeeper_user_id=None, event="X", message="y"
            ),
            lambda: ns.notify_support_event(
                db, shopkeeper_user_id=None, title="t", message="b"
            ),
            lambda: ns.notify_inventory_update(
                db, shopkeeper_user_id=None, shop_product_id=1, message="m"
            ),
        )
        for call in calls:
            result = call()
            assert result.created is False
            assert result.reason == "no_recipient"
        assert db.query(Notification).count() == 0

    def test_inactive_user_is_not_notified(self, db, dispatch_log):
        user = make_user(db)
        user.is_active = False
        db.flush()
        result = ns.notify_shop_product_event(
            db, shopkeeper_user_id=user.id, shop_product_id=1, event="ADDED"
        )
        assert result.created is False
        assert result.reason == "user_inactive_or_missing"
        assert db.query(Notification).count() == 0

    def test_duplicate_event_is_suppressed(self, db, dispatch_log):
        user = make_user(db)
        first = ns.notify_import_event(
            db, shopkeeper_user_id=user.id, job_id=5, status="COMPLETED"
        )
        second = ns.notify_import_event(
            db, shopkeeper_user_id=user.id, job_id=5, status="COMPLETED"
        )
        assert first.created is True
        assert second.created is False
        assert second.reason == "duplicate"
        assert db.query(Notification).count() == 1

    def test_distinct_events_each_create_a_row(self, db, dispatch_log):
        user = make_user(db)
        ns.notify_shop_product_event(
            db, shopkeeper_user_id=user.id, shop_product_id=1, event="ADDED"
        )
        ns.notify_shop_product_event(
            db, shopkeeper_user_id=user.id, shop_product_id=1, event="UPDATED"
        )
        assert db.query(Notification).count() == 2


# ── System broadcast ──────────────────────────────────────────────────────

class TestSystemBroadcast:
    def test_broadcast_reaches_active_users(self, db, dispatch_log):
        a = make_user(db)
        b = make_user(db)
        ids = ns.broadcast_system_notification(
            db, title="Maintenance", body="Scheduled at 2 AM"
        )
        assert len(ids) == 2
        rows = db.query(Notification).all()
        assert {r.user_id for r in rows} == {a.id, b.id}
        assert all(r.type == ns.NotificationType.SYSTEM for r in rows)
        assert all(r.audience == ns.Audience.ADMIN for r in rows)

    def test_broadcast_skips_inactive_users(self, db, dispatch_log):
        keeper = make_user(db)
        gone = make_user(db)
        gone.is_active = False
        db.flush()
        ids = ns.broadcast_system_notification(db, title="t", body="b")
        assert len(ids) == 1
        assert db.query(Notification).one().user_id == keeper.id
# ── Shopkeeper service wiring ─────────────────────────────────────────────

class TestShopkeeperServiceWiring:
    """``shopkeeper_service._notify`` must resolve a recipient and emit."""

    @staticmethod
    def _access(shop_id=1):
        import types

        return types.SimpleNamespace(shop=types.SimpleNamespace(id=shop_id))

    def test_notify_uses_the_acting_user(self, db, dispatch_log):
        from app.services import shopkeeper_service as svc

        user = make_user(db)
        svc._notify(
            db,
            self._access(),
            user,
            "notify_shop_product_event",
            shop_product_id=12,
            event="ADDED",
            product_name="Rice",
        )
        assert types_for(db) == [ns.NotificationType.PRODUCT]

    def test_notify_emits_every_category(self, db, dispatch_log):
        from app.services import shopkeeper_service as svc

        user = make_user(db)
        svc._notify(
            db, self._access(), user, "notify_price_change",
            shop_product_id=1, old_price=10.0, new_price=9.0,
        )
        svc._notify(
            db, self._access(), user, "notify_import_event",
            job_id=2, status="PARTIAL", processed_rows=1, failed_rows=1,
        )
        svc._notify(
            db, self._access(), user, "notify_shop_offer_event",
            offer_id=3, event="ACTIVE", offer_title="Sale",
        )
        svc._notify(
            db, self._access(), user, "notify_account_event",
            event="SETTINGS_UPDATED", message="Saved.",
        )
        svc._notify(
            db, self._access(), user, "notify_support_event",
            title="Support", message="Reply", ticket_id=4,
        )
        svc._notify(
            db, self._access(), user, "notify_inventory_update",
            shop_product_id=5, message="Low stock",
        )
        assert types_for(db) == [
            ns.NotificationType.PRICING,
            ns.NotificationType.IMPORT,
            ns.NotificationType.SHOP_OFFER,
            ns.NotificationType.ACCOUNT,
            ns.NotificationType.SUPPORT,
            ns.NotificationType.INVENTORY_UPDATE,
        ]

    def test_notify_swallows_emitter_failures(self, db, dispatch_log):
        """A side-effect failure must never propagate to the caller."""
        from app.services import shopkeeper_service as svc

        user = make_user(db)
        svc._notify(db, self._access(), user, "no_such_emitter", shop_product_id=1)
        assert db.query(Notification).count() == 0

    def test_recipient_prefers_the_acting_user(self):
        from app.services import shopkeeper_service as svc

        actor = User(id=99, phone_number="+910000000099", name="Actor", role_id=1)
        # The DB is never touched on this path.
        assert svc._notification_recipient_id(None, self._access(), actor) == 99

    def test_recipient_falls_back_to_the_shop_owner(self):
        from app.models.shop import ShopOwner
        from app.services import shopkeeper_service as svc

        class _Query:
            def filter(self, *args, **kwargs):
                return self

            def order_by(self, *args):
                return self

            def first(self):
                return type("Owner", (), {"user_id": 4242})()

        class _Db:
            def query(self, model):
                assert model is ShopOwner
                return _Query()

        assert svc._notification_recipient_id(_Db(), self._access(), None) == 4242

    def test_recipient_is_none_without_actor_or_owner(self):
        from app.services import shopkeeper_service as svc

        class _Query:
            def filter(self, *args, **kwargs):
                return self

            def order_by(self, *args):
                return self

            def first(self):
                return None

        class _Db:
            def query(self, model):
                return _Query()

        assert svc._notification_recipient_id(_Db(), self._access(), None) is None