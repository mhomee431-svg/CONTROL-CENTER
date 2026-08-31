"""Shared Redis client configuration and factories (sync + async).

Every Redis consumer in the backend — the cache (db 0), the OTP store (db 4),
rate limiting (db 3) and Celery (dbs 1/2) — must behave predictably when the
server is slow or briefly unavailable. This module centralizes the connection
options so that behaviour is configured in exactly one place:

* **Connection**     — URL/port/db (``REDIS_URL`` family) plus optional
  ``REDIS_USERNAME`` / ``REDIS_PASSWORD`` overrides for secret-manager flows.
* **Authentication** — credentials ride inside ``REDIS_URL``
  (``redis[s]://[:password@]host:port/db``) or are injected from settings.
* **Timeout**        — ``socket_connect_timeout`` and ``socket_timeout`` bound
  worst-case wait so a hung Redis can never hang the request path.
* **Retry**          — bounded exponential-with-jitter retries for transient
  connection/timeout errors only (never retried: data errors).
* **Health**         — ``health_check_interval`` keeps idle pooled connections
  from silently going stale.
"""

from typing import Any, Dict, Optional

from app.core.config import settings
from app.core.logging import get_logger

logger = get_logger("app.redis")

# Exceptions that are safe to retry / degrade (transient network conditions).
from redis.exceptions import ConnectionError as _RedisConnectionError  # noqa: E402
from redis.exceptions import RedisError, TimeoutError as _RedisTimeoutError  # noqa: E402

RETRYABLE_REDIS_ERRORS: tuple[type[BaseException], ...] = (
    RedisError,
    _RedisConnectionError,
    _RedisTimeoutError,
    OSError,
)


def _retry_policy() -> Any:
    """Bounded exponential-with-jitter retry (redis-py >= 4.1)."""
    from redis.backoff import ExponentialWithJitterBackoff  # noqa: PLC0415
    from redis.retry import Retry  # noqa: PLC0415

    backoff = ExponentialWithJitterBackoff(
        cap=settings.REDIS_RETRY_BACKOFF_CAP,
        base=settings.REDIS_RETRY_BACKOFF_BASE,
    )
    return Retry(backoff, settings.REDIS_MAX_RETRIES)


def client_options(**overrides: Any) -> Dict[str, Any]:
    """Connection kwargs shared by the sync and async redis clients.

    ``from_url`` merges these with whatever is already in the URL (host, port,
    db, username/password, ssl scheme), so callers only need a ``redis://`` /
    ``rediss://`` string.
    """
    options: Dict[str, Any] = {
        "decode_responses": True,
        "socket_connect_timeout": settings.REDIS_SOCKET_CONNECT_TIMEOUT,
        "socket_timeout": settings.REDIS_SOCKET_TIMEOUT,
        "health_check_interval": settings.REDIS_HEALTH_CHECK_INTERVAL,
        "retry_on_timeout": settings.REDIS_RETRY_ON_TIMEOUT,
        "retry": _retry_policy(),
        "retry_on_error": [
            _RedisConnectionError,
            _RedisTimeoutError,
        ],
        "max_connections": settings.REDIS_MAX_CONNECTIONS,
    }
    # Secret-manager friendly override: inject credentials without rewriting
    # the URL. Explicit kwargs always win over URL-derived values in redis-py.
    if settings.REDIS_PASSWORD:
        options["password"] = settings.REDIS_PASSWORD
    if settings.REDIS_USERNAME:
        options["username"] = settings.REDIS_USERNAME
    options.update(overrides)
    return options


def build_sync_client(url: Optional[str] = None):
    """Return a synchronous redis client with hardened connection options."""
    import redis as _redis_sync  # noqa: PLC0415

    return _redis_sync.Redis.from_url(url or settings.REDIS_URL, **client_options())


def build_async_client(url: Optional[str] = None):
    """Return an async redis client with hardened connection options."""
    from redis.asyncio import from_url as _async_from_url  # noqa: PLC0415

    return _async_from_url(url or settings.REDIS_URL, **client_options())