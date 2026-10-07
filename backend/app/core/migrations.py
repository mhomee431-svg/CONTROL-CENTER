"""Run database schema migrations safely during application startup."""

from pathlib import Path

from alembic import command
from alembic.config import Config
from sqlalchemy import Engine, inspect, text

from app.core.database import engine
from app.models import Base

_MIGRATION_LOCK_ID = 724231
_ALEMBIC_CONFIG = Path(__file__).resolve().parents[2] / "alembic.ini"


def upgrade_database(target_engine: Engine = engine) -> None:
    config = Config(str(_ALEMBIC_CONFIG))
    config.set_main_option("script_location", str(_ALEMBIC_CONFIG.parent / "alembic"))

    with target_engine.connect() as connection:
        uses_postgres_lock = target_engine.dialect.name == "postgresql"
        if uses_postgres_lock:
            connection.execute(
                text("SELECT pg_advisory_lock(:lock_id)"),
                {"lock_id": _MIGRATION_LOCK_ID},
            )
            connection.commit()

        config.attributes["connection"] = connection
        try:
            existing_tables = set(inspect(connection).get_table_names())
            if "alembic_version" not in existing_tables:
                legacy_tables = set(Base.metadata.tables) - {"operational_events"}
                present_legacy_tables = existing_tables & legacy_tables
                if present_legacy_tables and not legacy_tables.issubset(existing_tables):
                    missing = ", ".join(sorted(legacy_tables - existing_tables))
                    raise RuntimeError(
                        "Cannot adopt the existing database schema: expected legacy tables "
                        f"are missing ({missing})"
                    )
                if present_legacy_tables:
                    command.stamp(config, "0001_initial_schema")
                    connection.commit()
            command.upgrade(config, "head")
            connection.commit()
        finally:
            if uses_postgres_lock:
                connection.rollback()
                released = connection.scalar(
                    text("SELECT pg_advisory_unlock(:lock_id)"),
                    {"lock_id": _MIGRATION_LOCK_ID},
                )
                connection.commit()
                if not released:
                    raise RuntimeError("Failed to release the database migration lock")
