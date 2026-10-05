"""The price data-entry spec on the backend update door.

The spec's validation list:

    valid numeric amount / non-negative amount / backend rules

Creation-time validation on every route refuses negative prices and MRP under
price. But the PRICE UPDATE door (`update_product`, the PATCH behind the
shopkeeper's Update Price screen) checked only the MRP-vs-price relationship —
a negative price, or a non-numeric string that `float()` chokes on, reached the
column unvalidated or crashed mid-request.

These pin the same three rules on the update door.
"""

import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from app.core.exceptions import ValidationError
from app.models.base import Base
from app.models.product import (
    Inventory,
    InventoryMovement,
    PriceHistory,
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
    PriceHistory.__table__,
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
    shopkeeper_service.create_product(access, db, user, data)
    db.commit()


def _listing(db, shop: Shop) -> ShopProduct:
    return db.query(ShopProduct).filter(ShopProduct.shop_id == shop.id).one()


class TestTheUpdateDoorHoldsTheSameThreeRules:
    """Spec: valid numeric amount / non-negative amount / backend rules."""

    def test_a_negative_price_is_refused(self, db):
        user = _user(db)
        shop = _shop(db)
        _create(db, _access(shop), user)
        listing = _listing(db, shop)

        with pytest.raises(ValidationError):
            shopkeeper_service.update_product(
                _access(shop), db, user, listing.id, {"price": -5.0}
            )
        db.rollback()
        assert float(_listing(db, shop).price) == 10.0

    def test_a_non_numeric_price_is_refused(self, db):
        user = _user(db)
        shop = _shop(db)
        _create(db, _access(shop), user)
        listing = _listing(db, shop)

        with pytest.raises(ValidationError):
            shopkeeper_service.update_product(
                _access(shop), db, user, listing.id, {"price": "twelve rupees"}
            )
        db.rollback()
        assert float(_listing(db, shop).price) == 10.0

    def test_a_negative_mrp_is_refused(self, db):
        user = _user(db)
        shop = _shop(db)
        _create(db, _access(shop), user)
        listing = _listing(db, shop)

        with pytest.raises(ValidationError):
            shopkeeper_service.update_product(
                _access(shop), db, user, listing.id, {"mrp": -1.0}
            )
        db.rollback()
        assert _listing(db, shop).mrp is None

    def test_mrp_under_price_is_still_refused(self, db):
        """The one rule this door already had — pinned so the new guards do
        not accidentally weaken it."""
        user = _user(db)
        shop = _shop(db)
        _create(db, _access(shop), user, mrp=15.0)
        listing = _listing(db, shop)

        with pytest.raises(ValidationError):
            shopkeeper_service.update_product(
                _access(shop), db, user, listing.id, {"price": 20.0}
            )

    def test_a_good_price_is_applied_and_history_is_kept(self, db):
        user = _user(db)
        shop = _shop(db)
        _create(db, _access(shop), user, mrp=15.0)
        listing = _listing(db, shop)

        shopkeeper_service.update_product(
            _access(shop), db, user, listing.id, {"price": 12.0}
        )
        db.commit()

        assert float(_listing(db, shop).price) == 12.0
        history = (
            db.query(PriceHistory)
            .filter(PriceHistory.shop_product_id == listing.id)
            .all()
        )
        assert [float(h.new_price) for h in history] == [12.0]


if __name__ == "__main__":
    raise SystemExit(pytest.main([__file__, "-v"]))