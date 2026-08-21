"""Health and readiness check endpoints."""

from fastapi import APIRouter
from sqlalchemy import text

from app.core.config import settings
from app.core.logging import get_logger
from app.database.session import async_engine, check_database_connection

logger = get_logger("app.health")
router = APIRouter()


async def check_database() -> bool:
    """Verify PostgreSQL connectivity."""
    return await check_database_connection()


async def check_redis() -> bool:
    """Verify Redis connectivity."""
    try:
        from app.core.cache import cache

        return await cache.ping()
    except Exception as exc:  # noqa: BLE001
        logger.warning("Redis health check failed: %s", exc)
        return False


async def check_postgis() -> bool:
    """Verify PostGIS extension is available."""
    try:
        async with async_engine.connect() as conn:
            result = await conn.execute(text("SELECT PostGIS_Version()"))
            return result.scalar() is not None
    except Exception as exc:  # noqa: BLE001
        logger.warning("PostGIS health check failed: %s", exc)
        return False


@router.get("/health", tags=["Health"])
async def health_check():
    """Liveness probe — always returns 200 if the process is alive."""
    return {
        "status": "healthy",
        "version": settings.APP_VERSION,
        "environment": settings.ENVIRONMENT,
    }


@router.get("/ready", tags=["Health"])
async def readiness_check():
    """Readiness probe — verifies DB, Redis, and PostGIS are reachable."""
    db_ok = await check_database()
    redis_ok = await check_redis()
    postgis_ok = await check_postgis()

    all_ok = db_ok and redis_ok and postgis_ok
    return {
        "status": "ready" if all_ok else "not_ready",
        "checks": {
            "database": db_ok,
            "redis": redis_ok,
            "postgis": postgis_ok,
        },
    }