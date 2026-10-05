"""POS price entry must obey the same rules as every other entry route.

The spec puts price validation under PRICE DATA ENTRY: a valid numeric amount,
a non-negative amount, and the backend rules on top. Manual, barcode and Excel
each enforce "MRP cannot be lower than selling price". POS did not — it called
`float(record.price)` straight into the column. A till feed carrying `-5` wrote
a negative price onto `shop_products.price`, a state the other three paths
refuse outright.

So this is a parity gap, not a new feature: the same rule, refused the same way,
on the fourth door.
"""

import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

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
    PriceHistory,
    ProductIdentifier,
    ProductMaster,
    ProductVariant,
    ShopProduct,
)
from app.services import pos_sync_service
from app.services.pos_integration.base import POSProductRecord

SHOP_ID = 10

TABLES = [
    POSIntegration.__table__,
    POSDevice.__table__,
    POSSyncJob.__table__,
    POSSyncLog.__table__,
    POSProductMapping.__table__,
    ProductMaster.__table__,
    ProductVariant.__table__,
    ProductIdentifier.__table__,
    ShopProduct.__table__,
    Inventory.__table__,
    InventoryMovement.__table__,
    PriceHistory.__table__,
]


@pytest.fixture()
def db():
    engine = create_engine("sqlite://")
    Base.metadata.create_all(engine, tables=TABLES)
    session = sessionmaker(bind=engine)()
    yield session
    session.close()
    engine.dispose()


def _integration(db):
    integration = POSIntegration(
        shop_id=SHOP_ID,
        provider_name="Generic Till",
        integration_type="generic",
        auto_create_products=True,
    )
    db.add(integration)
    db.flush()
    return integration


def _job(db):
    job = POSSyncJob(
        shop_id=SHOP_ID,
        integration_id=None,
        sync_type="FULL",
        trigger="TEST",
        status="RUNNING",
    )
    db.add(job)
    db.flush()
    return job


def _record(**kw):
    return POSProductRecord(
        pos_product_code=kw.get("code", "P-1"),
        name=kw.get("name", "Parle-G 250g"),
        sku=kw.get("sku"),
        barcode=kw.get("barcode"),
        price=kw.get("price", 10.0),
        mrp=kw.get("mrp"),
        quantity=kw.get("quantity", 5),
    )


class TestRefusesAnUnusableAmount:
    """Spec: "valid numeric amount", "non-negative amount"."""

    def test_a_negative_price_is_refused(self):
        with pytest.raises(pos_sync_service.ItemSyncError) as exc:
            pos_sync_service._validated_price(-5)
        assert "negative" in str(exc.value)

    def test_a_non_numeric_price_is_refused(self):
        with pytest.raises(pos_sync_service.ItemSyncError) as exc:
            pos_sync_service._validated_price("twelve rupees")
        assert "not a valid number" in str(exc.value)

    def test_a_negative_mrp_is_refused(self):
        with pytest.raises(pos_sync_service.ItemSyncError):
            pos_sync_service._validated_mrp(-1, 10.0)

    def test_a_non_numeric_mrp_is_refused(self):
        with pytest.raises(pos_sync_service.ItemSyncError):
            pos_sync_service._validated_mrp("unknown", 10.0)


class TestHoldsTheBackendRuleOnMrp:
    """Spec: MRP cannot sit below the selling price, on any route."""

    def test_mrp_below_price_is_refused(self):
        with pytest.raises(pos_sync_service.ItemSyncError) as exc:
            pos_sync_service._validated_mrp(5.0, 10.0)
        assert "MRP cannot be lower" in str(exc.value)

    def test_mrp_equal_to_price_is_allowed(self):
        """A flat MRP is not an error; only MRP *below* price is."""
        assert pos_sync_service._validated_mrp(10.0, 10.0) == 10.0

    def test_absent_mrp_is_not_an_error(self):
        assert pos_sync_service._validated_mrp(None, 10.0) is None


class TestAValidAmountPasses:
    def test_a_normal_price_survives(self):
        assert pos_sync_service._validated_price(24.5) == 24.5

    def test_zero_price_is_allowed(self):
        """Free/give-away lines exist; only negative is meaningless."""
        assert pos_sync_service._validated_price(0) == 0.0


class TestTheSyncItselfRefusesBadPrices:
    """The helpers are only worth having if the sync actually calls them."""

    def test_a_negative_price_does_not_reach_the_listing(self, db):
        integration = _integration(db)
        with pytest.raises(pos_sync_service.ItemSyncError):
            pos_sync_service._apply_record(
                db, integration, _job(db), _record(code="BAD", price=-5.0), "fp-bad"
            )
        db.rollback()
        assert db.query(ShopProduct).count() == 0

    def test_a_good_price_is_stored(self, db):
        integration = _integration(db)
        pos_sync_service._apply_record(
            db, integration, _job(db), _record(code="OK", price=42.0, mrp=50.0), "fp-ok"
        )
        db.flush()
        listing = db.query(ShopProduct).one()
        assert float(listing.price) == 42.0
        assert float(listing.mrp) == 50.0

    def test_mrp_below_price_does_not_reach_the_listing(self, db):
        integration = _integration(db)
        with pytest.raises(pos_sync_service.ItemSyncError):
            pos_sync_service._apply_record(
                db,
                integration,
                _job(db),
                _record(code="BAD2", price=10.0, mrp=5.0),
                "fp-bad2",
            )
        db.rollback()
        assert db.query(ShopProduct).count() == 0

    def test_a_good_mrp_with_a_conflicting_pos_price_still_syncs(self, db):
        """Under PLATFORM price authority, one field's disagreement must not
        condemn the other: a valid MRP judged against the persisted platform
        price (120) is coherent even when the incoming POS price (999) will be
        refused as a conflict. Without this rule the record fails as
        INVALID_MRP and the whole sync reports COMPLETED_WITH_ERRORS."""
        integration = _integration(db)
        pos_sync_service._apply_record(
            db,
            integration,
            _job(db),
            _record(code="SEED", price=120.0, mrp=150.0, quantity=5),
            "fp-seed",
        )
        db.flush()

        result = pos_sync_service._apply_record(
            db,
            integration,
            _job(db),
            _record(code="SEED", price=999.0, mrp=150.0, quantity=5),
            "fp-conflict",
        )
        db.flush()
        assert result["action"] == "UPDATED"
        conflicts = {c["field"]: c for c in result["conflicts"]}
        assert conflicts["price"]["resolution"] == "PRESERVED_PLATFORM"
        listing = db.query(ShopProduct).one()
        assert float(listing.price) == 120.0
        assert float(listing.mrp) == 150.0


if __name__ == "__main__":
    raise SystemExit(pytest.main([__file__, "-v"]))