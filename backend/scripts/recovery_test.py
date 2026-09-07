#!/usr/bin/env python
"""Phase 5 - automated, NON-DESTRUCTIVE database recovery drill.

Proves a database can be restored end-to-end (no leap of faith):

    1. Connect to ``--source-url`` and snapshot a lightweight state: alembic
       revision, every ``public`` table, per-table row counts, index count and
       foreign-key count.
    2. Take a logical backup with ``pg_dump -Fc``.
    3. Create a SCRATCH database on the SAME server (the source DB is never
       modified - drill only).
    4. Restore the backup into the scratch DB with ``pg_restore``.
    5. Verify the scratch DB is identical: same revision, same tables, same row
       counts, same schema surface (indexes / FKs).
    6. Drop the scratch DB and report PASS/FAIL. Exit code is 0 ONLY when every
       check passes.

Designed to run in CI on every push and locally against any PostgreSQL 14+
(PostGIS is not required for this drill; the PostGIS + approved-architecture
check is the separate scripts/verify_rds.py).

Usage:
    python scripts/recovery_test.py --source-url postgresql+asyncpg://... [options]
    DATABASE_URL=... python scripts/recovery_test.py

Options:
    --scratch-db-name NAME   scratch database name (default phase5_recovery_<ts>)
    --pg-dump PATH / --pg-restore PATH   binaries (default: found on PATH)
    --backup-dir DIR         where the temporary .pgc lives (default temp dir)
    --keep-backup            do not delete the dump after the drill
    --report-file PATH       write a JSON recovery report here
    --no-cleanup             leave the scratch DB in place (debugging)
"""
from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
import urllib.parse
from pathlib import Path

import psycopg

# Backend directory - importable from anywhere (needed for verifier reuse).
BACKEND_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BACKEND_DIR))


def to_sync_url(url: str) -> str:
    """Convert an async SQLAlchemy URL to the libpq/psycopg (sync) form.

    psycopg.connect() (and libpq) accept the plain ``postgresql://`` scheme.
    """
    for prefix in ("postgresql+asyncpg://", "postgres+asyncpg://",
                   "postgresql+psycopg://", "postgres+psycopg://"):
        if url.startswith(prefix):
            return url.replace(prefix, "postgresql://", 1)
    if not url.startswith("postgresql://"):
        url = url.replace("postgresql://", "postgresql://", 1)
    return url.replace("ssl=require", "sslmode=require")


def to_libpq_url(url: str) -> str:
    """Convert an async SQLAlchemy URL to the libpq form pg_dump expects."""
    for prefix in ("postgresql+asyncpg://", "postgres+asyncpg://",
                   "postgresql+psycopg://", "postgres+psycopg://"):
        if url.startswith(prefix):
            url = url.replace(prefix, "postgresql://", 1)
            break
    return url.replace("ssl=require", "sslmode=require")


def swap_db(url: str, dbname: str) -> str:
    """Return the same connection URL pointing at a different database."""
    parsed = urllib.parse.urlsplit(url)
    return urllib.parse.urlunsplit(parsed._replace(path="/" + dbname))


def db_name_of(url: str) -> str:
    parsed = urllib.parse.urlsplit(url)
    return parsed.path.rstrip("/").rsplit("/", 1)[-1]


def _public_tables(conn) -> list[str]:
    with conn.cursor() as cur:
        cur.execute(
            "SELECT table_name FROM information_schema.tables "
            "WHERE table_schema='public' AND table_type='BASE TABLE' ORDER BY 1")
        return [r[0] for r in cur.fetchall()]


def _table_counts(conn, tables: list[str]) -> dict[str, int]:
    counts: dict[str, int] = {}
    with conn.cursor() as cur:
        for t in tables:
            cur.execute(f'SELECT count(*) FROM "{t}"')
            counts[t] = int(cur.fetchone()[0])
    return counts


def _revision(conn):
    with conn.cursor() as cur:
        try:
            cur.execute("SELECT version_num FROM alembic_version LIMIT 1")
            return cur.fetchone()[0]
        except psycopg.errors.UndefinedTable:
            return "NO_ALEMBIC"


def _schema_surface(conn) -> dict:
    with conn.cursor() as cur:
        cur.execute("SELECT count(*) FROM pg_indexes WHERE schemaname='public'")
        indexes = int(cur.fetchone()[0])
        cur.execute(
            "SELECT count(*) FROM pg_constraint c "
            "JOIN pg_class t ON t.oid = c.conrelid "
            "JOIN pg_namespace n ON n.oid = t.relnamespace "
            "WHERE n.nspname='public' AND c.contype='f'")
        fks = int(cur.fetchone()[0])
    return {"indexes": indexes, "foreign_keys": fks}


def snapshot_state(url: str) -> dict:
    with psycopg.connect(to_sync_url(url)) as conn:
        tables = _public_tables(conn)
        return {
            "alembic_version": _revision(conn),
            "tables": tables,
            "rows": _table_counts(conn, tables),
            "schema_surface": _schema_surface(conn),
        }


def main() -> int:
    ap = argparse.ArgumentParser(description="Database recovery drill")
    ap.add_argument("--source-url", default=os.environ.get("DATABASE_URL", ""),
                    help="DB to back up (default: $DATABASE_URL)")
    ap.add_argument("--scratch-db-name", default="")
    ap.add_argument("--pg-dump", default=os.environ.get("PG_DUMP") or shutil.which("pg_dump") or "")
    ap.add_argument("--pg-restore", default=os.environ.get("PG_RESTORE") or shutil.which("pg_restore") or "")
    ap.add_argument("--backup-dir", default="")
    ap.add_argument("--keep-backup", action="store_true")
    ap.add_argument("--report-file", default="")
    ap.add_argument("--no-cleanup", action="store_true")
    args = ap.parse_args()

    if not args.source_url:
        ap.error("--source-url is required (or set DATABASE_URL)")
    if not args.pg_restore and not args.pg_dump:
        ap.error("pg_dump/pg_restore not found on PATH - install postgresql-client or pass --pg-dump/--pg-restore")
    pg_dump, pg_restore = args.pg_dump, args.pg_restore

    src = to_sync_url(args.source_url)
    libpq = to_libpq_url(args.source_url)
    src_db = db_name_of(src)

    scratch = args.scratch_db_name or f"phase5_recovery_{int(time.time())}"
    if scratch == src_db or db_name_of(libpq) == scratch:
        ap.error(f"--scratch-db-name '{scratch}' must differ from the source database")

    admin_admin = swap_db(libpq, "postgres")      # maintenance server
    scratch_url = swap_db(libpq, scratch)

    report = {"source": src_db, "scratch": scratch,
              "ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())}
    print("Phase 5 recovery drill")
    print(f"  source:  {src_db}   scratch: {scratch}")

    dump_file = ""
    try:
        backup_dir = args.backup_dir or tempfile.mkdtemp(prefix="phase5_")
        dump_file = os.path.join(backup_dir, f"phase5_{src_db}_{int(time.time())}.pgc")

        # 1. Capture pre-state + take the logical backup
        pre = snapshot_state(src)
        report["pre"] = pre
        print(f"  tables:  {len(pre['tables'])}   revision: {pre['alembic_version']}")
        print(f"  dump ->   {dump_file}")
        subprocess.run([pg_dump, "-Fc", "--no-owner", "--no-privileges",
                        "-f", dump_file, libpq], check=True)

        # 2. Create scratch DB (safe: same server, brand-new database)
        with psycopg.connect(admin_admin, autocommit=True) as admin:
            with admin.cursor() as cur:
                cur.execute(f'DROP DATABASE IF EXISTS "{scratch}"')
                cur.execute(f'CREATE DATABASE "{scratch}"')
        print(f"  created scratch database '{scratch}'")

        # 3. Restore into the scratch DB
        subprocess.run([pg_restore, "--no-owner", "--no-privileges", "--exit-on-error",
                        "-d", scratch_url, dump_file], check=True)
        print("  pg_restore OK")

        # 4. Verify
        post = snapshot_state(scratch_url)
        report["post"] = post
        checks = [
            ("alembic revision match", pre["alembic_version"] == post["alembic_version"]),
            ("table set match", sorted(pre["tables"]) == sorted(post["tables"])),
        ]
        mism = {t: (pre["rows"].get(t), post["rows"].get(t))
                for t in set(pre["tables"]) | set(post["tables"])
                if pre["rows"].get(t) != post["rows"].get(t)}
        checks.append(("row counts match", not mism))
        checks.append(("schema surface match", pre["schema_surface"] == post["schema_surface"]))

        over = sum(1 for _, ok in checks if ok)
        print(f"  verification: {over}/{len(checks)} checks passed")
        for name, ok in checks:
            print(f"    [{'PASS' if ok else 'FAIL'}] {name}")
            if not ok and name == "row counts match":
                print(f"      diffs (table: source->restored): {mism}")
        if any(not ok for _, ok in checks):
            report["result"] = "FAIL"
            print("!! RECOVERY FAILED - the restored database does not match the source.")
            rc = 1
        else:
            report["result"] = "PASS"
            print("OK RECOVERY VERIFIED - the database can be backed up, restored and matches.")
            rc = 0
    except subprocess.CalledProcessError as exc:
        report["result"] = "FAIL"
        print(f"!! tool failed: {exc}")
        rc = 1
    except Exception as exc:  # noqa: BLE001 - report any failure, keep running cleanup
        report["result"] = "FAIL"
        print(f"!! recovery drill error: {exc!r}")
        rc = 1
    finally:
        if not args.no_cleanup:
            try:
                with psycopg.connect(admin_admin, autocommit=True) as admin:
                    with admin.cursor() as cur:
                        cur.execute(f"SELECT pg_terminate_backend(pid) FROM pg_stat_activity "
                                    f"WHERE datname='{scratch}' AND pid <> pg_backend_pid()")
                        cur.execute(f'DROP DATABASE IF EXISTS "{scratch}"')
                print(f"  dropped scratch database '{scratch}'")
            except Exception as exc:  # noqa: BLE001
                print(f"  !! scratch cleanup failed (leaving '{scratch}'): {exc}")
        if dump_file and not args.keep_backup:
            try:
                os.remove(dump_file)
                print(f"  removed temp dump {dump_file}")
            except OSError:
                pass

    if args.report_file:
        Path(args.report_file).write_text(json.dumps(report, indent=2, sort_keys=True))
        print(f"  report -> {args.report_file}")
    return rc


if __name__ == "__main__":
    raise SystemExit(main())
