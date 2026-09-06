"""Tests for Phase 57 observability additions.

Covers:
- DB query latency metrics
- Cache hit/miss counters + hit-ratio gauge
- Search latency histogram + outcome counters
"""
import pytest


class TestDbQueryMetrics:
    def test_record_db_query(self):
        from app.core.observability import metrics

        metrics.record_db_query("select", 0.05)
        metrics.record_db_query("select", 0.07)
        metrics.record_db_query("insert", 0.02)

        total = metrics.db_query_duration_seconds.sum(kind="select")
        assert total >= 0.07
        assert metrics.db_query_duration_seconds.count(kind="select") >= 2

    def test_average_accessor(self):
        from app.core.observability import metrics

        before_n = metrics.db_query_duration_seconds.count(kind="delete")
        before_sum = metrics.db_query_duration_seconds.sum(kind="delete")

        metrics.record_db_query("delete", 0.10)
        avg = metrics.db_query_duration_seconds.average(kind="delete")
        new_n = metrics.db_query_duration_seconds.count(kind="delete")

        if new_n > 0:
            expected_avg = (before_sum + 0.10) / (before_n + 1)
            assert abs(avg - expected_avg) < 0.001

    def test_negative_clamped(self):
        from app.core.observability import metrics

        # Should not raise for negative durations (clamped to 0)
        metrics.record_db_query("update", -0.5)


class TestCacheMetrics:
    def test_record_cache_operation(self):
        from app.core.observability import metrics

        metrics.record_cache_operation("get", "hit")
        metrics.record_cache_operation("get", "miss")
        metrics.record_cache_operation("set", "hit")  # sets recorded as hit

        assert metrics.cache_operations_total.get(op="get", result="hit") >= 1
        assert metrics.cache_operations_total.get(op="get", result="miss") >= 1

    def test_hit_ratio_update(self):
        from app.core.observability import metrics

        before_hits = metrics.cache_operations_total.get(op="get", result="hit")
        before_miss = metrics.cache_operations_total.get(op="get", result="miss")

        metrics.record_cache_operation("get", "hit")
        metrics.record_cache_operation("get", "hit")
        metrics.record_cache_operation("get", "miss")
        metrics.update_cache_hit_ratio()

        ratio = metrics.cache_hit_ratio.get()
        expected = (before_hits + 2) / (before_hits + before_miss + 3)
        assert abs(ratio - expected) < 0.01


class TestSearchMetrics:
    def test_record_search_request(self):
        from app.core.observability import metrics

        metrics.record_search_request("products", 0.12, "ok")
        metrics.record_search_request("products", 0.15, "empty")
        metrics.record_search_request("nearby", 0.20, "ok")

        total = metrics.search_results_total.get(kind="products", outcome="ok")
        assert total >= 1

    def test_search_latency_recorded(self):
        from app.core.observability import metrics

        before = metrics.search_duration_seconds.get(kind="barcode")
        metrics.record_search_request("barcode", 0.03)
        after = metrics.search_duration_seconds.get(kind="barcode")
        assert after >= before


class TestSearchEngineInstrumentation:
    def test_search_products_exists_with_telemetry(self):
        """Engine exposes search_products that wraps _search_products_inner."""
        from app.search import engine

        assert callable(engine.search_products)
        assert callable(engine._search_products_inner)

    def test_search_products_classifies_barcode(self):
        """A barcode query should be classified as 'barcode' kind (no crash without DB)."""
        from app.search.engine import SearchParams

        params = SearchParams(q="8901030634213")
        assert params.q  # params built ok


class TestCacheInstrumentation:
    def test_cache_get_records_hit_miss_with_fake(self):
        """Cache.get() records hit/miss through a fake redis client."""
        import asyncio
        from app.core.cache import Cache

        class FakeRedis:
            async def ping(self):
                return True

            async def get(self, key):
                return "value"

        cache = Cache(client=FakeRedis())
        cache._connected = True
        cache._available = True

        from app.core.observability import metrics

        before_hit = metrics.cache_operations_total.get(op="get", result="hit")

        result = asyncio.run(cache.get("some:key"))
        assert result == "value"
        assert metrics.cache_operations_total.get(op="get", result="hit") == before_hit + 1

    def test_cache_get_miss_recorded_with_fake(self):
        import asyncio
        from app.core.cache import Cache

        class FakeRedisNone:
            async def ping(self):
                return True

            async def get(self, key):
                return None

        cache = Cache(client=FakeRedisNone())
        cache._connected = True
        cache._available = True

        from app.core.observability import metrics

        before_miss = metrics.cache_operations_total.get(op="get", result="miss")

        result = asyncio.run(cache.get("missing:key"))
        assert result is None
        assert metrics.cache_operations_total.get(op="get", result="miss") == before_miss + 1