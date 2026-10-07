from sqlalchemy import create_engine, inspect, text

from app.core.migrations import upgrade_database
from app.models import Base, OperationalEvent


def test_upgrade_database_applies_initial_schema_and_is_repeatable(tmp_path):
    database_path = tmp_path / "migration-test.db"
    engine = create_engine(f"sqlite:///{database_path}")

    upgrade_database(engine)
    upgrade_database(engine)

    with engine.connect() as connection:
        tables = set(inspect(connection).get_table_names())
        revision = connection.scalar(text("SELECT version_num FROM alembic_version"))

    assert "admin_users" in tables
    assert "shops" in tables
    assert "operational_events" in tables
    assert revision == "0002_operational_events"
    engine.dispose()


def test_upgrade_database_adopts_existing_legacy_schema(tmp_path):
    database_path = tmp_path / "legacy-test.db"
    engine = create_engine(f"sqlite:///{database_path}")
    legacy_tables = [
        table for table in Base.metadata.sorted_tables if table is not OperationalEvent.__table__
    ]
    Base.metadata.create_all(engine, tables=legacy_tables)

    upgrade_database(engine)

    with engine.connect() as connection:
        tables = set(inspect(connection).get_table_names())
        revision = connection.scalar(text("SELECT version_num FROM alembic_version"))

    assert "operational_events" in tables
    assert revision == "0002_operational_events"
    engine.dispose()
