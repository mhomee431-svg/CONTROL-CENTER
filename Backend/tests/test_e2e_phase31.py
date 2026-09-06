"""Phase 31 — End-to-end platform verification.

Proves the full business journey works from **shopkeeper data entry to customer
rediscovery**, and hardens the failure scenarios called out at platform level:

* **Redis / broker unavailable** — the fire-and-forget search-index enqueue must
  never block a request thread (regression for the hang captured in
  ``hang_trace.txt``).
* **Four intake sources converge** — manual / barcode / Excel / POS all land in
  the same canonical ``Inventory`` + ``InventoryMovement`` model, each tagged
  with its own ``InventorySource`` and staleness rule.
* **Shopkeeper -> customer discovery** — a shopkeeper publish flows through the
  search indexer into a ``SearchIndex`` entry that a customer search can surface
  (price, availability, freshness, geo).
* **Shop suspension / product deactivation** — removing the listing is reflected
  in the discovery index (is_shop_visible / is_available toggle).

Uses an in-memory SQLite engine with PostGIS Geography columns stripped via the
shared ``tests.geo_compat`` helper, so no PostgreSQL/PostGIS is required.
"""

import os
import sys
import time
from datetime import datetime, timedelta, timezone
from pathlib import Path

BACKEND_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BACKEND_DIR))

os.environ.setdefault("ENVIRONMENT", "test")
os.environ.setdefault("HYPERLOCAL_ENV", "test")

import pytest  # noqa: E402
from sqlalchemy import create_engine  # noqa: E402
from sqlalchemy.orm import sessionmaker  # noqa: E402
from sqlalchemy.pool import StaticPool  # noqa: E402

from app.core.config import settings  # noqa: E402
from app.database.session import Base  # noqa: E402

settings.RATE_LIMIT_ENABLED = False

# ── Register models BEFORE stripping geo (so Geography columns are seen) ────
from app.models.product import (  # noqa: E402
    BarcodeRelationship,
    Brand,
    Category,
    FreshnessStatus,
    Inventory,
    InventoryMovement,
    InventorySource,
    ProductIdentifier,
    ProductMaster,
    ProductStatus,
    ProductVariant,
    ShopProduct,
    ShopProductStatus,
    StockStatus,
)
from app.models.search import SearchIndex, SearchIndexEntityType, SearchIndexSync  # noqa: E402
from app.models.shop import Shop, ShopCategory, ShopStatus  # noqa: E402

# Adapt PostGIS Geography columns for plain SQLite (shared, reversible helper).
from tests.geo_compat import strip_geo_columns  # noqa: E402

strip_geo_columns()


def _portable_timestamp_defaults():
    """Replace server-side ``now()`` / ``false`` defaults with Python callables
    so SQLite stores real values (mirrors earlier phase test modules)."""
    from sqlalchemy import ColumnDefault

    def _now(ctx=None):
        return datetime.now(timezone.utc)

    for table in Base.metadata.tables.values():
        for col in table.columns:
            sd = getattr(col, "server_default", None)
            sd_arg = getattr(sd, "arg", None)
            if isinstance(sd_arg, str) and sd_arg.lower() == "now()":
                if col.default is None:
                    col.default = ColumnDefault(_now)
                col.server_default = None
            elif isinstance(sd_arg, str) and sd_arg.lower() == "false":
                if col.default is None and (
                    getattr(getattr(col.type, "python_type", None), "__name__", "") == "bool"
                ):
                    col.default = ColumnDefault(False)
                col.server_default = None
            ou = getattr(col, "onupdate", None)
            ou_arg = getattr(ou, "arg", None)
            if ou is not None and str(ou_arg).strip().lower().startswith("now"):
                col.onupdate = ColumnDefault(_now, for_update=True)


_portable_timestamp_defaults()


TABLES = [
    Category.__table__,
    Brand.__table__,
    ProductMaster.__table__,
    ProductIdentifier.__table__,
    BarcodeRelationship.__table__,
    ProductVariant.__table__,
    Shop.__table__,
    ShopProduct.__table__,
    Inventory.__table__,
    InventoryMovement.__table__,
    SearchIndex.__table__,
    SearchIndexSync.__table__,
]


def _dedupe_barcode_index():
    """The barcode_relationships model declares the same index twice
    (column index=True + explicit __table_args__ Index with the same
    name); SQLite rejects the duplicate. Drop one so create_all works."""
    tbl = BarcodeRelationship.__table__
    for ix in list(tbl.indexes):
        if ix.name == "ix_barcode_relationships_barcode":
            tbl.indexes.discard(ix)
            break


_dedupe_barcode_index()


@pytest.fixture()
def db():
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


NOW = datetime.now(timezone.utc)


def _make_product(db, *, name="Basmati Rice 1kg", status=ProductStatus.APPROVED, barcode="8901234567890"):
    brand = Brand(name="Annapurna", slug="annapurna")
    category = Category(name="Groceries", slug="groceries")
    db.add_all([brand, category])
    db.flush()
    product = ProductMaster(
        name=name,
        slug="basmati-rice-1kg",
        description="Long grain basmati rice",
        category_id=category.id,
        brand_id=brand.id,
        status=status,
        is_active=True,
        is_searchable=True,
        base_unit="kg",
        base_quantity=1.0,
    )
    db.add(product)
    db.flush()
    db.add(
        ProductIdentifier(
            product_master_id=product.id,
            identifier_type="EAN",
            identifier_value=barcode,
            is_primary=True,
            is_active=True,
        )
    )
    db.flush()
    return product, brand, category


def _make_shop(db, *, is_verified=True, is_accepting_orders=True):
    shop = Shop(
        name="Neighbour Mart",
        slug="neighbour-mart",
        status=ShopStatus.VERIFIED if is_verified else ShopStatus.REGISTERED,
        is_verified=is_verified,
        is_accepting_orders=is_accepting_orders,
        category=ShopCategory.GROCERY,
        rating=4.6,
        review_count=120,
        delivery_radius_km=5.0,
        location="POINT(85.14 25.59)",
        latitude=25.59,
        longitude=85.14,
    )
    db.add(shop)
    db.flush()
    return shop


def _make_inventory(db, product, shop, *, quantity=10, source=InventorySource.MANUAL):
    sp = ShopProduct(
        shop_id=shop.id,
        product_master_id=product.id,
        sku=f"{product.slug.upper()}-{source.value}",
        status=ShopProductStatus.ACTIVE,
        price=145.0,
        mrp=165.0,
        is_active=True,
        is_available=True,
        is_visible=True,
        stock_status=StockStatus.IN_STOCK,
        source=source,
        last_inventory_update=NOW,
    )
    db.add(sp)
    db.flush()
    inv = Inventory(
        shop_product_id=sp.id,
        quantity=quantity,
        reserved_quantity=0,
        available_quantity=quantity,
        is_available=True,
        stock_status=StockStatus.IN_STOCK,
        low_stock_threshold=5,
        last_updated_source=source,
        last_synced_at=NOW,
        freshness_status=FreshnessStatus.RECENTLY_UPDATED,
        freshness_checked_at=NOW,
    )
    db.add(inv)
    db.flush()
    db.add(
        InventoryMovement(
            inventory_id=inv.id,
            quantity_change=quantity,
            quantity_before=0,
            quantity_after=quantity,
            movement_type="INITIAL",
            source=source,
            reference_type=source.value,
        )
    )
    db.flush()
    return sp, inv


# ── 1. Resilience: Redis/broker down must not block the request thread ──────
def test_redis_down_enqueue_does_not_hang_or_raise(db, monkeypatch):
    """Regression: a degraded broker/result backend must not block inventory
    writes (see hang_trace.txt where send_task hung in the Redis pubsub
    reconnect loop)."""
    import app.core.celery_app as celery_mod
    from app.services import inventory_service

    def _hanging_send(*args, **kwargs):
        time.sleep(10)  # far beyond the 1s budget

    monkeypatch.setattr(celery_mod.celery_app, "send_task", _hanging_send)
    start = time.perf_counter()
    inventory_service._enqueue_search_index_update(12345)  # noqa: SLF001
    elapsed = time.perf_counter() - start
    assert elapsed < 3.0, f"enqueue blocked the caller for {elapsed:.2f}s"


def test_redis_down_enqueue_survives_raise(db, monkeypatch):
    import app.core.celery_app as celery_mod
    from app.services import inventory_service

    def _failing_publish(*args, **kwargs):
        raise RuntimeError("broker unreachable")

    monkeypatch.setattr(celery_mod.celery_app, "send_task", _failing_publish)
    inventory_service._enqueue_search_index_update(999)  # noqa: SLF001


def test_enqueue_publishes_correctly_when_healthy(db, monkeypatch):
    import app.core.celery_app as celery_mod

    captured = {}

    def _record_publish(name, args, **kwargs):
        captured["name"] = name
        captured["args"] = args
        captured["ignore_result"] = kwargs.get("ignore_result")

    monkeypatch.setattr(celery_mod.celery_app, "send_task", _record_publish)
    from app.services import inventory_service

    inventory_service._enqueue_search_index_update(7)  # noqa: SLF001
    assert captured["name"] == "app.services.tasks.index_shop_product"
    assert captured["args"] == [7]
    assert captured["ignore_result"] is True


# ── Convergence: all four intake sources land in the single Inventory model ──
def test_all_four_intake_sources_converge_on_inventory_model(db):
    from app.services.inventory_service import get_freshness_threshold

    sources = {
        InventorySource.MANUAL: timedelta(hours=24),
        InventorySource.BARCODE_SCAN: timedelta(hours=12),
        InventorySource.EXCEL_UPLOAD: timedelta(hours=48),
        InventorySource.POS_INTEGRATION: timedelta(minutes=30),
    }

    # Every source has a distinct staleness rule — proving they are route labels
    # on ONE canonical model, not separate storage.
    thresholds = {s: get_freshness_threshold(s) for s in sources}
    assert len(set(thresholds.values())) == 4

    product = _make_product(db, name="Convergence Rice", barcode="8901111111111")[0]
    shop = _make_shop(db)
    pairs = {}
    for i, src in enumerate(sources):
        sp, inv = _make_inventory(db, product, shop, quantity=5 + i, source=src)
        db.flush()
        pairs[src] = (sp, inv)
        assert inv.last_updated_source == src
        assert inv.stock_status == StockStatus.IN_STOCK
        mv = db.query(InventoryMovement).filter(InventoryMovement.inventory_id == inv.id).first()
        assert mv is not None and mv.source == src

    # All land in the same 'inventory' table — no per-source tables.
    ids = [v[0].id for v in pairs.values()]
    invs = db.query(Inventory).filter(Inventory.shop_product_id.in_(ids)).all()
    assert len(invs) == 4
    assert {i.last_updated_source for i in invs} == set(sources)


# ── E2E: shopkeeper data entry -> inventory -> search index -> discovery ────
def test_shopkeeper_to_customer_discovery_journey(db):
    from app.search.indexer import upsert_shop_product

    shop = _make_shop(db)
    product = _make_product(db)[0]
    sp, inv = _make_inventory(db, product, shop, quantity=10)

    # Shopkeeper publish triggers the indexer (what the enqueue task runs).
    upsert_shop_product(db, sp.id)
    db.flush()

    entry = (
        db.query(SearchIndex)
        .filter(
            SearchIndex.entity_type == SearchIndexEntityType.SHOP_PRODUCT,
            SearchIndex.entity_id == sp.id,
        )
        .first()
    )
    assert entry is not None, "shop-product not indexed after publish"
    assert entry.product_name == product.name
    assert float(entry.price) == 145.0
    assert entry.is_available is True
    assert entry.stock_status == "IN_STOCK"
    assert entry.freshness_status == "RECENTLY_UPDATED"
    assert entry.is_shop_visible is True
    assert entry.is_product_searchable is True
    assert entry.shop_name == "Neighbour Mart"
    assert abs(entry.latitude - 25.59) < 1e-6 and abs(entry.longitude - 85.14) < 1e-6

    # Customer-side visibility gate (what the search engine applies).
    discoverable = entry.is_available and entry.is_shop_visible and entry.is_product_searchable
    assert discoverable, "published listing is not discoverable by a customer"

    from app.search.normalizer import normalize_text

    assert "basmati" in normalize_text(entry.search_text)
    assert "rice" in normalize_text(entry.search_text)


def test_shop_suspension_hides_listing_from_discovery(db):
    from app.search.indexer import upsert_shop_product

    shop = _make_shop(db)
    product = _make_product(db)[0]
    sp, inv = _make_inventory(db, product, shop)
    upsert_shop_product(db, sp.id)
    db.flush()
    assert shop.is_accepting_orders is True

    shop.is_accepting_orders = False
    shop.status = ShopStatus.SUSPENDED
    db.flush()
    upsert_shop_product(db, sp.id)
    db.flush()

    entry = (
        db.query(SearchIndex)
        .filter(
            SearchIndex.entity_type == SearchIndexEntityType.SHOP_PRODUCT,
            SearchIndex.entity_id == sp.id,
        )
        .first()
    )
    assert entry is not None and entry.is_shop_visible is False
    assert not (entry.is_available and entry.is_shop_visible and entry.is_product_searchable)


def test_product_deactivation_hides_listing_from_discovery(db):
    from app.search.indexer import upsert_shop_product

    shop = _make_shop(db)
    product = _make_product(db)[0]
    sp, inv = _make_inventory(db, product, shop, quantity=20)
    upsert_shop_product(db, sp.id)
    db.flush()

    product.is_active = False
    product.is_searchable = False
    sp.is_active = False
    sp.is_available = False
    inv.is_available = False
    db.flush()
    upsert_shop_product(db, sp.id)
    db.flush()

    entry = (
        db.query(SearchIndex)
        .filter(
            SearchIndex.entity_type == SearchIndexEntityType.SHOP_PRODUCT,
            SearchIndex.entity_id == sp.id,
        )
        .first()
    )
    assert entry is not None
    assert entry.is_product_searchable is False
    assert entry.is_available is False
    assert not (entry.is_available and entry.is_shop_visible and entry.is_product_searchable)
