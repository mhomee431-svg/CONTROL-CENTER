"""Phase 20 — Search & Geo-Discovery Engine tests.

Covers:
- Exact product search
- Partial search
- Brand search
- Category search
- Barcode lookup
- Nearby shops
- Distance calculation
- Filters
- Sorting
- Pagination
- Search index synchronization
- Inventory freshness
- Search event recording
- Popular-search aggregation
"""

import os
import sys
from datetime import datetime, timezone
from pathlib import Path

BACKEND_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BACKEND_DIR))

os.environ.setdefault("ENVIRONMENT", "test")
os.environ.setdefault("HYPERLOCAL_ENV", "test")

import pytest  # noqa: E402

from app.core.config import settings  # noqa: E402
settings.RATE_LIMIT_ENABLED = False


# ── Model tests ─────────────────────────────────────────────────────────────
def test_search_index_model_exists():
    """SearchIndex model must be importable with all fields."""
    from app.models.search import SearchIndex, SearchIndexEntityType

    assert SearchIndex is not None
    assert hasattr(SearchIndex, "search_text")
    assert hasattr(SearchIndex, "search_vector")
    assert hasattr(SearchIndex, "barcode")
    assert hasattr(SearchIndex, "sku")
    assert hasattr(SearchIndex, "product_name")
    assert hasattr(SearchIndex, "brand_name")
    assert hasattr(SearchIndex, "category_name")
    assert hasattr(SearchIndex, "price")
    assert hasattr(SearchIndex, "is_available")
    assert hasattr(SearchIndex, "stock_status")
    assert hasattr(SearchIndex, "freshness_status")
    assert hasattr(SearchIndex, "location")

    # Enum values
    values = {e.value for e in SearchIndexEntityType}
    assert "SHOP_PRODUCT" in values
    assert "PRODUCT" in values
    assert "SHOP" in values
    assert "BRAND" in values
    assert "CATEGORY" in values


def test_search_index_model_has_geo():
    """SearchIndex must have PostGIS location for nearby search.

    Geo columns are stripped to Text by some SQLite fixture modules on the
    *shared* metadata, so assert against the pristine declared type via the
    reversible geo-compat registry (order-independent).
    """
    from app.models.search import SearchIndex
    from tests.geo_compat import declared_type

    table = SearchIndex.__table__
    if "location" not in table.columns:
        pytest.fail("SearchIndex has no location column")
    declared = declared_type(table.name, "location")
    assert declared is not None and "Geography" in type(declared).__name__, (
        f"SearchIndex.location should be a Geography column, got {type(declared).__name__}"
    )


def test_search_index_sync_model():
    """SearchIndexSync model must exist."""
    from app.models.search import SearchIndexSync, SearchIndexSyncStatus

    assert SearchIndexSync is not None
    assert hasattr(SearchIndexSync, "sync_type")
    assert hasattr(SearchIndexSync, "status")
    assert hasattr(SearchIndexSync, "total_created")
    assert hasattr(SearchIndexSync, "total_updated")

    values = {e.value for e in SearchIndexSyncStatus}
    assert "RUNNING" in values
    assert "COMPLETED" in values
    assert "FAILED" in values


def test_search_models_import_all():
    """All search models must be importable."""
    from app.models import (
        SearchIndex,
        SearchIndexSync,
        SearchHistory,
        SearchEvent,
        PopularSearch,
        BarcodeScan,
    )

    assert SearchIndex is not None
    assert SearchIndexSync is not None
    assert SearchHistory is not None
    assert SearchEvent is not None
    assert PopularSearch is not None
    assert BarcodeScan is not None


def test_search_event_has_shop_product_id():
    """SearchEvent must track clicked_shop_product_id for analytics."""
    from app.models.search import SearchEvent

    assert hasattr(SearchEvent, "clicked_shop_product_id")


# ── Schema tests ────────────────────────────────────────────────────────────
def test_search_schemas():
    """All search schemas must be importable."""
    from app.schemas.search import (
        SearchResultSchema,
        SearchResponse,
        SuggestionSchema,
        NearbyShopResponseSchema,
        NearbyShopsResponse,
        PopularSearchSchema,
        SearchHistorySchema,
        BarcodeResultSchema,
        SearchSuggestionSchema,
        ShopProductResultSchema,
    )

    assert SearchResultSchema is not None
    assert SearchResponse is not None
    assert SuggestionSchema is not None
    assert NearbyShopResponseSchema is not None
    assert NearbyShopsResponse is not None
    assert PopularSearchSchema is not None
    assert SearchHistorySchema is not None
    assert BarcodeResultSchema is not None
    assert SearchSuggestionSchema is not None
    assert ShopProductResultSchema is not None


def test_search_result_schema_fields():
    """SearchResultSchema must include distance, freshness, price."""
    from app.schemas.search import SearchResultSchema

    fields = SearchResultSchema.model_fields
    assert "distance_km" in fields
    assert "freshness_status" in fields
    assert "price" in fields
    assert "mrp" in fields
    assert "is_available" in fields
    assert "stock_status" in fields
    assert "relevance_score" in fields


# ── Normalizer tests ────────────────────────────────────────────────────────
def test_normalize_text():
    """normalize_text should lowercase, accent-fold, strip punctuation."""
    from app.search.normalizer import normalize_text

    assert normalize_text("Coca-Cola!") == "coca cola"
    assert normalize_text("  Hello   World  ") == "hello world"
    assert normalize_text("Café") == "cafe"
    assert normalize_text("") == ""


def test_tokenize():
    """tokenize should remove stop words and short tokens."""
    from app.search.normalizer import tokenize

    assert tokenize("the quick brown fox") == ["quick", "brown", "fox"]
    assert tokenize("a b c") == []


def test_build_search_text():
    """build_search_text concatenates normalized fields."""
    from app.search.normalizer import build_search_text

    result = build_search_text("Lays Classic", brand="PepsiCo", category="Snacks", sku="SKU123")
    assert "lays" in result
    assert "classic" in result
    assert "pepsico" in result
    assert "snacks" in result
    assert "sku123" in result


def test_similarity_threshold():
    """similarity_threshold should scale with query length."""
    from app.search.normalizer import similarity_threshold

    assert similarity_threshold(3) == 0.5
    assert similarity_threshold(5) == 0.4
    assert similarity_threshold(7) == 0.3
    assert similarity_threshold(10) == 0.25


def test_is_barcode_query():
    """is_barcode_query detects numeric barcode patterns."""
    from app.search.normalizer import is_barcode_query

    assert is_barcode_query("8901234567890") is True
    assert is_barcode_query("12345") is False
    assert is_barcode_query("ABCDEF") is False


# ── Ranking tests ───────────────────────────────────────────────────────────
def test_compute_relevance_score():
    """compute_relevance_score should weight correctly."""
    from app.search.ranking import compute_relevance_score, RELEVANCE_WEIGHTS

    score = compute_relevance_score(
        text_match_score=1.0,
        is_available=True,
        is_in_stock=True,
        distance_km=1.0,
        shop_rating=4.5,
        freshness_status="RECENTLY_UPDATED",
        popularity_score=0.5,
    )
    assert score > 50  # strong overall

    # Fresh history should beat stale
    fresh_score = compute_relevance_score(freshness_status="RECENTLY_UPDATED")
    stale_score = compute_relevance_score(freshness_status="STALE")
    assert fresh_score > stale_score


def test_text_match_score():
    """text_match_score should reflect token matching."""
    from app.search.ranking import text_match_score

    assert text_match_score(["lays"], "lays classic") == 1.0
    assert text_match_score(["lays"], "kurkure") == 0.0
    assert text_match_score([], "anything") == 1.0  # empty query


def test_default_sort_key():
    """default_sort_key should sort by expected modes."""
    from app.search.ranking import default_sort_key, SearchSort

    items = [
        {"distance_km": 5.0, "price": 50, "shop_rating": 3.5, "is_available": True, "freshness_status": "RECENTLY_UPDATED", "relevance_score": 60.0},
        {"distance_km": 1.0, "price": 30, "shop_rating": 4.8, "is_available": True, "freshness_status": "STALE", "relevance_score": 80.0},
        {"distance_km": 3.0, "price": 10, "shop_rating": 4.0, "is_available": False, "freshness_status": "RECENTLY_UPDATED", "relevance_score": 40.0},
    ]

    # Distance sort
    sorted_dist = sorted(items, key=default_sort_key(SearchSort.DISTANCE))
    assert sorted_dist[0]["distance_km"] == 1.0

    # Price asc
    sorted_price = sorted(items, key=default_sort_key(SearchSort.PRICE_ASC))
    assert sorted_price[0]["price"] == 10

    # Relevance
    sorted_rel = sorted(items, key=default_sort_key(SearchSort.RELEVANCE))
    assert sorted_rel[0]["relevance_score"] == 80.0


# ── Search engine module tests ─────────────────────────────────────────────
def test_search_engine_importable():
    """Search engine must be importable."""
    from app.search.engine import (
        SearchParams,
        search_products,
        nearby_shops,
        search_suggestions,
        barcode_lookup,
        popular_searches,
        search_history,
        record_search,
        record_search_event,
        aggregate_popular_searches,
    )

    assert SearchParams is not None
    assert callable(search_products)
    assert callable(nearby_shops)
    assert callable(search_suggestions)
    assert callable(barcode_lookup)
    assert callable(popular_searches)
    assert callable(search_history)
    assert callable(record_search)
    assert callable(record_search_event)
    assert callable(aggregate_popular_searches)


def test_search_params_defaults():
    """SearchParams should have sensible defaults."""
    from app.search.engine import SearchParams

    params = SearchParams()
    assert params.q == ""
    assert params.radius_km == 10.0
    assert params.page == 1
    assert params.limit == 20
    assert params.sort == "relevance"


def test_search_params_strips_query():
    """SearchParams should strip whitespace from query."""
    from app.search.engine import SearchParams

    params = SearchParams(q="  lays  ")
    assert params.q == "lays"


def test_resolve_sort():
    """_resolve_sort should map aliases."""
    from app.search.engine import _resolve_sort
    from app.search.ranking import SearchSort

    assert _resolve_sort("nearest") == SearchSort.DISTANCE
    assert _resolve_sort("lowest_price") == SearchSort.PRICE_ASC
    assert _resolve_sort("highest_rated") == SearchSort.RATING
    assert _resolve_sort("recently_updated") == SearchSort.FRESHNESS
    assert _resolve_sort("offers") == SearchSort.OFFERS
    assert _resolve_sort("unknown") == SearchSort.RELEVANCE


# ── Indexer tests ───────────────────────────────────────────────────────────
def test_indexer_importable():
    """Search indexer must be importable."""
    from app.search.indexer import (
        build_shop_product_index,
        upsert_shop_product,
        full_rebuild,
        incremental_sync,
    )

    assert callable(build_shop_product_index)
    assert callable(upsert_shop_product)
    assert callable(full_rebuild)
    assert callable(incremental_sync)


def test_customer_stock_mapping():
    """_customer_stock should map internal to customer-facing."""
    from app.search.indexer import _customer_stock

    assert _customer_stock("IN_STOCK") == "IN_STOCK"
    assert _customer_stock("LOW_STOCK") == "LIMITED_STOCK"
    assert _customer_stock("LIMITED_STOCK") == "LIMITED_STOCK"
    assert _customer_stock("OUT_OF_STOCK") == "OUT_OF_STOCK"
    assert _customer_stock("PRE_ORDER") == "UNKNOWN"


# ── API route tests ─────────────────────────────────────────────────────────
def test_search_router_v2_routes_exist():
    """Search router must expose all v2 discovery endpoints."""
    from app.api.routes.search import router

    paths = {r.path for r in router.routes}
    assert "/search/v2/products" in paths
    assert "/search/v2/nearby-shops" in paths
    assert "/search/v2/suggestions" in paths
    assert "/search/v2/popular" in paths
    assert "/search/v2/history" in paths
    assert "/search/v2/barcodes/{barcode}" in paths
    assert "/search/v2/events" in paths
    assert "/search/v2/index/rebuild" in paths
    assert "/search/v2/index/sync" in paths
    assert "/search/v2/index/status" in paths


def test_search_router_registered_in_main():
    """Search router should be registered in main app."""
    from app.main import app

    # Verify there are routes
    included = [r for r in app.routes if type(r).__name__ == "_IncludedRouter"]
    assert len(included) > 0

    from app.api.routes.search import router
    assert len(router.routes) > 0


def test_search_uses_postgis():
    """Search engine should use PostGIS functions."""
    import inspect
    from app.search import engine

    source = inspect.getsource(engine)
    assert "ST_DWithin" in source
    assert "ST_Distance" in source
    assert "ST_GeogFromText" in source


def test_search_uses_trigram():
    """Search engine should use pg_trgm for typo tolerance."""
    import inspect

    from app.search import engine

    source = inspect.getsource(engine)
    assert "similarity" in source or "trgm" in source.lower()


def test_search_uses_inventory_service():
    """Search engine should use inventory service for offers."""
    import inspect

    from app.search import engine

    source = inspect.getsource(engine)
    assert "get_offer_text_for_shop_product" in source


def test_search_has_record_functions():
    """Search engine must have event/history recording functions."""
    import inspect

    from app.search import engine

    source = inspect.getsource(engine)
    assert "record_search" in source
    assert "record_search_event" in source
    assert "aggregate_popular_searches" in source


# ── Celery task tests ───────────────────────────────────────────────────────
def test_search_tasks_defined():
    """Search-related Celery tasks should be defined."""
    from app.services.tasks import (
        index_shop_product,
        index_product,
        index_shop,
        sync_search_index,
        full_rebuild_search_index,
        aggregate_popular_searches_task,
    )

    assert callable(index_shop_product)
    assert callable(index_product)
    assert callable(index_shop)
    assert callable(sync_search_index)
    assert callable(full_rebuild_search_index)
    assert callable(aggregate_popular_searches_task)


def test_celery_beat_schedule_has_search_sync():
    """Celery beat should include search-index sync tasks."""
    from app.core.celery_app import celery_app

    schedule = celery_app.conf.beat_schedule
    assert "search-index-incremental-sync" in schedule
    assert "daily-popular-searches" in schedule


# ── Mock DB helpers for engine tests ───────────────────────────────────────
class MockEngineQuery:
    """Simplified query for SearchIndex-based tests."""

    def __init__(self, rows=None, total=0):
        self._rows = rows or []
        self._total = total

    def filter(self, *args, **kwargs):
        return self

    def add_columns(self, *args):
        return self

    def order_by(self, *args):
        return self

    def offset(self, *args):
        return self

    def limit(self, *args):
        return self

    def count(self):
        return self._total

    def all(self):
        return self._rows

    def first(self):
        return self._rows[0] if self._rows else None


class MockSearchIndexEntry:
    """Lightweight SearchIndex-like row for engine tests."""

    def __init__(self, **kwargs):
        defaults = {
            "id": 1,
            "entity_type": "SHOP_PRODUCT",
            "entity_id": 1,
            "product_id": 1,
            "shop_product_id": 1,
            "shop_id": 1,
            "brand_id": 1,
            "category_id": 1,
            "product_name": "Lays Classic",
            "brand_name": "PepsiCo",
            "category_name": "Snacks",
            "variant_name": None,
            "search_text": "lays classic pepsico snacks",
            "discovery_text": "lays classic pepsico snacks 8901234567890 sku123",
            "search_vector": "lays classic pepsico snacks",
            "barcode": "8901234567890",
            "sku": "SKU123",
            "is_product_searchable": True,
            "is_shop_visible": True,
            "price": 10.0,
            "mrp": 15.0,
            "is_available": True,
            "stock_status": "IN_STOCK",
            "freshness_status": "RECENTLY_UPDATED",
            "last_inventory_update": datetime.now(timezone.utc),
            "shop_name": "Neighbour Market",
            "shop_rating": 4.5,
            "shop_review_count": 100,
            "is_shop_accepting_orders": True,
            "location": None,
            "latitude": 25.5941,
            "longitude": 85.1376,
            "popularity_score": 0.5,
            "is_synced": True,
            "last_synced_at": datetime.now(timezone.utc),
        }
        defaults.update(kwargs)
        for k, v in defaults.items():
            setattr(self, k, v)


def test_search_products_returns_dict():
    """search_products should return a dict with results/pagination."""
    from app.search.engine import search_products, SearchParams

    db = MockDBEngine()
    params = SearchParams(q="lays", page=1, limit=10)
    result = search_products(db, params)

    assert "results" in result
    assert "total" in result
    assert "page" in result
    assert "limit" in result
    assert "has_more" in result


class MockDBEngine:
    """Minimal DB mock for engine-level tests."""

    def __init__(self, rows=None):
        self._rows = rows or [MockSearchIndexEntry()]

    def query(self, model):
        return MockEngineQuery(self._rows, total=len(self._rows))

    def add(self, obj):
        pass

    def flush(self):
        pass

    def commit(self):
        pass


# ── Barcode lookup test with mocks ─────────────────────────────────────────
def test_shop_offers_payload_includes_open_state():
    """Product-detail shop offers must carry open/closed, like search does.

    A customer comparing the same shop on the search page and the product page
    must not see two different answers about whether it is open.
    """
    from app.api.routes.products import _shop_offers_payload

    class _Shop:
        id = 7
        name = "Neighbour Market"
        image_url = None
        latitude = 25.5941
        longitude = 85.1376
        rating = 4.5
        is_accepting_orders = True

    class _Inv:
        stock_status = "IN_STOCK"
        is_available = True
        updated_at = None
        freshness_status = None

    class _SP:
        id = 11
        shop_id = 7
        price = 42.0
        mrp = 50.0
        last_inventory_update = None
        is_available = True
        inventory = _Inv()

    class _Product:
        id = 3

    class _DB:
        def query(self, model):
            return self

        def join(self, *a, **k):
            return self

        def options(self, *a, **k):
            return self

        def filter(self, *a, **k):
            return self

        def all(self):
            return [_SP()]

        def first(self):
            return _Shop()

    monkeypatched = {}

    import app.api.routes.products as products_module

    # The route computes open state through the canonical helper; stub it so the
    # test asserts plumbing rather than opening-hours parsing (covered elsewhere).
    original_is_shop_open = products_module.is_shop_open
    original_offer_text = products_module.get_offer_text_for_shop_product
    try:
        products_module.is_shop_open = lambda shop, at_time=None: True
        products_module.get_offer_text_for_shop_product = lambda db, sp_id: None
        offers = _shop_offers_payload(_DB(), _Product(), None, None, 25.0)
    finally:
        products_module.is_shop_open = original_is_shop_open
        products_module.get_offer_text_for_shop_product = original_offer_text

    assert len(offers) == 1
    assert offers[0]["is_open_now"] is True
    assert offers[0]["is_accepting_orders"] is True
    assert monkeypatched == {}


def test_shop_offers_payload_tolerates_open_state_failure():
    """A failing opening-hours lookup must not break the product page.

    The offer still has to be returned with an *unknown* (None) open state, so
    the UI hides the badge instead of guessing.
    """
    from app.api.routes.products import _shop_offers_payload

    class _Shop:
        id = 7
        name = "Neighbour Market"
        image_url = None
        latitude = None
        longitude = None
        rating = 4.0
        is_accepting_orders = True

    class _Inv:
        stock_status = "IN_STOCK"
        is_available = True
        updated_at = None
        freshness_status = None

    class _SP:
        id = 11
        shop_id = 7
        price = 42.0
        mrp = None
        last_inventory_update = None
        is_available = True
        inventory = _Inv()

    class _Product:
        id = 3

    class _DB:
        def query(self, model):
            return self

        def join(self, *a, **k):
            return self

        def options(self, *a, **k):
            return self

        def filter(self, *a, **k):
            return self

        def all(self):
            return [_SP()]

        def first(self):
            return _Shop()

    import app.api.routes.products as products_module

    def _boom(shop, at_time=None):
        raise RuntimeError("opening hours unavailable")

    original_is_shop_open = products_module.is_shop_open
    original_offer_text = products_module.get_offer_text_for_shop_product
    try:
        products_module.is_shop_open = _boom
        products_module.get_offer_text_for_shop_product = lambda db, sp_id: None
        offers = _shop_offers_payload(_DB(), _Product(), None, None, 25.0)
    finally:
        products_module.is_shop_open = original_is_shop_open
        products_module.get_offer_text_for_shop_product = original_offer_text

    # The shop is still listed; only the open state is unknown.
    assert len(offers) == 1
    assert offers[0]["is_open_now"] is None
    assert offers[0]["is_accepting_orders"] is None


class _BarcodeQuery:
    """SearchIndex query stub honouring the barcode page contract.

    `filter`/`order_by` keep the chain and record the order request; `offset`
    and `limit` record what the engine asked for and slice the queued rows, so
    a test can assert on the page the engine actually requested rather than on
    the rows it happened to receive.
    """

    def __init__(self, rows):
        self.rows = list(rows)
        self.ordered_by = []
        self.requested_offset = None
        self.requested_limit = None

    def filter(self, *args, **kwargs):
        return self

    def order_by(self, *args, **kwargs):
        self.ordered_by.append(args)
        return self

    def offset(self, value):
        self.requested_offset = value
        return self

    def limit(self, value):
        self.requested_limit = value
        return self

    def all(self):
        start = self.requested_offset or 0
        if self.requested_limit is None:
            return self.rows[start:]
        return self.rows[start:start + self.requested_limit]


def test_barcode_lookup_works():
    """barcode_lookup should find products by barcode."""
    from app.search.engine import barcode_lookup

    # Mock a SearchIndex entry for barcode lookup
    class MockEntry:
        id = 1
        shop_product_id = 1
        product_id = 1
        product_name = "Lays Classic"
        brand_name = "PepsiCo"
        category_name = "Snacks"
        price = 10.0
        mrp = 15.0
        is_available = True
        stock_status = "IN_STOCK"
        freshness_status = "RECENTLY_UPDATED"
        last_inventory_update = datetime(2026, 3, 15, 10, 0, tzinfo=timezone.utc)
        shop_id = 1
        shop_name = "Neighbour Market"
        distance_km = None
        shop_rating = 4.5
        latitude = 25.5941
        longitude = 85.1376

    class MockDBC:
        def query(self, model):
            if getattr(model, "__name__", str(model)) != "SearchIndex":
                return _InertQuery()
            return _BarcodeQuery([MockEntry()])

    db = MockDBC()
    result = barcode_lookup(db, "8901234567890")
    assert len(result) == 1
    assert result[0]["product_name"] == "Lays Classic"
    assert result[0]["shop_name"] == "Neighbour Market"


def test_barcode_lookup_reports_freshness_timestamp():
    """A scanned product must be dated exactly like a typed one.

    Without `last_inventory_update` the client has no evidence for its
    freshness copy and can only render "Unknown" — so the barcode path would
    silently disagree with the text-search path about the same listing.
    """
    from app.search.engine import barcode_lookup

    stamp = datetime(2026, 3, 15, 10, 0, tzinfo=timezone.utc)

    class MockEntry:
        id = 1
        shop_product_id = 1
        product_id = 1
        product_name = "Amul Butter"
        brand_name = "Amul"
        category_name = "Dairy"
        price = 55.0
        mrp = 60.0
        is_available = True
        stock_status = "IN_STOCK"
        freshness_status = "STALE"
        last_inventory_update = stamp
        shop_id = 1
        shop_name = "Local Mart"
        shop_rating = 4.2
        latitude = 25.5941
        longitude = 85.1376

    class MockDBC:
        def query(self, model):
            if getattr(model, "__name__", str(model)) != "SearchIndex":
                return _InertQuery()
            return _BarcodeQuery([MockEntry()])

    result = barcode_lookup(MockDBC(), "8901234567890")

    assert len(result) == 1
    assert result[0]["last_inventory_update"] == stamp
    assert result[0]["freshness_status"] == "STALE"


def test_barcode_lookup_tolerates_row_without_timestamp():
    """A partial row must not crash the lookup — freshness is simply unknown."""

    from app.search.engine import barcode_lookup

    class MockEntry:
        id = 1
        shop_product_id = 1
        product_id = 1
        product_name = "Colgate MaxFresh"
        brand_name = "Colgate"
        category_name = "Oral Care"
        price = 95.0
        mrp = None
        is_available = True
        stock_status = "IN_STOCK"
        freshness_status = None
        shop_id = 2
        shop_name = "Apothecary"
        shop_rating = 4.0
        latitude = 25.5941
        longitude = 85.1376
        # No last_inventory_update attribute at all.

    class MockDBC:
        def query(self, model):
            if getattr(model, "__name__", str(model)) != "SearchIndex":
                return _InertQuery()
            return _BarcodeQuery([MockEntry()])

    result = barcode_lookup(MockDBC(), "8901234567890")

    assert len(result) == 1
    assert result[0]["last_inventory_update"] is None
    assert result[0]["freshness_status"] is None


def test_barcode_lookup_empty():
    """barcode_lookup should return empty list when not found."""
    from app.search.engine import barcode_lookup

    class MockDBE:
        def query(self, model):
            return _BarcodeQuery([])

    result = barcode_lookup(MockDBE(), "0000000000000")
    assert result == []


def test_barcode_lookup_pages_shop_hits():
    """A barcode stocked by many shops comes back one page at a time.

    One GS1 code can be carried by every shop in a city, and the old lookup
    materialised all of them for a single scan. The engine must ask the
    database for a bounded page, and it must order that page in SQL: sorting
    inside Python would only order the rows of one page, so a shop could move
    between pages and be shown twice or never.
    """
    from app.search.engine import barcode_lookup

    class _Entry:
        def __init__(self, n):
            self.id = n
            self.shop_product_id = n
            self.product_id = 1
            self.product_name = f"Tin {n}"
            self.brand_name = "Beans"
            self.category_name = "Grocery"
            self.price = 10.0 + n
            self.mrp = None
            self.is_available = True
            self.stock_status = "IN_STOCK"
            self.freshness_status = "RECENTLY_UPDATED"
            self.last_inventory_update = None
            self.shop_id = n
            self.shop_name = f"Shop {n}"
            self.shop_rating = 4.0
            # No coordinates: the un-ordered-by-distance branch is the one
            # under test, and a NULL location must not break the page.
            self.latitude = None
            self.longitude = None

    rows = [_Entry(n) for n in range(1, 6)]

    class _DB:
        def __init__(self):
            self.search_index_query = _BarcodeQuery(rows)

        def query(self, model):
            if getattr(model, "__name__", str(model)) != "SearchIndex":
                return _InertQuery()
            return self.search_index_query

    db = _DB()

    first = barcode_lookup(db, "8901234567890", page=1, limit=2)
    assert [r["product_name"] for r in first] == ["Tin 1", "Tin 2"]
    assert db.search_index_query.requested_offset == 0
    assert db.search_index_query.requested_limit == 2
    assert db.search_index_query.ordered_by, (
        "the page must be ordered in SQL before it is sliced"
    )

    second = barcode_lookup(db, "8901234567890", page=2, limit=2)
    assert [r["product_name"] for r in second] == ["Tin 3", "Tin 4"]
    assert db.search_index_query.requested_offset == 2

    # The last partial page returns what is left instead of padding or
    # repeating, and the page after it is honestly empty.
    third = barcode_lookup(db, "8901234567890", page=3, limit=2)
    assert [r["product_name"] for r in third] == ["Tin 5"]
    assert barcode_lookup(db, "8901234567890", page=4, limit=2) == []


def test_barcode_lookup_defaults_to_one_bounded_page():
    """Callers that pass nothing still get a bounded query, not all rows."""
    from app.search.engine import barcode_lookup

    class _Entry:
        id = 1
        shop_product_id = 1
        product_id = 1
        product_name = "Tin"
        brand_name = "Beans"
        category_name = "Grocery"
        price = 10.0
        mrp = None
        is_available = True
        stock_status = "IN_STOCK"
        freshness_status = "RECENTLY_UPDATED"
        last_inventory_update = None
        shop_id = 1
        shop_name = "Shop"
        shop_rating = 4.0
        latitude = None
        longitude = None

    query = _BarcodeQuery([_Entry()])

    class _DB:
        def query(self, model):
            if getattr(model, "__name__", str(model)) != "SearchIndex":
                return _InertQuery()
            return query

    barcode_lookup(_DB(), "8901234567890")

    assert query.requested_offset == 0
    assert query.requested_limit == 20


# ── Popular search aggregation test ────────────────────────────────────────
def test_aggregate_popular_searches_function_exists():
    """Aggregation foundation exists and is callable."""
    from app.search.engine import aggregate_popular_searches

    assert callable(aggregate_popular_searches)


def test_search_event_recording():
    """record_search_event should write a SearchEvent."""
    from app.search.engine import record_search_event

    class MockDBEvent:
        def __init__(self):
            self.events = []

        def add(self, obj):
            self.events.append(obj)

        def flush(self):
            pass

    db = MockDBEvent()
    event = record_search_event(
        db,
        user_id=1,
        query="lays",
        event_type="SEARCH",
        result_count=5,
        device_type="android",
    )
    # Verify an event was added
    assert len(db.events) == 1
    # Set ID manually after flush mock
    db.events[0].id = 1
    assert event.query == "lays"
    assert event.event_type == "SEARCH"


# ── Freshness prevention test ──────────────────────────────────────────────
def test_low_relevance_for_stale():
    """Stale inventory should rank lower than fresh."""
    from app.search.ranking import compute_relevance_score

    fresh = compute_relevance_score(
        text_match_score=0.8,
        is_available=True,
        is_in_stock=True,
        freshness_status="RECENTLY_UPDATED",
    )
    stale = compute_relevance_score(
        text_match_score=0.8,
        is_available=True,
        is_in_stock=True,
        freshness_status="STALE",
    )
    assert fresh > stale


def test_low_relevance_for_unavailable():
    """Unavailable inventory should rank lower."""
    from app.search.ranking import compute_relevance_score

    available = compute_relevance_score(is_available=True, is_in_stock=True)
    unavailable = compute_relevance_score(is_available=False, is_in_stock=False)
    assert available > unavailable
# ── Engine-level coverage: mapping, filters, sorting, pagination ──────────
class _DistanceExpr:
    """Stand-in for a SQL expression supporting .asc() ordering."""

    def asc(self):
        return ("distance_expr", "asc")


class _TrackingQuery:
    """Query mock that records filter/order calls and applies offset/limit."""

    def __init__(self, rows=None):
        self._rows = rows or []
        self.filter_calls = []
        self.order_calls = []
        self._offset = None
        self._limit = None

    def filter(self, *args, **kwargs):
        self.filter_calls.append(args)
        return self

    def add_columns(self, *args):
        return self

    @property
    def column_descriptions(self):
        # Mimic SQLAlchemy: last column is the added distance expression.
        return [{"expr": _DistanceExpr()}]

    def order_by(self, *args):
        self.order_calls.append(args)
        return self

    def offset(self, value):
        self._offset = value
        return self

    def limit(self, value):
        self._limit = value
        return self

    def count(self):
        return len(self._rows)

    def all(self):
        rows = self._rows
        if self._offset is not None:
            rows = rows[self._offset:]
        if self._limit is not None:
            rows = rows[:self._limit]
        return rows


class _InertQuery:
    """Inert query for non-SearchIndex lookups (e.g., offer enrichment)."""

    def filter(self, *args, **kwargs):
        return self

    def join(self, *args, **kwargs):
        return self

    def all(self):
        return []


class _TrackingDB:
    """DB mock tracking the SearchIndex query (other models get inert mocks)."""

    def __init__(self, rows=None):
        self.rows = rows or [MockSearchIndexEntry()]
        self.last_query = None

    def query(self, model):
        if getattr(model, "__name__", str(model)) != "SearchIndex":
            return _InertQuery()
        self.last_query = _TrackingQuery(self.rows)
        return self.last_query

    def add(self, obj):
        pass

    def flush(self):
        pass


def _make_entries():
    """Three entries with distinct prices/ratings/freshness for sort tests."""
    fresh_now = datetime.now(timezone.utc)
    old = datetime(2026, 1, 1, tzinfo=timezone.utc)
    return [
        MockSearchIndexEntry(shop_product_id=1, price=30.0, shop_rating=3.0,
                             freshness_status="STALE", last_inventory_update=old),
        MockSearchIndexEntry(shop_product_id=2, price=20.0, shop_rating=4.9,
                             freshness_status="RECENTLY_UPDATED", last_inventory_update=fresh_now),
        MockSearchIndexEntry(shop_product_id=3, price=10.0, shop_rating=4.0,
                             is_available=False,
                             freshness_status="RECENTLY_UPDATED", last_inventory_update=fresh_now),
    ]


def test_exact_product_match_content():
    """Exact product search maps index fields into the result payload."""
    from app.search.engine import SearchParams, search_products

    db = _TrackingDB([MockSearchIndexEntry()])
    result = search_products(db, SearchParams(q="Lays Classic"))
    assert result["total"] == 1
    r = result["results"][0]
    assert r["product_name"] == "Lays Classic"
    assert r["brand_name"] == "PepsiCo"
    assert r["category_name"] == "Snacks"
    assert r["price"] == 10.0
    assert r["mrp"] == 15.0
    assert r["is_available"] is True
    assert r["shop_name"] == "Neighbour Market"
    assert r["relevance_score"] > 0


def test_partial_brand_category_variant_mapping():
    """Partial query still carries brand/category/variant metadata through."""
    from app.search.engine import SearchParams, search_products

    entry = MockSearchIndexEntry(variant_name="Family Pack")
    db = _TrackingDB([entry])
    result = search_products(db, SearchParams(q="lay"))  # partial token
    r = result["results"][0]
    assert r["variant_name"] == "Family Pack"
    assert r["brand_name"] == "PepsiCo"
    assert r["category_name"] == "Snacks"


def test_barcode_query_routes_to_exact_lookup():
    """Numeric barcode queries bypass text matching and hit the barcode column."""
    from app.search.engine import SearchParams, search_products

    db = _TrackingDB()
    search_products(db, SearchParams(q="8901234567890"))
    # One filter call for the barcode equality + one visibility block
    assert len(db.last_query.filter_calls) >= 2


def test_filters_are_applied_to_query():
    """Every supported discovery filter adds its predicate to the SQL query."""
    from app.search.engine import SearchParams, search_products

    db = _TrackingDB(_make_entries())
    params = SearchParams(
        q="lays",
        category_id=7,
        brand_id=5,
        min_price=5.0,
        max_price=50.0,
        min_rating=3.5,
        in_stock_only=True,
        exclude_stale=True,
        exclude_unavailable=True,
    )
    result = search_products(db, params)
    # category+brand+min_price+max_price+min_rating+in_stock+exclude_stale
    # +exclude_unavailable+visibility block = 9 filter invocations
    assert len(db.last_query.filter_calls) >= 9
    assert "results" in result


def test_default_params_use_single_visibility_filter():
    """With no q and no geo/filters, only the visibility block filter applies."""
    from app.search.engine import SearchParams, search_products

    db = _TrackingDB(_make_entries())
    search_products(db, SearchParams())
    assert len(db.last_query.filter_calls) == 1


def test_pagination_first_page_has_more():
    """Page 1 of 3 rows @ limit 2 → two results and has_more=True."""
    from app.search.engine import SearchParams, search_products

    db = _TrackingDB(_make_entries())
    result = search_products(db, SearchParams(page=1, limit=2))
    assert len(result["results"]) == 2
    assert result["total"] == 3
    assert result["has_more"] is True
    assert db.last_query._offset == 0


def test_pagination_last_page_no_more():
    """Page 2 of 3 rows @ limit 2 → one result, offset applied, has_more=False."""
    from app.search.engine import SearchParams, search_products

    db = _TrackingDB(_make_entries())
    result = search_products(db, SearchParams(page=2, limit=2))
    assert len(result["results"]) == 1
    assert result["total"] == 3
    assert result["has_more"] is False
    assert db.last_query._offset == 2
    assert result["page"] == 2


def test_relevance_sort_orders_by_score():
    """Python-side relevance ordering puts the highest score first."""
    from app.search.engine import SearchParams, search_products

    db = _TrackingDB(_make_entries())
    result = search_products(db, SearchParams(sort="relevance"))
    scores = [r["relevance_score"] for r in result["results"]]
    assert scores == sorted(scores, reverse=True)


def test_distance_sort_sql_ordering_applied():
    """Distance sort issues an ORDER BY on the computed distance column."""
    from app.search.engine import SearchParams, search_products

    db = _TrackingDB(_make_entries())
    search_products(db, SearchParams(latitude=25.5941, longitude=85.1376, sort="distance"))
    assert len(db.last_query.order_calls) >= 1


def test_price_and_rating_sql_ordering_applied():
    """Price and rating sorts issue ORDER BY clauses server-side."""
    from app.search.engine import SearchParams, search_products

    db = _TrackingDB(_make_entries())
    search_products(db, SearchParams(sort="lowest_price"))
    assert len(db.last_query.order_calls) == 1

    db2 = _TrackingDB(_make_entries())
    search_products(db2, SearchParams(sort="highest_rated"))
    assert len(db2.last_query.order_calls) == 1


def test_freshness_python_sort_puts_fresh_first():
    """FRESHNESS python-side sort must rank recently-updated before stale."""
    from app.search.ranking import default_sort_key, SearchSort

    items = [
        {"freshness_status": "STALE"},
        {"freshness_status": "RECENTLY_UPDATED"},
        {"freshness_status": "STALE"},
        {"freshness_status": "RECENTLY_UPDATED"},
    ]
    ordered = sorted(items, key=default_sort_key(SearchSort.FRESHNESS))
    statuses = [i["freshness_status"] for i in ordered]
    assert statuses == ["RECENTLY_UPDATED", "RECENTLY_UPDATED", "STALE", "STALE"]


def test_availability_python_sort_puts_available_first():
    """AVAILABILITY sort ranks available items before unavailable ones."""
    from app.search.ranking import default_sort_key, SearchSort

    items = [{"is_available": False}, {"is_available": True}, {"is_available": False}]
    ordered = sorted(items, key=default_sort_key(SearchSort.AVAILABILITY))
    flags = [i["is_available"] for i in ordered]
    assert flags == [True, False, False]


def test_index_sync_run_lifecycle_fields():
    """A sync run tracks processed/created/updated/removed/error counters."""
    from app.models.search import SearchIndexSync

    cols = SearchIndexSync.__table__.columns
    # Counters default to zero (applied at insert time by SQLAlchemy)
    for name in ("total_processed", "total_created", "total_updated",
                 "total_removed", "error_count"):
        assert cols[name].default is not None
        assert cols[name].default.arg == 0
    # Lifecycle transitions on the status enum
    from app.models.search import SearchIndexSyncStatus
    run = SearchIndexSync(sync_type="INCREMENTAL", status=SearchIndexSyncStatus.RUNNING)
    assert run.status == SearchIndexSyncStatus.RUNNING
    run.status = SearchIndexSyncStatus.COMPLETED
    assert run.status == SearchIndexSyncStatus.COMPLETED


def test_popularity_score_bounded_0_1():
    """Indexer popularity helper must stay within 0..1."""
    from app.search.indexer import _popularity

    class _CountOnly:
        def __init__(self, n):
            self._n = n

        def filter(self, *a, **k):
            return self

        def count(self):
            return self._n

    class _DB:
        def query(self, model):
            return _CountOnly(1000)  # huge click/view count

    score = _popularity(_DB(), product_id=1)
    assert 0.0 <= score <= 1.0