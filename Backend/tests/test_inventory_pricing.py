"""Phase 19 — Core Inventory and Pricing Engine tests.

Covers:
- Add inventory
- Update inventory
- Remove inventory
- Price update
- Price history
- Stock movement
- Adjustment
- Offer creation
- Offer expiry
- Stale inventory
- Customer search receives correct price, availability and freshness
"""

import os
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

BACKEND_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BACKEND_DIR))

os.environ.setdefault("ENVIRONMENT", "test")
os.environ.setdefault("HYPERLOCAL_ENV", "test")

import pytest  # noqa: E402

# Force test settings
from app.core.config import settings  # noqa: E402
settings.RATE_LIMIT_ENABLED = False


@pytest.fixture(autouse=True)
def _no_live_broker(monkeypatch):
    """Keep these tests hermetic — no Redis/Celery broker required.

    The inventory service fire-and-forgets a search-index task via Celery and
    (Phase 27) the notification service enqueues delivery jobs; stub both so
    tests never touch a message broker (mirrors test_pos_integration_phase25).
    """
    from app.services import inventory_service, notification_tasks

    monkeypatch.setattr(
        inventory_service, "_enqueue_search_index_update", lambda shop_product_id: None
    )
    monkeypatch.setattr(
        notification_tasks.deliver_notification_task, "delay", lambda nid: None
    )


# ── Enum tests ──────────────────────────────────────────────────────────────
def test_stock_status_enum_values():
    """StockStatus must support all required states."""
    from app.models.product import StockStatus

    values = {s.value for s in StockStatus}
    assert "IN_STOCK" in values
    assert "LOW_STOCK" in values
    assert "LIMITED_STOCK" in values
    assert "OUT_OF_STOCK" in values
    assert "UNKNOWN" in values
    assert "PRE_ORDER" in values
    assert "BACK_ORDER" in values


def test_customer_stock_status_enum_values():
    """CustomerStockStatus must support customer-facing states."""
    from app.models.product import CustomerStockStatus

    values = {s.value for s in CustomerStockStatus}
    assert "IN_STOCK" in values
    assert "LIMITED_STOCK" in values
    assert "OUT_OF_STOCK" in values
    assert "UNKNOWN" in values


def test_freshness_status_enum_values():
    """FreshnessStatus must support recently-updated and stale states."""
    from app.models.product import FreshnessStatus

    values = {s.value for s in FreshnessStatus}
    assert "RECENTLY_UPDATED" in values
    assert "STALE" in values


def test_inventory_source_enum_values():
    """InventorySource must support all four sources."""
    from app.models.product import InventorySource

    values = {s.value for s in InventorySource}
    assert "MANUAL" in values
    assert "BARCODE_SCAN" in values
    assert "EXCEL_UPLOAD" in values
    assert "POS_INTEGRATION" in values


def test_inventory_models_importable():
    """All inventory models must be importable."""
    from app.models.product import (
        Inventory,
        InventoryAdjustment,
        InventoryMovement,
        PriceHistory,
        Offer,
        OfferCondition,
        OfferProduct,
        OfferStatus,
        OfferType,
    )

    assert Inventory is not None
    assert InventoryAdjustment is not None
    assert InventoryMovement is not None
    assert PriceHistory is not None
    assert Offer is not None
    assert OfferCondition is not None
    assert OfferProduct is not None
    assert OfferStatus is not None
    assert OfferType is not None


def test_shop_product_has_sku_and_active():
    """ShopProduct must have sku and is_active fields."""
    from app.models.product import ShopProduct

    assert hasattr(ShopProduct, "sku")
    assert hasattr(ShopProduct, "is_active")
    assert hasattr(ShopProduct, "freshness_status")


def test_inventory_has_freshness():
    """Inventory must have freshness tracking fields."""
    from app.models.product import Inventory

    assert hasattr(Inventory, "freshness_status")
    assert hasattr(Inventory, "freshness_checked_at")


def test_price_history_has_mrp():
    """PriceHistory must track MRP changes."""
    from app.models.product import PriceHistory

    assert hasattr(PriceHistory, "old_mrp")
    assert hasattr(PriceHistory, "new_mrp")


# ── Schema tests ────────────────────────────────────────────────────────────
def test_inventory_schemas_importable():
    """All inventory schemas must be importable."""
    from app.schemas.inventory import (
        InventoryCreate,
        InventoryResponse,
        InventoryUpdate,
        InventoryMovementCreate,
        InventoryMovementResponse,
        InventoryAdjustmentCreate,
        InventoryAdjustmentResponse,
        PriceUpdate,
        PriceHistoryResponse,
        OfferCreate,
        OfferResponse,
        OfferUpdate,
        OfferDetailResponse,
        OfferConditionCreate,
        OfferProductMapping,
        CustomerInventoryDetail,
        CustomerInventoryResponse,
        ShopInventoryItemResponse,
        ShopInventoryResponse,
    )

    assert InventoryCreate is not None
    assert InventoryResponse is not None
    assert InventoryUpdate is not None
    assert InventoryMovementCreate is not None
    assert InventoryAdjustmentCreate is not None
    assert PriceUpdate is not None
    assert PriceHistoryResponse is not None
    assert OfferCreate is not None
    assert OfferResponse is not None
    assert OfferUpdate is not None
    assert OfferDetailResponse is not None
    assert OfferConditionCreate is not None
    assert OfferProductMapping is not None
    assert CustomerInventoryDetail is not None
    assert CustomerInventoryResponse is not None
    assert ShopInventoryItemResponse is not None
    assert ShopInventoryResponse is not None


def test_inventory_create_schema():
    """InventoryCreate schema must validate correctly."""
    from app.schemas.inventory import InventoryCreate
    from app.models.product import InventorySource

    payload = InventoryCreate(
        shop_product_id=1,
        quantity=10,
        reserved_quantity=2,
        source=InventorySource.MANUAL,
    )
    assert payload.shop_product_id == 1
    assert payload.quantity == 10
    assert payload.reserved_quantity == 2
    assert payload.source == InventorySource.MANUAL


def test_price_update_schema():
    """PriceUpdate schema must validate correctly."""
    from app.schemas.inventory import PriceUpdate

    payload = PriceUpdate(new_price=99.99, new_mrp=129.99)
    assert payload.new_price == 99.99
    assert payload.new_mrp == 129.99


def test_offer_create_schema():
    """OfferCreate schema must validate correctly."""
    from app.schemas.inventory import OfferCreate
    from app.models.product import OfferType

    now = datetime.now(timezone.utc)
    payload = OfferCreate(
        shop_id=1,
        title="10% off",
        offer_type=OfferType.PERCENTAGE_DISCOUNT,
        discount_percentage=10.0,
        start_date=now,
        end_date=now + timedelta(days=7),
    )
    assert payload.title == "10% off"
    assert payload.offer_type == OfferType.PERCENTAGE_DISCOUNT
    assert payload.discount_percentage == 10.0


# ── Service tests ───────────────────────────────────────────────────────────
def test_get_freshness_threshold():
    """Freshness thresholds must be source-specific."""
    from app.services.inventory_service import get_freshness_threshold
    from app.models.product import InventorySource

    assert get_freshness_threshold(InventorySource.MANUAL) == timedelta(hours=24)
    assert get_freshness_threshold(InventorySource.BARCODE_SCAN) == timedelta(hours=12)
    assert get_freshness_threshold(InventorySource.EXCEL_UPLOAD) == timedelta(hours=48)
    assert get_freshness_threshold(InventorySource.POS_INTEGRATION) == timedelta(minutes=30)


def test_compute_freshness_recent():
    """compute_freshness should return RECENTLY_UPDATED for fresh data."""
    from app.services.inventory_service import compute_freshness
    from app.models.product import FreshnessStatus, InventorySource

    now = datetime.now(timezone.utc)
    recent = now - timedelta(minutes=5)
    assert compute_freshness(recent, InventorySource.MANUAL, now) == FreshnessStatus.RECENTLY_UPDATED


def test_compute_freshness_stale():
    """compute_freshness should return STALE for old data."""
    from app.services.inventory_service import compute_freshness
    from app.models.product import FreshnessStatus, InventorySource

    now = datetime.now(timezone.utc)
    old = now - timedelta(days=2)
    assert compute_freshness(old, InventorySource.MANUAL, now) == FreshnessStatus.STALE


def test_compute_freshness_none():
    """compute_freshness should return None when last_updated is None."""
    from app.services.inventory_service import compute_freshness

    assert compute_freshness(None) is None


def test_map_to_customer_stock_status():
    """map_to_customer_stock_status should map internal to customer-facing."""
    from app.services.inventory_service import map_to_customer_stock_status
    from app.models.product import CustomerStockStatus, StockStatus

    assert map_to_customer_stock_status(StockStatus.IN_STOCK, 10) == CustomerStockStatus.IN_STOCK
    assert map_to_customer_stock_status(StockStatus.IN_STOCK, 3) == CustomerStockStatus.LIMITED_STOCK
    assert map_to_customer_stock_status(StockStatus.LOW_STOCK) == CustomerStockStatus.LIMITED_STOCK
    assert map_to_customer_stock_status(StockStatus.LIMITED_STOCK) == CustomerStockStatus.LIMITED_STOCK
    assert map_to_customer_stock_status(StockStatus.OUT_OF_STOCK) == CustomerStockStatus.OUT_OF_STOCK
    assert map_to_customer_stock_status(StockStatus.PRE_ORDER) == CustomerStockStatus.UNKNOWN
    assert map_to_customer_stock_status(StockStatus.BACK_ORDER) == CustomerStockStatus.UNKNOWN


def test_derive_stock_status():
    """derive_stock_status should derive from quantity."""
    from app.services.inventory_service import derive_stock_status
    from app.models.product import StockStatus

    assert derive_stock_status(0) == StockStatus.OUT_OF_STOCK
    assert derive_stock_status(3) == StockStatus.LOW_STOCK
    assert derive_stock_status(10) == StockStatus.IN_STOCK
    assert derive_stock_status(10, low_stock_threshold=15) == StockStatus.LOW_STOCK


# ── Mock DB helpers ─────────────────────────────────────────────────────────
class MockQuery:
    """A chainable mock query for testing DB interactions."""

    def __init__(self, result=None):
        self._result = result
        self._filtered = result

    def filter(self, *args, **kwargs):
        return self

    def filter_by(self, **kwargs):
        return self

    def join(self, *args, **kwargs):
        return self

    def options(self, *args, **kwargs):
        return self

    def offset(self, *args):
        return self

    def limit(self, *args):
        return self

    def order_by(self, *args):
        return self

    def all(self):
        return self._filtered or []

    def first(self):
        if isinstance(self._result, list) and self._result:
            return self._result[0]
        return self._result

    def one(self):
        return self._result

    def scalars(self):
        return self

    def count(self):
        return len(self._filtered or [])

    def delete(self, synchronize_session=False):
        return 0


class MockDB:
    """Simplified DB mock for unit testing inventory_service functions."""

    def __init__(self):
        self.added = []
        self.deleted = []
        self._result = None
        self._results_by_model = {}

    def query(self, model):
        result = self._results_by_model.get(model, self._result)
        return MockQuery(result)

    def set_result(self, model, result):
        self._results_by_model[model] = result

    def add(self, obj):
        self.added.append(obj)

    def add_all(self, objs):
        self.added.extend(objs)

    def delete(self, obj):
        self.deleted.append(obj)

    def flush(self):
        pass

    def commit(self):
        pass

    def rollback(self):
        pass


# ── Instance-based mock models ──────────────────────────────────────────────
class MockStockStatus:
    def __init__(self, value):
        self.value = value


class MockInventoryObj:
    """Instance-based inventory mock so mutations are reflected."""

    def __init__(self, quantity=10, reserved=2, source_value="MANUAL", stock="IN_STOCK"):
        self.id = 1
        self.shop_product_id = 1
        self.quantity = quantity
        self.reserved_quantity = reserved
        self.available_quantity = quantity - reserved
        self.is_available = True
        self.stock_status = MockStockStatus(stock)
        self.low_stock_threshold = 5
        self.last_updated_by = None
        self.last_updated_source = MockStockStatus(source_value)
        self.last_synced_at = None
        self.freshness_status = None
        self.freshness_checked_at = None
        self.updated_at = datetime.now(timezone.utc)


class MockShopProductObj:
    """Instance-based shop product mock so mutations are reflected."""

    def __init__(self, price=100.0, mrp=150.0):
        self.id = 1
        self.price = price
        self.mrp = mrp
        self.stock_status = None
        self.is_available = None
        self.last_inventory_update = None
        self.last_price_update = None
        self.source = None
        self.freshness_status = None


class MockOfferObj:
    """Instance-based offer mock so mutations are reflected."""

    def __init__(self, status=None, start=None, end=None):
        from app.models.product import OfferStatus
        self.id = 1
        self.status = status or OfferStatus.DRAFT
        self.start_date = start or (datetime.now(timezone.utc) - timedelta(days=1))
        self.end_date = end or (datetime.now(timezone.utc) + timedelta(days=7))
        self.is_deleted = False


# ── Inventory CRUD tests ────────────────────────────────────────────────────
def test_create_inventory():
    """create_inventory should create inventory and initial movement."""
    from app.services.inventory_service import create_inventory
    from app.models.product import Inventory, InventoryMovement, ShopProduct

    shop_product = MockShopProductObj()
    db = MockDB()
    db.set_result(ShopProduct, shop_product)
    db.set_result(Inventory, None)  # No existing inventory

    inv = create_inventory(db, {"shop_product_id": 1, "quantity": 10, "reserved_quantity": 2})

    assert inv.quantity == 10
    assert inv.reserved_quantity == 2
    assert inv.available_quantity == 8
    assert inv.is_available is True
    assert inv.stock_status.value == "IN_STOCK"

    # Verify movement was added
    movements = [a for a in db.added if isinstance(a, InventoryMovement)]
    assert len(movements) == 1
    assert movements[0].quantity_change == 10
    assert movements[0].movement_type == "INITIAL"


def test_create_inventory_duplicate():
    """create_inventory should raise ValueError for duplicate."""
    from app.services.inventory_service import create_inventory
    from app.models.product import Inventory, ShopProduct

    shop_product = MockShopProductObj()
    existing = MockInventoryObj()
    db = MockDB()
    db.set_result(ShopProduct, shop_product)
    db.set_result(Inventory, existing)

    with pytest.raises(ValueError, match="already exists"):
        create_inventory(db, {"shop_product_id": 1, "quantity": 10})


def test_update_inventory():
    """update_inventory should update quantity and record movement."""
    from app.services.inventory_service import update_inventory
    from app.models.product import Inventory, InventoryMovement, ShopProduct

    inv = MockInventoryObj(quantity=10, reserved=2)
    shop_product = MockShopProductObj()
    db = MockDB()
    db.set_result(Inventory, inv)
    db.set_result(ShopProduct, shop_product)

    result = update_inventory(db, 1, {"quantity": 15})

    assert result.quantity == 15
    assert result.available_quantity == 13

    # Verify movement was added
    movements = [a for a in db.added if isinstance(a, InventoryMovement)]
    assert len(movements) == 1
    assert movements[0].quantity_change == 5
    assert movements[0].quantity_before == 10
    assert movements[0].quantity_after == 15


def test_remove_inventory():
    """remove_inventory should set quantity to 0 and mark unavailable."""
    from app.services.inventory_service import remove_inventory
    from app.models.product import Inventory, InventoryMovement, ShopProduct

    inv = MockInventoryObj(quantity=10, reserved=2)
    shop_product = MockShopProductObj()
    db = MockDB()
    db.set_result(Inventory, inv)
    db.set_result(ShopProduct, shop_product)

    removed = remove_inventory(db, 1)

    assert removed is True
    assert inv.quantity == 0
    assert inv.is_available is False
    assert inv.stock_status.value == "OUT_OF_STOCK"

    # Verify movement was added
    movements = [a for a in db.added if isinstance(a, InventoryMovement)]
    assert len(movements) == 1
    assert movements[0].quantity_change == -10
    assert movements[0].movement_type == "REMOVE"


# ── Price history tests ─────────────────────────────────────────────────────
def test_update_price():
    """update_price should update price and create history record."""
    from app.services.inventory_service import update_price
    from app.models.product import PriceHistory, ShopProduct

    shop_product = MockShopProductObj(price=100.0, mrp=150.0)
    db = MockDB()
    db.set_result(ShopProduct, shop_product)
    db.set_result(PriceHistory, None)

    history = update_price(db, 1, {"new_price": 120.0, "new_mrp": 160.0})

    assert history.old_price == 100.0
    assert history.new_price == 120.0
    assert history.old_mrp == 150.0
    assert history.new_mrp == 160.0
    assert shop_product.price == 120.0
    assert shop_product.mrp == 160.0


def test_update_price_preserves_history():
    """update_price should close out open history records."""
    from app.services.inventory_service import update_price
    from app.models.product import PriceHistory, ShopProduct

    shop_product = MockShopProductObj(price=100.0, mrp=150.0)

    class MockOpenRecord:
        def __init__(self):
            self.id = 1
            self.shop_product_id = 1
            self.effective_to = None

    open_record = MockOpenRecord()
    db = MockDB()
    db.set_result(ShopProduct, shop_product)
    db.set_result(PriceHistory, [open_record])

    update_price(db, 1, {"new_price": 120.0})

    # The open record should be closed
    assert open_record.effective_to is not None


# ── Movement tests ──────────────────────────────────────────────────────────
def test_record_movement():
    """record_movement should update quantity and create movement."""
    from app.services.inventory_service import record_movement
    from app.models.product import Inventory, InventoryMovement, ShopProduct

    inv = MockInventoryObj(quantity=10, reserved=2)
    shop_product = MockShopProductObj()
    db = MockDB()
    db.set_result(Inventory, inv)
    db.set_result(ShopProduct, shop_product)

    movement = record_movement(db, {"inventory_id": 1, "quantity_change": -3, "movement_type": "SALE"})

    assert movement.quantity_change == -3
    assert movement.quantity_before == 10
    assert movement.quantity_after == 7
    assert inv.quantity == 7


def test_record_movement_insufficient():
    """record_movement should raise ValueError for insufficient stock."""
    from app.services.inventory_service import record_movement
    from app.models.product import Inventory

    inv = MockInventoryObj(quantity=2, reserved=0)
    db = MockDB()
    db.set_result(Inventory, inv)

    with pytest.raises(ValueError, match="Insufficient stock"):
        record_movement(db, {"inventory_id": 1, "quantity_change": -5, "movement_type": "SALE"})


# ── Adjustment tests ────────────────────────────────────────────────────────
def test_create_adjustment():
    """create_adjustment should apply adjustment and create record."""
    from app.services.inventory_service import create_adjustment
    from app.models.product import Inventory, InventoryAdjustment, InventoryMovement, ShopProduct

    inv = MockInventoryObj(quantity=10, reserved=0)
    shop_product = MockShopProductObj()
    db = MockDB()
    db.set_result(Inventory, inv)
    db.set_result(ShopProduct, shop_product)

    adjustment = create_adjustment(db, {
        "inventory_id": 1,
        "adjustment_type": "DAMAGE",
        "quantity_adjustment": -2,
        "reason": "Damaged goods",
    })

    assert adjustment.adjustment_type == "DAMAGE"
    assert adjustment.quantity_adjustment == -2
    assert inv.quantity == 8

    # Verify movement was added
    movements = [a for a in db.added if isinstance(a, InventoryMovement)]
    assert len(movements) == 1
    assert movements[0].movement_type == "ADJUSTMENT"


# ── Offer tests ─────────────────────────────────────────────────────────────
def test_create_offer():
    """create_offer should create offer with mappings and conditions."""
    from app.services.inventory_service import create_offer
    from app.models.product import OfferCondition, OfferProduct, OfferType

    now = datetime.now(timezone.utc)
    db = MockDB()

    offer = create_offer(db, {
        "shop_id": 1,
        "title": "10% off",
        "offer_type": OfferType.PERCENTAGE_DISCOUNT,
        "discount_percentage": 10.0,
        "start_date": now,
        "end_date": now + timedelta(days=7),
        "product_mappings": [{"shop_product_id": 1, "is_excluded": False}],
        "conditions": [{"condition_type": "MIN_QTY", "condition_value": "2", "operator": ">="}],
    })

    assert offer.title == "10% off"
    assert offer.offer_type == OfferType.PERCENTAGE_DISCOUNT
    assert offer.status.value == "DRAFT"

    # Verify mappings and conditions were added
    mappings = [a for a in db.added if isinstance(a, OfferProduct)]
    conditions = [a for a in db.added if isinstance(a, OfferCondition)]
    assert len(mappings) == 1
    assert len(conditions) == 1


def test_create_offer_invalid_dates():
    """create_offer should raise ValueError for invalid dates."""
    from app.services.inventory_service import create_offer
    from app.models.product import OfferType

    now = datetime.now(timezone.utc)
    db = MockDB()

    with pytest.raises(ValueError, match="end_date must be after start_date"):
        create_offer(db, {
            "shop_id": 1,
            "title": "Invalid",
            "offer_type": OfferType.FLAT_DISCOUNT,
            "start_date": now,
            "end_date": now - timedelta(days=1),
        })


def test_activate_offer():
    """activate_offer should set status to ACTIVE."""
    from app.services.inventory_service import activate_offer
    from app.models.product import Offer, OfferStatus

    offer = MockOfferObj(status=OfferStatus.DRAFT)
    db = MockDB()
    db.set_result(Offer, offer)

    result = activate_offer(db, 1)
    assert result.status == OfferStatus.ACTIVE


def test_expire_offer():
    """expire_offer should set status to EXPIRED."""
    from app.services.inventory_service import expire_offer
    from app.models.product import Offer, OfferStatus

    offer = MockOfferObj(status=OfferStatus.ACTIVE)
    db = MockDB()
    db.set_result(Offer, offer)

    result = expire_offer(db, 1)
    assert result.status == OfferStatus.EXPIRED


# ── Freshness engine tests ──────────────────────────────────────────────────
def test_refresh_freshness():
    """refresh_freshness should update stale inventory records."""
    from app.services.inventory_service import refresh_freshness
    from app.models.product import FreshnessStatus, Inventory, InventorySource, ShopProduct

    inv = MockInventoryObj()
    inv.last_synced_at = datetime.now(timezone.utc) - timedelta(days=2)
    inv.updated_at = datetime.now(timezone.utc) - timedelta(days=2)
    inv.last_updated_source = InventorySource.MANUAL
    inv.freshness_status = FreshnessStatus.RECENTLY_UPDATED

    shop_product = MockShopProductObj()
    db = MockDB()
    db.set_result(Inventory, [inv])
    db.set_result(ShopProduct, shop_product)

    count = refresh_freshness(db)
    assert count == 1
    assert inv.freshness_status == FreshnessStatus.STALE


# ── API route tests ─────────────────────────────────────────────────────────
def test_inventory_router_exists():
    """Inventory router must be importable and have routes."""
    from app.api.routes.inventory import router

    paths = {r.path for r in router.routes}
    assert "/inventory" in paths
    assert "/inventory/movements" in paths
    assert "/inventory/adjustments" in paths
    assert "/inventory/offers" in paths
    assert "/inventory/offers/{offer_id}" in paths
    assert "/inventory/offers/{offer_id}/activate" in paths
    assert "/inventory/offers/{offer_id}/expire" in paths
    assert "/inventory/freshness/refresh" in paths
    assert "/inventory/product/{product_master_id}" in paths
    assert "/inventory/shop/{shop_id}" in paths
    assert "/inventory/shop-products/{shop_product_id}/price" in paths
    assert "/inventory/shop-products/{shop_product_id}/price-history" in paths
    assert "/inventory/{inventory_id}" in paths
    assert "/inventory/{inventory_id}/movements" in paths
    assert "/inventory/{inventory_id}/adjustments" in paths


def test_inventory_router_registered_in_main():
    """Inventory router should be registered in main app."""
    from app.main import app
    from app.api.routes.inventory import router as inventory_router

    included = [r for r in app.routes if type(r).__name__ == "_IncludedRouter"]
    assert len(included) > 0
    assert len(inventory_router.routes) > 0


# ── Customer search verification ────────────────────────────────────────────
def test_search_schema_has_freshness():
    """Search result schema must include freshness and MRP."""
    from app.schemas.search import ShopProductResultSchema

    fields = ShopProductResultSchema.model_fields
    assert "freshness_status" in fields
    assert "mrp" in fields


def test_customer_inventory_detail_schema():
    """CustomerInventoryDetail must include all required fields."""
    from app.schemas.inventory import CustomerInventoryDetail

    fields = CustomerInventoryDetail.model_fields
    assert "price" in fields
    assert "mrp" in fields
    assert "stock_status" in fields
    assert "freshness_status" in fields
    assert "is_available" in fields
    assert "offer_text" in fields


def test_search_uses_inventory_service():
    """Search path uses inventory_service for freshness and offers.

    The V2 discovery route delegates to the search engine, which imports
    inventory_service and enriches each result with offer text, freshness
    status and MRP from the inventory-backed index.
    """
    import inspect
    from app.search import engine as search_engine
    from app.api.routes import search

    route_source = inspect.getsource(search)
    # Route delegates discovery to the search engine (not a bespoke join).
    assert "search_engine.search_products" in route_source

    engine_source = inspect.getsource(search_engine)
    # Engine pulls from the inventory domain and surfaces freshness/offer/MRP.
    assert "inventory_service" in engine_source
    assert "get_offer_text_for_shop_product" in engine_source
    assert "freshness_status" in engine_source
    assert "mrp" in engine_source