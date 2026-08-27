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

from app.core.config import settings


def _client_key(request: Request) -> str:
    if settings.TRUST_X_FORWARDED_FOR:
        forwarded = request.headers.get("X-Forwarded-For", "")
        first_hop = forwarded.split(",")[0].strip()
        if first_hop:
            return first_hop
    return request.client.host if request.client else "anonymous"


limiter = Limiter(
    key_func=_client_key,
    default_limits=[settings.RATE_LIMIT_DEFAULT],
    storage_uri=settings.RATE_LIMIT_STORAGE_URI,
    enabled=settings.RATE_LIMIT_ENABLED,
    headers_enabled=True,
)


def auth_rate_limit():
    """Rate limit for authentication endpoints (stricter)."""
    return limiter.limit(settings.RATE_LIMIT_AUTH_ENDPOINT)


def default_rate_limit():
    """Default rate limit for general endpoints."""
    return limiter.limit(settings.RATE_LIMIT_DEFAULT)