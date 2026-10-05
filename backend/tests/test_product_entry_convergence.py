"""All four product-entry routes must converge on one domain model.

The spec is explicit: "All four methods must converge on the same backend domain
model." These tests hold the part that is easy to get wrong silently — the
DEDUPE rule. A product that arrives by hand and then by POS import, or by
barcode and then by hand, must end up as ONE `ProductMaster` with ONE
`ShopProduct` for that shop.

Divergence here is invisible in a single test and destructive in production: the
shop's catalogue quietly splits in two, and the same item shows two prices.
"""

import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from app.core.exceptions import ConflictError
from app.models.base import Base
from app.models.pos import POSIntegration
from app.models.product import (
    Inventory,
    InventoryMovement,
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
from app.services import pos_sync_service, shopkeeper_service
from app.services.shopkeeper_service import find_matching_master

TABLES = [
    POSIntegration.__table__,
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


def _shop(db) -> Shop:
    shop = Shop(
        name="Corner", description="d", status="ACTIVE", latitude=1.0, longitude=2.0
    )
    db.add(shop)
    db.flush()
    return shop


def _master_count(db) -> int:
    return db.query(ProductMaster).count()


class TestTheDedupeRuleIsShared:
    """`find_matching_master` is the one rule, and every route must call it."""

    def test_a_hand_entered_product_is_found_by_name(self, db):
        db.add(ProductMaster(name="Parle-G 250g", slug="parle-g"))
        db.commit()
        assert find_matching_master(db, "parle-g 250g") is not None

    def test_the_match_is_normalised(self, db):
        """Case and spacing must not create a second copy."""
        db.add(ProductMaster(name="Parle-G 250g", slug="parle-g"))
        db.commit()
class TestPosSyncConvergesOnTheSameMaster:
    """The route that actually diverged.

    POS matched only on barcode/SKU. A product the shopkeeper added by hand has
    no identifier for the POS barcode yet, so POS sync created a SECOND master
    for it — two masters, two listings, one real product.
    """

    def _record(self, **kw):
        from app.services.pos_integration.base import POSProductRecord

        return POSProductRecord(
            pos_product_code=kw.get("code", "P-1"),
            name=kw.get("name", "Parle-G 250g"),
            sku=kw.get("sku"),
            barcode=kw.get("barcode"),
            price=kw.get("price", 10.0),
            quantity=kw.get("quantity", 5),
        )

    def _integration(self, db, shop):
        integration = POSIntegration(
            shop_id=shop.id,
            provider_name="Generic Till",
            integration_type="generic",
        )
        db.add(integration)
        db.flush()
        return integration

    def test_a_hand_entered_product_is_not_duplicated_by_pos(self, db):
        shop = _shop(db)
        db.add(ProductMaster(name="Parle-G 250g", slug="parle-g"))
        db.commit()
        before = _master_count(db)

        integration = self._integration(db, shop)
        master, _variant = pos_sync_service._create_product(
            db, integration, self._record()
        )
        db.commit()

        assert master.name == "Parle-G 250g"
        assert _master_count(db) == before, (
            "POS created a second master for a product already in the catalogue"
        )

    def test_the_variant_lands_under_the_existing_master(self, db):
        shop = _shop(db)
        db.add(ProductMaster(name="Parle-G 250g", slug="parle-g"))
        db.commit()
        integration = self._integration(db, shop)

        master, variant = pos_sync_service._create_product(
            db, integration, self._record(sku="POS-SKU-1")
        )
        db.commit()

        assert variant.product_master_id == master.id

    def test_a_genuinely_new_product_still_creates_a_master(self, db):
        """The convergence must not collapse genuinely different products."""
        shop = _shop(db)
        integration = self._integration(db, shop)
        before = _master_count(db)

        master, _ = pos_sync_service._create_product(
            db, integration, self._record(name="Amul Butter 500g", code="P-9")
        )
        db.commit()

        assert master.name == "Amul Butter 500g"
        assert _master_count(db) == before + 1

    def test_two_different_products_do_not_collide(self, db):
        shop = _shop(db)
        integration = self._integration(db, shop)
        first, _ = pos_sync_service._create_product(
            db, integration, self._record(name="Amul Butter", code="A")
        )
        second, _ = pos_sync_service._create_product(
            db, integration, self._record(name="Amul Cheese", code="B")
        )
        db.commit()
        assert first.id != second.id

    def test_the_same_product_twice_from_pos_yields_one_master(self, db):
        """Two sync runs of the same till item must not double the catalogue."""
        shop = _shop(db)
        integration = self._integration(db, shop)
        before = _master_count(db)

        pos_sync_service._create_product(db, integration, self._record(sku="S1"))
        db.commit()
        pos_sync_service._create_product(db, integration, self._record(sku="S1"))
        db.commit()

        assert _master_count(db) == before + 1


class TestTheDomainModelIsTheSameShape:
    """Every route produces the same three rows with the same invariants."""

    def test_a_listing_is_master_plus_shop_product_plus_inventory(self, db):
        shop = _shop(db)
        user = _user(db)
        access = shopkeeper_service.ShopAccess(
            shop=shop,
            role_name="owner",
            is_owner=True,
            permissions={"product:create", "product:update"},
        )

        shopkeeper_service.create_product(
            access,
            db,
            user,
            {
                "name": "Parle-G 250g",
                "price": 10.0,
                "quantity": 5,
                "low_stock_threshold": 3,
            },
        )
        db.commit()

        sp = db.query(ShopProduct).one()
        inv = db.query(Inventory).one()
        assert sp.product_master_id is not None
        assert inv.shop_product_id == sp.id
        # The invariants every other route must reproduce.
        assert inv.available_quantity == inv.quantity - inv.reserved_quantity
        assert inv.low_stock_threshold == 3
        assert sp.stock_status is not None
        assert sp.source is not None

    def test_the_same_product_twice_by_hand_gives_one_listing(self, db):
        shop = _shop(db)
        user = _user(db)
        access = shopkeeper_service.ShopAccess(
            shop=shop,
            role_name="owner",
            is_owner=True,
            permissions={"product:create", "product:update"},
        )

        shopkeeper_service.create_product(
            access, db, user, {"name": "Parle-G 250g", "price": 10.0, "quantity": 5}
        )
        db.commit()

        with pytest.raises(ConflictError):
            shopkeeper_service.create_product(
                access, db, user, {"name": "Parle-G 250g", "price": 10.0, "quantity": 5}
            )
        db.rollback()

        assert db.query(ShopProduct).count() == 1


if __name__ == "__main__":
    raise SystemExit(pytest.main([__file__, "-v"]))
