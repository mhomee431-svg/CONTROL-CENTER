"""Health and readiness check endpoints (Phase 24 observability enriched).

* ``/health`` — liveness: process is alive. Returns deployment identity.
* ``/ready``  — readiness: verifies DB, Redis, PostGIS, storage and the
  background-job queue. Returns ``200`` when ready and ``503`` when not,
  so orchestrators / load balancers / the Docker HEALTHCHECK can steer
  traffic away from a warming container.

Every probe also updates the ``hl_health_component`` gauges and the
``hl_health_checks_total`` counter, so scraping ``/metrics`` after a probe
reflects the last observed component state.
"""

from fastapi import APIRouter
from fastapi.responses import JSONResponse
from sqlalchemy import text

import asyncio

from app.core.config import settings
from app.core.logging import get_logger
from app.core.observability.deployment import deployment_metadata
from app.core.observability.metrics import health_checks_total, set_component_health
from app.database.session import async_engine, check_database_connection

logger = get_logger("app.health")
router = APIRouter()

# Component names used for health gauges and readiness results.
_COMPONENT_DATABASE = "database"
_COMPONENT_REDIS = "redis"
_COMPONENT_POSTGIS = "postgis"
_COMPONENT_STORAGE = "storage"
_COMPONENT_QUEUE = "background_queue"


async def check_database() -> bool:
    """Verify PostgreSQL connectivity."""
    ok = False
    try:
        ok = await check_database_connection()
    except Exception as exc:  # noqa: BLE001
        logger.warning("Database health check failed: %s", exc)
    set_component_health(_COMPONENT_DATABASE, ok)
    from app.core.observability.metrics import set_db_available

    set_db_available(ok)
    return ok


async def check_redis() -> bool:
    """Verify Redis connectivity."""
    ok = False
    try:
        from app.core.cache import cache

        ok = await cache.ping()
    except Exception as exc:  # noqa: BLE001
        logger.warning("Redis health check failed: %s", exc)
    set_component_health(_COMPONENT_REDIS, ok)
    from app.core.observability.metrics import set_redis_available

    set_redis_available(ok)
    return ok


async def check_postgis() -> bool:
    """Verify PostGIS extension is available."""
    ok = False
    try:
        async with async_engine.connect() as conn:
            result = await conn.execute(text("SELECT PostGIS_Version()"))
            ok = result.scalar() is not None
    except Exception as exc:  # noqa: BLE001
        logger.warning("PostGIS health check failed: %s", exc)
    set_component_health(_COMPONENT_POSTGIS, ok)
    return ok


async def check_storage() -> bool:
    """Verify the configured object-storage provider is reachable."""
    from app.core.storage import check_storage_health

    return await check_storage_health()


async def check_background_queue() -> bool:
    """Verify the background-job queue is reachable (best-effort).

    Redis broker ping via the Celery inspection API with a hard timeout.
    A missing broker never crashes readiness — it degrades to a warning.
    """
    ok = False
    try:
        from celery import current_app

        inspector = current_app.control.inspect(timeout=2.0)
        ok = bool(inspector.ping())
    except Exception as exc:  # noqa: BLE001
        logger.warning("Background queue health check failed: %s", exc)
    set_component_health(_COMPONENT_QUEUE, ok)
    return ok


async def _run_readiness_checks() -> dict:
    """Run every component probe concurrently and return booleans.

    Concurrency keeps the total probe time bounded (~max single check) so
    the Docker HEALTHCHECK / ALB timeout budgets are never blown.
    """
    results = await asyncio.gather(
        check_database(),
        check_redis(),
        check_postgis(),
        check_storage(),
        check_background_queue(),
    )
    return {
        _COMPONENT_DATABASE: results[0],
        _COMPONENT_REDIS: results[1],
        _COMPONENT_POSTGIS: results[2],
        _COMPONENT_STORAGE: results[3],
        _COMPONENT_QUEUE: results[4],
    }


@router.get("/health", tags=["Health"])
async def health_check():
    """Liveness probe — always returns 200 if the process is alive."""
    return {
        "status": "healthy",
        "version": settings.APP_VERSION,
        "environment": settings.ENVIRONMENT,
        "deployment": deployment_metadata(),
    }


@router.get("/ready", tags=["Health"])
async def readiness_check():
    """Readiness probe — DB, Redis, PostGIS, storage, and queue reachable."""
    checks = await _run_readiness_checks()
    all_ok = all(checks.values())
    health_checks_total.inc(result="ready" if all_ok else "not_ready")
    body = {
        "status": "ready" if all_ok else "not_ready",
        "checks": checks,
        "deployment": deployment_metadata(),
    }
    return JSONResponse(status_code=200 if all_ok else 503, content=body)