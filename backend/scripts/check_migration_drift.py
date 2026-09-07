#!/usr/bin/env python
"""Phase 26 — ORM ↔ database migration drift checker.

Compares the schema the ORM models *declare* (``Base.metadata``) against the
schema the *migrations* actually produced (reflected from a live database).

When a developer changes a model and forgets to author a migration, the ORM
knows columns the database does not — classic silent drift. This checker makes
that drift visible (and optionally a hard gate) BEFORE staging/production.

What is compared per public-schema table:
  - table presence (ORM table missing from DB         -> DRIFT)
  - column presence (ORM column missing from DB      -> DRIFT)
  - nullability mismatch                              -> DRIFT
  - coarse type-family mismatch (int/string/numeric/boolean/time/json/binary/geo)
                                                     -> DRIFT
  - DB tables/columns the ORM does not know          -> INFO (sometimes intentional)

PostGIS (Geography/Geometry) columns are compared by family only — their
nullability reflects environment-driven details and is not a drift signal.

By default the checker REPORTS only and exits 0 (safe to run in CI as an
audit). Pass ``--fail-on-drift`` to make any drift a hard gate.

Usage:
    DATABASE_URL=postgresql+asyncpg://... python scripts/check_migration_drift.py
    python scripts/check_migration_drift.py --fail-on-drift --report-file drift.json
    python scripts/check_migration_drift.py --url postgresql://...
"""
from __future__ import annotations

import argparse
import json
import os
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, List

BACKEND_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BACKEND_DIR))

import sqlalchemy as sa
from sqlalchemy import create_engine, inspect, text


def to_sync_url(url: str) -> str:
    for prefix in ("postgresql+asyncpg://", "postgres+asyncpg://",
                   "postgresql+psycopg://", "postgres+psycopg://"):
        if url.startswith(prefix):
            url = url.replace(prefix, "postgresql://", 1)
            break
    if not url.startswith("postgresql://"):
        url = url.replace("postgresql://", "postgresql://", 1)
    return url.replace("ssl=require", "sslmode=require")


# ── Type-family canonicalisation ─────────────────────────────────────────────
_INT: set[str] = {"INTEGER", "BIGINT", "SMALLINT", "INT"}
_STR: set[str] = {"VARCHAR", "TEXT", "CHAR", "CHARACTER", "STRING", "ENUM", "UUID"}
_NUM: set[str] = {"NUMERIC", "DECIMAL", "FLOAT", "REAL", "DOUBLE", "DOUBLE_PRECISION"}
_BOOL: set[str] = {"BOOLEAN", "BOOL"}
_TIME: set[str] = {"TIMESTAMP", "DATETIME", "DATE", "TIME"}
_JSON: set[str] = {"JSON", "JSONB"}
_BIN: set[str] = {"BYTEA", "BLOB", "LARGEBINARY", "VARBINARY", "BINARY"}
_GEO: set[str] = {"GEOGRAPHY", "GEOMETRY"}


def type_family(col_type: Any) -> str:
    name = type(col_type).__name__.upper()
    for family in (_INT, _STR, _NUM, _BOOL, _TIME, _JSON, _BIN, _GEO):
        if name in family:
            return next(iter(family))
    return name


IGNORE_TABLES: set[str] = {
    "alembic_version", "spatial_ref_sys", "geometry_columns",
    "geography_columns", "raster_columns", "raster_overviews", "topology", "layer",
}


def build_orm_schema(metadata) -> Dict[str, Dict[str, Dict[str, Any]]]:
    """Snapshot the ORM-declared schema as {table: {col: {family, nullable}}}."""
    schema: Dict[str, Dict[str, Dict[str, Any]]] = {}
    for name, table in sorted(metadata.tables.items()):
        schema[name] = {}
        for col in table.columns:
            schema[name][col.name] = {
                "family": type_family(col.type),
                "nullable": bool(col.nullable),
            }
    return schema


def build_db_schema(engine) -> Dict[str, Dict[str, Dict[str, Any]]]:
    """Reflect the public schema a live database currently has."""
    schema: Dict[str, Dict[str, Dict[str, Any]]] = {}
    insp = inspect(engine)
    for name in sorted(insp.get_table_names(schema="public")):
        if name in IGNORE_TABLES:
            continue
        schema[name] = {}
        for col in insp.get_columns(name, schema="public"):
            schema[name][col["name"]] = {
                "family": type_family(col["type"]),
                "nullable": bool(col["nullable"]),
            }
    return schema


def compare(orm: Dict[str, Dict[str, Dict[str, Any]]],
            db: Dict[str, Dict[str, Dict[str, Any]]]) -> Dict[str, Any]:
    """Return {drift: [...], info: [...]} records between ORM and DB schemas."""
    drift: List[Dict[str, Any]] = []
    info: List[Dict[str, Any]] = []

    for table, cols in orm.items():
        if table in IGNORE_TABLES:
            continue
        if table not in db:
            drift.append({"kind": "table-missing", "table": table,
                          "detail": f"ORM declares {table} but migrations never created it"})
            continue
        for col, orm_info in cols.items():
            db_info = db[table].get(col)
            if db_info is None:
                drift.append({"kind": "column-missing", "table": table, "column": col,
                              "detail": f"ORM column {table}.{col} missing from the migrated schema"})
                continue
            if orm_info["family"] != db_info["family"]:
                drift.append({"kind": "type-family", "table": table, "column": col,
                              "detail": f"{col}: ORM {orm_info['family']} vs DB {db_info['family']}"})
            if orm_info["family"] not in _GEO and db_info["family"] not in _GEO:
                if orm_info["nullable"] != db_info["nullable"]:
                    drift.append({"kind": "nullability", "table": table, "column": col,
                                  "detail": f"{col}: ORM nullable={orm_info['nullable']} "
                                            f"vs DB nullable={db_info['nullable']}"})

    for table, cols in db.items():
        if table in IGNORE_TABLES:
            continue
        if table not in orm:
            info.append({"kind": "table-extra", "table": table,
                         "detail": f"DB table {table} has no ORM model (pause: intentional?)"})
            continue
        for col in cols:
            if col not in orm[table]:
                info.append({"kind": "column-extra", "table": table, "column": col,
                             "detail": f"DB column {table}.{col} has no ORM attribute"})

    return {"drift": drift, "info": info}


def run(url: str) -> Dict[str, Any]:
    """Connect, reflect, import the ORM metadata and diff."""
    engine = create_engine(to_sync_url(url), pool_pre_ping=True)
    try:
        db_schema = build_db_schema(engine)

        # Import the full ORM surface (registers every model on Base.metadata).
        from app.database.session import Base
        import app.models  # noqa: F401

        orm_schema = build_orm_schema(Base.metadata)
        result = compare(orm_schema, db_schema)
        result["db_tables"] = len(db_schema)
        result["orm_tables"] = len(orm_schema)
        return result
    finally:
        engine.dispose()


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Phase 26 ORM<->DB migration drift checker")
    parser.add_argument("--url", default="")
    parser.add_argument("--report-file", type=Path,
                        default=BACKEND_DIR / "migration_drift_report.json")
    parser.add_argument("--fail-on-drift", action="store_true")
    args = parser.parse_args(argv)

    url = args.url or os.environ.get("DATABASE_URL", "")
    if not url:
        print("!! DATABASE_URL not set (or pass --url)", file=sys.stderr)
        return 1

    try:
        result = run(url)
    except Exception as exc:  # noqa: BLE001
        print(f"!! drift check failed: {exc!r}", file=sys.stderr)
        return 1

    drift = result["drift"]
    info = result["info"]
    report = {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "db_tables": result["db_tables"],
        "orm_tables": result["orm_tables"],
        "drift_count": len(drift),
        "drift": drift,
        "info_count": len(info),
        "info": info,
        "verdict": "DRIFT" if drift else "CLEAN",
    }
    args.report_file.write_text(json.dumps(report, indent=2), encoding="utf-8")

    print(f"ORM tables         : {report['orm_tables']}")
    print(f"DB tables          : {report['db_tables']}")
    print(f"drift count        : {len(drift)}")
    for d in drift:
        print(f"  [DRIFT] {d['kind']:14s} {d['table']}.{d.get('column', '')} — {d['detail']}")
    print(f"info count         : {len(info)}  (DB-only tables/columns the ORM does not model)")
    for i in info:
        print(f"  [INFO ] {i['kind']:14s} {i['table']}.{i.get('column', '')} — {i['detail']}")
    print(f"verdict            : {report['verdict']}")
    print(f"report             : {args.report_file}")

    if drift and args.fail_on_drift:
        print("DRIFT detected and --fail-on-drift is set → failing", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())