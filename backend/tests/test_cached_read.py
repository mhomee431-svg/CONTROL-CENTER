"""Tests for the stampede-safe cached read used by the hot endpoints.

The behaviour under test is what lets the API survive a burst of concurrent
customers on one popular key, so the tests drive REAL concurrency with
``asyncio.gather`` rather than asserting on a mocked call count.
"""

import asyncio
import time

import pytest

from app.core import cached_read as cr
from app.core.cached_read import cached_read


class FakeCache:
    """In-memory stand-in for the Redis cache.

    Implements exactly the members `cached_read` uses. Two details are load
    bearing and were verified against `app/core/cache.py`:

    * `available` is a PROPERTY on the real cache (circuit-breaker state), so
      it is one here too. Defining it as a method made this fake disagree with
      production and let a real bug ship green.
    * `set_nx` returns False both when the key exists AND when Redis is down,
      because `cache.set` swallows the error and returns its False default.
    """

    def __init__(self, *, available: bool = True):
        self.available_flag = available
        self.data: dict[str, object] = {}
        self.locks: dict[str, object] = {}

    @property
    def available(self) -> bool:
        return self.available_flag

    async def get_json(self, domain, key, default=None):
        return self.data.get(f"{domain}:{key}", default)

    async def set_json(self, domain, key, value, ttl=None):
        self.data[f"{domain}:{key}"] = value
        return True

    async def set_nx(self, key, value, ttl=None):
        if not self.available_flag:
            # Matches the real client: a Redis failure surfaces as False.
            return False
        if key in self.locks:
            return False
        self.locks[key] = value
        return True

    async def delete(self, key):
        return self.locks.pop(key, None) is not None


@pytest.fixture
def fake_cache(monkeypatch):
    fc = FakeCache()
    monkeypatch.setattr(cr, "cache", fc)
    return fc


@pytest.mark.asyncio
async def test_fake_matches_the_real_cache_available_contract():
    """Guards the fake itself.

    `available` is a property on the real client. When this fake declared it as
    a method, every test in this file passed while the production call raised
    ``TypeError: 'bool' object is not callable`` -- the fake was validating the
    code against a shape that does not exist. A test double that disagrees with
    production is worse than no double, so this asserts the shape directly.
    """
    from app.core.cache import cache as real_cache

    assert isinstance(type(real_cache).available, property), (
        "cache.available must remain a property -- cached_read reads it "
        "without calling it, and this fake mirrors that shape"
    )
    assert isinstance(FakeCache().available, bool)


@pytest.mark.asyncio
async def test_warm_cache_skips_the_producer_entirely(fake_cache):
    """The point of the cache: a hit must not touch the database."""
    calls = 0

    async def producer():
        nonlocal calls
        calls += 1
        return ["a", "b"]
@pytest.mark.asyncio
async def test_concurrent_readers_collapse_to_one_query(fake_cache):
    """THE stampede test: 50 simultaneous cold readers, one database query.

    Without single-flight this is 50 identical queries holding 50 connections
    at once, which is exactly what throttles the API under load.
    """
    calls = 0

    async def slow_producer():
        nonlocal calls
        calls += 1
        # Hold the key long enough for every other caller to pile up behind it.
        await asyncio.sleep(0.05)
        return ["result"]

    results = await asyncio.gather(
        *[cached_read("search", "dove", slow_producer) for _ in range(50)]
    )

    assert all(r == ["result"] for r in results), "every caller gets the value"
    assert calls == 1, f"expected 1 query for 50 concurrent readers, got {calls}"


@pytest.mark.asyncio
async def test_a_failing_producer_still_releases_the_claim(fake_cache):
    """A producer that raises must not leave a phantom lock behind.

    Otherwise every later caller waits out the full timeout before producing
    anything itself, turning one failure into a self-inflicted outage.
    """

    async def boom():
        raise RuntimeError("database is down")

    with pytest.raises(RuntimeError):
        await cached_read("cat", "boom", boom)

    assert fake_cache.locks == {}, "claim must be released even on failure"


@pytest.mark.asyncio
async def test_waiters_recover_after_a_producer_dies_holding_the_claim(fake_cache):
    """The crash-recovery path: a claim nobody will ever release.

    Simulates the winner being killed mid-produce. The waiter must still serve
    the customer rather than hanging until the process restarts.
    """
@pytest.mark.asyncio
async def test_redis_outage_produces_inline_without_waiting(monkeypatch):
    """A cache outage must degrade to slow, never to a queue.

    `set_nx` returns False both when a lock is held AND when Redis is
    unreachable. Treating the second as the first would make every request wait
    out the full timeout during an outage -- trading a Redis problem for a
    total API outage. Availability is therefore checked first.
    """
    fc = FakeCache(available=False)
    monkeypatch.setattr(cr, "cache", fc)
    calls = 0

    async def producer():
        nonlocal calls
        calls += 1
        return ["live"]

    started = time.perf_counter()
    values = await asyncio.gather(
        *[cached_read("search", "dove", producer, wait_timeout=5.0) for _ in range(20)]
    )
    elapsed = time.perf_counter() - started

    assert all(v == ["live"] for v in values)
    # 20 callers produce inline rather than queueing 5s on a phantom lock.
    assert elapsed < 1.0, f"took {elapsed:.2f}s -- callers queued on a dead cache"
    assert calls == 20, "no single-flight is possible without a cache"


@pytest.mark.asyncio
async def test_different_keys_do_not_collide(fake_cache):
    """Two distinct searches must never share one cache entry."""

    async def one():
        return ["dove"]

    async def two():
        return ["shampoo"]

    assert await cached_read("search", "dove", one) == ["dove"]
    assert await cached_read("search", "shampoo", two) == ["shampoo"]
    assert await cached_read("search", "dove", one) == ["dove"]