"""Database connection management with pooling, PostGIS, and transaction handling."""

from collections.abc import AsyncIterator, Iterator
from contextlib import asynccontextmanager
from typing import Optional

from sqlalchemy import create_engine, text
from sqlalchemy.ext.asyncio import (
    AsyncEngine,
    AsyncSession,
    async_sessionmaker,
    create_async_engine,
)
from sqlalchemy.orm import DeclarativeBase, Session, sessionmaker
from sqlalchemy.pool import AsyncAdaptedQueuePool, QueuePool

from app.core.config import settings
from app.core.logging import get_logger

logger = get_logger("app.database.session")


class Base(DeclarativeBase):
    """Declarative base class for all ORM models."""


# ── Async Engine (used by FastAPI) ─────────────────────────────────────────
async_engine: Optional[AsyncEngine] = create_async_engine(
    settings.DATABASE_URL,
    poolclass=AsyncAdaptedQueuePool,
    pool_size=settings.DATABASE_POOL_SIZE,
    max_overflow=settings.DATABASE_MAX_OVERFLOW,
    pool_timeout=settings.DATABASE_POOL_TIMEOUT,
    pool_pre_ping=True,
    pool_recycle=settings.DATABASE_POOL_RECYCLE,
    echo=settings.DATABASE_ECHO,
)
AsyncSessionLocal = async_sessionmaker(expire_on_commit=False, bind=async_engine)


# ─────────────────────────────────────────────────────────────────────────────
# ── Sync Engine (used by Alembic / Celery tasks / scripts) ───────────────────
sync_engine = create_engine(
    settings.sqlalchemy_sync_url,
    poolclass=QueuePool,
    pool_size=min(settings.DATABASE_POOL_SIZE, 10),
    max_overflow=min(settings.DATABASE_MAX_OVERFLOW, 20),
    pool_timeout=settings.DATABASE_POOL_TIMEOUT,
    pool_pre_ping=True,
    pool_recycle=settings.DATABASE_POOL_RECYCLE,
    echo=settings.DATABASE_ECHO,
)
SessionLocal = sessionmaker(bind=sync_engine, autocommit=False, autoflush=False)


# ─────────────────────────────────────────────────────────────────────────────
# ── SQLite PostGIS compatibility shims (dev/local only) ─────────────────────
# The ORM persists `shops.location` / `search_indexes.location` with
# GeoAlchemy2 PostGIS bind expressions (e.g. `ST_GeogFromText(?)`). On a real
# PostgreSQL + PostGIS server those run natively; on the SQLite dev database
# they used to raise `no such function: ST_GeogFromText` → every shop
# creation (including the Shopkeeper create-profile flow) returned HTTP 500.
# These Python shims registered on the SQLite connection provide the same
# functions with faithful semantics (haversine geodesics + pg_trgm trigram
# similarity), so production SQL executes unchanged on SQLite.
# ─────────────────────────────────────────────────────────────────────────────
from sqlalchemy import event as sa_event


def _parse_wkt_point(value):
    """Parse a WKT 'POINT(lng lat)' value into (longitude, latitude)."""
    if value is None:
        return None
    raw = str(value)
    if not raw.startswith("POINT") or "(" not in raw or ")" not in raw:
        return None
    try:
        inner = raw[raw.index("(") + 1 : raw.rindex(")")]
        parts = inner.split()
        if len(parts) == 2:
            return float(parts[0]), float(parts[1])
    except (ValueError, TypeError, IndexError):
        return None
    return None


def _wkt_distance_m(value_a, value_b) -> float:
    """Geodesic distance in metres between two WKT POINT values (haversine)."""
    pa = _parse_wkt_point(value_a)
    pb = _parse_wkt_point(value_b)
    if pa is None or pb is None:
        return 0.0
    lon1, lat1 = pa
    lon2, lat2 = pb

    def _hav_km(a1, b1, a2, b2) -> float:
        from math import asin, cos, radians, sin, sqrt

        la1, lo1, la2, lo2 = map(radians, (a1, b1, a2, b2))
        dlat, dlon = la2 - la1, lo2 - lo1
        h = sin(dlat / 2) ** 2 + cos(la1) * cos(la2) * sin(dlon / 2) ** 2
        return 6371.0 * 2 * asin(min(1.0, sqrt(h)))

    return _hav_km(lat1, lon1, lat2, lon2) * 1000.0


def _trigrams(text):
    """pg_trgm-style trigram generation: 2-space padding + lowercase."""
    if not text:
        return []
    padded = "  " + str(text).lower() + "  "
    if len(padded) < 3:
        return []
    return [padded[i : i + 3] for i in range(len(padded) - 2)]


def _trigram_similarity(text_a, text_b) -> float:
    """Reproduce PostgreSQL ``pg_trgm similarity`` = common/(n1+n2-common)."""
    ta, tb = _trigrams(text_a), _trigrams(text_b)
    if not ta or not tb:
        return 0.0
    ca: dict[str, int] = {}
    for t in ta:
        ca[t] = ca.get(t, 0) + 1
    common = 0
    total = 0
    for t, n in ca.items():
        total += n
        m = tb.count(t)
        if m:
            common += n if n < m else m
    total += len(tb)
    denom = total - common
    return common / denom if denom > 0 else 0.0


def _register_sqlite_postgis_shims(dbapi_conn, connection_record):  # noqa: ANN001
    """Register the PostGIS / pg_trgm SQL functions the production engine emits
    so the real queries execute unmodified on the SQLite dev database."""
    create_function = getattr(dbapi_conn, "create_function", None)
    if create_function is None:
        return
    try:
        create_function("ST_GeogFromText", 1, lambda value: value)
        create_function("ST_GeomFromText", 1, lambda value: value)
        create_function("ST_AsText", 1, lambda value: value)
        create_function("AsBinary", 1, lambda value: value)
        create_function("ST_AsBinary", 1, lambda value: value)
        create_function("ST_AsEWKB", 1, lambda value: value)
        create_function("ST_Distance", 2, lambda a, b: _wkt_distance_m(a, b))

        def _dwithin(a, b, radius_m):
            distance = _wkt_distance_m(a, b)
            if distance is None:
                return 0
            return 1 if distance <= (radius_m or 0.0) else 0

        create_function("ST_DWithin", 3, _dwithin)
        create_function("similarity", 2, _trigram_similarity)
        # `NULL` is emitted by some pg_trgm-tolerant snippets; a 0-arg no-op
        # keeps such SQL valid on SQLite.
        create_function("NULL", 0, lambda: None)
    except Exception:  # noqa: BLE001  (dev-only compatibility shims)
        logger.debug("Could not register SQLite PostGIS compatibility shims", exc_info=True)


def _set_sqlite_pragmas(dbapi_conn, connection_record):  # noqa: ANN001
    try:
        # aiosqlite exposes an async cursor; these PRAGMAs are only applied on
        # the sync pysqlite connection (best effort for dev performance).
        cursor = dbapi_conn.cursor()
        if _is_awaitable(cursor):
            return
        cursor.execute("PRAGMA journal_mode=WAL")
        cursor.execute("PRAGMA busy_timeout=30000")
        cursor.close()
    except Exception:  # noqa: BLE001  (best effort on dev databases only)
        pass


def _is_awaitable(value) -> bool:
    return hasattr(value, "__await__") or hasattr(value, "__iter__") and hasattr(value, "__next__")


def _is_sqlite_engine(engine) -> bool:
    url = getattr(engine, "url", None)
    return url is not None and str(url.drivername).startswith("sqlite")


if _is_sqlite_engine(async_engine):
    sa_event.listen(
        async_engine.sync_engine, "connect", _register_sqlite_postgis_shims
    )
    sa_event.listen(async_engine.sync_engine, "connect", _set_sqlite_pragmas)

if _is_sqlite_engine(sync_engine):
    sa_event.listen(sync_engine, "connect", _register_sqlite_postgis_shims)
    sa_event.listen(sync_engine, "connect", _set_sqlite_pragmas)


# ─────────────────────────────────────────────────────────────────────────────
# ── PostGIS bootstrap ─────────────────────────────────────────────────────────
async def enable_postgis(engine: Optional[AsyncEngine] = None) -> None:
    """Ensure the PostGIS extension is enabled on the database."""
    eng = engine or async_engine
    try:
        async with eng.connect() as conn:
            await conn.execute(text(f'CREATE EXTENSION IF NOT EXISTS "{settings.POSTGIS_EXTENSION}"'))
            await conn.commit()
        logger.info("PostGIS extension enabled")
    except Exception as exc:  # noqa: BLE001
        logger.warning("Failed to enable PostGIS extension: %s", exc)


# ─────────────────────────────────────────────────────────────────────────────
# ── Lifecycle ─────────────────────────────────────────────────────────────────
async def check_database_connection() -> bool:
    """Verify the database is reachable."""
    try:
        async with async_engine.connect() as conn:
            await conn.execute(text("SELECT 1"))
        return True
    except Exception as exc:  # noqa: BLE001
        logger.warning("Database connectivity check failed: %s", exc)
        return False


async def dispose_database() -> None:
    """Dispose of all engine pools (call on app shutdown)."""
    await async_engine.dispose()
    sync_engine.dispose()
    logger.info("Database engines disposed")


# ─────────────────────────────────────────────────────────────────────────────
# ── Dependency injection ─────────────────────────────────────────────────────
async def get_async_db() -> AsyncIterator[AsyncSession]:
    """FastAPI dependency that yields an async session with auto-commit."""
    async with AsyncSessionLocal() as session:
        try:
            yield session
            await session.commit()
        except Exception:
            await session.rollback()
            raise
        finally:
            await session.close()


def get_db() -> Iterator[Session]:
    """Sync dependency for scripts / legacy routes."""
    db = SessionLocal()
    try:
        yield db
        db.commit()
    except Exception:
        db.rollback()
        raise
    finally:
        db.close()


# ─────────────────────────────────────────────────────────────────────────────
# ── Transaction handling ──────────────────────────────────────────────────────
@asynccontextmanager
async def transaction(session: AsyncSession) -> AsyncIterator[AsyncSession]:
    """Flattened transaction scope: commits on success, rolls back on error."""
    try:
        yield session
        await session.commit()
    except Exception:
        await session.rollback()
        raise


@asynccontextmanager
async def unit_of_work() -> AsyncIterator[AsyncSession]:
    """
    Full unit-of-work context manager.

    Usage:
        async with unit_of_work() as uow:
            uow.add(obj)
        # auto-commited on success, rolled back on failure
    """
    async with AsyncSessionLocal() as session:
        try:
            yield session
            await session.commit()
        except Exception:
            await session.rollback()
            raise
        finally:
            await session.close()


def require_db_session():
    """Placeholder for future eager-connect checks."""
    return None