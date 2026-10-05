"""The inventory data-entry flow, end to end through the manual door.

The spec's flow:

    Product -> Current Stock -> Enter New Quantity -> Validate -> Save
      -> Backend Confirmation -> Updated Inventory

and its display contract: "Show: Last Updated, Source, Freshness," with
"Never report success before backend confirmation."

Coverage already held elsewhere pins pieces of this (the confirmation panel
renders server truth in Flutter; the update-stock screen pins source /
freshness / last-updated on one line). What those cannot pin is the backend
half: that an absolute quantity update stamps source + freshness + a movement
on the canonical inventory row. Two shops found divergent rows for exactly this
reason last time this was audited, so this file pins the manual update path to
the same provenance every other route writes.
"""

import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from app.models.base import Base
from app.models.product import (
    Inventory,
    InventoryMovement,
    InventorySource,
    ProductAttribute,
    ProductAttributeValue,
    ProductIdentifier,
    ProductImage,
    ProductMaster,
    ProductVariant,
    ShopProduct,
)
from app.models.shop import Shop, ShopOwner
from app.models.subscription import Subscription, SubscriptionPlan
from app.models.user import User
from app.services import shopkeeper_service

TABLES = [
    SubscriptionPlan.__table__,
    Subscription.__table__,
    User.__table__,
    Shop.__table__,
    ShopOwner.__table__,
    ProductMaster.__table__,
    ProductImage.__table__,
    ProductAttribute.__table__,
    ProductAttributeValue.__table__,
    ProductIdentifier.__table__,
    ProductVariant.__table__,
    ShopProduct.__table__,
    Inventory.__table__,
    InventoryMovement.__table__,
]


@pytest.fixture()
def db():
    from tests.geo_compat import strip_geo_columns

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


def _user(db) -> User:
    user = User(email="owner@example.com", is_active=True)
    db.add(user)
    db.flush()
    return user


def _shop(db, name="Kirana") -> Shop:
    shop = Shop(
        name=name, description="d", status="ACTIVE", latitude=1.0, longitude=2.0
    )
    db.add(shop)
    db.flush()
    return shop


def _access(shop: Shop):
    return shopkeeper_service.ShopAccess(
        shop=shop,
        role_name="owner",
        is_owner=True,
        permissions={"product:create", "product:update"},
    )


def _create(db, access, user, **overrides):
    data = {"name": "Parle-G 250g", "price": 10.0, "quantity": 5}
    data.update(overrides)
    payload = shopkeeper_service.create_product(access, db, user, data)
    db.commit()
    return payload


def _listing(db, shop: Shop) -> ShopProduct:
    return db.query(ShopProduct).filter(ShopProduct.shop_id == shop.id).one()


def _inventory(db, listing: ShopProduct) -> Inventory:
    return (
        db.query(Inventory).filter(Inventory.shop_product_id == listing.id).one()
    )


class TestAnAbsoluteQuantityUpdateCarriesTheSameProvenance:
    """Enter New Quantity -> Validate -> Save leaves the same row shape."""

    def test_the_update_stamps_source_and_freshness(self, db):
        user = _user(db)
        shop = _shop(db)
        _create(db, _access(shop), user)

        shopkeeper_service.update_product(
            _access(shop), db, user, _listing(db, shop).id, {"quantity": 12}
        )
        db.commit()

        inv = _inventory(db, _listing(db, shop))
        assert inv.quantity == 12
        assert inv.last_updated_source == InventorySource.MANUAL
        assert inv.freshness_status is not None
        assert inv.freshness_checked_at is not None

    def test_the_update_leaves_a_movement(self, db):
        user = _user(db)
        shop = _shop(db)
        _create(db, _access(shop), user)

        shopkeeper_service.update_product(
            _access(shop), db, user, _listing(db, shop).id, {"quantity": 12}
        )
        db.commit()

        movements = (
            db.query(InventoryMovement)
            .filter(
                InventoryMovement.inventory_id
                == _inventory(db, _listing(db, shop)).id
            )
            .order_by(InventoryMovement.id)
            .all()
        )
        assert [m.quantity_after for m in movements] == [5, 12]
        assert movements[-1].source == InventorySource.MANUAL

    def test_unchanged_quantity_writes_no_new_movement(self, db):
        """Re-saving 5 as 5 is not a stock event; the trail must stay quiet."""
        user = _user(db)
        shop = _shop(db)
        _create(db, _access(shop), user)

        before = db.query(InventoryMovement).count()
        shopkeeper_service.update_product(
            _access(shop), db, user, _listing(db, shop).id, {"quantity": 5}
        )
        db.commit()

        assert db.query(InventoryMovement).count() == before

    def test_zero_stock_marks_the_listing_unavailable(self, db):
        """Availability follows stock: the "Availability" bullet is derived,
        not asked twice."""
        user = _user(db)
        shop = _shop(db)
        _create(db, _access(shop), user)

        shopkeeper_service.update_product(
            _access(shop), db, user, _listing(db, shop).id, {"quantity": 0}
        )
        db.commit()

        listing = _listing(db, shop)
        assert _inventory(db, listing).is_available is False
        assert listing.is_available is False


if __name__ == "__main__":
    raise SystemExit(pytest.main([__file__, "-v"]))