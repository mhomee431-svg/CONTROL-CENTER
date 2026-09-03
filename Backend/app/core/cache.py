"""Redis cache abstraction with connection lifecycle management.

Phase 6 — production hardening. This is the ONE place the cache talks to
Redis, so it implements every resiliency requirement in one file:

* **Connection / auth** — built from ``settings.REDIS_URL`` (auth may ride in
  the URL or be injected via ``REDIS_USERNAME`` / ``REDIS_PASSWORD``).
* **Timeout**           — every command is bound by ``REDIS_SOCKET_TIMEOUT``;
  connecting is bound by ``REDIS_SOCKET_CONNECT_TIMEOUT``.
* **Retry**             — bounded exponential-with-jitter retries for transient
  connection/timeout errors (see :mod:`app.core.redis`).
* **Health check**      — ``ping()`` performs a real probe and, when the cache
  is known-bad, attempts a reconnect (recovery).
* **Graceful failure**  — every operation returns a safe default (``None`` /
  ``False`` / ``0``) instead of raising while Redis is unavailable. A circuit
  breaker short-circuits ops for ``REDIS_UNAVAILABLE_GRACE_SECONDS`` between
  reconnect attempts so an outage cannot hammer the network or block callers.
* **Cache invalidation strategy** — keys are namespaced
  ``<REDIS_KEY_PREFIX><domain>:<key>``; entity writes ``invalidate()`` exact
  keys, bulk changes ``invalidate_domain()`` / ``invalidate_prefix()`` delete
  every matching key via a chunked SCAN, and TTLs age everything out even if a
  call site forgets to invalidate. Domain-level cached counts can additionally
  use the version-bump helpers (``domain_version`` / ``bump_domain_version``).

Redis is NEVER the source of truth: PostgreSQL stays authoritative. A Redis
outage therefore degrades caching to "cache miss → hit PostgreSQL", which is
always correct, never a data-loss condition.
"""

import asyncio
import json
import time
from contextlib import asynccontextmanager
from typing import Any, Optional

from app.core.config import settings
from app.core.logging import get_logger
from app.core.observability.metrics import record_redis_error, set_redis_available
from app.core.redis import RETRYABLE_REDIS_ERRORS, build_async_client

logger = get_logger("app.cache")


def cache_key(domain: str, key: Any) -> str:
    """Build a namespaced cache key: ``<domain>:<key>``.

    The caller-supplied key is normalized to a string so int ids etc. work.
    """
    return f"{domain}:{key}"


class Cache:
    """Async Redis cache wrapper with circuit-breaker graceful degradation."""

    def __init__(self, url: Optional[str] = None, client: Optional[Any] = None):
        # ``client`` is an injection point for tests; production builds from URL.
        self._url = url or settings.REDIS_URL
        self._client_override = client
        self._redis: Optional[Any] = None
        self._connected = False
        self._available = True          # circuit breaker state
        self._last_attempt = 0.0        # monotonic timestamp of last reconnect try

    # ── Key helpers ──────────────────────────────────────────────────────────
    @staticmethod
    def _prefixed(key: str) -> str:
        """Apply the global key prefix (scopes the cache across dbs/apps)."""
        return f"{settings.REDIS_KEY_PREFIX}{key}"

    # ── Lifecycle ────────────────────────────────────────────────────────────
    async def connect(self) -> None:
        """Establish the Redis connection (idempotent)."""
        if self._connected and self._redis is not None:
            return
        self._redis = await self._build_client()
        self._connected = True
        self._available = True
        logger.info("Redis cache connected (%s)", self._url)
        set_redis_available(True)

    async def _build_client(self) -> Any:
        if self._client_override is not None:
            return self._client_override
        client = build_async_client(self._url)
        await client.ping()
        return client

    async def close(self) -> None:
        """Close the Redis connection (idempotent)."""
        if self._redis is not None:
            try:
                await self._redis.aclose()
            except Exception:  # noqa: BLE001 — closing a dead client must not raise
                pass
            self._redis = None
            self._client_override = None
            self._connected = False
            self._available = True
            logger.info("Redis cache closed")

    @property
    def connected(self) -> bool:
        return self._connected

    @property
    def available(self) -> bool:
        """True when Redis is believed reachable (circuit breaker state)."""
        return self._available

    # ── Health / recovery ────────────────────────────────────────────────────
    async def ping(self) -> bool:
        """Connectivity probe with auto-recovery.

        When Redis is believed healthy this is a plain PING. When it is known
        bad, a reconnect is attempted at most once per
        ``REDIS_UNAVAILABLE_GRACE_SECONDS``.
        """
        if self._available and self._redis is not None:
            try:
                return bool(
                    await asyncio.wait_for(
                        self._redis.ping(), settings.REDIS_HEALTH_PING_TIMEOUT
                    )
                )
            except RETRYABLE_REDIS_ERRORS as exc:  # noqa: BLE001
                logger.warning("Redis ping failed: %s", exc)
                self._available = False
                self._connected = False
                record_redis_error("ping")
                set_redis_available(False)
        return await self._maybe_reconnect()

    async def _maybe_reconnect(self) -> bool:
        """Attempt (re)connection if the grace period has elapsed."""
        now = time.monotonic()
        if now - self._last_attempt < settings.REDIS_UNAVAILABLE_GRACE_SECONDS:
            return False
        self._last_attempt = now
        try:
            if self._redis is None:
                self._redis = await self._build_client()
            await asyncio.wait_for(
                self._redis.ping(), settings.REDIS_HEALTH_PING_TIMEOUT
            )
            self._connected = True
            self._available = True
            logger.info("Redis cache recovered")
            set_redis_available(True)
            return True
        except Exception as exc:  # noqa: BLE001
            self._connected = False
            self._available = False
            logger.warning("Redis cache unavailable: %s", exc)
            record_redis_error("reconnect")
            set_redis_available(False)
            return False

    # ── Core op runner (graceful degradation) ───────────────────────────────
    async def _run(self, coro_factory: Any, default: Any) -> Any:
        """Execute a Redis command; never raise while Redis is unavailable.

        ``coro_factory`` is a zero-arg callable returning an awaitable.
        """
        if self._redis is None or not self._available:
            if not await self._maybe_reconnect():
                return default
        try:
            return await coro_factory()
        except RETRYABLE_REDIS_ERRORS as exc:  # noqa: BLE001
            self._available = False
            self._connected = False
            logger.warning("Redis operation failed (%s) — degrading to cache-miss", exc)
            record_redis_error("command")
            set_redis_available(False)
            return default

# ── Core ops ─────────────────────────────────────────────────────────────
    async def get(self, key: str) -> Optional[str]:
        return await self._run(lambda: self._redis.get(self._prefixed(key)), None)

    async def set(
        self,
        key: str,
        value: str,
        ttl: Optional[int] = None,
        nx: bool = False,
    ) -> bool:
        ttl = ttl if ttl is not None else settings.CACHE_DEFAULT_TTL
        prefixed = self._prefixed(key)

        async def _set():
            if nx:
                result = await self._redis.set(prefixed, value, ex=ttl, nx=True)
                return result is True
            await self._redis.set(prefixed, value, ex=ttl)
            return True

        return await self._run(_set, False)

    async def set_nx(self, key: str, value: str, ttl: Optional[int] = None) -> bool:
        """Set only if the key does not exist (locks / idempotency guards)."""
        return await self.set(key, value, ttl=ttl, nx=True)

    async def delete(self, key: str) -> bool:
        result = await self._run(lambda: self._redis.delete(self._prefixed(key)), 0)
        return bool(result)

    async def expire(self, key: str, ttl: int) -> bool:
        result = await self._run(lambda: self._redis.expire(self._prefixed(key), ttl), 0)
        return bool(result)

    async def ttl(self, key: str) -> int:
        """Remaining TTL in seconds (-1 = no expiry, -2 = key absent)."""
        return int(await self._run(lambda: self._redis.ttl(self._prefixed(key)), -2))

    async def exists(self, key: str) -> bool:
        result = await self._run(lambda: self._redis.exists(self._prefixed(key)), 0)
        return bool(result)

    async def incr(self, key: str, amount: int = 1) -> int:
        return int(await self._run(lambda: self._redis.incr(self._prefixed(key), amount), 0))
# ── Structured caching (JSON) ────────────────────────────────────────────
    async def get_json(self, domain: str, key: Any, default: Any = None) -> Any:
        """Return the JSON-decoded value cached under ``domain:key``."""
        raw = await self.get(cache_key(domain, key))
        if raw is None:
            return default
        try:
            return json.loads(raw)
        except (TypeError, ValueError) as exc:
            logger.warning("Cache JSON decode failed for %s:%s: %s", domain, key, exc)
            return default

    async def set_json(
        self,
        domain: str,
        key: Any,
        value: Any,
        ttl: Optional[int] = None,
    ) -> bool:
        """Store ``value`` as JSON under ``domain:key`` with default TTL."""
        try:
            payload = json.dumps(value, default=str)
        except (TypeError, ValueError) as exc:
            logger.warning("Cache JSON encode failed for %s:%s: %s", domain, key, exc)
            return False
        return await self.set(cache_key(domain, key), payload, ttl)

    # ── Invalidation strategy ────────────────────────────────────────────────
    async def invalidate(self, domain: str, key: Any) -> bool:
        """Exact-key invalidation (entity write path: delete ``domain:key``)."""
        return await self.delete(cache_key(domain, key))

    async def invalidate_domain(self, domain: str) -> int:
        """Invalidate a whole domain by deleting every ``domain:*`` key.

        Used by bulk writers. O(N) over the domain's keys via a chunked SCAN;
        correct and simple. For O(1) whole-domain invalidation see
        ``bump_domain_version``.
        """
        return await self.invalidate_prefix(cache_key(domain, ""))

    async def invalidate_prefix(self, prefix: str) -> int:
        """Delete every key whose global name starts with ``prefix``.

        ``prefix`` is treated as a literal prefix, so ``"product"`` matches
        ``product:1`` and ``product:2`` but never ``productivity:1`` (note the
        missing ``:``). Callers wanting exactly one domain should pass
        ``cache_key(domain, "")`` (i.e. ``"product:"``).
        """
        pattern = self._prefixed(prefix) + "*"

        async def _delete_matching():
            deleted = 0
            assert self._redis is not None
            async for key in self._redis.scan_iter(match=pattern, count=200):
                deleted += await self._redis.delete(key)
            return deleted

        return int(await self._run(_delete_matching, 0))

    async def domain_version(self, domain: str) -> int:
        """Current cache version for ``domain`` (0 when never bumped)."""
        raw = await self._run(
            lambda: self._redis.get(self._prefixed(cache_key(domain, "__version__"))),
            None,
        )
        try:
            return int(raw) if raw is not None else 0
        except (TypeError, ValueError):
            return 0

    async def bump_domain_version(self, domain: str) -> int:
        """O(1) whole-domain invalidation: INCR ``domain:__version__``.

        Paired with ``domain_version`` this lets readers embed ``v<version>``
        into their keys and drop every key at once with a single INCR instead
        of a SCAN.
        """
        return int(
            await self._run(
                lambda: self._redis.incr(
                    self._prefixed(cache_key(domain, "__version__"))
                ),
                0,
            )
        )

    async def clear_all(self) -> int:
        """Delete every key under the app's cache prefix (ops/test isolation)."""
        return await self.invalidate_prefix("")

    # ── Context manager ──────────────────────────────────────────────────────
    @asynccontextmanager
    async def auto(self):
        """Context manager that auto-connects / auto-closes (for scripts)."""
        await self.connect()
        try:
            yield self
        finally:
            await self.close()


# Module-level singleton
_cache = Cache()


def get_cache() -> Cache:
    return _cache


def get_redis() -> Any:
    """Return the live async redis client (creates a hardened one if needed)."""
    if _cache._redis is None:
        return build_async_client()
    return _cache._redis


cache = get_cache()