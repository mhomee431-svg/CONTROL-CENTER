"""The product LIST path, measured rather than asserted.

`list_products` runs on the screen a shopkeeper opens most, and it walks the same
relations for every row. Left lazy, each product costs ~5 queries — five products
is 25, five hundred is 2,500, and at several hundred concurrent shopskeepers the
database queue IS the product list.

The tests here COUNT statements, so a regression back to per-row loading fails
with a number rather than a feeling.
"""

import pytest
from sqlalchemy import create_engine, event
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from app.models.base import Base
from app.models.product import (
    Inventory,
    ProductImage,
    ProductMaster,
    ShopProduct,
)
from app.models.shop import Shop, ShopOwner
from app.models.user import User
from app.services import shopkeeper_service
from app.services.shopkeeper_service import MAX_PRODUCTS_PER_RESPONSE
from tests.geo_compat import strip_geo_columns

TABLES = [
    User.__table__,
    Shop.__table__,
    ShopOwner.__table__,
    ProductMaster.__table__,
    ProductImage.__table__,
    ShopProduct.__table__,
    Inventory.__table__,
]


@pytest.fixture()
def db():
    # `shops.location` is a real geography(POINT,4326), which SQLite cannot
    # create. The suite already has one helper for exactly this, so it is used
    # rather than a second copy that could drift from it.
    strip_geo_columns()
    engine = create_engine(
        "sqlite://",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    Base.metadata.create_all(engine, tables=TABLES)
    session = sessionmaker(bind=engine)()
    yield session
    session.close()
    engine.dispose()


@pytest.fixture()
def counted(db):
    """Counts the SQL statements a block of work issues."""
    counter = {"n": 0}

    def _before(conn, cursor, statement, parameters, context, executemany):
        counter["n"] += 1

    event.listen(db.get_bind(), "before_cursor_execute", _before)
    try:
        yield counter
    finally:
        event.remove(db.get_bind(), "before_cursor_execute", _before)


def _shop(db) -> Shop:
    shop = Shop(
        name="Corner Store",
        description="d",
        status="ACTIVE",
        latitude=25.59,
        longitude=85.13,
    )
    db.add(shop)
    db.flush()
    return shop


def _seed(db, shop, count, start=0):
    for i in range(start, start + count):
        master = ProductMaster(
            name=f"Product {i}", slug=f"product-{i}", base_unit="pc"
        )
        db.add(master)
        db.flush()
        sp = ShopProduct(
            shop_id=shop.id,
            product_master_id=master.id,
            sku=f"SKU-{i}",
            price=10.0,
            mrp=20.0,
        )
        db.add(sp)
        db.flush()
        db.add(Inventory(shop_product_id=sp.id, quantity=5))
    db.commit()


class _Access:
    """The minimum `ShopAccess` shape `list_products` reads."""

    def __init__(self, shop):
        self.shop = shop

    def require(self, *_a, **_k):
        return None


class TestTheProductListQueryCount:
    """The number that decides whether 500 shops can open at once."""

    def test_query_count_is_flat_as_the_catalogue_grows(self, db, counted):
        """Ten products and a hundred must cost the SAME number of queries.

        This is the property that matters. A constant query count is what lets a
        shop scale; "linear but small" is still a hang at enough rows.
        """
        shop = _shop(db)
        _seed(db, shop, 10, start=0)
        counted["n"] = 0
        shopkeeper_service.list_products(_Access(shop), db)
        for_ten = counted["n"]

        _seed(db, shop, 90, start=100)
        counted["n"] = 0
        shopkeeper_service.list_products(_Access(shop), db)
        for_hundred = counted["n"]

        assert for_hundred == for_ten, (
            f"10 products cost {for_ten} queries but 100 cost {for_hundred} — "
            "something is still loading per row"
        )

    def test_a_hundred_products_stay_under_a_dozen_queries(self, db, counted):
        """A generous ceiling, and one that failed before the eager-loading fix.

        Lazy relations made this roughly 500 statements.
        """
        shop = _shop(db)
        _seed(db, shop, 100)
        counted["n"] = 0
        products = shopkeeper_service.list_products(_Access(shop), db)
        assert len(products) == 100
        assert counted["n"] < 12, f"{counted['n']} queries for 100 products"

    def test_the_count_does_not_grow_between_twenty_and_two_hundred(self, db, counted):
        """A second, independent statement of the same property."""
        shop = _shop(db)
        _seed(db, shop, 20)
        counted["n"] = 0
        shopkeeper_service.list_products(_Access(shop), db)
        small = counted["n"]

        _seed(db, shop, 180, start=500)
        counted["n"] = 0
        shopkeeper_service.list_products(_Access(shop), db, limit=200)
        large = counted["n"]

        assert large <= small + 1, f"{small} queries at 20 rows, {large} at 200"


class TestTheProductListIsBounded:
    def test_a_huge_catalogue_cannot_be_returned_in_one_go(self, db):
        """One runaway shop must not be able to load every row into every page
        view — that is what starves the pool for everyone else."""
        shop = _shop(db)
        _seed(db, shop, MAX_PRODUCTS_PER_RESPONSE + 5)
        products = shopkeeper_service.list_products(_Access(shop), db)
        assert len(products) == MAX_PRODUCTS_PER_RESPONSE

    def test_truncation_is_reported_rather_than_looking_complete(self, db):
        shop = _shop(db)
        _seed(db, shop, MAX_PRODUCTS_PER_RESPONSE + 5)
        products = shopkeeper_service.list_products(_Access(shop), db)
        assert products[-1].get("_truncated") is True

    def test_a_small_catalogue_is_not_marked_truncated(self, db):
        shop = _shop(db)
        _seed(db, shop, 3)
        products = shopkeeper_service.list_products(_Access(shop), db)
        assert not any(p.get("_truncated") for p in products)

    def test_a_caller_cannot_ask_for_more_than_the_cap(self, db):
        shop = _shop(db)
        # More than the cap must actually exist, otherwise this proves nothing.
        _seed(db, shop, MAX_PRODUCTS_PER_RESPONSE + 10)
        products = shopkeeper_service.list_products(
            _Access(shop), db, limit=100_000
        )
        assert len(products) == MAX_PRODUCTS_PER_RESPONSE

    def test_a_caller_can_ask_for_a_smaller_page(self, db):
        shop = _shop(db)
        _seed(db, shop, 30)
        products = shopkeeper_service.list_products(_Access(shop), db, limit=5)
        assert len(products) == 5

    def test_offset_pages_through_the_catalogue(self, db):
        shop = _shop(db)
        _seed(db, shop, 10)
        first = shopkeeper_service.list_products(_Access(shop), db, limit=4)
        second = shopkeeper_service.list_products(
            _Access(shop), db, limit=4, offset=4
        )
        assert {p["id"] for p in first} & {p["id"] for p in second} == set()


if __name__ == "__main__":
    raise SystemExit(pytest.main([__file__, "-v"]))
