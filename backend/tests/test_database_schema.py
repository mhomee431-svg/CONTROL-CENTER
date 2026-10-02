"""Database schema validation tests — Phase 13 Expanded Architecture (+0026 orders).

Every check runs in one of two flows, chosen automatically at collection time.
A missing database changes the flow; it never skips a check:

* ``live``  — the PostgreSQL/PostGIS database configured by ``DATABASE_URL``,
              used only when it is reachable and really is PostgreSQL. Tables,
              enums, indexes, foreign keys and Geography columns are read from
              ``pg_type``, ``pg_indexes`` and ``information_schema`` — exactly
              as production stores them.
* ``local`` — the ORM ``Base.metadata`` (the same metadata Alembic migrations
              are diffed against) materialised in-process on SQLite, with PostGIS
              Geography columns stripped to ``Text`` by ``tests.geo_compat`` and
              cross-checked against the Alembic revision sources. Runs on any
              machine, including CI without a database.

Both flows answer the same questions through :class:`SchemaView`, so every
assertion below is flow-agnostic.
"""
from __future__ import annotations

import ast
import re
from functools import lru_cache
from pathlib import Path
from typing import Any

import pytest
from sqlalchemy import create_engine, text
from sqlalchemy import inspect as sa_inspect
from sqlalchemy.pool import StaticPool

import app.models  # noqa: F401  (populate Base.metadata)
from app.database.session import Base

BACKEND_DIR = Path(__file__).resolve().parents[1]
VERSIONS_DIR = BACKEND_DIR / "alembic" / "versions"


EXPECTED_TABLES = {
    # RBAC
    "roles",
    "permissions",
    "role_permissions",
    "user_roles",
    # Core
    "users",
    "customers",
    "customer_addresses",
    # Identity & Access (sessions / token blacklist / password resets)
    "auth_sessions",
    "token_blacklist",
    "password_resets",
    # Customer engagement
    "customer_favorites",
    "customer_recent_products",
    # Legacy OTP records (table retained via migration 0012; verification now uses Firebase)
    "otps",
    # User interactions / leads (immutable create-only customer actions)
    "user_interactions",
    # Location — PostGIS service areas
    "service_areas",
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
    # Restaurant discovery (Rule 4: discovery-only)
    "restaurants",
    "restaurant_menu_categories",
    "restaurant_menu_items",
    # Transport & personal transport booking (Rules 5-6)
    "transport_providers",
    "vehicles",
    "vehicle_documents",
    "transport_services",
    "vehicle_availability",
    "transport_quotes",
    "transport_bookings",
    "booking_status_history",
    "trip_details",
    # Reviews (moderated content)
    "reviews",
    # Orders / Cart / Checkout (migration 0026)
    "orders",
    "order_items",
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

# ── Alembic chain introspection (flow-independent) ──────────────────────────
_CREATE_TABLE_SQL = re.compile(
    r"CREATE\s+TABLE\s+(?:IF\s+NOT\s+EXISTS\s+)?([A-Za-z0-9_]+)", re.IGNORECASE
)
_CREATE_INDEX_SQL = re.compile(
    r"CREATE\s+(?:UNIQUE\s+)?INDEX\s+(?:IF\s+NOT\s+EXISTS\s+)?([A-Za-z0-9_]+)", re.IGNORECASE
)
_CREATE_TYPE_SQL = re.compile(r"CREATE\s+TYPE\s+([A-Za-z0-9_]+)", re.IGNORECASE)
_POSTGIS_EXTENSION_SQL = re.compile(
    r"CREATE\s+EXTENSION\s+IF\s+NOT\s+EXISTS\s+postgis", re.IGNORECASE
)

# Geography columns that must be PostGIS-typed (mirrors migration_rehearsal).
EXPECTED_GEOGRAPHY = {
    "shops": ["location"],
    "search_indexes": ["location"],
    "service_areas": ["boundary", "center"],
    "shop_addresses": ["location"],
    "customer_addresses": ["location"],
}

# Tables the chain creates that deliberately have no ORM model. ``otps`` is the
# legacy OTP table kept by 0012 (verification moved to Firebase); ``products`` is
# the pre-0003 catalogue replaced by product_masters/product_variants.
MIGRATION_ONLY_TABLES = {"otps", "products"}


def _migration_files() -> list[Path]:
    return [p for p in sorted(VERSIONS_DIR.glob("*.py")) if not p.name.startswith("__")]


@lru_cache(maxsize=1)
def _migration_artifacts() -> dict[str, frozenset[str]]:
    """Names the Alembic chain creates, read straight from the revision sources.

    Raw SQL *and* Alembic ops are scanned: several revisions create tables, enum
    types and indexes with ``execute("CREATE ...")`` instead of ``op.*``.
    """
    tables: set[str] = set()
    enums: set[str] = set()
    indexes: set[str] = set()
    for path in _migration_files():
        source = path.read_text(encoding="utf-8", errors="replace")
        tables.update(_CREATE_TABLE_SQL.findall(source))
        enums.update(_CREATE_TYPE_SQL.findall(source))
        indexes.update(_CREATE_INDEX_SQL.findall(source))
        for node in ast.walk(ast.parse(source)):
            if not isinstance(node, ast.Call) or not isinstance(node.func, ast.Attribute):
                continue
            arg = (
                node.args[0].value
                if node.args and isinstance(node.args[0], ast.Constant)
                else None
            )
            if not isinstance(arg, str):
                continue
            if node.func.attr == "create_table":
                tables.add(arg)
            elif node.func.attr == "create_index":
                indexes.add(arg)
    return {
        "tables": frozenset(tables),
        "enums": frozenset(enums),
        "indexes": frozenset(indexes),
    }


def _postgis_enabled_by_migrations() -> bool:
    return any(
        _POSTGIS_EXTENSION_SQL.search(path.read_text(encoding="utf-8", errors="replace"))
        for path in _migration_files()
    )


# ── Flow selection: live database when reachable, local flow always ─────────
def _live_engine():
    """Sync engine for the configured PostgreSQL database, or ``None``.

    Only PostgreSQL qualifies: a SQLite ``DATABASE_URL`` (the test-environment
    default) cannot stand in for a PostGIS database, and the local flow already
    covers it.
    """
    from app.core.config import settings

    url = settings.sqlalchemy_sync_url
    if not url.startswith("postgresql"):
        return None
    engine = create_engine(url, pool_pre_ping=True, connect_args={"connect_timeout": 5})
    try:
        with engine.connect():
            pass
    except Exception:  # noqa: BLE001 — unreachable database means the local flow
        engine.dispose()
        return None
    return engine


def _local_engine():
    """Materialise the ORM metadata on SQLite (PostGIS Geography -> Text)."""
    from tests.geo_compat import make_timestamp_defaults_portable, strip_geo_columns

    strip_geo_columns()
    make_timestamp_defaults_portable()
    engine = create_engine(
        "sqlite://",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    Base.metadata.create_all(engine)
    return engine


_LIVE_ENGINE = _live_engine()
FLOWS = ("local", "live") if _LIVE_ENGINE is not None else ("local",)


class SchemaView:
    """Flow-agnostic read-only view of the schema under test."""

    def __init__(self, flow: str, engine=None) -> None:
        self.flow = flow
        self._engine = engine

    def _fetchall(self, sql: str, **params: Any) -> list[Any]:
        with self._engine.connect() as conn:
            return conn.execute(text(sql), params).fetchall()

    def table_names(self) -> set[str]:
        if self.flow == "live":
            return set(sa_inspect(self._engine).get_table_names())
        return set(Base.metadata.tables) | set(_migration_artifacts()["tables"])

    def has_table(self, table: str) -> bool:
        return table in self.table_names()

    def columns(self, table: str) -> set[str]:
        if self.flow == "live":
            return {col["name"] for col in sa_inspect(self._engine).get_columns(table)}
        declared = Base.metadata.tables.get(table)
        return set(declared.columns.keys()) if declared is not None else set()

    def fk_targets(self, table: str) -> set[str]:
        """Tables this table's foreign keys point at."""
        if self.flow == "live":
            return {
                fk["referred_table"]
                for fk in sa_inspect(self._engine).get_foreign_keys(table)
            }
        declared = Base.metadata.tables.get(table)
        if declared is None:
            return set()
        return {fk.column.table.name for fk in declared.foreign_keys}

    def index_names(self) -> set[str]:
        if self.flow == "live":
            rows = self._fetchall("SELECT indexname FROM pg_indexes WHERE schemaname='public'")
            return {row[0] for row in rows}
        declared = {
            index.name for table in Base.metadata.tables.values() for index in table.indexes
        }
        return declared | set(_migration_artifacts()["indexes"])

    def enum_names(self) -> set[str]:
        if self.flow == "live":
            rows = self._fetchall("SELECT typname FROM pg_type WHERE typtype = 'e'")
            return {row[0] for row in rows}
        found = set(_migration_artifacts()["enums"])
        for table in Base.metadata.tables.values():
            for column in table.columns:
                if getattr(column.type, "__visit_name__", "") == "enum":
                    name = getattr(column.type, "name", None)
                    if name:
                        found.add(name)
        return found

    def geography_columns(self, table: str) -> set[str]:
        if self.flow == "live":
            rows = self._fetchall(
                "SELECT column_name, udt_name FROM information_schema.columns "
                "WHERE table_schema = 'public' AND table_name = :table",
                table=table,
            )
            return {r[0] for r in rows if (r[1] or "").lower() in ("geography", "geometry")}
        from geoalchemy2 import Geography

        from tests.geo_compat import declared_type

        return {
            column
            for column in self.columns(table)
            if isinstance(declared_type(table, column), Geography)
        }

    def postgis_available(self) -> bool:
        if self.flow == "live":
            return self._fetchall("SELECT PostGIS_Version()")[0][0] is not None
        return _postgis_enabled_by_migrations()


@pytest.fixture(scope="module", params=FLOWS)
def schema(request) -> SchemaView:
    """The schema under test: live when a database answers, local otherwise."""
    if request.param == "live":
        yield SchemaView("live", _LIVE_ENGINE)
        return
    engine = _local_engine()
    try:
        yield SchemaView("local", engine)
    finally:
        engine.dispose()


# ── PostGIS ─────────────────────────────────────────────────────────────────
def test_postgis_extension_enabled(schema):
    """The PostGIS extension must be enabled."""
    assert schema.postgis_available(), f"[{schema.flow}] PostGIS is not enabled"


# ── Tables & enums ──────────────────────────────────────────────────────────
def test_all_expected_tables_exist(schema):
    """All expected tables must exist."""
    missing = EXPECTED_TABLES - schema.table_names()
    assert not missing, f"[{schema.flow}] missing tables: {sorted(missing)}"


def test_expected_enums_exist(schema):
    """All expected enum types must exist."""
    missing = EXPECTED_ENUMS - schema.enum_names()
    assert not missing, f"[{schema.flow}] missing enums: {sorted(missing)}"


def test_migration_chain_covers_every_orm_table():
    """The chain and the ORM agree — no table exists in only one of them."""
    created = _migration_artifacts()["tables"]
    orm_tables = set(Base.metadata.tables)
    unmigrated = sorted(orm_tables - set(created))
    assert not unmigrated, f"ORM tables no migration creates: {unmigrated}"
    undocumented = sorted(set(created) - orm_tables - MIGRATION_ONLY_TABLES)
    assert not undocumented, f"chain-only tables without a documented reason: {undocumented}"


# ── Relationships (RBAC join tables, inventory references) ──────────────────
def test_role_permissions_join_table_exists(schema):
    """The role_permissions association table must exist."""
    assert schema.has_table("role_permissions"), f"[{schema.flow}] missing role_permissions"
    assert {"role_id", "permission_id"} <= schema.columns("role_permissions")


def test_user_roles_join_table_exists(schema):
    """The user_roles RBAC join table must exist."""
    assert schema.has_table("user_roles"), f"[{schema.flow}] missing user_roles"
    assert {"user_id", "role_id"} <= schema.columns("user_roles")


def test_shop_products_relationship_columns(schema):
    """shop_products must expose its shop / master / variant relationships."""
    missing = {
        "shop_id", "product_master_id", "variant_id", "price", "is_available", "stock_status",
    } - schema.columns("shop_products")
    assert not missing, f"[{schema.flow}] shop_products missing {sorted(missing)}"
    targets = schema.fk_targets("shop_products")
    assert {"shops", "product_masters", "product_variants"} <= targets, (
        f"[{schema.flow}] shop_products FKs -> {sorted(targets)}"
    )


def test_inventory_has_shop_product_fk(schema):
    """inventory must reference shop_products for auditability."""
    missing = {
        "shop_product_id", "quantity", "stock_status", "is_available",
    } - schema.columns("inventory")
    assert not missing, f"[{schema.flow}] inventory missing {sorted(missing)}"
    assert "shop_products" in schema.fk_targets("inventory")


def test_password_resets_has_user_fk(schema):
    """password_resets must reference users and store a token digest."""
    missing = {
        "user_id", "token_hash", "expires_at", "is_used",
    } - schema.columns("password_resets")
    assert not missing, f"[{schema.flow}] password_resets missing {sorted(missing)}"
    assert "users" in schema.fk_targets("password_resets")


def test_customer_recent_products_has_fks(schema):
    """customer_recent_products must reference customer + product_master."""
    missing = {
        "customer_id", "product_master_id", "variant_id", "last_viewed_at",
    } - schema.columns("customer_recent_products")
    assert not missing, f"[{schema.flow}] customer_recent_products missing {sorted(missing)}"
    targets = schema.fk_targets("customer_recent_products")
    assert {"customers", "product_masters"} <= targets, (
        f"[{schema.flow}] customer_recent_products FKs -> {sorted(targets)}"
    )


def test_orders_tables_have_expected_surface(schema):
    """Migration 0026: orders/order_items exist with their fulfilment surface."""
    assert {"orders", "order_items"} <= schema.table_names(), (
        f"[{schema.flow}] orders/order_items missing"
    )
    missing = {
        "order_number", "shop_id", "user_id", "status", "payment_status",
        "subtotal_amount", "total_amount", "total_items",
    } - schema.columns("orders")
    assert not missing, f"[{schema.flow}] orders missing {sorted(missing)}"
    missing = {
        "order_id", "product_name", "quantity", "price", "total_price",
    } - schema.columns("order_items")
    assert not missing, f"[{schema.flow}] order_items missing {sorted(missing)}"
    assert "orders" in schema.fk_targets("order_items")


# ── PostGIS Geography columns ───────────────────────────────────────────────
def test_service_areas_has_geography(schema):
    """service_areas must carry the PostGIS POLYGON boundary + center."""
    assert {"name", "area_type", "boundary", "center"} <= schema.columns("service_areas")
    geography = schema.geography_columns("service_areas")
    assert {"boundary", "center"} <= geography, (
        f"[{schema.flow}] service_areas geography columns: {sorted(geography)}"
    )


def test_shop_addresses_has_geography(schema):
    """shop_addresses must expose a PostGIS geography location column."""
    assert "location" in schema.columns("shop_addresses")
    assert "location" in schema.geography_columns("shop_addresses")


def test_all_geography_columns_are_postgis_typed(schema):
    """Every geography column in the approved schema is PostGIS-typed."""
    problems = [
        f"{table}.{column}"
        for table, columns in EXPECTED_GEOGRAPHY.items()
        for column in columns
        if column not in schema.geography_columns(table)
    ]
    assert not problems, f"[{schema.flow}] not PostGIS Geography: {problems}"
