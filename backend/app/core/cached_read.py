"""Stampede-safe cached reads for hot endpoints.

WHY THIS EXISTS
---------------
At 500 concurrent customers the expensive read path is not the query itself --
it is that a single popular query (a category list, a product page, one search
term) is executed hundreds of times simultaneously because the cache is cold or
has just expired. Every one of those duplicates holds a database connection for
the full duration, and the connection pool -- correctly sized and deliberately
small -- becomes the queue that throttles the whole API.

This module provides ONE way to do a cached read so every hot endpoint gets the
same protection:

* a warm key is a pure Redis round-trip, no database work at all;
* on a miss, exactly ONE caller runs the producer and the rest wait briefly and
  then re-read the cache, rather than all of them hammering the database;
* the wait is time-boxed, so a producer that dies cannot pin requests;
* a Redis outage degrades to a direct producer call, which is slower but always
  correct -- caching is never allowed to become a dependency.

`cache.set_nx` is what makes the single-flight work: it is an atomic
"claim this key", so the winner is decided by Redis itself rather than by a
check-then-set race inside this process.
"""

from __future__ import annotations

import asyncio
import logging
from typing import Any, Awaitable, Callable, Optional

from app.core.cache import cache

logger = logging.getLogger("app.core.cached_read")

# How long a waiter blocks before giving up and producing the value itself.
#
# Deliberately short. The point is to collapse a burst into one query, not to
# add a queue in front of the database: if the single winner is slow (or died),
# every waiter must still return a real answer within the request budget rather
# than queue indefinitely.
DEFAULT_WAIT_TIMEOUT_SECONDS = 2.0

# How often a waiter re-checks the cache while waiting for the winner.
_POLL_INTERVAL_SECONDS = 0.02


async def cached_read(
    domain: str,
    key: Any,
    producer: Callable[[], Awaitable[Any]],
    *,
    ttl: Optional[int] = None,
    wait_timeout: float = DEFAULT_WAIT_TIMEOUT_SECONDS,
) -> Any:
    """Return ``producer()``'s result, cached under ``domain``/``key``.

    Args:
        domain: Cache namespace. Writers invalidate it via
            ``cache.invalidate_domain(domain)``.
        key: Cache key within the namespace.
        producer: Zero-argument awaitable that performs the real read. Only one
            caller runs it per cold key.
        ttl: Optional override of the configured default TTL.
        wait_timeout: How long a losing caller waits for the winner before
            producing the value itself.

    Returns:
        The cached value, or a freshly produced one. Never raises because of a
        cache problem -- a cache failure must degrade to the uncached path, not
        turn a readable endpoint into a 500.
    """
    # Fast path: warm cache. This is the common case and must stay allocation
    # and branch free enough to be worth having.
    cached = await cache.get_json(domain, key)
    if cached is not None:
        return cached

    # Miss. Try to become the single producer.
    #
    # `available` is a PROPERTY on the real cache (circuit-breaker state), not a
    # method. `set_nx` returns False for TWO different reasons -- "another
    # caller holds the claim" AND "Redis is unreachable" (cache.set swallows the
    # error and returns the False default). Treating the second as the first is
    # how a Redis outage becomes an outage of everything: every request would
    # queue behind a lock nobody holds, wait out the full timeout, and only then
    # hit the database. So availability is checked FIRST and an unavailable
    # cache skips single-flight entirely -- many duplicate reads are strictly
    # better than every request waiting on a phantom lock.
    if not cache.available:
        return await producer()

    claimed = await cache.set_nx(_lock_key(domain, key), "1", ttl=wait_timeout * 4)
    if claimed:
        try:
            value = await producer()
            await cache.set_json(domain, key, value, ttl=ttl)
            return value
        finally:
            # Released in a finally block so a producer that RAISES cannot leave
            # the key claimed -- which would make every later caller wait out
            # the full timeout before producing anything itself.
            await cache.delete(_lock_key(domain, key))

    # Someone else is producing. Wait for them rather than duplicating the work.
    return await _await_winner(domain, key, producer, ttl=ttl, timeout=wait_timeout)


async def _await_winner(
    domain: str,
    key: Any,
    producer: Callable[[], Awaitable[Any]],
    *,
    ttl: Optional[int],
    timeout: float,
) -> Any:
    """Poll for the in-flight producer's result, then fall back to producing.

    The fallback is the important part. If the winner is slow, crashed, or the
    process it ran in was killed between claiming the key and writing the
    value, waiters must still serve the customer. Waiting is an optimisation,
    never a correctness requirement.
    """
    deadline = asyncio.get_running_loop().time() + timeout
    while asyncio.get_running_loop().time() < deadline:
        await asyncio.sleep(_POLL_INTERVAL_SECONDS)
        cached = await cache.get_json(domain, key)
        if cached is not None:
            return cached

    logger.warning(
        "Cache single-flight wait timed out for %s:%s; producing inline",
        domain,
        key,
    )
    value = await producer()
    # Store it anyway: the next caller should not have to wait either.
    await cache.set_json(domain, key, value, ttl=ttl)
    return value


def _lock_key(domain: str, key: Any) -> str:
    """Namespaced name for the single-flight claim key.

    Kept distinct from the data key via a ``lock:`` prefix so
    ``invalidate_domain`` (which deletes by prefix) cannot collide with the
    value being protected, and so a lock is never mistaken for data.
    """
    return f"lock:{domain}:{key}"