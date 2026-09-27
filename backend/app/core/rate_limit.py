"""Rate limiting foundation using slowapi.

Provides a shared limiter instance and helper decorators.
The storage backend is configurable via RATE_LIMIT_STORAGE_URI
(memory:// for dev/test, redis:// for production).

Phase 30 — proxy-aware client keying: when the app runs behind a trusted
reverse proxy, the direct peer address is the proxy, not the client. Enable
TRUST_X_FORWARDED_FOR only when the deployment actually has such a proxy;
the left-most X-Forwarded-For entry is then used (spoofable otherwise, so it
stays off by default).
"""

from fastapi import Request
from slowapi import Limiter
from typing import Any, Callable

from app.core.config import settings


def _client_key(request: Request) -> str:
    if settings.TRUST_X_FORWARDED_FOR:
        forwarded = request.headers.get("X-Forwarded-For", "")
        first_hop = forwarded.split(",")[0].strip()
        if first_hop:
            return first_hop
    return request.client.host if request.client else "anonymous"


# Phase 6 — graceful Redis failure for rate limiting:
#   * storage_options bound every Redis command (no unbounded waits).
#   * in_memory_fallback_enabled means a Redis outage automatically falls back
#     to per-process counters instead of 500ing every request. Limits degrade
#     (per-worker instead of shared) but the API stays up and PostgreSQL bleeds
#     nothing — the counter is temporary by design.
limiter = Limiter(
    key_func=_client_key,
    default_limits=[settings.RATE_LIMIT_DEFAULT],
    storage_uri=settings.RATE_LIMIT_STORAGE_URI,
    storage_options={
        "socket_connect_timeout": settings.REDIS_SOCKET_CONNECT_TIMEOUT,
        "socket_timeout": settings.REDIS_SOCKET_TIMEOUT,
        "health_check_interval": settings.REDIS_HEALTH_CHECK_INTERVAL,
        "retry_on_timeout": settings.REDIS_RETRY_ON_TIMEOUT,
    },
    in_memory_fallback_enabled=True,
    enabled=settings.RATE_LIMIT_ENABLED,
    headers_enabled=True,
)


def auth_rate_limit() -> Callable[..., Any]:
    """Rate limit for authentication endpoints (stricter)."""
    return limiter.limit(settings.RATE_LIMIT_AUTH_ENDPOINT)


def default_rate_limit() -> Callable[..., Any]:
    """Default rate limit for general endpoints."""
    return limiter.limit(settings.RATE_LIMIT_DEFAULT)