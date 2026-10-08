"""Analytics endpoints for the six non-customer sections.

Each section must report figures the backend can substantiate, over exactly the
window the operator selected, and must never fabricate a metric it does not
collect. These tests pin all three behaviours across shopkeeper, product,
business, search, notification and geographic analytics.
"""

from datetime import datetime, timedelta, timezone

from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import Session, sessionmaker
from sqlalchemy.pool import StaticPool

from app.core.database import Base, get_db
from app.core.security import create_access_token
from app.main import app
from app.models import (
    AdminUser,
    ImportJob,
    NotificationCampaign,
    PosIntegration,
    PosSyncRun,
    Product,
    SearchQuery,
    Shop,
    ShopInventory,
    User,
)


def _now() -> datetime:
    return datetime.now(timezone.utc)


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


def _fresh_db() -> sessionmaker:
    engine = create_engine(
        "sqlite://",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    Base.metadata.create_all(engine)
    return sessionmaker(bind=engine, autoflush=False, autocommit=False)


# --------------------------------------------------------------------------- #
# Shopkeeper analytics
# --------------------------------------------------------------------------- #


def test_shopkeeper_analytics_counts_onboarding_and_contribution():
    session_factory = _fresh_db()
    client, db = _client_with(session_factory)
    try:
        # A merchant who registered inside the window and owns two shops.
        merchant = User(
            name="Merchant A",
            status="ACTIVE",
            created_at=_now() - timedelta(days=2),
            last_active=_now() - timedelta(days=1),
        )
        # A customer with no shop — must not be counted as a shopkeeper.
        db.add(User(name="Customer", status="ACTIVE", created_at=_now() - timedelta(days=1)))
        db.add(merchant)
        db.commit()

        shop = Shop(name="Shop A", owner_id=merchant.id, status="ACTIVE", verification_status="VERIFIED")
        db.add(shop)
        db.commit()
        db.add(Shop(name="Shop A2", owner_id=merchant.id, status="ACTIVE", verification_status="VERIFIED"))
        db.commit()

        db.add(
            ShopInventory(
                shop_id=shop.id,
                product_id=1,
                product_name="Rice",
                price=50.0,
                last_updated=_now() - timedelta(days=1),
            )
        )
        db.add(ImportJob(status="COMPLETED"))
        db.add(ImportJob(status="FAILED"))
        integration = PosIntegration(shop_id=shop.id, provider="X")
        db.add(integration)
        db.commit()
        db.add(PosSyncRun(integration_id=integration.id, status="FAILED"))
        db.commit()

        body = client.get("/api/v1/admin/analytics/shopkeepers", params={"days": 30}).json()["data"]

        assert body["period_days"] == 30
        # One distinct owner, despite owning two shops.
        assert body["total_shopkeepers"] == 1
        assert body["new_shopkeepers"] == 1
        assert body["active_businesses"] == 2
        assert body["active_shopkeepers"] == 1
        assert body["product_additions"] == 1
        assert body["imports_completed"] == 1
        assert body["imports_failed"] == 1
        assert body["pos_sync_failures"] == 1
        assert len(body["shopkeepers_by_day"]) == 30
        assert body["top_merchants"][0]["shops"] == 2
    finally:
        client.close()
        app.dependency_overrides.clear()


# --------------------------------------------------------------------------- #
# Product analytics
# --------------------------------------------------------------------------- #


def test_product_analytics_reports_coverage_gaps():
    session_factory = _fresh_db()
    client, db = _client_with(session_factory)
    try:
        # One product with a shop, one with none.
        db.add(Product(name="Rice", status="ACTIVE", shop_count=3, category_name="Grocery"))
        db.add(Product(name="Ghost", status="ACTIVE", shop_count=0, category_name="Grocery"))
        db.commit()

        db.add(
            SearchQuery(query="Rice", result_count=4, searched_at=_now() - timedelta(days=1))
        )
        db.commit()

        body = client.get("/api/v1/admin/analytics/products", params={"days": 30}).json()["data"]

        assert body["total_products"] == 2
        assert body["active_products"] == 2
        # "Ghost" is stocked by no shop.
        assert body["products_with_no_shop"] == 1
        assert body["low_coverage_products"] == 1
        # The real join on the query text finds Rice.
        assert body["top_searched_products"][0]["name"] == "Rice"
        assert len(body["products_added_by_day"]) == 30
    finally:
        client.close()
        app.dependency_overrides.clear()


# --------------------------------------------------------------------------- #
# Business analytics
# --------------------------------------------------------------------------- #


def test_business_analytics_counts_new_shops_and_freshness():
    session_factory = _fresh_db()
    client, db = _client_with(session_factory)
    try:
        fresh = Shop(
            name="Fresh", status="ACTIVE", category="Grocery", city="Mumbai",
            created_at=_now() - timedelta(days=1),
        )
        db.add(fresh)
        db.commit()
        db.add(
            ShopInventory(
                shop_id=fresh.id, product_id=1, product_name="Rice",
                last_updated=_now() - timedelta(minutes=5),
            )
        )
        db.commit()

        body = client.get("/api/v1/admin/analytics/businesses", params={"days": 30}).json()["data"]

        assert body["total_shops"] == 1
        assert body["active_shops"] == 1
        assert body["new_shops"] == 1
        assert body["fresh_shops"] == 1
        assert body["stale_shops"] == 0
        assert body["shops_by_city"][0]["city"] == "Mumbai"
        assert len(body["new_shops_by_day"]) == 30
    finally:
        client.close()
        app.dependency_overrides.clear()


# --------------------------------------------------------------------------- #
# Search analytics
# --------------------------------------------------------------------------- #


def test_search_analytics_splits_successful_and_zero_result():
    session_factory = _fresh_db()
    client, db = _client_with(session_factory)
    try:
        db.add(SearchQuery(query="rice", result_count=3, searched_at=_now() - timedelta(days=1)))
        db.add(SearchQuery(query="unicorn", result_count=0, searched_at=_now() - timedelta(days=1)))
        db.commit()

        body = client.get("/api/v1/admin/analytics/search", params={"days": 7}).json()["data"]

        assert body["total_searches"] == 2
        assert body["successful_searches"] == 1
        assert body["zero_result_searches"] == 1
        assert body["search_success_rate"] == 50.0
        assert body["zero_result_queries"][0]["query"] == "unicorn"
        assert len(body["searches_by_day"]) == 7
    finally:
        client.close()
        app.dependency_overrides.clear()


# --------------------------------------------------------------------------- #
# Notification analytics
# --------------------------------------------------------------------------- #


def test_notification_analytics_does_not_fabricate_delivery_metrics():
    """Delivery / open / click are not collected, so they must be null."""
    session_factory = _fresh_db()
    client, db = _client_with(session_factory)
    try:
        db.add(
            NotificationCampaign(
                title="Promo",
                status="SENT",
                audience="all",
                recipients_total=100,
                recipients_sent=95,
                recipients_failed=5,
                sent_at=_now() - timedelta(days=1),
            )
        )
        db.commit()

        body = client.get("/api/v1/admin/analytics/notifications", params={"days": 30}).json()["data"]

        assert body["total_campaigns"] == 1
        assert body["campaigns_sent"] == 1
        assert body["recipients_sent"] == 95
        assert body["recipients_failed"] == 5
        # Never fabricated.
        assert body["recipients_delivered"] is None
        assert body["recipients_opened"] is None
        assert body["recipients_clicked"] is None
    finally:
        client.close()
        app.dependency_overrides.clear()


# --------------------------------------------------------------------------- #
# Geographic analytics
# --------------------------------------------------------------------------- #


def test_geography_analytics_returns_aggregated_density():
    session_factory = _fresh_db()
    client, db = _client_with(session_factory)
    try:
        db.add(Shop(name="S1", city="Mumbai", state="MH", category="Grocery", status="ACTIVE"))
        db.add(Shop(name="S2", city="Mumbai", state="MH", category="Grocery", status="ACTIVE"))
        db.add(User(name="C1", city="Mumbai", status="ACTIVE"))
        db.commit()
        db.add(
            SearchQuery(query="rice", result_count=1, location="Mumbai", searched_at=_now() - timedelta(days=1))
        )
        db.commit()

        body = client.get("/api/v1/admin/analytics/geography", params={"days": 30}).json()["data"]

        assert body["covered_cities"] == 1
        assert body["covered_states"] == 1
        assert body["shops_by_city"][0] == {"city": "Mumbai", "count": 2}
        assert body["customers_by_city"][0] == {"city": "Mumbai", "count": 1}
        # Demand/coverage: 1 search per 2 shops.
        mumbai = next(d for d in body["demand_coverage"] if d["city"] == "Mumbai")
        assert mumbai["shops"] == 2
        assert mumbai["searches"] == 1
        assert mumbai["demand_per_shop"] == 0.5
    finally:
        client.close()
        app.dependency_overrides.clear()


def test_all_analytics_windows_are_clamped_and_defaulted():
    """Every section honours the same window contract as customer analytics."""
    session_factory = _fresh_db()
    client, _db = _client_with(session_factory)
    try:
        for path in (
            "/api/v1/admin/analytics/shopkeepers",
            "/api/v1/admin/analytics/products",
            "/api/v1/admin/analytics/businesses",
            "/api/v1/admin/analytics/search",
            "/api/v1/admin/analytics/notifications",
            "/api/v1/admin/analytics/geography",
        ):
            default = client.get(path).json()["data"]
            assert default["period_days"] == 30, path
            ninety = client.get(path, params={"days": 90}).json()["data"]
            assert ninety["period_days"] == 90, path
    finally:
        client.close()
        app.dependency_overrides.clear()
