"""Backend-driven shop capabilities (spec 103) - DERIVATION + ROUTE wiring.

`entitlements.derive_shop_capabilities` maps the resolved subscription
entitlements onto the four ``canX`` flags the Flutter app gates on, and
`shopkeeper_service.capabilities_payload` publishes them on three surfaces:

  * ``GET /shopkeeper/shops/{id}/capabilities`` (dedicated, cheap refresh);
  * ``GET /shopkeeper/shops/{id}``            (shop detail);
  * ``GET /shopkeeper/shops/{id}/dashboard``  (the app's shell root).

These tests pin the contract the frontend depends on:

  * the flag NAMES and the boolean type are stable (the Dart
    `ShopCapabilities.fromJson` keys);
  * each flag maps to exactly ONE entitlement (``pos_support``,
    ``BULK_IMPORT``, ``offers``, ``analytics``) - never a plan-name check;
  * grandfathered shops (no subscription rows at all) keep legacy behaviour
    (all ``True``), matching `enforce_feature`;
  * terminal subscriptions (CANCELED / EXPIRED) fall back to the free tier,
    so the flags go False without the frontend re-implementing the ladder;
  * a lookup failure degrades PERMISSIVELY, never to a lock-out;
  * the endpoint is shop-scoped: a non-associated user gets 403, not flags.
"""

from __future__ import annotations

from collections.abc import Callable, Iterator
from datetime import datetime, timedelta, timezone
from typing import Any, NamedTuple, cast

import httpx
import pytest
from fastapi.testclient import TestClient
from sqlalchemy import Table, create_engine
from sqlalchemy.engine import Engine
from sqlalchemy.orm import Session as OrmSession
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from app.core.config import settings
from app.models.base import Base
from app.models.product import (
    Category,
    Inventory,
    Offer,
    OfferProduct,
    ProductMaster,
    ProductStatus,
    ShopProduct,
    ShopProductStatus,
)
from app.models.role import Permission, Role, role_permissions
from app.models.shop import (
    Shop,
    ShopAddress,
    ShopManager,
    ShopOwner,
    ShopStatus,
    ShopVerification,
)
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


def _table(model: type[Any]) -> Table:
    """SQLAlchemy declares ``__table__`` as a ``FromClause``; a mapped class
    always carries a real ``Table``, which is what ``create_all`` wants."""
    return cast(Table, model.__table__)


# Only the tables this harness touches (the full metadata needs PostGIS types).
TABLES: list[Table] = [
    _table(Role),
    _table(Permission),
    role_permissions,
    _table(User),
    _table(Shop),
    _table(ShopOwner),
    _table(ShopManager),
    _table(ShopAddress),
    _table(ShopVerification),
    _table(SubscriptionPlan),
    _table(Subscription),
    _table(Category),
    _table(ProductMaster),
    _table(ShopProduct),
    _table(Inventory),
    _table(Offer),
    _table(OfferProduct),
]

API_PREFIX = settings.API_PREFIX
SHOPS = f"{API_PREFIX}/shopkeeper/shops"


class _Owner(NamedTuple):
    """``resolve_shop_access`` reads only ``id`` + ``role.name`` - a stub keeps
    the harness free of auth tokens (same pattern as
    ``test_pos_entitlement_gate``)."""

    id: int
    role: Any


class _Role(NamedTuple):
    name: str


OWNER = _Owner(id=1, role=_Role(name="shopkeeper"))

# The exact four keys the Dart `ShopCapabilities` model parses. A rename here
# silently turns every flag into the permissive default, so the names are
# pinned as a set, not merely "present".
CAN_FLAG_KEYS: set[str] = {
    "canUsePos",
    "canUploadExcel",
    "canCreateOffers",
    "canViewReports",
}

_counter = {"n": 0}


def _next_id() -> int:
    _counter["n"] += 1
    return _counter["n"]


def _make_engine() -> Engine:
    engine = create_engine(
        "sqlite://",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    Base.metadata.create_all(engine, tables=TABLES)
    return engine


def _override_get_db(
    SessionFactory: sessionmaker[OrmSession],
) -> Callable[[], Iterator[OrmSession]]:
    def _get_db() -> Iterator[OrmSession]:
        session = SessionFactory()
        try:
            yield session
        finally:
            session.close()

    return _get_db


class Ctx(NamedTuple):
    """The in-memory DB + client pair every route test needs.

    ``client`` is typed as the ``httpx.Client`` base on purpose. Starlette's
    ``TestClient`` annotates its verb overrides against ``httpx2`` under
    ``TYPE_CHECKING``, and that package is not installed, so ``TestClient.get``
    resolves to an unknown type and poisons every call site. We only ever use
    the plain client surface, and that one is fully typed.
    """

    db: OrmSession
    client: httpx.Client


@pytest.fixture()
def ctx() -> Iterator[Ctx]:
    """One in-memory DB + client + the dependency wiring, torn down after."""
    from app.main import app

    engine = _make_engine()
    SessionFactory = sessionmaker(bind=engine)
    db = SessionFactory()

    previous = dict(app.dependency_overrides)
    app.dependency_overrides[get_db] = _override_get_db(SessionFactory)
    app.dependency_overrides[get_current_user] = lambda: OWNER
    client = TestClient(app)
    try:
        yield Ctx(db=db, client=client)
    finally:
        app.dependency_overrides.clear()
        app.dependency_overrides.update(previous)
        db.close()
        engine.dispose()


# -- Factories ---------------------------------------------------------------


def make_shop(db: OrmSession, *, owner_id: int = OWNER.id) -> Shop:
    n = _next_id()
    shop = Shop(
        name=f"Cap Shop {n}",
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


def make_product(db: OrmSession, shop: Shop) -> ShopProduct:
    """A minimal ACTIVE listing so the dashboard payload can be built."""
    n = _next_id()
    master = ProductMaster(
        name=f"P {n}",
        slug=f"p-{n}",
        status=ProductStatus.APPROVED,
    )
    db.add(master)
    db.flush()
    sp = ShopProduct(
        shop_id=shop.id,
        product_master_id=master.id,
        price=10.0 + n,
        status=ShopProductStatus.ACTIVE,
    )
    db.add(sp)
    db.flush()
    db.add(Inventory(shop_product_id=sp.id, quantity=5, low_stock_threshold=2))
    db.flush()
    return sp


def make_plan(db: OrmSession, **features: Any) -> SubscriptionPlan:
    plan = SubscriptionPlan(
        name=f"Plan {_next_id()}",
        price_monthly=199.0,
        price_annual=1990.0,
        features_json=features,
    )
    db.add(plan)
    db.flush()
    return plan


def subscribe(
    db: OrmSession,
    shop: Shop,
    *,
    status: SubscriptionStatus = SubscriptionStatus.ACTIVE,
    **features: Any,
) -> Subscription:
    plan = make_plan(db, **features)
    now = datetime.now(timezone.utc)
    sub = Subscription(
        user_id=OWNER.id,
        shop_id=shop.id,
        plan_id=plan.id,
        status=status,
        current_period_start=now - timedelta(days=30),
        current_period_end=now + timedelta(days=30),
    )
    db.add(sub)
    db.flush()
    return sub


def caps_url(shop_id: int) -> str:
    return f"{SHOPS}/{shop_id}/capabilities"


def _data(response: httpx.Response) -> dict[str, Any]:
    """The unwrapped ``data`` envelope of a success response."""
    body: dict[str, Any] = response.json()
    return cast(dict[str, Any], body["data"])


def _code(response: httpx.Response) -> str:
    """The backend's typed error code from a failure envelope."""
    body: dict[str, Any] = response.json()
    return str(body["error_code"])


def fetch_caps(client: httpx.Client, shop_id: int) -> dict[str, Any]:
    response = client.get(caps_url(shop_id))
    assert response.status_code == 200, response.text
    return _data(response)


# -- 1. Pure derivation ------------------------------------------------------


class TestDeriveShopCapabilities:
    """The flags are a pure function of the RESOLVED entitlements."""

    def test_grandfathered_shop_keeps_legacy_behaviour(self):
        from app.services.subscription.entitlements import derive_shop_capabilities

        caps = derive_shop_capabilities({"grandfathered": True, "entitlements": {}})

        # A shop that never entered the subscription system must not be locked
        # out of anything (matches `enforce_feature`).
        assert caps == {
            "canUsePos": True,
            "canUploadExcel": True,
            "canCreateOffers": True,
            "canViewReports": True,
        }

    def test_full_plan_turns_everything_on(self):
        from app.services.subscription.entitlements import derive_shop_capabilities

        caps = derive_shop_capabilities(
            {
                "grandfathered": False,
                "entitlements": {
                    "pos_support": True,
                    "listing_features": ["BASIC", "BULK_IMPORT"],
                    "offers": True,
                    "analytics": True,
                },
            }
        )

        assert caps == {
            "canUsePos": True,
            "canUploadExcel": True,
            "canCreateOffers": True,
            "canViewReports": True,
        }

    def test_basic_plan_turns_off_exactly_the_paid_features(self):
        from app.services.subscription.entitlements import derive_shop_capabilities

        caps = derive_shop_capabilities(
            {
                "grandfathered": False,
                "entitlements": {
                    "pos_support": False,
                    "listing_features": ["BASIC"],
                    "offers": False,
                    "analytics": False,
                },
            }
        )

        assert caps == {
            "canUsePos": False,
            "canUploadExcel": False,
            "canCreateOffers": False,
            "canViewReports": False,
        }

    def test_each_flag_maps_to_its_own_entitlement(self):
        """A flag is ONE entitlement - never a plan-name string comparison.

        Operators tune plans in the DB (`features_json`), so a renamed plan row
        must not change what the app may show.
        """
        from app.services.subscription.entitlements import derive_shop_capabilities

        caps = derive_shop_capabilities(
            {
                "grandfathered": False,
                "entitlements": {
                    "pos_support": True,
                    "listing_features": ["BASIC"],
                    "offers": False,
                    "analytics": True,
                },
            }
        )

        assert caps["canUsePos"] is True
        assert caps["canUploadExcel"] is False
        assert caps["canCreateOffers"] is False
        # `analytics` is the reports flag - NOT `advanced_analytics`.
        assert caps["canViewReports"] is True

    def test_missing_entitlements_default_to_false_not_true(self):
        """An absent key is a refusal, never a silent grant."""
        from app.services.subscription.entitlements import derive_shop_capabilities

        caps = derive_shop_capabilities({"grandfathered": False, "entitlements": {}})

        assert all(value is False for value in caps.values())

    def test_returns_exactly_the_four_contract_keys(self):
        from app.services.subscription.entitlements import derive_shop_capabilities

        caps = derive_shop_capabilities({"grandfathered": False, "entitlements": {}})

        assert set(caps) == CAN_FLAG_KEYS
        assert all(isinstance(value, bool) for value in caps.values())


# -- 2. Route + payload wiring ----------------------------------------------


class TestCapabilitiesRoute:
    def test_grandfathered_shop_sees_every_flag(self, ctx: Ctx):
        shop = make_shop(ctx.db)
        ctx.db.commit()

        caps = fetch_caps(ctx.client, shop.id)

        assert set(caps) == CAN_FLAG_KEYS
        assert all(caps.values()) is True

    def test_active_plan_flags_come_from_the_resolved_entitlements(self, ctx: Ctx):
        shop = make_shop(ctx.db)
        subscribe(
            ctx.db,
            shop,
            pos_support=True,
            listing_features=["BASIC", "BULK_IMPORT"],
            offers=True,
            analytics=False,
        )
        ctx.db.commit()

        caps = fetch_caps(ctx.client, shop.id)

        assert caps["canUsePos"] is True
        assert caps["canUploadExcel"] is True
        assert caps["canCreateOffers"] is True
        assert caps["canViewReports"] is False

    def test_canceled_subscription_falls_back_to_the_free_tier(self, ctx: Ctx):
        shop = make_shop(ctx.db)
        subscribe(
            ctx.db,
            shop,
            status=SubscriptionStatus.CANCELED,
            pos_support=True,
            listing_features=["BASIC", "BULK_IMPORT"],
            offers=True,
            analytics=True,
        )
        ctx.db.commit()

        caps = fetch_caps(ctx.client, shop.id)

        # The plan still says yes; the RESOLVED state says the shop is not paid
        # any more. The frontend must not have to re-derive this.
        assert not any(caps.values())

    def test_expired_subscription_falls_back_to_the_free_tier(self, ctx: Ctx):
        shop = make_shop(ctx.db)
        subscribe(
            ctx.db,
            shop,
            status=SubscriptionStatus.EXPIRED,
            pos_support=True,
            listing_features=["BASIC", "BULK_IMPORT"],
            offers=True,
            analytics=True,
        )
        ctx.db.commit()

        caps = fetch_caps(ctx.client, shop.id)

        assert not any(caps.values())


    def test_flags_are_the_same_on_the_dashboard_payload(self, ctx: Ctx):
        """The app's shell root carries the flags, so the hub gates correctly
        with no extra round-trip."""
        shop = make_shop(ctx.db)
        make_product(ctx.db, shop)
        subscribe(
            ctx.db,
            shop,
            pos_support=False,
            listing_features=["BASIC"],
            offers=True,
            analytics=False,
        )
        ctx.db.commit()

        response = ctx.client.get(f"{SHOPS}/{shop.id}/dashboard")
        assert response.status_code == 200, response.text
        caps = _data(response)["capabilities"]

        assert caps == {
            "canUsePos": False,
            "canUploadExcel": False,
            "canCreateOffers": True,
            "canViewReports": False,
        }

    def test_flags_are_the_same_on_the_shop_detail_payload(self, ctx: Ctx):
        shop = make_shop(ctx.db)
        subscribe(
            ctx.db,
            shop,
            pos_support=True,
            listing_features=["BASIC"],
            offers=False,
            analytics=True,
        )
        ctx.db.commit()

        response = ctx.client.get(f"{SHOPS}/{shop.id}")
        assert response.status_code == 200, response.text
        caps = _data(response)["capabilities"]

        assert caps == {
            "canUsePos": True,
            "canUploadExcel": False,
            "canCreateOffers": False,
            "canViewReports": True,
        }

    def test_all_three_surfaces_never_disagree(self, ctx: Ctx):
        """One derivation, three surfaces - they cannot drift."""
        shop = make_shop(ctx.db)
        make_product(ctx.db, shop)
        subscribe(
            ctx.db,
            shop,
            pos_support=True,
            listing_features=["BASIC", "BULK_IMPORT"],
            offers=False,
            analytics=True,
        )
        ctx.db.commit()

        dedicated = fetch_caps(ctx.client, shop.id)
        dashboard = _data(ctx.client.get(f"{SHOPS}/{shop.id}/dashboard"))
        detail = _data(ctx.client.get(f"{SHOPS}/{shop.id}"))

        assert dashboard["capabilities"] == dedicated
        assert detail["capabilities"] == dedicated


    def test_lookup_failure_degrades_permissively(self, ctx: Ctx, monkeypatch: pytest.MonkeyPatch):
        """An outage must never lock a shopkeeper out of their own screens.

        `capabilities_payload` swallows the resolution error and returns the
        grandfathered (all-True) set; the backend still enforces on the real
        request, so the worst case is a visible feature that 403s.
        """
        import app.services.subscription.entitlements as entitlements_module

        def _boom(*_args: Any, **_kwargs: Any) -> None:
            raise RuntimeError("subscription table unavailable")

        monkeypatch.setattr(entitlements_module, "resolve_shop_entitlements", _boom)

        shop = make_shop(ctx.db)
        ctx.db.commit()

        caps = fetch_caps(ctx.client, shop.id)

        assert set(caps) == CAN_FLAG_KEYS
        assert all(caps.values()) is True

    def test_flags_are_scoped_to_the_requested_shop(self, ctx: Ctx):
        """A Pro shop's flags must not leak onto a Basic shop in the same
        account - the payload is derived per shop_id, not per user."""
        pro = make_shop(ctx.db)
        basic = make_shop(ctx.db)
        subscribe(
            ctx.db,
            pro,
            pos_support=True,
            listing_features=["BASIC", "BULK_IMPORT"],
            offers=True,
            analytics=True,
        )
        subscribe(
            ctx.db,
            basic,
            pos_support=False,
            listing_features=["BASIC"],
            offers=False,
            analytics=False,
        )
        ctx.db.commit()

        assert all(fetch_caps(ctx.client, pro.id).values()) is True
        assert not any(fetch_caps(ctx.client, basic.id).values())


class TestCapabilitiesAuthorization:
    def test_non_associated_user_gets_403_not_flags(self, ctx: Ctx):
        shop = make_shop(ctx.db, owner_id=999)  # owned by somebody else
        ctx.db.commit()

        response = ctx.client.get(caps_url(shop.id))

        assert response.status_code == 403, response.text
        assert "capabilities" not in response.text

    def test_unknown_shop_is_not_found(self, ctx: Ctx):
        response = ctx.client.get(caps_url(987654))

        assert response.status_code == 404, response.text
        assert _code(response) == "NOT_FOUND"


class TestSubscribeAuthorization:
    """POST /shopkeeper/subscription/subscribe must not accept a forged
    shop_id: a caller with no DB-backed association to the shop gets 403
    and no billable row is created."""

    def test_subscribe_with_forged_shop_id_is_403(self, ctx: Ctx):
        from app.schemas.subscription import SubscribeRequest
        from app.models.subscription import Subscription
        from app.api.routes import shopkeeper_subscription
        import asyncio

        shop = make_shop(ctx.db, owner_id=999)  # owned by somebody else
        plan = make_plan(ctx.db)
        ctx.db.commit()

        async def call():
            return await shopkeeper_subscription.subscribe_to_plan(
                payload=SubscribeRequest(
                    plan_id=plan.id,
                    shop_id=shop.id,
                    billing_cycle="MONTHLY",
                ),
                current_user=OWNER,
                db=ctx.db,
            )

        response = asyncio.run(call())

        assert response.status_code == 403, response.body
        assert ctx.db.query(Subscription).count() == 0

    def test_subscribe_without_shop_id_is_allowed(self, ctx: Ctx):
        from app.schemas.subscription import SubscribeRequest
        from app.models.subscription import Subscription
        from app.api.routes import shopkeeper_subscription
        import asyncio

        plan = make_plan(ctx.db)
        ctx.db.commit()

        async def call():
            return await shopkeeper_subscription.subscribe_to_plan(
                payload=SubscribeRequest(
                    plan_id=plan.id,
                    shop_id=None,
                    billing_cycle="MONTHLY",
                ),
                current_user=OWNER,
                db=ctx.db,
            )

        response = asyncio.run(call())

        assert response.status_code == 201, response.body
        assert ctx.db.query(Subscription).count() == 1


# -- 3. Fail-soft helper -----------------------------------------------------


class TestCapabilitiesPayloadHelper:
    def test_returns_booleans_for_a_plain_shop(self, ctx: Ctx):
        from app.services import shopkeeper_service

        shop = make_shop(ctx.db)
        ctx.db.commit()

        caps = shopkeeper_service.capabilities_payload(ctx.db, shop)

        assert set(caps) == CAN_FLAG_KEYS
        assert all(isinstance(value, bool) for value in caps.values())

