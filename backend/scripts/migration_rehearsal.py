#!/usr/bin/env python
"""Phase 26 — automated database migration rehearsal

Proves, against a throwaway (scratch) PostGIS database on the SAME server as
``DATABASE_URL``, that the versioned Alembic chain satisfies every guarantee
normal development relies on — nothing is taken on faith:

  1. CHAIN INTEGRITY (static, no DB) — linear, single-head, every revision
     resolves, revisions are sequential integers.
  2. FORWARD MIGRATION  — ``alembic upgrade head`` from an empty database
     succeeds and leaves ``alembic_version`` at the computed head.
  3. ROLLBACK (where supported) — ``alembic downgrade -1`` from head reverses
     the newest revision, and ``--full-chain-rollback`` also walks the ENTIRE
     chain ``downgrade base`` and re-applies ``upgrade head`` cleanly.
  4. DATA SAFETY —
       static: every ``add_column(..., nullable=False)`` on an existing table
       must ship a ``server_default`` (or an explicit backfill).
       live: a drill row is inserted into a stable table, a ``-1`` downgrade /
       re-upgrade round-trip must preserve it.
  5. INDEX CREATION — representative migration-created indexes (btree,
     composite, GIN trigram) exist after ``upgrade head``.
  6. FOREIGN KEYS — representative FKs exist in ``pg_constraint`` AND are
     enforced (a deliberately orphaned insert must raise an integrity error).
  7. POSTGIS CHANGES — the ``postgis`` extension is installed, Geography
     columns are correctly typed, and spatial GiST indexes exist.

The scratch database is created and dropped by the drill; ``DATABASE_URL``
itself is NEVER modified. Safe in CI or locally.

Usage:
    DATABASE_URL=postgresql+asyncpg://... python scripts/migration_rehearsal.py
    python scripts/migration_rehearsal.py --full-chain-rollback
    python scripts/migration_rehearsal.py --chain-only   # static checks only

Options:
    --versions-dir DIR       migrations dir (default backend/alembic/versions)
    --scratch-db-name NAME    scratch database name (default hyperlocal_rehearsal_<ts>)
    --full-chain-rollback    also drill downgrade base -> upgrade head
    --chain-only             only static checks (chain integrity + data-safety)
    --report-file PATH       JSON report (default migration_rehearsal_report.json)
    --no-cleanup             keep the scratch database (debugging)

Exit codes: 0 = all checks passed, 2 = chain/policy violation, 1 = error.
"""
from __future__ import annotations

import argparse
import ast
import json
import os
import re
import subprocess
import sys
import time
import urllib.parse
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, List, Optional

# Backend directory (scripts/..) so `app` is importable when needed by callers.
BACKEND_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BACKEND_DIR))

try:
    import psycopg
except ImportError:  # pragma: no cover — chain-only (static) mode still works
    psycopg = None  # type: ignore[assignment]
import sqlalchemy as sa
from sqlalchemy import create_engine, text

DEFAULT_VERSIONS_DIR = BACKEND_DIR / "alembic" / "versions"


def to_sync_url(url: str) -> str:
    """Convert an async SQLAlchemy URL to the psycopg (sync) form."""
    for prefix in ("postgresql+asyncpg://", "postgres+asyncpg://",
                   "postgresql+psycopg://", "postgres+psycopg://"):
        if url.startswith(prefix):
            url = url.replace(prefix, "postgresql://", 1)
            break
    if not url.startswith("postgresql://"):
        url = url.replace("postgresql://", "postgresql://", 1)
    return url.replace("ssl=require", "sslmode=require")


def db_name_of(url: str) -> str:
    return urllib.parse.urlsplit(url).path.rstrip("/").rsplit("/", 1)[-1]


def swap_db(url: str, dbname: str) -> str:
    parsed = urllib.parse.urlsplit(url)
    return urllib.parse.urlunsplit(parsed._replace(path="/" + dbname))


# ─────────────────────────────────────────────────────────────────────────────
# 1. Chain integrity (static — no database required)
# ─────────────────────────────────────────────────────────────────────────────
def revision_meta(source: str) -> tuple[Optional[str], Optional[str]]:
    """Return ``(revision, down_revision)`` from a revision file's source."""
    revision: Optional[str] = None
    down: Optional[str] = None
    try:
        tree = ast.parse(source)
        for node in ast.walk(tree):
            if isinstance(node, ast.Assign) and any(
                isinstance(t, ast.Name) and t.id in ("revision", "down_revision")
                for t in node.targets
            ):
                for tgt in node.targets:
                    if not isinstance(tgt, ast.Name):
                        continue
                    if not isinstance(node.value, ast.Constant) or not isinstance(
                        node.value.value, str
                    ):
                        continue
                    if tgt.id == "revision":
                        revision = node.value.value
                    elif tgt.id == "down_revision":
                        down = node.value.value
            elif isinstance(node, ast.AnnAssign) and isinstance(node.target, ast.Name):
                if not isinstance(node.value, ast.Constant) or not isinstance(
                    node.value.value, str
                ):
                    continue
                if node.target.id == "revision":
                    revision = node.value.value
                elif node.target.id == "down_revision":
                    down = node.value.value
    except SyntaxError:
        pass
    return revision, down


def parse_revisions(versions_dir: Path) -> List[Dict[str, str]]:
    """List every revision with its file, revision id and down_revision."""
    revisions: List[Dict[str, str]] = []
    for path in sorted(Path(versions_dir).glob("*.py")):
        if path.name.startswith("__"):
            continue
        src = path.read_text(encoding="utf-8", errors="replace")
        rev, down = revision_meta(src)
        if rev is None:
            continue  # not a revision file / unparseable
        revisions.append({"file": path.name, "revision": rev, "down_revision": down})
    return revisions


def head_revision(revisions: List[Dict[str, str]]) -> Optional[str]:
    """Return the single head (the revision nobody is the down_revision of)."""
    if not revisions:
        return None
    ids = {r["revision"] for r in revisions}
    referenced = {r["down_revision"] for r in revisions if r.get("down_revision")}
    heads = ids - referenced
    if len(heads) == 1:
        return next(iter(heads))
    return None


def chain_issues(revisions: List[Dict[str, str]]) -> List[str]:
    """Human-readable chain-integrity problems (empty = OK)."""
    issues: List[str] = []
    if not revisions:
        return ["no revisions found"]
    ids = [r["revision"] for r in revisions]
    if len(ids) != len(set(ids)):
        issues.append("duplicate revision ids found")
    id_set = set(ids)
    for r in revisions:
        down = r.get("down_revision")
        if down is not None and down not in id_set:
            issues.append(f"{r['file']}: down_revision {down!r} does not exist")
        if down is None and r["revision"] != "0001":
            issues.append(f"{r['file']}: revision {r['revision']} is a base but != 0001")
    # Linear: a revision may be referenced as down_revision at most once.
    referenced = [r["down_revision"] for r in revisions if r.get("down_revision")]
    if len(referenced) != len(set(referenced)):
        issues.append("chain is NOT linear (a revision has multiple children — a fork)")
    head = head_revision(revisions)
    if head is None:
        issues.append("no single head revision (multiple heads / circular chain)")
    nums: List[int] = []
    for r in revisions:
        try:
            nums.append(int(r["revision"]))
        except ValueError:
            issues.append(f"{r['file']}: revision {r['revision']!r} is not numeric")
    if nums and sorted(nums) != nums:
        issues.append("revision ids are not in ascending order")
    # Revisions must form one contiguous 0001..N sequence (project convention).
    if nums and nums != list(range(min(nums), max(nums) + 1)):
        issues.append("revision ids have gaps (must be contiguous 0001..N)")
    return issues


# ─────────────────────────────────────────────────────────────────────────────
# 2. Data-safety policy (static — no database required)
# ─────────────────────────────────────────────────────────────────────────────
def scan_data_safety_violations(versions_dir: Path) -> List[Dict[str, Any]]:
    """Flag ``op.add_column(<table>, Column(..., nullable=False))`` calls that do
    NOT ship a ``server_default``.

    Adding a hard NOT NULL column to a populated table without a server default
    (or a separate data-backfill step) breaks every existing row — the classic
    deployment-time data loss. Returns a list of violation records.
    """
    violations: List[Dict[str, Any]] = []
    for path in sorted(Path(versions_dir).glob("*.py")):
        if path.name.startswith("__"):
            continue
        try:
            tree = ast.parse(path.read_text(encoding="utf-8", errors="replace"))
        except SyntaxError:
            continue
        for node in ast.walk(tree):
            if not isinstance(node, ast.Call):
                continue
            if not (isinstance(node.func, ast.Attribute) and node.func.attr == "add_column"):
                continue
            table = "?"
            if node.args and isinstance(node.args[0], ast.Constant) and isinstance(
                node.args[0].value, str
            ):
                table = node.args[0].value
            column_call = None
            if len(node.args) > 1 and isinstance(node.args[1], ast.Call):
                column_call = node.args[1]
            if column_call is None:
                continue
            nullable_false = server_default = False
            for kw in column_call.keywords:
                if kw.arg is None:
                    continue
                if kw.arg == "nullable" and isinstance(kw.value, ast.Constant):
                    nullable_false = kw.value.value is False
                if kw.arg == "server_default":
                    server_default = True
            if nullable_false and not server_default:
                violations.append({
                    "file": path.name,
                    "line": getattr(node, "lineno", 0),
                    "table": table,
                    "detail": "add_column(..., nullable=False) without server_default "
                              "on an existing table — every existing row would get NULL",
                })
    return violations


# ─────────────────────────────────────────────────────────────────────────────
# 3. Live schema-surface verification (requires an engine)
# ─────────────────────────────────────────────────────────────────────────────
# Representative surface the migrations must have created. Keep these lists in
# sync with the latest revision; the rehearsal fails when any is missing.
EXPECTED_TABLES: set[str] = {
    "users", "roles", "permissions", "shops", "shop_products", "product_masters",
    "inventory", "search_indexes", "search_index_sync_runs", "service_areas",
    "restaurants", "restaurant_menu_categories", "restaurant_menu_items",
    "subscriptions", "notifications", "customer_favorites", "auth_sessions",
    "saved_products", "saved_shops",
    # 0016 transport & personal transport booking (Rules 5-6)
    "transport_providers", "vehicles", "vehicle_documents", "transport_services",
    "vehicle_availability", "transport_quotes", "transport_bookings",
    "booking_status_history", "trip_details",
    # 0017 reviews + pharmacy compliance
    "reviews",
    # 0019 merchant onboarding & verification
    "merchant_categories", "merchant_verification_requirements",
    "merchant_onboardings", "business_identity_verifications",
    "bank_account_verifications", "category_document_verifications",
    "verification_attempts", "verification_provider_logs",
}
EXPECTED_INDEXES: set[str] = {
    "ix_users_phone_number",                # 0001 unique
    "ix_search_index_shop_available",       # 0006 composite filter index
    "ix_search_index_shop_rating",          # 0006 composite filter index
    "ix_search_index_barcode_trgm",         # 0006 GIN trigram
    "ix_search_index_search_text_trgm",     # 0006 GIN trigram
    "ix_search_index_search_vector",        # 0006 GIN trigram on search_vector
    "ix_restaurant_menu_categories_restaurant_id",  # 0015
    "ix_restaurant_menu_items_restaurant_id",       # 0015
    "ix_restaurant_menu_items_menu_category_id",    # 0015
    "ix_service_areas_pincode_prefix",      # 0014
    "ix_vehicles_provider_id",              # 0016
    "ix_transport_quotes_customer_user_id", # 0016
    "ix_transport_bookings_customer_user_id",  # 0016
    "ix_transport_bookings_booking_ref",    # 0016 unique
    "ix_booking_status_history_booking_id", # 0016
    "ix_trip_details_booking_id",           # 0016 unique
    "ix_reviews_shop_status",               # 0017 composite filter index
    "ix_product_masters_prescription_required",  # 0017 partial index
    # 0019 merchant onboarding & verification
    "ix_merchant_onboardings_status",       # 0019
    "ix_merchant_onboardings_user_id",      # 0019
    "ix_business_identity_verifications_onboarding",  # 0019
    "ix_bank_account_verifications_onboarding",       # 0019
    "ix_category_document_verifications_onboarding",  # 0019
    "ix_verification_attempts_onboarding",  # 0019
    "ix_verification_provider_logs_onboarding",  # 0019
}
# (table, expected default Alembic FK constraint name). Default naming is
# {table}_{columns}_fkey unless the migration named it explicitly.
EXPECTED_FKS: dict[str, str] = {
    "restaurants": "restaurants_shop_id_fkey",
    "restaurant_menu_categories": "restaurant_menu_categories_restaurant_id_fkey",
    "restaurant_menu_items": "restaurant_menu_items_menu_category_id_fkey",
    "search_events": "fk_search_events_shop_product",  # explicitly named in 0006
    "transport_providers": "transport_providers_user_id_fkey",  # 0016
    "vehicles": "vehicles_provider_id_fkey",                   # 0016
    "vehicle_documents": "vehicle_documents_vehicle_id_fkey",  # 0016
    "transport_services": "transport_services_provider_id_fkey",  # 0016
    "vehicle_availability": "vehicle_availability_vehicle_id_fkey",  # 0016
    "transport_quotes": "transport_quotes_provider_id_fkey",    # 0016
    "transport_bookings": "transport_bookings_quote_id_fkey",   # 0016
    "booking_status_history": "booking_status_history_booking_id_fkey",  # 0016
    "trip_details": "trip_details_booking_id_fkey",             # 0016
    "reviews": "reviews_user_id_fkey",                          # 0017
}
# (table, [columns]) — Geography columns that must be PostGIS-typed.
GEOGRAPHY_COLUMNS: dict[str, list[str]] = {
    "shops": ["location"],
    "search_indexes": ["location"],
    "service_areas": ["boundary", "center"],
    "shop_addresses": ["location"],
    "customer_addresses": ["location"],
}
# (table, [index names]) — spatial GiST indexes that must exist.
SPATIAL_INDEXES: dict[str, list[str]] = {
    "service_areas": ["ix_service_areas_boundary", "ix_service_areas_center"],
    "shops": ["ix_shops_location"],
    "customer_addresses": ["ix_customer_addresses_location"],
    "shop_addresses": ["ix_shop_addresses_location"],
}


def check_schema_surface(engine) -> tuple[list[dict[str, Any]], list[str]]:
    """Return ``(checks, errors)`` — every live schema verification."""
    checks: list[dict[str, Any]] = []
    errors: list[str] = []

    def record(name: str, ok: bool, detail: str) -> None:
        checks.append({"name": name, "ok": bool(ok), "detail": detail})
        if not ok:
            errors.append(f"{name}: {detail}")

    with engine.connect() as conn:
        # 3.1 Tables
        rows = conn.execute(text(
            "SELECT tablename FROM pg_tables WHERE schemaname='public'"
        )).fetchall()
        tables = {r[0] for r in rows}
        missing = sorted(EXPECTED_TABLES - tables)
        record("tables created by migrations",
               not missing,
               f"missing: {missing}" if missing else f"{len(EXPECTED_TABLES)} tables present")

        # 3.2 Indexes (btree, composite, GIN trigram)
        rows = conn.execute(text(
            "SELECT indexname, indexdef FROM pg_indexes WHERE schemaname='public'"
        )).fetchall()
        indexes = {r[0] for r in rows}
        miss = sorted(EXPECTED_INDEXES - indexes)
        record("indexes created by migrations",
               not miss,
               f"missing indexes: {miss}" if miss else f"{len(EXPECTED_INDEXES)} indexes present")

        # 3.3 Foreign keys exist in pg_constraint
        fk_rows = conn.execute(text(
            "SELECT conrelid::regclass::text, conname FROM pg_constraint "
            "WHERE contype='f' AND connamespace='public'::regnamespace"
        )).fetchall()
        fk_by_table: dict[str, set[str]] = {}
        for tbl, cname in fk_rows:
            fk_by_table.setdefault(tbl.split(".")[-1], set()).add(cname)
        missing_fk = [f"{t}.{n}" for t, n in EXPECTED_FKS.items()
                      if n not in fk_by_table.get(t, set())]
        record("foreign keys created by migrations",
               not missing_fk,
               f"missing: {missing_fk}" if missing_fk else f"{len(EXPECTED_FKS)} FKs present")

        # 3.4 PostGIS extension installed
        ext = conn.execute(text(
            "SELECT extversion FROM pg_extension WHERE extname='postgis'"
        )).fetchone()
        record("postgis extension installed",
               ext is not None,
               f"version={ext[0]}" if ext else "postgis extension missing")

        # 3.5 Geography columns correctly typed (udt_name = geography|geometry)
        bad_geo = []
        for tbl, cols in GEOGRAPHY_COLUMNS.items():
            for col in cols:
                row = conn.execute(text(
                    "SELECT udt_name FROM information_schema.columns "
                    "WHERE table_schema='public' AND table_name=:t AND column_name=:c"
                ), {"t": tbl, "c": col}).fetchone()
                if row is None:
                    bad_geo.append(f"{tbl}.{col} (missing)")
                elif (row[0] or "").lower() not in ("geography", "geometry"):
                    bad_geo.append(f"{tbl}.{col} ({row[0]})")
        record("geography columns are PostGIS-typed",
               not bad_geo,
               ", ".join(bad_geo) if bad_geo else "all Geography columns correctly typed")

        # 3.6 Spatial GiST indexes (exact names, plus a tolerant lookup for the
        # GeoAlchemy auto-named index on search_indexes.location).
        spatial_rows = conn.execute(text(
            "SELECT tablename, indexname FROM pg_indexes "
            "WHERE schemaname='public' AND indexdef ILIKE '%GIST%'"
        )).fetchall()
        spatial: dict[str, set[str]] = {}
        for tblname, idxname in spatial_rows:
            spatial.setdefault(tblname, set()).add(idxname)
        bad_spatial = []
        for tbl, names in SPATIAL_INDEXES.items():
            for n in names:
                if n not in spatial.get(tbl, set()):
                    bad_spatial.append(f"{tbl}.{n}")
        # search_indexes.location (0006 declares spatial_index=True, so
        # GeoAlchemy auto-names it) - accept ANY GiST index on the table.
        if "search_indexes" in tables and not spatial.get("search_indexes"):
            bad_spatial.append("search_indexes.<GiST on location>")
        record("spatial GiST indexes created",
               not bad_spatial,
               ", ".join(bad_spatial) if bad_spatial else "all spatial GiST indexes present")

    return checks, errors


# ─────────────────────────────────────────────────────────────────────────────
# 4. Live data-safety + rollback drill
# ─────────────────────────────────────────────────────────────────────────────
def run_alembic(args: list[str], db_url: str, backend_dir: Path) -> str:
    """Run an alembic CLI command against ``db_url`` (fail-fast on non-zero)."""
    env = dict(os.environ)
    env["DATABASE_URL"] = db_url
    proc = subprocess.run(
        [sys.executable, "-m", "alembic", *args],
        cwd=str(backend_dir),
        env=env,
        capture_output=True,
        text=True,
        check=True,
    )
    return (proc.stdout or "") + (proc.stderr or "")


def read_version(engine) -> Optional[str]:
    """Read alembic_version; None when no version is stamped."""
    try:
        with engine.connect() as conn:
            row = conn.execute(text("SELECT version_num FROM alembic_version")).fetchone()
            return row[0] if row else None
    except Exception:  # noqa: BLE001 — table missing => not migrated
        return None


def create_scratch_db(admin_url: str, scratch_name: str) -> str:
    """Create+return the scratch database URL (never touches the target DB)."""
    with psycopg.connect(admin_url, autocommit=True) as admin:
        with admin.cursor() as cur:
            cur.execute(f'DROP DATABASE IF EXISTS "{scratch_name}"')
            cur.execute(f'CREATE DATABASE "{scratch_name}"')
    return swap_db(admin_url, scratch_name)


def drop_scratch_db(admin_url: str, scratch_name: str) -> None:
    """Terminate lingering connections and drop the scratch database."""
    try:
        with psycopg.connect(admin_url, autocommit=True) as admin:
            with admin.cursor() as cur:
                cur.execute(
                    "SELECT pg_terminate_backend(pid) FROM pg_stat_activity "
                    "WHERE datname=%(db)s AND pid <> pg_backend_pid()",
                    {"db": scratch_name},
                )
                cur.execute(f'DROP DATABASE IF EXISTS "{scratch_name}"')
    except Exception as exc:  # noqa: BLE001
        print(f"  !! scratch cleanup failed (leaving '{scratch_name}'): {exc}")


def drill_forward_and_rollback(engine, scratch_url: str, backend_dir: Path,
                              full: bool, head: str, prev_rev: Optional[str]):
    """Forward migration, schema surface, data-safety, -1 rollback and (when
    ``full``) full-chain downgrade->re-upgrade. Returns (checks, errors)."""
    checks: list[dict[str, Any]] = []
    errors: list[str] = []

    def record(name: str, ok: bool, detail: str) -> None:
        checks.append({"name": name, "ok": bool(ok), "detail": detail})
        if not ok:
            errors.append(f"{name}: {detail}")

    def has_table(name: str) -> bool:
        from sqlalchemy import inspect as sa_inspect
        insp = sa_inspect(engine)
        return insp.has_table(name)

    # Schema surface (indexes / FKs / PostGIS) at head
    surface_checks, surface_errors = check_schema_surface(engine)
    checks.extend(surface_checks)
    errors.extend(surface_errors)

    # 4.1 Forward migration reached head
    version_now = read_version(engine)
    record("forward migration reached head",
           version_now == head,
           f"alembic_version={version_now} (expected {head})")

    # 4.2 Materialize drill rows (positive FK path: shops -> restaurants -> menu)
    with engine.begin() as conn:
        shop_id = conn.execute(
            text("INSERT INTO shops (name) VALUES (:n) RETURNING id"),
            {"n": "__phase26_rehearsal_shop__"},
        ).scalar()
        restaurant_id = conn.execute(
            text("INSERT INTO restaurants (shop_id) VALUES (:sid) RETURNING id"),
            {"sid": shop_id},
        ).scalar()
        conn.execute(
            text("INSERT INTO restaurant_menu_categories (restaurant_id, name) "
                 "VALUES (:rid, :n)"),
            {"rid": restaurant_id, "n": "__phase26_rehearsal_menu__"},
        )
        area_id = conn.execute(
            text("INSERT INTO service_areas (name, area_type) "
                 "VALUES (:n, 'CITY') RETURNING id"),
            {"n": "__phase26_rehearsal_area__"},
        ).scalar()
    record("drill rows inserted (positive FK path)",
           bool(shop_id and restaurant_id and area_id),
           f"shop={shop_id}, restaurant={restaurant_id}, area={area_id}")

    # 4.3 FK enforcement — an orphaned child insert must be rejected.
    fk_rejected = False
    try:
        with engine.begin() as conn:
            conn.execute(
                text("INSERT INTO restaurant_menu_categories (restaurant_id, name) "
                     "VALUES (:rid, :n)"),
                {"rid": 999_999_999, "n": "__phase26_rehearsal_orphan__"},
            )
    except sa.exc.IntegrityError:
        fk_rejected = True
    record("foreign keys are enforced",
           fk_rejected,
           "orphaned insert rejected with IntegrityError" if fk_rejected
           else "orphaned insert SUCCEEDED — FK not enforced!")

    # 4.4 Roll back exactly one revision (newest migration's downgrade) and
    #     prove unrelated data survives.
    run_alembic(["downgrade", "-1"], scratch_url, backend_dir)
    version_after_down = read_version(engine)
    area_survived = False
    if has_table("service_areas"):
        with engine.connect() as conn:
            area_survived = conn.execute(
                text("SELECT 1 FROM service_areas WHERE name=:n AND id=:i"),
                {"n": "__phase26_rehearsal_area__", "i": area_id},
            ).fetchone() is not None
    record("downgrade -1 reverses newest migration",
           version_after_down == prev_rev,
           f"alembic_version={version_after_down} (expected {prev_rev})")
    record("downgrade -1 drops only the newest schema (restaurants gone)",
           not has_table("restaurants") and has_table("service_areas"),
           "restaurants dropped, service_areas intact")
    record("unrelated data survives the -1 rollback",
           area_survived,
           "service_areas drill row present" if area_survived
           else "service_areas drill row LOST during downgrade!")

    # 4.5 Re-apply and confirm the data is still there.
    run_alembic(["upgrade", "head"], scratch_url, backend_dir)
    version_after_up = read_version(engine)
    area_again = False
    if has_table("service_areas"):
        with engine.connect() as conn:
            area_again = conn.execute(
                text("SELECT 1 FROM service_areas WHERE name=:n AND id=:i"),
                {"n": "__phase26_rehearsal_area__", "i": area_id},
            ).fetchone() is not None
    record("re-upgrade head after rollback",
           version_after_up == head and has_table("restaurants"),
           f"alembic_version={version_after_up}, restaurants={has_table('restaurants')}")
    record("data preserved across downgrade+upgrade round-trip",
           area_again,
           "drill row still present" if area_again else "drill row LOST!")

    # 4.6 Full-chain rollback (--full-chain-rollback): downgrade base, then
    #     re-apply the entire chain. This is the strongest rollback guarantee:
    #     the chain must be fully reversible to an empty schema AND re-appliable.
    if full:
        run_alembic(["downgrade", "base"], scratch_url, backend_dir)
        base_state = read_version(engine)
        base_tables_gone = not has_table("shops") and not has_table("restaurants")
        record("full-chain rollback reaches base",
               base_state is None,
               f"alembic_version={base_state} (expected None/empty after downgrade base)")
        record("full-chain rollback drops the schema",
               base_tables_gone,
               "shops/restaurants absent" if base_tables_gone
               else "tables still present after downgrade base!")
        run_alembic(["upgrade", "head"], scratch_url, backend_dir)
        re_head = read_version(engine)
        record("chain re-applies cleanly (base -> head)",
               re_head == head,
               f"alembic_version={re_head} (expected {head})")

    return checks, errors


# ─────────────────────────────────────────────────────────────────────────────
# CLI entrypoint
# ─────────────────────────────────────────────────────────────────────────────
def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Phase 26 database migration rehearsal")
    parser.add_argument("--versions-dir", type=Path, default=DEFAULT_VERSIONS_DIR)
    parser.add_argument("--scratch-db-name", default="")
    parser.add_argument("--full-chain-rollback", action="store_true",
                        help="also drill downgrade base -> upgrade head")
    parser.add_argument("--chain-only", action="store_true",
                        help="only static checks (no database required)")
    parser.add_argument("--report-file", type=Path,
                        default=BACKEND_DIR / "migration_rehearsal_report.json")
    parser.add_argument("--no-cleanup", action="store_true")
    args = parser.parse_args(argv)

    revisions = parse_revisions(args.versions_dir)
    issues = chain_issues(revisions)
    head = head_revision(revisions) or ""
    prev_rev = next((r["down_revision"] for r in revisions if r["revision"] == head), None)
    violations = scan_data_safety_violations(args.versions_dir)

    checks: list[dict[str, Any]] = [
        {
            "name": "chain integrity (linear, single head, sequential)",
            "ok": not issues,
            "detail": "; ".join(issues) if issues else f"{len(revisions)} revisions, head={head}",
        },
        {
            "name": "data-safety policy (no silent NOT NULL column adds)",
            "ok": not violations,
            "detail": f"{len(violations)} violation(s)" if violations else "all add_column() calls are safe",
        },
    ]
    for v in violations:
        checks.append({"name": f"violation: {v['file']}:{v['line']} {v['table']}",
                       "ok": False, "detail": v["detail"]})

    report: dict[str, Any] = {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "head_revision": head,
        "revisions": revisions,
        "chain_issues": issues,
        "data_safety_violations": violations,
        "checks": checks,
        "full_chain_rollback": args.full_chain_rollback,
    }

    print(f"head revision      : {head or '(unknown)'}")
    print(f"revisions          : {len(revisions)}")
    print(f"chain issues       : {len(issues)}")
    print(f"data-safety        : {len(violations)} violation(s)")

    if args.chain_only:
        failed = [c for c in checks if not c["ok"]]
        report.update(verdict="PASS" if not failed else "FAIL", mode="chain-only")
        args.report_file.write_text(json.dumps(report, indent=2), encoding="utf-8")
        print(f"verdict            : {report['verdict']}")
        print(f"report             : {args.report_file}")
        return 2 if failed else 0

    url = os.environ.get("DATABASE_URL") or ""
    if not url:
        print("!! DATABASE_URL not set — export it to run the live drill "
              "(or use --chain-only).", file=sys.stderr)
        return 1
    if psycopg is None:
        print("!! psycopg is required for the live drill — "
              "pip install -r requirements.txt", file=sys.stderr)
        return 1

    scratch_name = args.scratch_db_name or f"hyperlocal_rehearsal_{time.strftime('%Y%m%dT%H%M%SZ')}"
    sync_admin = swap_db(to_sync_url(url), "postgres")  # maintenance DB on the same server
    scratch_async = swap_db(url, scratch_name)          # async form for alembic
    engine = None
    try:
        with psycopg.connect(sync_admin, connect_timeout=10):
            pass
    except Exception as exc:  # noqa: BLE001
        print(f"!! cannot reach the database server at {sync_admin}: {exc}", file=sys.stderr)
        return 1

    try:
        scratch_sync = create_scratch_db(sync_admin, scratch_name)
        print(f"scratch database   : {scratch_name} (created, dropped at the end)")
        engine = create_engine(scratch_sync, pool_pre_ping=True)

        up = run_alembic(["upgrade", "head"], scratch_async, BACKEND_DIR)
        print("==> alembic upgrade head")
        drill_checks, drill_errors = drill_forward_and_rollback(
            engine, scratch_async, BACKEND_DIR,
            full=args.full_chain_rollback, head=head, prev_rev=prev_rev,
        )
        checks.extend(drill_checks)

        report.update(
            verdict="PASS" if not drill_errors else "FAIL",
            mode="live-drill",
            scratch_db_name=scratch_name,
            upgrade_output_tail=up.strip().splitlines()[-6:],
        )
        if up.strip():
            print(up.strip().splitlines()[-4:])
    except subprocess.CalledProcessError as exc:
        report.update(verdict="FAIL", mode="live-drill", error=str(exc))
    except Exception as exc:  # noqa: BLE001
        report.update(verdict="FAIL", mode="live-drill", error=repr(exc))
    finally:
        if engine is not None:
            engine.dispose()
        if not args.no_cleanup:
            drop_scratch_db(sync_admin, scratch_name)
        else:
            print(f"  (--no-cleanup: leaving scratch database '{scratch_name}')")

    failed = [c for c in checks if not c["ok"]]
    hard_failed = report.get("verdict") == "FAIL"
    print(f"checks             : {len(checks) - len(failed)}/{len(checks)} passed")
    for c in failed:
        print(f"  [FAIL] {c['name']}: {c['detail']}")
    if hard_failed and not failed:
        print("  [FAIL] drill aborted (see report['error']); no individual check recorded")
    print(f"verdict            : {report['verdict']}")
    args.report_file.write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(f"report             : {args.report_file}")
    return 2 if (failed or hard_failed) else 0


if __name__ == "__main__":
    raise SystemExit(main())
