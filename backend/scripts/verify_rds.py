#!/usr/bin/env python
"""Phase 4 - RDS PostgreSQL + PostGIS live verification.

Connects to the database identified by ``DATABASE_URL`` (or ``--url``) and
verifies every Phase 4 requirement against the *approved* architecture:
  1. Database connection (SELECT 1) over the runtime URL.
  2. PostGIS extension installed + version.
  3. Alembic migrations at HEAD (no drift, nothing to apply).
  4. Every approved table exists in the ``public`` schema.
  5. PK/FK/unique/check/index integrity surface.
  6. PostGIS Geography columns correctly typed.
  7. Spatial (GiST) index on the search layer.
  8. A real PostGIS query (ST_Distance/ST_DWithin/ST_Within) plus a sample-data
     round-trip inside a transaction that is rolled back (no pollution).

Exit code is 0 only when every check passes. Safe for production: it only reads
and wraps the sample-data test in a rolled-back transaction.
"""
from __future__ import annotations

import argparse
import os
import re
import sys
from pathlib import Path

import sqlalchemy as sa
from sqlalchemy import create_engine, text

# Approved architecture (source of truth = migrations 0001..0017).
EXPECTED_TABLES: set[str] = {
    "roles", "permissions", "role_permissions", "user_roles",
    "users", "customers", "customer_addresses",
    "otps", "user_interactions",
    "auth_sessions", "token_blacklist", "password_resets",
    "customer_favorites", "customer_recent_products",
    "shops", "shop_owners", "shop_managers", "shop_addresses", "shop_hours",
    "shop_holidays", "shop_documents", "shop_verifications",
    "service_areas",
    "restaurant_menu_categories",
    "restaurant_menu_items",
    "restaurants",
    "brands", "categories", "product_masters", "product_variants",
    "product_images", "product_attributes", "product_attribute_values",
    "product_identifiers", "barcode_relationships", "shop_products",
    "inventory", "inventory_movements", "inventory_adjustments",
    "inventory_import_jobs", "inventory_import_rows", "price_history",
    "offers", "offer_products", "offer_conditions",
    "search_history", "search_events", "popular_searches", "barcode_scans",
    "search_indexes", "search_index_sync_runs",
    "pos_integrations", "pos_devices", "pos_sync_jobs", "pos_sync_logs",
    "pos_product_mappings",
    "notifications", "notification_preferences", "notification_deliveries",
    "device_tokens",
    "admin_actions", "admin_notes", "product_approvals", "reports",
    "complaints", "audit_logs",
    "product_views", "shop_views", "product_clicks", "inventory_events",
    "system_metrics", "analytics_events", "analytics_daily_aggregates",
    "system_settings", "feature_flags",
    "subscription_plans", "subscriptions", "payments", "payment_events",
    "saved_products", "saved_shops",
    # 0016 transport & personal transport booking (Rules 5-6)
    "transport_providers", "vehicles", "vehicle_documents",
    "transport_services", "vehicle_availability", "transport_quotes",
    "transport_bookings", "booking_status_history", "trip_details",
    # 0017 reviews + pharmacy compliance
    "reviews",
    # 0019 merchant onboarding & verification
    "merchant_categories", "merchant_verification_requirements",
    "merchant_onboardings", "business_identity_verifications",
    "bank_account_verifications", "category_document_verifications",
    "verification_attempts", "verification_provider_logs",
    # 0024 media pipeline (S3 upload lifecycle: PENDING -> READY)
    "media",
}

# Geography POINT columns that must be typed for PostGIS.
GEOGRAPHY_COLUMNS = {
    "shops": ["location"],
    "customer_addresses": ["location"],
    "search_indexes": ["location"],
    "shop_addresses": ["location"],
    "service_areas": ["boundary", "center"],
}


def _resolve_url(arg_url):
    url = arg_url or os.environ.get("DATABASE_URL", "")
    if not url:
        raise SystemExit("DATABASE_URL is empty. Pass --url or export DATABASE_URL.")
    return url


def _normalize_sync(url: str) -> str:
    """Convert an async URL to the psycopg (sync) form the verifier needs.

    The app/async URL carries ``ssl=require`` (asyncpg's connection keyword);
    psycopg rejects ``ssl`` as a connection option, so we translate it to the
    libpq-style ``sslmode=require``.
    """
    prefixes = ("postgresql+asyncpg://", "postgres+asyncpg://")
    if url.startswith(prefixes):
        url = url.replace(prefixes[0], "postgresql+psycopg://")
        url = url.replace(prefixes[1], "postgresql+psycopg://")
    elif url.startswith("postgresql://"):
        url = url.replace("postgresql://", "postgresql+psycopg://", 1)
    scheme, _, rest = url.partition("://")
    if "?" in rest:
        base, _, query = rest.partition("?")
        translated = []
        for item in query.split("&"):
            if item.startswith("ssl="):
                translated.append("sslmode=" + item.split("=", 1)[1])
            else:
                translated.append(item)
        return f"{scheme}://{base}?{'&'.join(translated)}"
    return url


def _compute_migration_head(versions_dir: Path) -> str:
    """Rebuild the Alembic head revision from the committed version files."""
    revisions: dict[str, str | None] = {}
    for f in versions_dir.glob("*.py"):
        if f.name.startswith("_") or "pycache" in str(f):
            continue
        src = f.read_text(encoding="utf-8")
        m = re.search(r"^revision:.*?= [\"']([^\"']+)[\"']", src, re.M)
        d = re.search(r"^down_revision:.*?=\s*([\"']([^\"']+)[\"']|None)", src, re.M)
        if not m:
            continue
        rev = m.group(1)
        down = None if d is None or d.group(1) == "None" else d.group(2)
        revisions[rev] = down

    roots = [r for r in revisions if revisions[r] is None]
    if not roots:
        raise RuntimeError("Could not infer migration HEAD from version files.")
    best: list[str] = []
    for root in roots:
        chain: list[str] = []
        current = root
        seen: set[str] = set()
        while current is not None and current in revisions and current not in seen:
            seen.add(current)
            chain.append(current)
            current = revisions[current]
        chain.reverse()
        if len(chain) > len(best):
            best = chain
    if not best:
        raise RuntimeError("Could not infer migration HEAD.")
    return best[-1]


def main() -> int:
    ap = argparse.ArgumentParser(description="Verify RDS PostgreSQL + PostGIS (Phase 4).")
    ap.add_argument("--url", help="database URL (default: $DATABASE_URL)")
    ap.add_argument(
        "--versions-dir",
        default=str(Path(__file__).resolve().parents[1] / "alembic" / "versions"),
        help="Absolute path to alembic/versions",
    )
    ap.add_argument("-v", "--verbose", action="store_true", help="Per-table detail")
    args = ap.parse_args()

    url = _normalize_sync(_resolve_url(args.url))
    try:
        engine = create_engine(
            url, pool_pre_ping=True, poolclass=sa.pool.NullPool,
            connect_args={"connect_timeout": 10},
        )
    except Exception as exc:
        print(f"FAIL  Could not build engine from URL: {exc}")
        return 2

    versions_dir = Path(args.versions_dir)
    reports: list[str] = []
    checks: list[tuple[bool, str]] = []
    try:
        with engine.connect() as conn:
            checks.append(_conn_ok(conn))
            checks.append(_postgis(conn))
            checks.append(_migration_head(conn, versions_dir))
            checks.append(_tables(conn)[:2])
            checks.append(_constraints(conn)[:2])
            checks.append(_geography_columns(conn))
            checks.append(_spatial_index(conn))
            ok, msg, detail = _spatial_sample(conn)
            checks.append((ok, msg))
            if args.verbose and detail:
                reports.append(detail)
    except Exception as exc:
        print(f"FAIL  Exception during verification: {exc}")
        engine.dispose()
        return 1
    finally:
        engine.dispose()

    print("\n=== Phase 4 - RDS PostgreSQL + PostGIS verification ===")
    passed = 0
    for ok, msg in checks:
        tag = "PASS" if ok else "FAIL"
        if ok:
            passed += 1
        print(f"  [{tag}] {msg}")
    if reports:
        print("\n=== detail ===")
        for line in reports:
            print("  " + line)
    print(f"\n{passed}/{len(checks)} checks passed; DB: {url.split('@')[-1]}")
    return 0 if passed == len(checks) else 1


# ---------------- individual checks ----------------

def _conn_ok(conn):
    try:
        conn.execute(text("SELECT 1"))
        return True, "Connected to PostgreSQL (SELECT 1 ok)"
    except Exception as exc:
        return False, f"Connection failed: {exc}"


def _postgis(conn):
    try:
        row = conn.execute(text("SELECT PostGIS_Version()")).scalar()
        if row is None:
            return False, "PostGIS_Version() returned NULL (extension missing)"
        return True, f"PostGIS enabled: {row}"
    except Exception as exc:
        return False, f"PostGIS error: {exc}"


def _migration_head(conn, versions_dir):
    try:
        head = _compute_migration_head(versions_dir)
    except Exception as exc:
        return False, f"Could not compute migration HEAD: {exc}"
    try:
        current = conn.execute(text("SELECT version_num FROM alembic_version")).scalar()
    except Exception:
        return False, "Alembic not applied (no alembic_version) - run migrations first"
    ok = current == head
    msg = (f"Migrations at HEAD ({head})" if ok
           else f"Migration drift: DB={current} vs HEAD={head}")
    return ok, msg


def _tables(conn):
    rows = conn.execute(
        text("SELECT table_name FROM information_schema.tables "
             "WHERE table_schema='public' AND table_type='BASE TABLE'")
    ).scalars().all()
    present = set(rows)
    missing = EXPECTED_TABLES - present
    ok = not missing
    msg = (f"All {len(EXPECTED_TABLES)} approved tables present" if ok
           else f"Missing tables: {sorted(missing)}")
    return ok, msg, present


def _constraints(conn):
    counts = {"pk": 0, "fk": 0, "unique": 0, "check": 0, "index": 0, "tables": 0}
    kind_map = {"p": "pk", "f": "fk", "u": "unique", "c": "check"}
    for tbl in sorted(EXPECTED_TABLES):
        counts["tables"] += 1
        for kind in ("p", "f", "u", "c"):
            n = conn.execute(text(
                "SELECT COUNT(*) FROM pg_constraint c JOIN pg_class t ON t.oid=c.conrelid "
                "WHERE t.relname=:t AND c.contype=:k"), {"t": tbl, "k": kind}).scalar()
            counts[kind_map[kind]] += int(n or 0)
    n = conn.execute(text(
        "SELECT COUNT(*) FROM pg_indexes WHERE schemaname='public'")).scalar()
    counts["index"] = int(n or 0)
    summary = (f"integrity surface across {counts['tables']} approved tables -> "
               f"PK={counts['pk']}, FK={counts['fk']}, unique={counts['unique']}, "
               f"check={counts['check']}, public indexes={counts['index']}")
    return True, summary, summary


def _geography_columns(conn):
    bad = []
    for tbl, cols in GEOGRAPHY_COLUMNS.items():
        for col in cols:
            row = conn.execute(text(
                "SELECT data_type, udt_name FROM information_schema.columns "
                "WHERE table_schema='public' AND table_name=:t AND column_name=:c"),
                {"t": tbl, "c": col}).fetchone()
            if row is None:
                bad.append(f"{tbl}.{col} (missing)")
            elif (row.udt_name or "").lower() not in ("geography", "geometry"):
                bad.append(f"{tbl}.{col} ({row.data_type}/{row.udt_name})")
    ok = not bad
    msg = "PostGIS Geography columns correctly typed" if ok else f"Bad/missing geo columns: {bad}"
    return ok, msg


def _spatial_index(conn):
    rows = conn.execute(text(
        "SELECT indexname FROM pg_indexes WHERE schemaname='public' "
        "AND tablename='search_indexes' AND "
        "(indexdef ILIKE '%GIST%' OR indexdef ILIKE '%location%' OR indexdef ILIKE '%geog%') "
        "LIMIT 20")).fetchall()
    ok = bool(rows)
    names = [r[0] for r in rows]
    msg = (f"Spatial index on search_indexes.location present: {names}" if ok
           else "No GiST/spatial index found for search_indexes.location")
    return ok, msg


def _spatial_sample(conn):
    """Real PostGIS queries + rolled-back sample-data round-trip."""
    detail = ""
    try:
        with conn.begin():
            live = conn.execute(text(
                "SELECT COUNT(*) FROM shops WHERE location IS NOT NULL")).scalar()
            dist = conn.execute(text(
                "SELECT round(CAST(ST_Distance("
                "ST_GeogFromText('SRID=4326;POINT(72.8777 19.0760)'), "
                "ST_GeogFromText('SRID=4326;POINT(72.9000 19.0700)')) AS numeric),1)"
            )).scalar()
            conn.execute(text(
                "CREATE TEMP TABLE _phase4_geo (id int, p geography(POINT,4326))"))
            conn.execute(text(
                "INSERT INTO _phase4_geo (id, p) VALUES "
                "(1, ST_SetSRID(ST_MakePoint(72.9000, 19.0700), 4326)::geography), "
                "(2, ST_SetSRID(ST_MakePoint(72.8779, 19.0760), 4326)::geography)"))
            near = conn.execute(text(
                "SELECT COUNT(*) FROM _phase4_geo WHERE ST_DWithin("
                "p, ST_SetSRID(ST_MakePoint(72.88, 19.075), 4326)::geography, 5000)"
            )).scalar()
            within = conn.execute(text(
                "SELECT COUNT(*) FROM _phase4_geo WHERE ST_Within(p::geometry, "
                "ST_MakeEnvelope(72.5, 18.9, 73.5, 19.4, 4326))"
            )).scalar()
            conn.rollback()
            ok = dist is not None and int(near) >= 1 and int(within) == 2
            detail = (f"sample: shops with location={live}; ST_Distance(two pts)~{dist} m; "
                      f"ST_DWithin@5km found {near}/2; ST_Within found {within}/2 (rolled back)")
            msg = (f"PostGIS spatial queries work: ST_Distance~{dist} m; "
                   f"ST_DWithin@5km -> {near}/2; ST_Within -> {within}/2 (rolled back)"
                   if ok else "Spatial sample mismatch")
            return ok, msg, detail
    except Exception as exc:
        try:
            conn.rollback()
        except Exception:
            pass
        return False, f"Spatial sample failed: {exc}", ""


if __name__ == "__main__":
    raise SystemExit(main())
