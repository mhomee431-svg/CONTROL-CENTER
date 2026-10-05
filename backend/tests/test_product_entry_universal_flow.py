"""The four entry routes must land on one product-management model.

The spec draws four flows — manual, barcode, Excel/CSV, POS — and closes with
"All four methods must converge on the same backend domain model."

The steps shared by all four are identical: resolve-or-create the master, attach
it to the shop, set price, set inventory. This pins those steps so no route can
quietly reintroduce its own version.

The fixture shape is copied from test_master_shop_separation.py so the two files
cannot drift apart on setup.
"""

import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from app.models.base import Base
from app.models.pos import (
    POSDevice,
    POSIntegration,
    POSProductMapping,
    POSSyncJob,
    POSSyncLog,
)
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
from app.services import product_convergence

TABLES = [
    POSIntegration.__table__,
    POSDevice.__table__,
    POSSyncJob.__table__,
    POSSyncLog.__table__,
    POSProductMapping.__table__,
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

ALL_SOURCES = [
    InventorySource.MANUAL,
    InventorySource.BARCODE_SCAN,
    InventorySource.EXCEL_UPLOAD,
    InventorySource.POS_INTEGRATION,
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


def _master(db, name="Parle-G 250g") -> ProductMaster:
    master = ProductMaster(name=name, slug=name.lower().replace(" ", "-"))
    db.add(master)
    db.flush()
    return master


class TestAttachIsIdempotent:
    """The step all four routes share: attach a master to a shop."""

    def test_first_attach_creates_the_listing(self, db):
        master = _master(db)
        sp = product_convergence.attach_product_to_shop(
            db, shop_id=10, master=master, price=10.0
        )
        db.flush()
        assert sp.id is not None
        assert db.query(ShopProduct).count() == 1

    def test_second_attach_returns_the_same_listing(self, db):
        """Re-importing or re-syncing must not double the listing."""
        master = _master(db)
        first = product_convergence.attach_product_to_shop(
            db, shop_id=10, master=master, price=10.0
        )
        second = product_convergence.attach_product_to_shop(
            db, shop_id=10, master=master, price=11.0
        )
        db.flush()
        assert first.id == second.id
        assert db.query(ShopProduct).count() == 1

    def test_another_shop_gets_its_own_listing(self, db):
        """Shared master, per-shop listing — the spec's whole point."""
        master = _master(db)
        product_convergence.attach_product_to_shop(db, shop_id=10, master=master)
        product_convergence.attach_product_to_shop(db, shop_id=20, master=master)
        db.flush()
        assert db.query(ShopProduct).count() == 2
        assert db.query(ProductMaster).count() == 1

    def test_a_different_variant_is_a_different_listing(self, db):
        master = _master(db)
        small = ProductVariant(product_master_id=master.id, sku="S", name="250g")
        db.add(small)
        db.flush()
        product_convergence.attach_product_to_shop(db, shop_id=10, master=master)
        product_convergence.attach_product_to_shop(
            db, shop_id=10, master=master, variant=small
        )
        db.flush()
        assert db.query(ShopProduct).count() == 2

    def test_a_withdrawn_listing_does_not_block_a_fresh_one(self, db):
        """Soft-deleted rows must not resurrect, but must not block either."""
        master = _master(db)
        first = product_convergence.attach_product_to_shop(
            db, shop_id=10, master=master
        )
        first.is_deleted = True
        db.flush()
        second = product_convergence.attach_product_to_shop(
            db, shop_id=10, master=master
        )
        db.flush()
        assert second.id != first.id


class TestEverySourceLeavesTheSameAuditTrail:
    """One inventory row shape for all four sources is the point.

    POS used to write only `source` — no movement, no freshness — so a POS stock
    change was invisible to the audit trail manual, barcode and Excel all fed.
    """

    @pytest.mark.parametrize("source", ALL_SOURCES)
    def test_source_is_recorded(self, db, source):
        master = _master(db)
        sp = product_convergence.attach_product_to_shop(
            db, shop_id=10, master=master, source=source
        )
        inv = product_convergence.set_inventory(db, sp, quantity=7, source=source)
        db.flush()
        assert inv.last_updated_source == source

    @pytest.mark.parametrize("source", ALL_SOURCES)
    def test_freshness_is_recorded(self, db, source):
        master = _master(db)
        sp = product_convergence.attach_product_to_shop(
            db, shop_id=10, master=master, source=source
        )
        inv = product_convergence.set_inventory(db, sp, quantity=7, source=source)
        db.flush()
        assert inv.freshness_status is not None
        assert inv.freshness_checked_at is not None

    @pytest.mark.parametrize("source", ALL_SOURCES)
    def test_a_movement_is_recorded(self, db, source):
        master = _master(db)
        sp = product_convergence.attach_product_to_shop(
            db, shop_id=10, master=master, source=source
        )
        inv = product_convergence.set_inventory(db, sp, quantity=7, source=source)
        db.flush()
        movements = (
            db.query(InventoryMovement)
            .filter(InventoryMovement.inventory_id == inv.id)
            .all()
        )
        assert len(movements) == 1
        assert movements[0].quantity_after == 7
        assert movements[0].source == source


class TestInventoryIsAbsoluteNotADelta:
    """Re-running an import must land on the same number, not double it."""

    def test_setting_the_same_quantity_twice_changes_nothing(self, db):
        master = _master(db)
        sp = product_convergence.attach_product_to_shop(db, shop_id=10, master=master)
        product_convergence.set_inventory(db, sp, quantity=10)
        inv = product_convergence.set_inventory(db, sp, quantity=10)
        db.flush()
        assert inv.quantity == 10

    def test_a_second_set_replaces_rather_than_adds(self, db):
        master = _master(db)
        sp = product_convergence.attach_product_to_shop(db, shop_id=10, master=master)
        product_convergence.set_inventory(db, sp, quantity=10)
        inv = product_convergence.set_inventory(db, sp, quantity=4)
        db.flush()
        assert inv.quantity == 4

    def test_a_changed_quantity_leaves_an_adjustment(self, db):
        master = _master(db)
        sp = product_convergence.attach_product_to_shop(db, shop_id=10, master=master)
        inv = product_convergence.set_inventory(db, sp, quantity=10)
        product_convergence.set_inventory(db, sp, quantity=6)
        db.flush()
        movements = (
            db.query(InventoryMovement)
            .filter(InventoryMovement.inventory_id == inv.id)
            .order_by(InventoryMovement.id)
            .all()
        )
        assert [m.quantity_after for m in movements] == [10, 6]
        assert movements[-1].quantity_change == -4

    def test_a_negative_quantity_is_clamped(self, db):
        """Stock cannot go below zero just because a feed said so."""
        master = _master(db)
        sp = product_convergence.attach_product_to_shop(db, shop_id=10, master=master)
        inv = product_convergence.set_inventory(db, sp, quantity=-3)
        db.flush()
        assert inv.quantity == 0

    def test_zero_stock_is_not_available(self, db):
        master = _master(db)
        sp = product_convergence.attach_product_to_shop(db, shop_id=10, master=master)
        inv = product_convergence.set_inventory(db, sp, quantity=0)
        db.flush()
        assert inv.is_available is False


class TestPriceStep:
    def test_a_price_is_applied_and_stamped(self, db):
        master = _master(db)
        sp = product_convergence.attach_product_to_shop(db, shop_id=10, master=master)
        product_convergence.set_price(db, sp, price=25.0, mrp=30.0)
        db.flush()
        assert float(sp.price) == 25.0
        assert float(sp.mrp) == 30.0
        assert sp.last_price_update is not None

    def test_a_missing_price_leaves_the_existing_one(self, db):
        """A feed without a price must not wipe the shop's price."""
        master = _master(db)
        sp = product_convergence.attach_product_to_shop(
            db, shop_id=10, master=master, price=42.0
        )
        product_convergence.set_price(db, sp, mrp=50.0)
        db.flush()
        assert float(sp.price) == 42.0
        assert float(sp.mrp) == 50.0


class TestTwoDoorsOneProduct:
    """The spec's real requirement, end to end through two of the routes."""

    def test_manual_then_pos_leaves_one_of_everything(self, db):
        from app.services.pos_integration.base import POSProductRecord
        from app.services.pos_sync_service import _apply_record
        from app.services.shopkeeper_service import ShopAccess, create_product

        user = User(email="owner@example.com", is_active=True)
        db.add(user)
        shop = Shop(
            name="Kirana", description="d", status="ACTIVE",
            latitude=1.0, longitude=2.0,
        )
        db.add(shop)
        db.flush()

        create_product(
            ShopAccess(
                shop=shop, role_name="owner", is_owner=True,
                permissions={"product:create"},
            ),
            db,
            user,
            {"name": "Amul Butter 500g", "price": 55.0, "quantity": 12},
        )
        db.flush()

        integration = POSIntegration(
            shop_id=shop.id,
            provider_name="Generic Till",
            integration_type="generic",
            auto_create_products=True,
        )
        db.add(integration)
        db.flush()
        job = POSSyncJob(
            shop_id=shop.id, integration_id=None,
            sync_type="FULL", trigger="TEST", status="RUNNING",
        )
        db.add(job)
        db.flush()

        _apply_record(
            db, integration, job,
            POSProductRecord(
                pos_product_code="P-AMUL",
                name="Amul Butter 500g",
                sku=None, barcode=None,
                price=55.0, quantity=12,
            ),
            "fp-amul",
        )
        db.flush()

        assert db.query(ProductMaster).count() == 1
        assert db.query(ShopProduct).count() == 1
        assert db.query(Inventory).count() == 1

    def test_pos_inventory_carries_the_same_provenance(self, db):
        """The POS door must leave what manual, barcode and Excel leave."""
        from app.services.pos_integration.base import POSProductRecord
        from app.services.pos_sync_service import _apply_record

        integration = POSIntegration(
            shop_id=10,
            provider_name="Generic Till",
            integration_type="generic",
            auto_create_products=True,
        )
        db.add(integration)
        db.flush()
        job = POSSyncJob(
            shop_id=10, integration_id=None,
            sync_type="FULL", trigger="TEST", status="RUNNING",
        )
        db.add(job)
        db.flush()

        _apply_record(
            db, integration, job,
            POSProductRecord(
                pos_product_code="P-SHAPE",
                name="Parle-G 250g",
                sku=None, barcode=None,
                price=10.0, quantity=5,
            ),
            "fp-shape",
        )
        db.flush()

        inv = db.query(Inventory).one()
        assert inv.last_updated_source == InventorySource.POS_INTEGRATION
        assert inv.freshness_status is not None
        movement = (
            db.query(InventoryMovement)
            .filter(InventoryMovement.inventory_id == inv.id)
            .one()
        )
        assert movement.source == InventorySource.POS_INTEGRATION


if __name__ == "__main__":
    raise SystemExit(pytest.main([__file__, "-v"]))