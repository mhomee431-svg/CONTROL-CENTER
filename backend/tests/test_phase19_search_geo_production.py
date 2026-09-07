"""Phase 19 — Search + Geo-Discovery PRODUCTION test.

Tests the ACTUAL core business flow a customer experiences:

    1. Customer selects a real location
    2. Customer searches a real product
    3. Backend finds the product
    4. System finds the matching SHOP PRODUCTS (per shop)
    5. PostGIS-style proximity finds the nearby shops
    6. Pricing is returned
    7. Availability is returned
    8. Results are sorted / filtered
    9. Customer opens the shop
   10. Customer gets directions

Every search result must carry PRODUCT + SHOP + PRICE + AVAILABILITY + DISTANCE.

This module runs the REAL production code — the search indexer
(``app.search.indexer.upsert_shop_product``), the real search engine
(``app.search.engine.search_products`` / ``nearby_shops`` / ``barcode_lookup``)
and the real HTTP routes (via ``TestClient``) — against an in-memory SQLite
engine. The PostGIS SQL functions the production engine emits
(``ST_GeogFromText``, ``ST_DWithin``, ``ST_Distance``) and pg_trgm
``similarity`` are registered as Python implementations (haversine geodesics +
faithful pg_trgm trigram similarity — 2-space padding,
``common/(n1+n2-common)``), so the production queries execute end-to-end with
no engine mocking. ``tests.geo_compat.strip_geo_columns`` makes the Geography columns
SQLite-portable (shared, order-independent helper).

Scenario matrix (from the phase-19 production review checklist):

    - exact product
    - partial search
    - category
    - brand
    - price
    - availability
    - distance
    - sorting
    - filtering
    - no results
    - stale inventory
    - multiple shops
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
from sqlalchemy import create_engine, event  # noqa: E402
from sqlalchemy.orm import sessionmaker  # noqa: E402
from sqlalchemy.pool import StaticPool  # noqa: E402

from app.core.config import settings  # noqa: E402
from app.database.session import Base  # noqa: E402

settings.RATE_LIMIT_ENABLED = False

# ── Register ALL production models BEFORE stripping geo ─────────────────────
from app.models.product import (  # noqa: E402
    BarcodeRelationship,
    Brand,
    Category,
    FreshnessStatus,
    Inventory,
    InventoryMovement,
    InventorySource,
    ProductIdentifier,
    ProductImage,
    ProductMaster,
    ProductStatus,
    ProductVariant,
    ShopProduct,
    ShopProductStatus,
    StockStatus,
)
from app.models.search import (  # noqa: E402
    BarcodeScan,
    PopularSearch,
    SearchEvent,
    SearchHistory,
    SearchIndex,
    SearchIndexEntityType,
    SearchIndexSync,
)
from app.models.shop import (  # noqa: E402
    Shop,
    ShopAddress,
    ShopCategory,
    ShopDocument,
    ShopHour,
    ShopHoliday,
    ShopManager,
    ShopOwner,
    ShopStatus,
    ShopVerification,
)
from app.models.analytics import ProductClick, ProductView  # noqa: E402
from app.models.analytics_event import AnalyticsEvent  # noqa: E402
from app.models.user import User  # noqa: E402

# Adapt PostGIS Geography columns for plain SQLite (shared, reversible helper).
from tests.geo_compat import strip_geo_columns  # noqa: E402

# Must run at import time, AFTER all models are registered, so create_all on
# the in-memory SQLite engine sees Text columns instead of Geography.
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
    ProductImage.__table__,
    Shop.__table__,
    ShopAddress.__table__,
    ShopHour.__table__,
    ShopHoliday.__table__,
    ShopDocument.__table__,
    ShopOwner.__table__,
    ShopManager.__table__,
    ShopVerification.__table__,
    ShopProduct.__table__,
    Inventory.__table__,
    InventoryMovement.__table__,
    SearchIndex.__table__,
    SearchIndexSync.__table__,
    SearchHistory.__table__,
    SearchEvent.__table__,
    PopularSearch.__table__,
    BarcodeScan.__table__,
    User.__table__,
    AnalyticsEvent.__table__,
    ProductClick.__table__,
    ProductView.__table__,
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


# ── PostGIS-in-SQLite compatibility functions ───────────────────────────────
def _parse_wkt_point(value):
    """Parse a WKT 'POINT(lng lat)' value into (longitude, latitude)."""
    if value is None:
        return None
    raw = str(value)
    if not raw.startswith("POINT"):
        return None
    try:
        inner = raw[raw.index("(") + 1 : raw.rindex(")")]
        parts = inner.split()
        if len(parts) == 2:
            return float(parts[0]), float(parts[1])
    except (ValueError, TypeError, IndexError):
        return None
    return None


def _wkt_distance_m(value_a, value_b):
    """Geodesic distance in metres between two WKT POINT values (haversine)."""
    pa = _parse_wkt_point(value_a)
    pb = _parse_wkt_point(value_b)
    if pa is None or pb is None:
        return None
    lon1, lat1 = pa
    lon2, lat2 = pb
    from app.services.geo_service import haversine_km

    return haversine_km(lat1, lon1, lat2, lon2) * 1000.0


def _trigrams(text):
    """pg_trgm-style trigram generation: 2-space padding + lowercase.

    ``show_trgm('hello')`` -> ['  h', ' he', 'hel', 'ell', 'llo', 'lo ', 'o  ']
    """
    if not text:
        return []
    padded = "  " + str(text).lower() + "  "
    if len(padded) < 3:
        return []
    return [padded[i : i + 3] for i in range(len(padded) - 2)]


def _trigram_similarity(text_a, text_b):
    """Reproduce PostgreSQL ``pg_trgm`` ``similarity()``:
    ``common / (len_a + len_b - common)`` over trigram multisets."""
    ta = _trigrams(text_a)
    tb = _trigrams(text_b)
    if not ta or not tb:
        return 0.0
    ca = {}
    cb = {}
    for t in ta:
        ca[t] = ca.get(t, 0) + 1
    for t in tb:
        cb[t] = cb.get(t, 0) + 1
    common = 0
    for t, n in ca.items():
        m = cb.get(t, 0)
        if m:
            common += n if n < m else m
    total = sum(ca.values()) + sum(cb.values())
    if total - common <= 0:
        return 0.0
    return common / (total - common)


def _register_sqlite_functions(dbapi_conn, connection_record):
    """Register the PostGIS / pg_trgm SQL functions the production engine emits
    so the real queries run unmodified on the in-memory SQLite engine."""
    dbapi_conn.create_function("ST_GeogFromText", 1, lambda value: value)
    dbapi_conn.create_function("ST_Distance", 2, lambda a, b: _wkt_distance_m(a, b) or 0.0)
    dbapi_conn.create_function("NULL", 0, lambda: None)

    def _dwithin(a, b, radius_m):
        d = _wkt_distance_m(a, b)
        if d is None:
            return 0
        return 1 if d <= (radius_m or 0.0) else 0

    dbapi_conn.create_function("ST_DWithin", 3, _dwithin)
    dbapi_conn.create_function("similarity", 2, _trigram_similarity)


@pytest.fixture()
def world():
    """In-memory production database engine + session with the full Phase-19
    Patna dataset seeded through the real indexer."""

    class World:
        pass

    engine = create_engine(
        "sqlite://",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    event.listen(engine, "connect", _register_sqlite_functions)
    Base.metadata.create_all(engine, tables=TABLES)
    session = sessionmaker(bind=engine)()
    data = _seed_world(session)
    w = World()
    w.db = session
    w.engine = engine
    for key, value in data.items():
        setattr(w, key, value)
    yield w
    session.close()
    engine.dispose()


# ── Customer location (Phase 19 — "customer selects a real location") ──────
PATNA_LAT = 25.5941
PATNA_LNG = 85.1376
# ── Seed-data helpers (real ORM models + real indexer) ─────────────────────
def _make_category(db, name, slug):
    c = Category(name=name, slug=slug, is_active=True)
    db.add(c)
    db.flush()
    return c


def _make_brand(db, name, slug):
    b = Brand(name=name, slug=slug, is_active=True)
    db.add(b)
    db.flush()
    return b


def _make_product(db, *, name, slug, brand, category, barcode, description=""):
    p = ProductMaster(
        name=name,
        slug=slug,
        description=description,
        category_id=category.id,
        brand_id=brand.id,
        status=ProductStatus.APPROVED,
        is_active=True,
        is_searchable=True,
        base_unit="piece",
        base_quantity=1.0,
    )
    db.add(p)
    db.flush()
    db.add(
        ProductIdentifier(
            product_master_id=p.id,
            identifier_type="EAN",
            identifier_value=barcode,
            is_primary=True,
            is_active=True,
        )
    )
    db.flush()
    return p


def _make_shop(
    db,
    *,
    name,
    slug,
    lat,
    lng,
    category=ShopCategory.GROCERY,
    rating=4.0,
    status=ShopStatus.VERIFIED,
):
    s = Shop(
        name=name,
        slug=slug,
        status=status,
        is_verified=True,
        is_accepting_orders=True,
        category=category,
        rating=rating,
        review_count=100,
        delivery_radius_km=15.0,
        location=f"POINT({lng} {lat})",
        latitude=lat,
        longitude=lng,
        subcategories="[]",
    )
    db.add(s)
    db.flush()
    return s


def _seed_listing(
    db,
    *,
    product,
    shop,
    price,
    mrp=None,
    quantity=10,
    is_available=True,
    stock_status=StockStatus.IN_STOCK,
    freshness=FreshnessStatus.RECENTLY_UPDATED,
    last_synced=None,
    sku=None,
):
    """Create a ShopProduct + Inventory + InventoryMovement row and push it
    through the REAL search indexer (what the Celery task runs).

    ``sku`` is ``None`` by default so the indexer falls back to the product's
    EAN identifier as the scanned barcode (production barcode-scan path)."""
    sp = ShopProduct(
        shop_id=shop.id,
        product_master_id=product.id,
        sku=sku,
        status=ShopProductStatus.ACTIVE,
        price=price,
        mrp=mrp if mrp is not None else price,
        is_active=True,
        is_available=is_available,
        is_visible=True,
        stock_status=stock_status,
        source=InventorySource.MANUAL,
        last_inventory_update=last_synced or datetime.now(timezone.utc),
    )
    db.add(sp)
    db.flush()

    inv = Inventory(
        shop_product_id=sp.id,
        quantity=quantity,
        reserved_quantity=0,
        available_quantity=quantity if is_available else 0,
        is_available=is_available,
        stock_status=stock_status,
        low_stock_threshold=5,
        last_updated_source=InventorySource.MANUAL,
        last_synced_at=last_synced or datetime.now(timezone.utc),
        freshness_status=freshness,
        freshness_checked_at=last_synced or datetime.now(timezone.utc),
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
            source=InventorySource.MANUAL,
            reference_type="MANUAL",
        )
    )
    db.flush()

    from app.search.indexer import upsert_shop_product

    upsert_shop_product(db, sp.id)
    db.flush()
    return sp, inv
def _seed_world(db):
    """Build the production-like Patna dataset used by every flow test."""
    groceries = _make_category(db, "Groceries", "groceries")
    beverages = _make_category(db, "Beverages", "beverages")
    personal_care = _make_category(db, "Personal Care", "personal-care")

    annapurna = _make_brand(db, "Annapurna", "annapurna")
    coca_cola = _make_brand(db, "Coca-Cola", "coca-cola")
    pepsico = _make_brand(db, "PepsiCo", "pepsico")
    dettol = _make_brand(db, "Dettol", "dettol")
    parle = _make_brand(db, "Parle", "parle")
    abbott = _make_brand(db, "Abbott", "abbott")

    basmati = _make_product(
        db,
        name="Basmati Rice 1kg",
        slug="basmati-rice-1kg",
        brand=annapurna,
        category=groceries,
        barcode="8901010101010",
        description="Premium long grain basmati rice",
    )
    coke = _make_product(
        db,
        name="Coca-Cola 750ml",
        slug="coca-cola-750ml",
        brand=coca_cola,
        category=beverages,
        barcode="8901020202020",
    )
    pepsi = _make_product(
        db,
        name="Pepsi Black 750ml",
        slug="pepsi-black-750ml",
        brand=pepsico,
        category=beverages,
        barcode="8901030303030",
    )
    dettol_wash = _make_product(
        db,
        name="Dettol Handwash 500ml",
        slug="dettol-handwash-500ml",
        brand=dettol,
        category=personal_care,
        barcode="8901040404040",
    )
    parle_g = _make_product(
        db,
        name="Parle-G Biscuit 400g",
        slug="parle-g-biscuit-400g",
        brand=parle,
        category=groceries,
        barcode="8901050505050",
    )
    horlicks = _make_product(
        db,
        name="Horlicks 500g",
        slug="horlicks-500g",
        brand=abbott,
        category=groceries,
        barcode="8901060606060",
        description="Malted milk food drink powder",
    )

    corner = _make_shop(
        db,
        name="Patna Corner Store",
        slug="patna-corner-store",
        lat=25.6000,
        lng=85.1400,
        rating=4.5,
    )
    boring = _make_shop(
        db,
        name="Boring Road SuperMart",
        slug="boring-road-supermart",
        lat=25.6136,
        lng=85.1440,
        rating=4.2,
    )
    gandhi = _make_shop(
        db,
        name="Gandhi Maidan Medicas",
        slug="gandhi-maidan-medicas",
        category=ShopCategory.PHARMACY,
        lat=PATNA_LAT,
        lng=PATNA_LNG,
        rating=3.8,
    )
    far = _make_shop(
        db,
        name="Far Flung Mall",
        slug="far-flung-mall",
        lat=25.5000,
        lng=86.0000,
        rating=4.9,
    )

    NOW = datetime.now(timezone.utc)
    stale_cutoff = NOW - timedelta(days=3)

    # Basmati Rice — listed in 3 nearby shops (price ladder) + 1 far shop.
    _seed_listing(db, product=basmati, shop=corner, price=145.0, mrp=165.0, quantity=10)
    _seed_listing(db, product=basmati, shop=boring, price=139.0, mrp=165.0, quantity=20)
    _seed_listing(
        db,
        product=basmati,
        shop=gandhi,
        price=155.0,
        mrp=165.0,
        quantity=0,
        is_available=True,
        stock_status=StockStatus.OUT_OF_STOCK,
    )
    _seed_listing(db, product=basmati, shop=far, price=120.0, mrp=160.0, quantity=5)

    # Beverages.
    _seed_listing(db, product=coke, shop=corner, price=45.0, mrp=50.0, quantity=8)
    _seed_listing(db, product=coke, shop=boring, price=42.0, mrp=50.0, quantity=3)
    _seed_listing(db, product=pepsi, shop=boring, price=60.0, mrp=68.0, quantity=4)

    # Personal care.
    _seed_listing(db, product=dettol_wash, shop=gandhi, price=98.0, mrp=110.0, quantity=10)

    # Parle-G: one STALE entry (corner, still in stock) + one unavailable (boring).
    _seed_listing(
        db,
        product=parle_g,
        shop=corner,
        price=20.0,
        mrp=25.0,
        quantity=40,
        freshness=FreshnessStatus.STALE,
        last_synced=stale_cutoff,
    )
    _seed_listing(
        db,
        product=parle_g,
        shop=boring,
        price=22.0,
        mrp=25.0,
        quantity=0,
        is_available=False,
        stock_status=StockStatus.OUT_OF_STOCK,
    )

    # Horlicks — single-word product name in two nearby shops (typo-tolerance
    # scenario: pg_trgm similarity works on short product names).
    _seed_listing(db, product=horlicks, shop=corner, price=210.0, mrp=240.0, quantity=6)
    _seed_listing(db, product=horlicks, shop=boring, price=205.0, mrp=240.0, quantity=9)

    db.commit()

    return {
        "groceries": groceries,
        "beverages": beverages,
        "personal_care": personal_care,
        "annapurna": annapurna,
        "coca_cola": coca_cola,
        "pepsico": pepsico,
        "dettol": dettol,
        "parle": parle,
        "abbott": abbott,
        "basmati": basmati,
        "coke": coke,
        "pepsi": pepsi,
        "dettol_wash": dettol_wash,
        "parle_g": parle_g,
        "horlicks": horlicks,
        "corner": corner,
        "boring": boring,
        "gandhi": gandhi,
        "far": far,
    }


# ── Small runner helper for the real engine ─────────────────────────────────
def run_search(world, **overrides):
    """Run the REAL ``search_products`` engine against the seeded world."""
    from app.search.engine import SearchParams, search_products

    params = SearchParams(
        q="",
        latitude=PATNA_LAT,
        longitude=PATNA_LNG,
        radius_km=10.0,
        sort="relevance",
        page=1,
        limit=50,
    )
    for key, value in overrides.items():
        setattr(params, key, value)
    return search_products(world.db, params)


# ═══════════════════════════════════════════════════════════════════════════
# 1. Search-index build (shopkeeper publish → index)
# ═══════════════════════════════════════════════════════════════════════════
def test_indexer_built_all_search_entries(world):
    """Every seeded shop-product must exist in the search index with geo data."""
    from app.models.search import SearchIndex, SearchIndexEntityType  # noqa: F811 - re-import mirrors module import

    entries = (
        world.db.query(SearchIndex)
        .filter(SearchIndex.entity_type == SearchIndexEntityType.SHOP_PRODUCT)
        .all()
    )
    assert len(entries) == 12
    for entry in entries:
        assert entry.is_synced is True
        assert entry.is_product_searchable is True
        assert entry.is_shop_visible is True
        assert entry.latitude is not None and entry.longitude is not None
        assert str(entry.location).startswith("POINT(")
        assert entry.price is not None
        assert entry.stock_status in {"IN_STOCK", "OUT_OF_STOCK"}


# ═══════════════════════════════════════════════════════════════════════════
# 2. Exact product
# ═══════════════════════════════════════════════════════════════════════════
def test_exact_product_search(world):
    """Searching the exact product name returns the matching shop products only."""
    result = run_search(world, q="Basmati Rice 1kg")
    assert result["total"] == 3
    shops = {r["shop_id"] for r in result["results"]}
    assert shops == {world.corner.id, world.boring.id, world.gandhi.id}
    assert world.far.id not in shops  # outside the geo radius
    for r in result["results"]:
        assert r["product_id"] == world.basmati.id
        assert r["product_name"] == "Basmati Rice 1kg"


def test_partial_prefix_search(world):
    """A partial prefix must surface the product from every nearby shop."""
    result = run_search(world, q="basma")
    assert result["total"] == 3
    assert {r["product_name"] for r in result["results"]} == {"Basmati Rice 1kg"}


def test_partial_fuzzy_search(world):
    """Typo-tolerant search (pg_trgm stand-in) must surface a single-word
    product name even with a transposed letter (real pg_trgm semantics)."""
    result = run_search(world, q="horlics")
    assert result["total"] == 2
    assert {r["product_name"] for r in result["results"]} == {"Horlicks 500g"}


# ═══════════════════════════════════════════════════════════════════════════
# 4. Category
# ═══════════════════════════════════════════════════════════════════════════
def test_category_filter(world):
    """Filtering by category returns only that category's shop products."""
    result = run_search(world, q="", category_id=world.beverages.id)
    assert result["total"] == 3  # coke x2 + pepsi x1
    assert {r["category_name"] for r in result["results"]} == {"Beverages"}
    assert {r["product_id"] for r in result["results"]} == {world.coke.id, world.pepsi.id}


def test_category_keyword_search(world):
    """Typing a category keyword discovers every product in it."""
    result = run_search(world, q="beverages")
    assert result["total"] == 3
    assert {r["category_name"] for r in result["results"]} == {"Beverages"}


# ═══════════════════════════════════════════════════════════════════════════
# 5. Brand
# ═══════════════════════════════════════════════════════════════════════════
def test_brand_filter(world):
    """Filtering by brand returns only that brand's shop products."""
    result = run_search(world, q="", brand_id=world.annapurna.id)
    assert result["total"] == 3  # basmati at three nearby shops
    assert {r["brand_name"] for r in result["results"]} == {"Annapurna"}


def test_brand_keyword_search(world):
    """Typing a brand keyword discovers its products (normalized text match)."""
    result = run_search(world, q="coca cola")
    assert result["total"] == 2  # coke at corner + boring
    assert {r["product_id"] for r in result["results"]} == {world.coke.id}
# ═══════════════════════════════════════════════════════════════════════════
# 6. Price
# ═══════════════════════════════════════════════════════════════════════════
def test_price_filter_min_max(world):
    """Price bounds return only shop products inside the range."""
    result = run_search(world, q="basmati", min_price=140.0, max_price=160.0)
    assert result["total"] == 2  # corner 145 + gandhi 155; boring 139 excluded
    prices = {r["price"] for r in result["results"]}
    assert prices == {145.0, 155.0}

    result_low = run_search(world, q="basmati", max_price=140.0)
    assert result_low["total"] == 1
    assert result_low["results"][0]["price"] == 139.0


# ═══════════════════════════════════════════════════════════════════════════
# 7. Availability
# ═══════════════════════════════════════════════════════════════════════════
def test_availability_status_is_returned(world):
    """Stock status must be surfaced on every result (incl. out-of-stock)."""
    result = run_search(world, q="basmati")
    by_shop = {r["shop_id"]: r for r in result["results"]}
    assert by_shop[world.gandhi.id]["stock_status"] == "OUT_OF_STOCK"
    assert by_shop[world.corner.id]["stock_status"] == "IN_STOCK"
    assert by_shop[world.boring.id]["stock_status"] == "IN_STOCK"


def test_in_stock_filter_hides_out_of_stock(world):
    """in_stock_only=True must drop every OUT_OF_STOCK shop product."""
    result = run_search(world, q="basmati", in_stock_only=True)
    assert result["total"] == 2
    assert {r["shop_id"] for r in result["results"]} == {world.corner.id, world.boring.id}


def test_exclude_unavailable_hides_unavailable_listings(world):
    """exclude_unavailable=True must drop listings with is_available=False."""
    default = run_search(world, q="parle")
    assert default["total"] == 2

    filtered = run_search(world, q="parle", exclude_unavailable=True)
    assert filtered["total"] == 1
    assert filtered["results"][0]["shop_id"] == world.corner.id


# ═══════════════════════════════════════════════════════════════════════════
# 8. Distance (PostGIS ST_DWithin / ST_Distance)
# ═══════════════════════════════════════════════════════════════════════════
def test_distance_returned_matches_haversine(world):
    """distance_km must match the real geodesic distance to each shop."""
    from app.services.geo_service import haversine_km

    result = run_search(world, q="basmati")
    by_shop = {r["shop_id"]: r for r in result["results"]}
    for shop, r in (
        (world.corner, by_shop[world.corner.id]),
        (world.boring, by_shop[world.boring.id]),
        (world.gandhi, by_shop[world.gandhi.id]),
    ):
        expected = round(haversine_km(PATNA_LAT, PATNA_LNG, shop.latitude, shop.longitude), 2)
        assert r["distance_km"] == pytest.approx(expected, abs=0.02)


def test_radius_filter_excludes_distant_shops(world):
    """ST_DWithin must exclude shops beyond the customer's radius."""
    tight = run_search(world, q="basmati", radius_km=1.0)
    # gandhi (~0.0 km) + corner (~0.7 km); boring (~2.2 km) and far (~87 km) gone
    assert tight["total"] == 2
    assert {r["shop_id"] for r in tight["results"]} == {world.gandhi.id, world.corner.id}

    default = run_search(world, q="basmati", radius_km=10.0)
    assert world.far.id not in {r["shop_id"] for r in default["results"]}

    huge = run_search(world, q="basmati", radius_km=100.0)
    assert world.far.id in {r["shop_id"] for r in huge["results"]}


def test_nearby_shops_postgis_engine(world):
    """The PostGIS nearby-shops query (engine.nearby_shops) ranks by distance."""
    from app.search.engine import nearby_shops

    result = nearby_shops(
        world.db,
        latitude=PATNA_LAT,
        longitude=PATNA_LNG,
        radius_km=10.0,
    )
    assert result["total"] >= 1
    distances = [s["distance_km"] for s in result["shops"]]
    assert distances == sorted(distances)
    for shop in result["shops"]:
        assert shop["latitude"] is not None and shop["longitude"] is not None


def test_nearby_shops_service_route(world):
    """The customer nearby-shops service returns verified shops with distance."""
    from app.services.shop_service import nearby_shops

    shops = nearby_shops(world.db, latitude=PATNA_LAT, longitude=PATNA_LNG, radius_km=10.0)
    shop_ids = {s["id"] for s in shops}
    assert {world.corner.id, world.boring.id, world.gandhi.id} <= shop_ids
    assert world.far.id not in shop_ids
    distances = [s["distance_km"] for s in shops]
    assert distances == sorted(distances)
# ═══════════════════════════════════════════════════════════════════════════
# 9. Sorting
# ═══════════════════════════════════════════════════════════════════════════
def test_sort_by_distance(world):
    """sort=distance must order results nearest → farthest."""
    result = run_search(world, q="basmati", sort="distance")
    order = [(r["shop_id"], r["distance_km"]) for r in result["results"]]
    assert order[0][0] == world.gandhi.id  # same coordinates as the customer
    assert [d for _, d in order] == sorted(d for _, d in order)


def test_sort_by_price_asc_and_desc(world):
    """sort=price_asc / price_desc must order by the shop-product price."""
    asc = run_search(world, q="basmati", sort="price_asc")
    assert [r["price"] for r in asc["results"]] == [139.0, 145.0, 155.0]

    desc = run_search(world, q="basmati", sort="price_desc")
    assert [r["price"] for r in desc["results"]] == [155.0, 145.0, 139.0]


def test_sort_by_rating(world):
    """sort=rating must order by shop rating, highest first."""
    result = run_search(world, q="basmati", sort="rating")
    assert [r["shop_id"] for r in result["results"]] == [
        world.corner.id,  # 4.5
        world.boring.id,  # 4.2
        world.gandhi.id,  # 3.8
    ]
# ═══════════════════════════════════════════════════════════════════════════
# 10. Filtering (combined)
# ═══════════════════════════════════════════════════════════════════════════
def test_combined_filters_and_sort(world):
    """Category + price + availability can be combined and sorted."""
    result = run_search(
        world,
        q="basmati",
        category_id=world.groceries.id,
        in_stock=True,
        max_price=150.0,
        sort="price_asc",
    )
    assert result["total"] == 2
    assert [r["price"] for r in result["results"]] == [139.0, 145.0]
    assert [r["shop_id"] for r in result["results"]] == [world.boring.id, world.corner.id]


def test_filtering_by_brand_and_category_together(world):
    """Brand + category together narrow the result set to the intersection."""
    result = run_search(world, q="", category_id=world.beverages.id, brand_id=world.pepsico.id)
    assert result["total"] == 1
    assert result["results"][0]["product_id"] == world.pepsi.id


# ═══════════════════════════════════════════════════════════════════════════
# 11. No results
# ═══════════════════════════════════════════════════════════════════════════
def test_no_results_query(world):
    """A nonsense query must return an empty, well-formed response."""
    result = run_search(world, q="zzzzqqqq unicorn dust")
    assert result["total"] == 0
    assert result["results"] == []
    assert result["has_more"] is False


def test_no_results_for_nonexistent_category(world):
    """Filtering against an empty slice must return nothing."""
    result = run_search(world, q="", category_id=999999)
    assert result["total"] == 0
    assert result["results"] == []


# ═══════════════════════════════════════════════════════════════════════════
# 12. Stale inventory
# ═══════════════════════════════════════════════════════════════════════════
def test_stale_inventory_is_flagged(world):
    """STALE freshness must be surfaced so customers can tell data is old."""
    result = run_search(world, q="parle")
    stale = [r for r in result["results"] if r["shop_id"] == world.corner.id]
    assert len(stale) == 1
    assert stale[0]["freshness_status"] == "STALE"
    assert stale[0]["is_available"] is True  # stale ≠ unavailable
    assert stale[0]["last_inventory_update"] is not None


def test_stale_inventory_can_be_excluded(world):
    """exclude_stale=True must drop STALE entries from discovery."""
    default = run_search(world, q="parle")
    assert default["total"] == 2

    fresh = run_search(world, q="parle", exclude_stale=True)
    assert fresh["total"] == 1
    assert fresh["results"][0]["freshness_status"] != "STALE"
# ═══════════════════════════════════════════════════════════════════════════
# 13. Multiple shops (price/availability comparison)
# ═══════════════════════════════════════════════════════════════════════════
def test_multiple_shops_for_same_product(world):
    """One product can be offered by several nearby shops with distinct prices."""
    result = run_search(world, q="Basmati Rice 1kg")
    assert len(result["results"]) == 3
    assert len({r["shop_id"] for r in result["results"]}) == 3
    prices = {r["price"] for r in result["results"]}
    assert prices == {139.0, 145.0, 155.0}
    for r in result["results"]:
        assert r["mrp"] is not None
        assert r["price"] <= r["mrp"]
        assert r["is_available"] is not None


# ═══════════════════════════════════════════════════════════════════════════
# 14. Result contract — PRODUCT + SHOP + PRICE + AVAILABILITY + DISTANCE
# ═══════════════════════════════════════════════════════════════════════════
def test_search_result_contract_product_shop_price_availability_distance(world):
    """Every result must carry the full business payload for one result row."""
    required = {
        "product_id", "product_name", "brand_name", "category_name",
        "shop_id", "shop_name", "shop_rating",
        "price", "mrp",
        "is_available", "stock_status", "freshness_status",
        "distance_km", "relevance_score",
    }
    result = run_search(world, q="Basmati Rice 1kg")
    assert result["total"] >= 1
    for r in result["results"]:
        assert required <= set(r.keys())
        assert r["product_id"] is not None
        assert r["shop_id"] is not None
        assert r["price"] is not None
        assert r["is_available"] is not None
        assert r["distance_km"] is not None
# ═══════════════════════════════════════════════════════════════════════════
# 15. Barcode lookup
# ═══════════════════════════════════════════════════════════════════════════
def test_barcode_lookup_finds_product_across_shops(world):
    """Scanning a barcode must resolve the product across nearby shops."""
    from app.search.engine import barcode_lookup

    matches = barcode_lookup(
        world.db,
        "8901010101010",
        latitude=PATNA_LAT,
        longitude=PATNA_LNG,
    )
    assert len(matches) == 3
    for m in matches:
        assert m["product_name"] == "Basmati Rice 1kg"
        assert m["price"] is not None
        assert m["distance_km"] is not None


def test_barcode_lookup_unknown(world):
    from app.search.engine import barcode_lookup

    assert barcode_lookup(world.db, "9999999999999") == []
# ═══════════════════════════════════════════════════════════════════════════
# 16. HTTP — full customer business flow (steps 1 → 10)
# ═══════════════════════════════════════════════════════════════════════════
def _make_http_client(db):
    """FastAPI TestClient with the get_db dependency overridden to the world."""
    from fastapi.testclient import TestClient

    from app.database.session import get_db
    from app.main import app

    app.dependency_overrides[get_db] = lambda: db
    return TestClient(app)


def test_http_customer_business_flow_end_to_end(world):
    """The complete customer journey over the real HTTP API.

    Steps verified:
      1. Customer selects a real location (locations/manual-search)
      2. Customer searches a real product (search/v2/products)
      3–5. Backend finds matching shop products within the geo radius
      6. Pricing returned        7. Availability returned
      8. Results sorted/filtered  9. Customer opens the shop
     10. Customer gets directions (coordinates + distance)
    """
    from app.main import app
    from app.services.geo_service import haversine_km

    client = _make_http_client(world.db)
    try:
        # ── Step 1: select a real location ─────────────────────────────
        resp = client.get("/api/v1/locations/manual-search", params={"q": "patna"})
        assert resp.status_code == 200
        locations = resp.json()["data"]
        assert locations, "location search returned no results"
        location = locations[0]
        assert location["city"] == "Patna"
        assert location["latitude"] == pytest.approx(PATNA_LAT, abs=1e-6)
        assert location["longitude"] == pytest.approx(PATNA_LNG, abs=1e-6)

        # ── Steps 2–8: search the product with geo + sort ──────────────
        resp = client.get(
            "/api/v1/search/v2/products",
            params={
                "q": "Basmati Rice 1kg",
                "latitude": PATNA_LAT,
                "longitude": PATNA_LNG,
                "radius_km": 10,
                "sort": "distance",
            },
        )
        assert resp.status_code == 200
        body = resp.json()
        assert body["success"] is True
        data = body["data"]
        assert data["total"] == 3
        results = data["results"]

        # Step 3–5 — matching shop products + PostGIS proximity
        shop_ids = {r["shop_id"] for r in results}
        assert shop_ids == {world.corner.id, world.boring.id, world.gandhi.id}
        distances = [r["distance_km"] for r in results]
        assert distances == sorted(distances)
        for r in results:
            assert r["distance_km"] is not None

        # Step 6 — pricing
        prices = sorted(r["price"] for r in results)
        assert prices == [139.0, 145.0, 155.0]
        for r in results:
            assert r["mrp"] >= r["price"]

        # Step 7 — availability
        stock = {r["shop_id"]: r["stock_status"] for r in results}
        assert stock[world.gandhi.id] == "OUT_OF_STOCK"
        assert stock[world.corner.id] == "IN_STOCK"
        assert all(r["is_available"] in (True, False) for r in results)

        # Step 8 — filtering (in-stock only over the same URL params)
        resp = client.get(
            "/api/v1/search/v2/products",
            params={
                "q": "Basmati Rice 1kg",
                "latitude": PATNA_LAT,
                "longitude": PATNA_LNG,
                "in_stock": True,
            },
        )
        assert resp.status_code == 200
        filtered_ids = {r["shop_id"] for r in resp.json()["data"]["results"]}
        assert filtered_ids == {world.corner.id, world.boring.id}

        # ── Step 9: open the shop ───────────────────────────────────────
        resp = client.get(
            f"/api/v1/shops/{world.corner.id}",
            params={"latitude": PATNA_LAT, "longitude": PATNA_LNG},
        )
        assert resp.status_code == 200
        shop = resp.json()["data"]
        assert shop["id"] == world.corner.id
        assert shop["name"] == "Patna Corner Store"
        assert any(p["name"] == "Basmati Rice 1kg" for p in shop["available_products"])

        # ── Step 10: directions (coordinates + distance to the shop) ─────
        assert shop["latitude"] == pytest.approx(world.corner.latitude, abs=1e-6)
        assert shop["longitude"] == pytest.approx(world.corner.longitude, abs=1e-6)
        expected = round(
            haversine_km(PATNA_LAT, PATNA_LNG, world.corner.latitude, world.corner.longitude),
            2,
        )
        assert shop["distance_km"] == pytest.approx(expected, abs=0.02)
    finally:
        app.dependency_overrides.clear()