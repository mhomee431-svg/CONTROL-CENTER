"""Phase 6 — Redis: connection, auth, timeout, retry, health check,
cache invalidation, graceful failure and recovery.

Coverage (required by the phase):
  * set / get round-trips (raw + JSON), missing-key behavior
  * TTL storage and expiration (unit via a virtual clock + live Redis)
  * invalidation: exact key, whole domain, prefix, version bump, clear_all
  * connection failure: safe defaults, no crash, circuit breaker
  * recovery: reconnect after an outage, ops work again
  * OTP store fails CLOSED with a controlled 503 when Redis is down
  * rate limiter configured for in-memory fallback during an outage

Live Redis integration tests auto-skip when :6379 is unreachable.
"""

import os
import sys
from pathlib import Path

BACKEND_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BACKEND_DIR))

os.environ.setdefault("ENVIRONMENT", "test")
os.environ.setdefault("HYPERLOCAL_ENV", "test")

import pytest  # noqa: E402
import redis as redis_sync  # noqa: E402

from app.core.config import settings  # noqa: E402
from app.core.cache import Cache, cache_key  # noqa: E402

settings.RATE_LIMIT_ENABLED = False


# ── Fake async redis client (test double, no network) ─────────────────────────
class FakeAsyncRedis:
    """Minimal redis.asyncio stand-in with a virtual clock for TTL tests.

    ``fail`` makes every command raise a ``ConnectionError``; ``fail_after``
    makes commands fail once the Nth underlying command has been issued
    (simulates Redis dying mid-interaction). ``advance(seconds)`` ages TTLs so
    expiration is observable without sleeping.
    """

    def __init__(self, fail: bool = False, fail_after: int = 0):
        self.data: dict[str, str] = {}
        self.ttls: dict[str, float] = {}
        self.now = 0.0
        self.fail = fail
        self.fail_after = fail_after
        self.command_count = 0
        self.ping_count = 0

    def _check(self):
        self.command_count += 1
        if self.fail_after and self.command_count > self.fail_after:
            raise redis_sync.exceptions.ConnectionError("simulated mid-stream outage")
        if self.fail:
            raise redis_sync.exceptions.ConnectionError("simulated outage")

    async def ping(self):
        self.ping_count += 1
        if self.fail:
            raise redis_sync.exceptions.ConnectionError("simulated outage")
        return True

    async def get(self, key):
        self._check()
        if key in self.ttls and self.ttls[key] <= 0:
            self.data.pop(key, None)
            self.ttls.pop(key, None)
        return self.data.get(key)

    async def set(self, key, value, ex=None, nx=False):
        self._check()
        if nx and key in self.data:
            return None
        self.data[key] = value
        if ex is not None:
            self.ttls[key] = float(ex)
        return True

    async def delete(self, key):
        self._check()
        existed = key in self.data
        self.data.pop(key, None)
        self.ttls.pop(key, None)
        return 1 if existed else 0

    async def expire(self, key, ttl):
        self._check()
        if key in self.data:
            self.ttls[key] = float(ttl)
            return 1
        return 0

    async def ttl(self, key):
        self._check()
        if key not in self.data:
            return -2
        return int(self.ttls.get(key, -1))

    async def exists(self, key):
        self._check()
        return 1 if key in self.data else 0

    async def incr(self, key, amount=1):
        self._check()
        value = int(self.data.get(key, 0)) + amount
        self.data[key] = str(value)
        return value

    async def scan_iter(self, match=None, count=100):
        self._check()
        pattern = match or "*"
        prefix = pattern.rstrip("*")
        for key in list(self.data):
            if key.startswith(prefix):
                yield key

    async def aclose(self):
        self._check()

    def advance(self, seconds):
        """Move the virtual clock — expires keys whose TTL has elapsed."""
        self.now += seconds
        for key in list(self.ttls):
            self.ttls[key] -= seconds
            if self.ttls[key] <= 0:
                self.data.pop(key, None)
                self.ttls.pop(key, None)


@pytest.fixture()
def fake():
    return FakeAsyncRedis()


@pytest.fixture()
def cache(fake, monkeypatch):
    monkeypatch.setattr(settings, "REDIS_UNAVAILABLE_GRACE_SECONDS", 0.0)
    return Cache(client=fake)


# ── set / get / TTL ───────────────────────────────────────────────────────────
class TestSetGet:
    @pytest.mark.asyncio
    async def test_set_get_roundtrip(self, cache, fake):
        assert await cache.set("product:1", "hello") is True
        assert await cache.get("product:1") == "hello"

    @pytest.mark.asyncio
    async def test_get_missing_returns_none(self, cache):
        assert await cache.get("never:set") is None

    @pytest.mark.asyncio
    async def test_keys_are_namespaced(self, cache, fake):
        await cache.set("product:1", "x")
        assert any(k.startswith(settings.REDIS_KEY_PREFIX + "product:1") for k in fake.data)

    @pytest.mark.asyncio
    async def test_ttl_is_stored(self, cache, fake):
        await cache.set("product:2", "x", ttl=120)
        assert await cache.ttl("product:2") == 120

    @pytest.mark.asyncio
    async def test_expiration_removes_key(self, cache, fake):
        await cache.set("product:3", "x", ttl=10)
        assert await cache.exists("product:3") is True
        fake.advance(11)
        assert await cache.get("product:3") is None
        assert await cache.exists("product:3") is False

    @pytest.mark.asyncio
    async def test_expire_method_wraps_ttl(self, cache):
        await cache.set("product:4", "x", ttl=10)
        assert await cache.expire("product:4", 300) is True
        assert await cache.ttl("product:4") == 300

    @pytest.mark.asyncio
    async def test_delete_invalidates(self, cache):
        await cache.set("product:5", "x")
        assert await cache.delete("product:5") is True
        assert await cache.get("product:5") is None

    @pytest.mark.asyncio
    async def test_set_nx_only_sets_when_absent(self, cache):
        assert await cache.set_nx("lock:op1", "1", ttl=5) is True
        assert await cache.set_nx("lock:op1", "2", ttl=5) is False
        assert await cache.get("lock:op1") == "1"

    @pytest.mark.asyncio
    async def test_incr(self, cache):
        assert await cache.incr("count:today") == 1
        assert await cache.incr("count:today") == 2


# ── JSON structured caching ───────────────────────────────────────────────────
class TestJson:
    @pytest.mark.asyncio
    async def test_json_roundtrip(self, cache):
        payload = {"id": 7, "names": ["a", "b"], "price": 99.5}
        assert await cache.set_json("product", 7, payload, ttl=60) is True
        assert await cache.get_json("product", 7) == payload

    @pytest.mark.asyncio
    async def test_get_json_default_when_missing(self, cache):
        assert await cache.get_json("product", 999, default=[]) == []

    @pytest.mark.asyncio
    async def test_get_json_bad_payload_returns_default(self, cache):
        await cache.set("junk:1", "not-json")
        assert await cache.get_json("junk", 1, default="fallback") == "fallback"


    @pytest.mark.asyncio
    async def test_cache_key_builder(self):
        assert cache_key("product", 7) == "product:7"
        assert cache_key("search__v3", "q=paracetamol") == "search__v3:q=paracetamol"


# ── Invalidation strategy ─────────────────────────────────────────────────────
class TestInvalidation:
    @pytest.mark.asyncio
    async def test_exact_key_invalidate(self, cache):
        await cache.set_json("product", 1, {"name": "a"})
        assert await cache.invalidate("product", 1) is True
        assert await cache.get_json("product", 1) is None

    @pytest.mark.asyncio
    async def test_invalidate_domain_removes_only_that_domain(self, cache):
        for i in (1, 2, 3):
            await cache.set_json("product", i, {"n": i})
        await cache.set_json("shop", 1, {"n": "s"})
        assert await cache.invalidate_domain("product") == 3
        assert await cache.get_json("product", 1) is None
        assert await cache.get_json("product", 2) is None
        assert await cache.get_json("product", 3) is None
        assert await cache.get_json("shop", 1) == {"n": "s"}  # untouched domain

    @pytest.mark.asyncio
    async def test_invalidate_prefix_matches_only_that_prefix(self, cache):
        await cache.set_json("category", "list", [1])
        await cache.set_json("catalog", 1, {"x": 1})
        assert await cache.invalidate_prefix("category") == 1
        assert await cache.get_json("category", "list") is None
        assert await cache.get_json("catalog", 1) == {"x": 1}

    @pytest.mark.asyncio
    async def test_domain_version_bump(self, cache):
        assert await cache.domain_version("search") == 0
        assert await cache.bump_domain_version("search") == 1
        assert await cache.domain_version("search") == 1

    @pytest.mark.asyncio
    async def test_clear_all_removes_every_prefixed_key(self, cache, fake):
        await cache.set_json("product", 1, {"n": 1})
        await cache.set_json("shop", 1, {"n": 1})
        assert await cache.clear_all() >= 2
        assert fake.data == {}


# ── Graceful failure / circuit breaker / recovery ─────────────────────────────
class TestGracefulFailure:
    @pytest.mark.asyncio
    async def test_ping_reports_down(self, fake, cache):
        fake.fail = True
        assert await cache.ping() is False
        assert cache.available is False

    @pytest.mark.asyncio
    async def test_ops_return_safe_defaults_when_redis_down(self, fake, cache):
        fake.fail = True
        assert await cache.get("product:1") is None
        assert await cache.set("product:1", "x") is False
        assert await cache.delete("product:1") is False
        assert await cache.incr("count:x") == 0
        assert await cache.exists("product:1") is False
        # The API stays up: nothing raised despite a full outage.
        assert await cache.ping() is False

    @pytest.mark.asyncio
    async def test_redis_dying_midway_degrades_not_crashes(self, fake, cache):
        fake.fail_after = 1  # first command succeeds, everything after fails
        assert await cache.set("product:1", "x") is True
        assert await cache.get("product:1") is None  # degrades, never raises

    @pytest.mark.asyncio
    async def test_grace_period_short_circuits_reconnect_attempts(self, fake, monkeypatch):
        monkeypatch.setattr(settings, "REDIS_UNAVAILABLE_GRACE_SECONDS", 60.0)
        cache = Cache(client=fake)
        fake.fail = True
        first = await cache.ping()          # attempt #1 (fails)
        assert first is False
        assert await cache.ping() is False  # attempt #2 short-circuited by grace
        assert fake.ping_count == 1

    @pytest.mark.asyncio
    async def test_recovery_after_outage(self, fake, monkeypatch):
        monkeypatch.setattr(settings, "REDIS_UNAVAILABLE_GRACE_SECONDS", 0.0)
        cache = Cache(client=fake)

        fake.fail = True
        assert await cache.ping() is False
        assert await cache.get("product:1") is None  # degraded

        fake.fail = False  # Redis comes back
        assert await cache.ping() is True
        assert await cache.set("product:1", "x") is True
        assert await cache.get("product:1") == "x"

    @pytest.mark.asyncio
    async def test_close_never_raises_on_dead_client(self, fake, cache):
        fake.fail = True
        await cache.set("x", "1")  # degrades quietly
        await cache.close()          # must not raise
        assert cache.connected is False


# ── Shared client factory / settings / rate limiter ───────────────────────────
class TestClientFactory:
    def test_settings_expose_redis_resilience_values(self):
        assert settings.REDIS_SOCKET_CONNECT_TIMEOUT > 0
        assert settings.REDIS_SOCKET_TIMEOUT > 0
        assert settings.REDIS_MAX_RETRIES >= 0
        assert settings.REDIS_KEY_PREFIX
        assert settings.REDIS_HEALTH_CHECK_INTERVAL >= 0

    def test_client_options_include_timeouts_and_retry(self):
        from app.core.redis import client_options

        opts = client_options()
        assert opts["decode_responses"] is True
        assert opts["socket_timeout"] == settings.REDIS_SOCKET_TIMEOUT
        assert opts["socket_connect_timeout"] == settings.REDIS_SOCKET_CONNECT_TIMEOUT
        assert opts["retry"]._retries == settings.REDIS_MAX_RETRIES  # noqa: SLF001 — config assertion
        assert opts["retry_on_timeout"] is settings.REDIS_RETRY_ON_TIMEOUT

    def test_async_client_builds_without_connecting(self):
        from app.core.redis import build_async_client

        client = build_async_client("redis://127.0.0.1:6379/15")  # lazy — no connect
        assert client is not None

    def test_rate_limiter_falls_back_to_memory_on_redis_outage(self):
        from app.core.rate_limit import limiter

        assert limiter._in_memory_fallback_enabled is True  # noqa: SLF001 — config assertion
        assert "socket_timeout" in limiter._storage_options  # noqa: SLF001


# ── OTP store fails closed on Redis outage ────────────────────────────────────
class TestOTPStoreFailClosed:
    def test_redis_otp_store_raises_controlled_503(self):
        from app.services.otp_store import OTPStorageUnavailableError, RedisOTPStore

        class ExplodingClient:
            def get(self, key):
                raise redis_sync.exceptions.ConnectionError("down")

            def setex(self, *args):
                raise redis_sync.exceptions.ConnectionError("down")

            def delete(self, *args):
                raise redis_sync.exceptions.ConnectionError("down")

            def scan_iter(self, *args, **kwargs):
                raise redis_sync.exceptions.ConnectionError("down")

        store = RedisOTPStore("redis://127.0.0.1:6379/4", client=ExplodingClient())
        with pytest.raises(OTPStorageUnavailableError) as exc_info:
            store.get("+919999999999")
        assert exc_info.value.status_code == 503

    def test_redis_otp_store_happy_path_still_works(self):
        from app.services.otp_store import RedisOTPStore

        store = RedisOTPStore("redis://127.0.0.1:6379/4", client=FakeSyncRedis())
        store.set("+919999999999", {"otp_hash": "h", "attempts": 0}, ttl_seconds=120)
        assert store.get("+919999999999") == {"otp_hash": "h", "attempts": 0}


class FakeSyncRedis:
    """Minimal sync redis stand-in for OTP store tests."""

    def __init__(self):
        self.data = {}

    def get(self, key):
        return self.data.get(key)

    def setex(self, key, ttl, value):
        self.data[key] = value

    def delete(self, key):
        self.data.pop(key, None)
        return 1

    def scan_iter(self, match=None):
        prefix = (match or "*").rstrip("*")
        for key in list(self.data):
            if key.startswith(prefix):
                yield key


# ── Live Redis integration (skipped without a reachable :6379) ────────────────
def _live_redis_available() -> bool:
    try:
        client = redis_sync.Redis.from_url(
            "redis://127.0.0.1:6379/15",
            socket_connect_timeout=0.5,
            socket_timeout=0.5,
        )
        return bool(client.ping())
    except Exception:  # noqa: BLE001 — unreachable Redis just means skip
        return False


@pytest.mark.skipif(not _live_redis_available(), reason="live Redis not reachable on :6379")
class TestLiveRedis:
    TEST_DB = "redis://127.0.0.1:6379/14"

    @pytest.mark.asyncio
    async def test_live_set_get_expiration(self):
        import asyncio

        cache = Cache(url=self.TEST_DB)
        await cache.connect()
        key = "phase6:live:expire"
        try:
            await cache.set(key, "x", ttl=1)
            assert await cache.get(key) == "x"
            assert await cache.ttl(key) <= 1
            await asyncio.sleep(1.1)  # let the 1s TTL elapse
            await cache.close()
            await cache.connect()          # fresh client — key now expired
            assert await cache.get(key) is None
            assert await cache.exists(key) is False
        finally:
            await cache.invalidate_prefix("phase6:live")
            await cache.close()

    @pytest.mark.asyncio
    async def test_live_invalidation(self):
        cache = Cache(url=self.TEST_DB)
        await cache.connect()
        try:
            await cache.set_json("live", "shop", {"id": 1})
            await cache.set_json("live", "product", {"id": 2})
            assert await cache.invalidate_prefix("live") >= 2
            assert await cache.get_json("live", "shop") is None
            assert await cache.get_json("live", "product") is None
        finally:
            await cache.invalidate_prefix("live")
            await cache.close()