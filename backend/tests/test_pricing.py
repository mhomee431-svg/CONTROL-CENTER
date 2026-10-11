"""Price Management endpoints.

The Price Management screen shows four coverage tiles and a price-change audit
table. These tests pin the two behaviours that make the screen trustworthy:
every tile is counted from real inventory rows (never fabricated), and the
detail table returns the recorded price changes joined to their shop and
product with the old/new prices recovered from history.
"""

from datetime import datetime, timedelta, timezone

from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import Session, sessionmaker
from sqlalchemy.pool import StaticPool

from app.core.database import Base, get_db
from app.core.security import create_access_token
from app.main import app
from app.models import AdminUser, InventoryHistory, Shop, ShopInventory, User


def _now() -> datetime:
    return datetime.now(timezone.utc)


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


def _fresh_db() -> sessionmaker:
    engine = create_engine(
        "sqlite://",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    Base.metadata.create_all(engine)
    return sessionmaker(bind=engine, autoflush=False, autocommit=False)


def test_pricing_summary_counts_real_inventory_rows():
    session_factory = _fresh_db()
    client, db = _client_with(session_factory)
    try:
        owner = User(name="Owner", status="ACTIVE")
        db.add(owner)
        db.commit()
        shop = Shop(name="Shop A", owner_id=owner.id, status="ACTIVE")
        db.add(shop)
        db.commit()

        # One fully priced row with a real discount (price < mrp).
        db.add(
            ShopInventory(
                shop_id=shop.id, product_id=1, product_name="Rice",
                quantity=10, price=50.0, mrp=60.0,
                last_updated=_now() - timedelta(hours=1),
            )
        )
        # One row priced but with no MRP — counts as priced, not as an offer.
        db.add(
            ShopInventory(
                shop_id=shop.id, product_id=2, product_name="Milk",
                quantity=5, price=20.0, mrp=None,
                last_updated=_now() - timedelta(hours=1),
            )
        )
        db.commit()

        body = client.get("/api/v1/admin/pricing/summary").json()["data"]

        assert body["currency"] == "INR"
        assert body["total_items"] == 2
        # Both rows carry a price; the priced base counts price OR mrp.
        assert body["priced_items"] == 2
        assert body["stats"]["current_price"]["count"] == 2
        assert body["stats"]["mrp"]["count"] == 1
        # Only the Rice row is a real discount (price strictly below mrp).
        assert body["stats"]["offer_price"]["count"] == 1
        # Shares are of the priced base (2), so MRP is 50% and offer is 50%.
        assert body["stats"]["mrp"]["percent"] == 50.0
        assert body["stats"]["offer_price"]["percent"] == 50.0
    finally:
        client.close()
        app.dependency_overrides.clear()


def test_pricing_summary_reports_null_share_when_nothing_is_priced():
    """With no priced rows there is no base to divide by, so shares are null."""
    session_factory = _fresh_db()
    client, _db = _client_with(session_factory)
    try:
        body = client.get("/api/v1/admin/pricing/summary").json()["data"]

        assert body["total_items"] == 0
        assert body["priced_items"] == 0
        assert body["stats"]["mrp"]["percent"] is None
        assert body["stats"]["offer_price"]["percent"] is None
        assert body["price_changes"] == 0
        assert body["last_change_at"] is None
    finally:
        client.close()
        app.dependency_overrides.clear()


def test_pricing_history_returns_changes_joined_to_shop_and_product():
    session_factory = _fresh_db()
    client, db = _client_with(session_factory)
    try:
        owner = User(name="Owner", status="ACTIVE")
        db.add(owner)
        db.commit()
        shop = Shop(name="Shop A", owner_id=owner.id, status="ACTIVE")
        db.add(shop)
        db.commit()
        inv = ShopInventory(
            shop_id=shop.id, product_id=1, product_name="Rice",
            quantity=10, price=50.0, mrp=60.0,
            last_updated=_now() - timedelta(hours=1),
        )
        db.add(inv)
        db.commit()
        db.add(
            InventoryHistory(
                shop_product_id=inv.id,
                change_type="PRICE",
                old_value="65.0",
                new_value="50.0",
                source="POS_SYNC",
                changed_by="System",
                created_at=_now() - timedelta(hours=2),
            )
        )
        db.commit()

        body = client.get("/api/v1/admin/pricing/history").json()["data"]

        assert body["total"] == 1
        row = body["items"][0]
        assert row["shop_name"] == "Shop A"
        assert row["product_name"] == "Rice"
        # History stores prices as strings; they are parsed back to numbers.
        assert row["old_price"] == 65.0
        assert row["new_price"] == 50.0
        assert row["mrp"] == 60.0
        assert row["source"] == "POS_SYNC"
        assert row["changed_by"] == "System"
        assert row["changed_at"] is not None
    finally:
        client.close()
        app.dependency_overrides.clear()


def test_pricing_history_filters_by_shop_and_search():
    session_factory = _fresh_db()
    client, db = _client_with(session_factory)
    try:
        owner = User(name="Owner", status="ACTIVE")
        db.add(owner)
        db.commit()
        shop_a = Shop(name="Alpha Mart", owner_id=owner.id, status="ACTIVE")
        shop_b = Shop(name="Beta Mart", owner_id=owner.id, status="ACTIVE")
        db.add_all([shop_a, shop_b])
        db.commit()
        inv_a = ShopInventory(shop_id=shop_a.id, product_id=1, product_name="Rice", quantity=1)
        inv_b = ShopInventory(shop_id=shop_b.id, product_id=2, product_name="Milk", quantity=1)
        db.add_all([inv_a, inv_b])
        db.commit()
        db.add_all([
            InventoryHistory(
                shop_product_id=inv_a.id, change_type="PRICE", old_value="10", new_value="9",
                source="MANUAL", changed_by="Admin", created_at=_now() - timedelta(hours=1),
            ),
            InventoryHistory(
                shop_product_id=inv_b.id, change_type="PRICE", old_value="20", new_value="18",
                source="POS_SYNC", changed_by="System", created_at=_now() - timedelta(hours=1),
            ),
        ])
        db.commit()

        # Shop filter narrows to a single business's changes.
        by_shop = client.get(
            "/api/v1/admin/pricing/history", params={"shop_id": shop_a.id}
        ).json()["data"]
        assert by_shop["total"] == 1
        assert by_shop["items"][0]["product_name"] == "Rice"

        # Free-text search matches the product name.
        by_search = client.get(
            "/api/v1/admin/pricing/history", params={"search": "Milk"}
        ).json()["data"]
        assert by_search["total"] == 1
        assert by_search["items"][0]["shop_name"] == "Beta Mart"
    finally:
        client.close()
        app.dependency_overrides.clear()


def test_pricing_history_reports_non_numeric_change_as_null():
    """A history value that is not a price is null, never a fabricated number."""
    session_factory = _fresh_db()
    client, db = _client_with(session_factory)
    try:
        owner = User(name="Owner", status="ACTIVE")
        db.add(owner)
        db.commit()
        shop = Shop(name="Shop A", owner_id=owner.id, status="ACTIVE")
        db.add(shop)
        db.commit()
        inv = ShopInventory(shop_id=shop.id, product_id=1, product_name="Rice", quantity=1)
        db.add(inv)
        db.commit()
        db.add(
            InventoryHistory(
                shop_product_id=inv.id, change_type="PRICE",
                old_value="IN_STOCK", new_value="50.0",
                source="MANUAL", changed_by="Admin", created_at=_now() - timedelta(hours=1),
            )
        )
        db.commit()

        row = client.get("/api/v1/admin/pricing/history").json()["data"]["items"][0]
        assert row["old_price"] is None
        assert row["new_price"] == 50.0
    finally:
        client.close()
        app.dependency_overrides.clear()


def test_pricing_endpoints_require_authentication():
    session_factory = _fresh_db()
    client, _db = _client_with(session_factory)
    try:
        # No bearer/cookie -> 401, so the console redirects to login.
        anonymous = TestClient(app)
        assert anonymous.get("/api/v1/admin/pricing/summary").status_code == 401
        assert anonymous.get("/api/v1/admin/pricing/history").status_code == 401
        anonymous.close()
    finally:
        client.close()
        app.dependency_overrides.clear()
