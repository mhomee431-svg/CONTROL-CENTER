"""Rate limiting foundation using slowapi.

Provides a shared limiter instance and helper decorators.
The storage backend is configurable via RATE_LIMIT_STORAGE_URI
(memory:// for dev/test, redis:// for production).
"""

from slowapi import Limiter
from slowapi.util import get_remote_address

from app.core.config import settings

limiter = Limiter(
    key_func=get_remote_address,
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