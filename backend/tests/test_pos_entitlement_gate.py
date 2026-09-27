"""POS plan entitlement gate — ROUTE + SCHEDULER wiring (Phase 28 follow-through).

`shopkeeper_service.enforce_pos_support` existed (and was unit-tested) but no
POS route ever called it, so a Basic/canceled/expired shop could register,
connect, sync and retry exactly like a Pro shop. These tests pin the wiring:

  * every STATE-CHANGING POS route requires the plan's ``pos_support``
    entitlement → 403 ENTITLEMENT_DENIED with the server's upgrade copy;
  * read-only routes (status / jobs) and ``disconnect`` stay open, so a lapsed
    shop can inspect and always stop its connector;
  * the background-sync scheduler (``find_due_integrations``) skips shops
    whose plan no longer grants POS;
  * grandfathered shops (no subscription rows at all) keep legacy behaviour.

The 403 codes match what the Flutter app classifies as an entitlement denial
(`ApiException.isEntitlementDenied` / `friendlyPosError`).
"""

from __future__ import annotations

from datetime import datetime, timedelta, timezone
from types import SimpleNamespace

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from app.core.config import settings
from app.models.base import Base
from app.models.pos import POSDevice, POSIntegration, POSIntegrationStatus, POSProductMapping, POSSyncJob
from app.models.role import Permission, Role, role_permissions
from app.models.shop import Shop, ShopOwner, ShopStatus
from app.models.subscription import (
    Subscription,
    SubscriptionPlan,
    SubscriptionStatus,
)
from app.models.user import User
from tests.geo_compat import make_timestamp_defaults_portable, strip_geo_columns

strip_geo_columns()
make_timestamp_defaults_portable()

from app.core.dependencies import get_current_user  # noqa: E402
from app.database.session import get_db  # noqa: E402

# Only the tables this harness touches (the full metadata needs PostGIS types).
TABLES = [
    Role.__table__,
    Permission.__table__,
    role_permissions,
    User.__table__,
    Shop.__table__,
    ShopOwner.__table__,
    SubscriptionPlan.__table__,
    Subscription.__table__,
    POSIntegration.__table__,
    POSDevice.__table__,
    POSProductMapping.__table__,
    POSSyncJob.__table__,
]

API_PREFIX = settings.API_PREFIX
POS = f"{API_PREFIX}/shopkeeper/pos"

# ``resolve_shop_access`` reads only ``id`` + ``role.name`` — a stub keeps the
# harness free of auth tokens (same pattern as ``test_orders_api``).
OWNER = SimpleNamespace(id=1, role=SimpleNamespace(name="shopkeeper"))

_counter = {"n": 0}


def _next_id() -> int:
    _counter["n"] += 1
    return _counter["n"]


def _make_engine():
    engine = create_engine(
        "sqlite://",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    Base.metadata.create_all(engine, tables=TABLES)
    return engine


def _override_get_db(Session):
    def _get_db():
        session = Session()
        try:
            yield session
        finally:
            session.close()

    return _get_db


@pytest.fixture()
def ctx():
    """One in-memory DB + client + the dependency wiring, torn down after."""
    from app.main import app

    engine = _make_engine()
    Session = sessionmaker(bind=engine)
    db = Session()

    previous = dict(app.dependency_overrides)
    app.dependency_overrides[get_db] = _override_get_db(Session)
    app.dependency_overrides[get_current_user] = lambda: OWNER
    client = TestClient(app)
    try:
        yield SimpleNamespace(db=db, client=client, Session=Session, engine=engine)
    finally:
        app.dependency_overrides.clear()
        app.dependency_overrides.update(previous)
        db.close()
        engine.dispose()



# ── Factories ────────────────────────────────────────────────────────────────

def make_shop(db, *, owner_id: int = OWNER.id) -> Shop:
    n = _next_id()
    shop = Shop(
        name=f"POS Shop {n}",
        description=f"desc {n}",
        status=ShopStatus.ACTIVE,
        latitude=25.59,
        longitude=85.13,
    )
    db.add(shop)
    db.flush()
    db.add(ShopOwner(shop_id=shop.id, user_id=owner_id, is_active=True))
    db.flush()
    return shop


def make_plan(db, *, pos_support: bool):
    plan = SubscriptionPlan(
        name=f"Plan {_next_id()}",
        price_monthly=199.0,
        price_annual=1990.0,
        features_json={"pos_support": pos_support},
    )
    db.add(plan)
    db.flush()
    return plan


def subscribe(db, shop, *, pos_support: bool, status=SubscriptionStatus.ACTIVE):
    plan = make_plan(db, pos_support=pos_support)
    now = datetime.now(timezone.utc)
    sub = Subscription(
        user_id=OWNER.id,
        shop_id=shop.id,
        plan_id=plan.id,
        status=status,
        current_period_start=now,
        current_period_end=now + timedelta(days=30),
    )
    db.add(sub)
    db.flush()
    return sub


def make_integration(db, shop, *, last_sync_days_ago: int | None = 2) -> POSIntegration:
    integration = POSIntegration(
        shop_id=shop.id,
        provider_code="MOCK",
        provider_name="Mock POS",
        integration_type="API",
        status=POSIntegrationStatus.ACTIVE,
        sync_enabled=True,
        sync_interval_minutes=60,
    )
    if last_sync_days_ago is not None:
        integration.last_successful_sync_at = (
            datetime.now(timezone.utc) - timedelta(days=last_sync_days_ago)
        )
    db.add(integration)
    db.flush()
    return integration


def sync_url(integration_id: int) -> str:
    return f"{POS}/integrations/{integration_id}/sync"


# ── Route gate ───────────────────────────────────────────────────────────────

class TestPosRoutePlanGate:
    def test_basic_plan_blocks_state_changing_routes(self, ctx):
        shop = make_shop(ctx.db)
        subscribe(ctx.db, shop, pos_support=False)  # Basic: POS not included
        integration = make_integration(ctx.db, shop)
        ctx.db.commit()

        response = ctx.client.post(
            sync_url(integration.id), json={"sync_type": "FULL"}
        )

        assert response.status_code == 403, response.text
        body = response.json()
        assert body["error_code"] == "ENTITLEMENT_DENIED"
        assert "Upgrade" in body["message"]
        assert "pos_support" in body["message"]

    def test_canceled_subscription_falls_back_to_free_tier(self, ctx):
        shop = make_shop(ctx.db)
        subscribe(
            ctx.db,
            shop,
            pos_support=True,
            status=SubscriptionStatus.CANCELED,
        )
        integration = make_integration(ctx.db, shop)
        ctx.db.commit()

        response = ctx.client.post(
            sync_url(integration.id), json={"sync_type": "FULL"}
        )

        assert response.status_code == 403
        assert response.json()["error_code"] == "ENTITLEMENT_DENIED"

    def test_expired_subscription_reports_the_renewal_copy(self, ctx):
        shop = make_shop(ctx.db)
        subscribe(
            ctx.db,
            shop,
            pos_support=True,
            status=SubscriptionStatus.EXPIRED,
        )
        integration = make_integration(ctx.db, shop)
        ctx.db.commit()

        response = ctx.client.post(
            sync_url(integration.id), json={"sync_type": "FULL"}
        )

        assert response.status_code == 403
        body = response.json()
        assert body["error_code"] == "SUBSCRIPTION_EXPIRED"
        assert "Renew" in body["message"]



    def test_pro_plan_and_grandfathered_shops_still_sync(self, ctx):
        pro_shop = make_shop(ctx.db)
        subscribe(ctx.db, pro_shop, pos_support=True)
        pro_integration = make_integration(ctx.db, pro_shop)

        # Grandfathered: never subscribed → legacy behaviour (no gate).
        legacy_shop = make_shop(ctx.db)
        legacy_integration = make_integration(ctx.db, legacy_shop)
        ctx.db.commit()

        pro = ctx.client.post(
            sync_url(pro_integration.id), json={"sync_type": "FULL"}
        )
        legacy = ctx.client.post(
            sync_url(legacy_integration.id), json={"sync_type": "FULL"}
        )

        assert pro.status_code == 202, pro.text
        assert legacy.status_code == 202, legacy.text

    def test_reads_and_disconnect_stay_open_for_a_lapsed_shop(self, ctx):
        shop = make_shop(ctx.db)
        subscribe(ctx.db, shop, pos_support=False)
        integration = make_integration(ctx.db, shop)
        ctx.db.commit()

        status = ctx.client.get(f"{POS}/integrations/{integration.id}/status")
        jobs = ctx.client.get(f"{POS}/integrations/{integration.id}/jobs")
        disconnect = ctx.client.post(
            f"{POS}/integrations/{integration.id}/disconnect"
        )

        assert status.status_code == 200, status.text
        assert jobs.status_code == 200, jobs.text
        # A downgraded merchant must always be able to stop the connector.
        assert disconnect.status_code == 200, disconnect.text


# ── Background scheduler gate ────────────────────────────────────────────────

class TestPosSchedulerPlanGate:
    def test_due_integrations_skip_lapsed_shops_only(self, ctx):
        from app.services.pos_sync_service import find_due_integrations

        pro_shop = make_shop(ctx.db)
        subscribe(ctx.db, pro_shop, pos_support=True)
        pro_integration = make_integration(ctx.db, pro_shop)

        legacy_shop = make_shop(ctx.db)
        legacy_integration = make_integration(ctx.db, legacy_shop)

        basic_shop = make_shop(ctx.db)
        subscribe(ctx.db, basic_shop, pos_support=False)
        basic_integration = make_integration(ctx.db, basic_shop)
        ctx.db.commit()

        due_ids = {i.id for i in find_due_integrations(ctx.db)}

        assert pro_integration.id in due_ids
        assert legacy_integration.id in due_ids
        assert basic_integration.id not in due_ids
