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