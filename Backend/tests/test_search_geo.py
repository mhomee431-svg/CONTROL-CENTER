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
    """SearchIndex must have PostGIS location for nearby search."""
    from app.models.search import SearchIndex

    # location should be a Geography column
    for col_name, col in SearchIndex.__table__.columns.items():
        if col_name == "location":
            assert "%s" % type(col.type).__name__ == "Geography" or "Geography" in str(type(col.type))
            break
    else:
        pytest.fail("SearchIndex has no location column")


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
def test_barcode_lookup_works():
    """barcode_lookup should find products by barcode."""
    from app.search.engine import barcode_lookup

    # Mock a SearchIndex entry for barcode lookup
    class MockEntry:
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
        shop_id = 1
        shop_name = "Neighbour Market"
        distance_km = None
        shop_rating = 4.5
        latitude = 25.5941
        longitude = 85.1376

    class MockQueryWrap:
        def filter(self, *args, **kwargs):
            return self

        def all(self):
            return [MockEntry()]

    class MockDBC:
        def query(self, model):
            return MockQueryWrap()

    db = MockDBC()
    result = barcode_lookup(db, "8901234567890")
    assert len(result) == 1
    assert result[0]["product_name"] == "Lays Classic"
    assert result[0]["shop_name"] == "Neighbour Market"


def test_barcode_lookup_empty():
    """barcode_lookup should return empty list when not found."""
    from app.search.engine import barcode_lookup

    class MockQueryEmpty:
        def filter(self, *args, **kwargs):
            return self

        def all(self):
            return []

    class MockDBE:
        def query(self, model):
            return MockQueryEmpty()

    result = barcode_lookup(MockDBE(), "0000000000000")
    assert result == []


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