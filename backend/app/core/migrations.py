"""Run database schema migrations safely during application startup."""

from pathlib import Path

from alembic import command
from alembic.config import Config
from sqlalchemy import Engine, inspect, text

from app.core.database import engine

_MIGRATION_LOCK_ID = 724231
_ALEMBIC_CONFIG = Path(__file__).resolve().parents[2] / "alembic.ini"
_LEGACY_BASELINE_TABLES = {
    "admin_notes",
    "admin_users",
    "announcements",
    "audit_logs",
    "banners",
    "brands",
    "categories",
    "complaints",
    "faqs",
    "feature_flags",
    "help_content",
    "import_errors",
    "import_jobs",
    "inventory_history",
    "notification_campaigns",
    "offers",
    "payments",
    "pos_integrations",
    "pos_sync_runs",
    "products",
    "product_variants",
    "promotional_cards",
    "revoked_admin_tokens",
    "search_queries",
    "shop_documents",
    "shop_inventory",
    "shop_pricing",
    "shops",
    "subscriptions",
    "system_messages",
    "system_settings",
    "users",
}


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
                present_legacy_tables = existing_tables & _LEGACY_BASELINE_TABLES
                if present_legacy_tables and not _LEGACY_BASELINE_TABLES.issubset(existing_tables):
                    missing = ", ".join(sorted(_LEGACY_BASELINE_TABLES - existing_tables))
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
