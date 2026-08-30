#!/usr/bin/env python
"""Phase 4 — run the Alembic migration chain + verifier on a free cloud DB.

This is the **safe migration workflow** for the free managed-cloud database:

    1. Resolve the async connection URL (``--url``, ``$DATABASE_URL``, or the
       ``Backend/.env.free`` file written by ``provision_free_db.py``).
    2. Run ``alembic upgrade head`` (idempotent — the chain is never recreated
       and a partially-applied upgrade resumes from the current revision).
    3. Run ``verify_rds.py`` (PostGIS, migration head, every approved table,
       PK/FK/unique/check/index surface, Geography columns, spatial sample).

The database itself is **never dropped or recreated**: if migrations already
exist (``alembic_version``), ``alembic upgrade`` simply applies the delta.

Usage
-----
    python scripts/migrate_free_db.py --url "$DATABASE_URL"      # explicit
    python scripts/migrate_free_db.py                            # reads .env.free
    python scripts/migrate_free_db.py --no-verify                # skip verifier

Exit code is 0 only when migrations are at head AND the verifier passes.
"""
from __future__ import annotations

import argparse
import os
import subprocess
import sys
from pathlib import Path


BACKEND_DIR = Path(__file__).resolve().parents[1]
ENV_FILE_NAME = ".env.free"


def _read_env_file(path: Path) -> dict:
    """Parse simple KEY=VALUE lines (no shell interpolation)."""
    values: dict = {}
    if not path.exists():
        return values
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, value = line.partition("=")
        values[key.strip()] = value.strip()
    return values


def resolve_url(arg_url: str | None) -> str:
    """Resolve the async connection URL in order: --url -> $DATABASE_URL -> env."""
    if arg_url:
        return arg_url
    from dotenv import load_dotenv  # only when a file is present
    env_path = BACKEND_DIR / ENV_FILE_NAME
    if env_path.exists():
        load_dotenv(env_path)
    url = os.environ.get("DATABASE_URL", "")
    if url:
        return url
    values = _read_env_file(env_path)
    url = values.get("DATABASE_URL", "")
    if url:
        return url
    raise SystemExit(
        "DATABASE_URL not found. Pass --url, export DATABASE_URL, or run "
        f"scripts/provision_free_db.py to write Backend/{ENV_FILE_NAME}.")


def to_async(url: str) -> str:
    """Normalize a URL to the asyncpg form Alembic's env.py expects."""
    for prefix in ("postgresql+psycopg://", "postgres+psycopg://"):
        if url.startswith(prefix):
            url = url.replace(prefix, "postgresql+asyncpg://")
            break
    else:
        if url.startswith("postgresql://"):
            url = url.replace("postgresql://", "postgresql+asyncpg://", 1)
    # asyncpg wants ssl=require (not libpq's sslmode=require).
    scheme, _, rest = url.partition("://")
    if "?" in rest:
        base, _, query = rest.partition("?")
        params = []
        for item in query.split("&"):
            if item.startswith("sslmode="):
                params.append("ssl=" + item.split("=", 1)[1])
            else:
                params.append(item)
        return f"{scheme}://{base}?{'&'.join(params)}"
    return url


def run_alembic(url: str, args: list[str]) -> int:
    """Run ``alembic <args>`` with DATABASE_URL set for the child process."""
    env = dict(os.environ)
    env["DATABASE_URL"] = url
    env["PYTHONUNBUFFERED"] = "1"
    cmd = [sys.executable, "-m", "alembic", *args]
    print(f"[migrate] $ {cmd}")
    proc = subprocess.run(cmd, cwd=str(BACKEND_DIR), env=env)
    return proc.returncode


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--url", default=None, help="Async DB URL (default: $DATABASE_URL / .env.free)")
    ap.add_argument("--no-verify", action="store_true", help="Skip the Phase-4 verifier")
    args = ap.parse_args(argv)

    url = to_async(resolve_url(args.url))
    print(f"=== Free cloud migration workflow ===\n[db   ] {url.split('@')[-1]}\n")

    code = run_alembic(url, ["upgrade", "head"])
    if code != 0:
        print(f"[FAIL] alembic upgrade head exited {code}", file=sys.stderr)
        return code

    if args.no_verify:
        print("[migrate] migrations at head (verifier skipped).")
        return 0

    print("\n[verify] Running Phase-4 architecture verifier ...")
    env = dict(os.environ)
    env["DATABASE_URL"] = to_sync(url)
    proc = subprocess.run(
        [sys.executable, str(BACKEND_DIR / "scripts" / "verify_rds.py"), "--url", to_sync(url)],
        cwd=str(BACKEND_DIR), env=env)
    return proc.returncode


def to_sync(url: str) -> str:
    """Convert an asyncpg URL to the psycopg form the verifier accepts."""
    for prefix in ("postgresql+asyncpg://", "postgres+asyncpg://"):
        if url.startswith(prefix):
            url = url.replace(prefix, "postgresql+psycopg://")
            break
    scheme, _, rest = url.partition("://")
    if "?" in rest:
        base, _, query = rest.partition("?")
        params = []
        for item in query.split("&"):
            if item.startswith("ssl="):
                params.append("sslmode=" + item.split("=", 1)[1])
            else:
                params.append(item)
        return f"{scheme}://{base}?{'&'.join(params)}"
    return url


if __name__ == "__main__":
    raise SystemExit(main())