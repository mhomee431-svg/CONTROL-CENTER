"""Redis cache abstraction with connection lifecycle management."""

from contextlib import asynccontextmanager
from typing import Any, Optional

from redis.asyncio import Redis, from_url

from app.core.config import settings
from app.core.logging import get_logger

logger = get_logger("app.cache")


class Cache:
    """Async Redis cache wrapper."""

    def __init__(self, url: Optional[str] = None):
        self._url = url or settings.REDIS_URL
        self._redis: Optional[Redis] = None
        self._connected = False

    # ── Lifecycle ──────────────────────────────────────────────────────────
    async def connect(self) -> None:
        """Establish the Redis connection (idempotent)."""
        if self._connected and self._redis:
            return
        self._redis = from_url(self._url, decode_responses=True)
        await self._redis.ping()
        self._connected = True
        logger.info("Redis cache connected")

    async def close(self) -> None:
        """Close the Redis connection (idempotent)."""
        if self._redis:
            await self._redis.aclose()
            self._redis = None
            self._connected = False
            logger.info("Redis cache closed")

    async def ping(self) -> bool:
        """Check connectivity."""
        try:
            await self.connect()
            assert self._redis is not None
            return bool(await self._redis.ping())
        except Exception as exc:  # noqa: BLE001
            logger.warning("Redis ping failed: %s", exc)
            return False

    @property
    def connected(self) -> bool:
        return self._connected

    # ── Core ops ───────────────────────────────────────────────────────────
    async def get(self, key: str) -> Optional[str]:
        if not self._connected or self._redis is None:
            return None
        return await self._redis.get(key)

    async def set(
        self,
        key: str,
        value: str,
        ttl: Optional[int] = None,
        nx: bool = False,
    ) -> bool:
        if not self._connected or self._redis is None:
            return False
        ttl = ttl if ttl is not None else settings.CACHE_DEFAULT_TTL
        if nx:
            result = await self._redis.set(key, value, ex=ttl, nx=True)
            return result is True
        await self._redis.set(key, value, ex=ttl)
        return True

    async def delete(self, key: str) -> bool:
        if not self._connected or self._redis is None:
            return False
        result = await self._redis.delete(key)
        return bool(result)

    async def expire(self, key: str, ttl: int) -> bool:
        if not self._connected or self._redis is None:
            return False
        return bool(await self._redis.expire(key, ttl))

    async def incr(self, key: str, amount: int = 1) -> int:
        if not self._connected or self._redis is None:
            return 0
        return int(await self._redis.incr(key, amount))

    # ── Context manager ────────────────────────────────────────────────────
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


def get_redis() -> Redis:
    """Return the raw Redis client for advanced use-cases."""
    if _cache._redis is None:
        # Create a one-off client
        return from_url(settings.REDIS_URL, decode_responses=True)
    return _cache._redis


cache = get_cache()