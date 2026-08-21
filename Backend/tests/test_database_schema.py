"""Database schema validation tests for Phase 13 Expanded Architecture.

Verifies:
- The PostGIS extension is enabled
- All expected tables exist
- Enums were created properly
- Key relationships (RBAC join table, inventory references, etc.)

NOTE: These are integration tests that require a running PostgreSQL/PostGIS
database. They are skipped automatically when the database is unreachable.
"""
import asyncio

import pytest
from sqlalchemy import inspect, text

from app.database.session import AsyncSessionLocal


EXPECTED_TABLES = {
    # RBAC
    "roles",
    "permissions",
    "role_permissions",
    # Core
    "users",
    "customers",
    "customer_addresses",
    # Shops
    "shops",
    "shop_owners",
    "shop_managers",
    "shop_addresses",
    "shop_hours",
    "shop_holidays",
    "shop_documents",
    "shop_verifications",
    # Products
    "brands",
    "categories",
    "product_masters",
    "product_variants",
    "product_images",
    "product_attributes",
    "product_attribute_values",
    "product_identifiers",
    "barcode_relationships",
    "shop_products",
    "inventory",
    "inventory_movements",
    "inventory_adjustments",
    "price_history",
    "offers",
    "offer_products",
    "offer_conditions",
    # Search
    "search_history",
    "search_events",
    "popular_searches",
    "barcode_scans",
    # POS
    "pos_integrations",
    "pos_devices",
    "pos_sync_jobs",
    "pos_sync_logs",
    # Notifications
    "notifications",
    "notification_preferences",
    "device_tokens",
    # Admin
    "admin_actions",
    "admin_notes",
    "product_approvals",
    "reports",
    "complaints",
    "audit_logs",
    # Analytics
    "product_views",
    "shop_views",
    "product_clicks",
    "inventory_events",
    "system_metrics",
    # System
    "system_settings",
    "feature_flags",
    # Subscriptions
    "subscription_plans",
    "subscriptions",
    "payments",
    # Saved
    "saved_products",
    "saved_shops",
}

EXPECTED_ENUMS = {
    "user_status",
    "shop_status",
    "verification_status",
    "product_status",
    "shop_product_status",
    "stock_status",
    "inventory_source",
    "offer_status",
    "offer_type",
    "approval_status",
    "complaint_status",
    "pos_integration_status",
    "pos_sync_status",
    "subscription_status",
    "billing_cycle",
    "identifier_type",
}


def _database_available() -> bool:
    """Probe the database with a short timeout; return False if unreachable."""
    try:
        import asyncpg

        async def _probe():
            conn = await asyncpg.connect(
                dsn=AsyncSessionLocal().bind.url.render_as_string(hide_password=True)
            )
            await conn.close()
            return True
        return asyncio.run(_probe())
    except Exception:
        return False


requires_db = pytest.mark.skipif(
    not _database_available(),
    reason="PostgreSQL integration test — requires a running database",
)


async def _run_sync(session, fn):
    """Run a sync fn against the async session's connection."""
    conn = await session.connection()
    return await conn.run_sync(fn)


@requires_db
def test_postgis_extension_enabled():
    """The PostGIS extension must be enabled."""
    async def _check():
        async with AsyncSessionLocal() as session:
            result = await session.execute(text("SELECT PostGIS_Version()"))
            return result.scalar() is not None
    assert asyncio.run(_check())


@requires_db
def test_all_expected_tables_exist():
    """All expected tables must exist."""
    async def _check():
        async with AsyncSessionLocal() as session:
            def _get_tables(conn):
                insp = inspect(conn)
                return set(insp.get_table_names())
            tables = await _run_sync(session, _get_tables)
            return EXPECTED_TABLES - tables
    missing = asyncio.run(_check())
    assert not missing, f"Missing tables: {missing}"


@requires_db
def test_expected_enums_exist():
    """All expected enum types must exist."""
    async def _check():
        async with AsyncSessionLocal() as session:
            def _get_enums(conn):
                rows = conn.execute(
                    text("SELECT typname FROM pg_type WHERE typtype = 'e'")
                ).fetchall()
                return {row[0] for row in rows}
            enums = await _run_sync(session, _get_enums)
            return EXPECTED_ENUMS - enums
    missing = asyncio.run(_check())
    assert not missing, f"Missing enums: {missing}"


@requires_db
def test_role_permissions_join_table_exists():
    """The role_permissions association table must exist."""
    async def _check():
        async with AsyncSessionLocal() as session:
            def _has_table(conn):
                return inspect(conn).has_table("role_permissions")
            return await _run_sync(session, _has_table)
    assert asyncio.run(_check()) is True


@requires_db
def test_shop_products_relationship_columns():
    """shop_products must have the expected FK columns."""
    async def _check():
        async with AsyncSessionLocal() as session:
            def _get_cols(conn):
                return {
                    c["name"]
                    for c in inspect(conn).get_columns("shop_products")
                }
            return await _run_sync(session, _get_cols)
    cols = asyncio.run(_check())
    assert "shop_id" in cols
    assert "product_master_id" in cols
    assert "variant_id" in cols
    assert "price" in cols
    assert "is_available" in cols
    assert "stock_status" in cols


@requires_db
def test_inventory_has_shop_product_fk():
    """inventory must reference shop_products for auditability."""
    async def _check():
        async with AsyncSessionLocal() as session:
            def _cols(conn):
                return {
                    c["name"]
                    for c in inspect(conn).get_columns("inventory")
                }
            return await _run_sync(session, _cols)
    cols = asyncio.run(_check())
    assert "shop_product_id" in cols
    assert "quantity" in cols
    assert "stock_status" in cols
    assert "is_available" in cols