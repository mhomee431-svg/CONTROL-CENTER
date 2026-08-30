#!/usr/bin/env python
"""Phase 4 — Free managed-cloud PostgreSQL provisioning (Neon / Supabase).

Provisions a *free-tier* serverless PostgreSQL database on **Neon** or
**Supabase** (no RDS, no cost), writes the connection strings the app and
Alembic already use (``DATABASE_URL`` / ``DATABASE_URL_SYNC``) into
``Backend/.env.<environment>``, and records provider metadata in a git-ignored
state file so every re-run is **idempotent** — the project is reused, never
recreated, and the database is never dropped.

Usage
-----
    # Neon (default) — needs NEON_API_KEY
    python scripts/provision_free_db.py neon --api-key "$NEON_API_KEY" \
        --region aws-ap-south-1 --name hyperlocal-free --db hyperlocal

    # Supabase — needs SUPABASE_ACCESS_TOKEN (+ optional --org)
    python scripts/provision_free_db.py supabase --access-token "$TOKEN" \
        --org <org-id> --region ap-south-1 --name hyperlocal-free

    # Reuse a database you already created in a dashboard / elsewhere
    python scripts/provision_free_db.py import --url \
        "postgresql+asyncpg://user:pw@host:5432/db?sslmode=require"

Secrets are never printed; masked summaries are shown. Uses only the Python
standard library (``urllib``) so it runs in any venv with zero extra deps.
"""
from __future__ import annotations

import argparse
import json
import os
import random
import string
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

# ─────────────────────────────────────────────────────────────────────────────
# Constants
# ─────────────────────────────────────────────────────────────────────────────
NEON_API_BASE = "https://console.neon.tech/api/v2"
SUPABASE_API_BASE = "https://api.supabase.com/v1"
STATE_FILE_NAME = ".free_cloud_db.json"
ENV_FILE_NAME = ".env.free"


# ─────────────────────────────────────────────────────────────────────────────
# HTTP helpers (stdlib; no `requests` dependency)
# ─────────────────────────────────────────────────────────────────────────────
def _http(method: str, url: str, headers: dict, body: dict | None = None,
          timeout: int = 60, retries: int = 4) -> tuple[str, int]:
    """Issue an authenticated JSON request with small retry/backoff."""
    data = None
    if body is not None:
        data = json.dumps(body).encode("utf-8")
    hdrs = {"Accept": "application/json"}
    hdrs.update(headers)
    if data is not None:
        hdrs["Content-Type"] = "application/json"

    last_exc: Exception | None = None
    for attempt in range(retries):
        try:
            req = urllib.request.Request(url, data=data, headers=hdrs, method=method)
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                return resp.read().decode("utf-8"), resp.status
        except urllib.error.HTTPError as exc:
            raw = exc.read().decode("utf-8", errors="replace")
            last_exc = exc
            if exc.code in (429, 503):
                time.sleep(2 ** attempt)
                continue
            raise RuntimeError(
                f"HTTP {exc.code} from {url}\n  {_error_brief(raw, exc.code)}"
            ) from exc
        except (urllib.error.URLError, TimeoutError, ConnectionError) as exc:
            last_exc = exc
            time.sleep(2 ** attempt)
    raise RuntimeError(f"Request failed after {retries} attempts: {last_exc}")
def _error_brief(raw: str, status: int) -> str:
    """Extract a human-readable message from a provider error response."""
    try:
        payload = json.loads(raw)
    except Exception:
        return raw[:500] if raw else f"(empty body, status {status})"
    if isinstance(payload, dict):
        msg = payload.get("message") or payload.get("error")
        if isinstance(msg, str):
            return msg[:500]
        if isinstance(payload.get("errors"), list):
            parts = []
            for e in payload["errors"][:3]:
                if isinstance(e, dict):
                    parts.append("; ".join(str(v) for v in e.values() if v))
            if parts:
                return " | ".join(parts)[:700]
        return json.dumps(payload)[:500] if payload else f"(empty body, status {status})"
    return json.dumps(payload)[:500] if payload else f"(empty body, status {status})"


def _json(raw: str) -> dict:
    payload = json.loads(raw)
    if not isinstance(payload, dict):
        raise ValueError(f"Expected JSON object, got {type(payload).__name__}")
    return payload


# ─────────────────────────────────────────────────────────────────────────────
# URL helpers
# ─────────────────────────────────────────────────────────────────────────────
def build_connection_url(host: str, port: int, database: str, role: str,
                         password: str, driver: str = "asyncpg") -> str:
    """Build a SQLAlchemy URL with TLS required.

    Providers (Neon/Supabase) always require SSL but the two drivers expect
    different keys: asyncpg uses ``ssl=require``; psycopg/psycopg2 use the
    libpq-style ``sslmode=require``. Passing ``sslmode`` to asyncpg raises
    ``TypeError`` at connect time, so the async (app) URL must use ``ssl``.
    """
    if driver not in ("asyncpg", "psycopg"):
        raise ValueError(f"Unsupported driver: {driver}")
    prefix = "postgresql+psycopg://" if driver == "psycopg" else "postgresql+asyncpg://"
    query = "sslmode=require" if driver == "psycopg" else "ssl=require"
    cred = f"{urllib.parse.quote(role, safe='')}:{urllib.parse.quote(password, safe='')}"
    return f"{prefix}{cred}@{host}:{port}/{database}?{query}"


def to_sync_url(url: str) -> str:
    """Convert an async (asyncpg) URL to the sync (psycopg) form.

    Also translates the asyncpg ``ssl=require`` query parameter into the
    libpq-style ``sslmode=require`` that psycopg understands.
    """
    for prefix in ("postgresql+asyncpg://", "postgres+asyncpg://"):
        if url.startswith(prefix):
            url = url.replace(prefix, "postgresql+psycopg://")
            break
    if url.startswith("postgresql://"):
        url = url.replace("postgresql://", "postgresql+psycopg://", 1)
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


def to_async_url(url: str) -> str:
    """Convert any URL to the async (asyncpg) form used by the FastAPI app.

    Translates libpq ``sslmode=require`` into asyncpg ``ssl=require``.
    """
    for prefix in ("postgresql+psycopg://", "postgres+psycopg://"):
        if url.startswith(prefix):
            url = url.replace(prefix, "postgresql+asyncpg://")
            break
    if url.startswith("postgresql://"):
        url = url.replace("postgresql://", "postgresql+asyncpg://", 1)
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


# ─────────────────────────────────────────────────────────────────────────────
# Neon provider
# ─────────────────────────────────────────────────────────────────────────────
class NeonProvider:
    def __init__(self, api_key: str, org_id: str | None = None):
        self.api_key = api_key
        self.org_id = org_id
        self._headers = {"Authorization": f"Bearer {api_key}"}

    def _project_url(self, project_id: str = "") -> str:
        base = f"{NEON_API_BASE}/projects"
        return base if not project_id else f"{base}/{project_id}"

    def list_projects(self) -> list:
        url = self._project_url()
        if self.org_id:
            url += f"?org_id={urllib.parse.quote(self.org_id)}"
        raw, _ = _http("GET", url, self._headers)
        return _json(raw).get("projects", [])

    def find_by_name(self, name: str):
        for project in self.list_projects() or []:
            if project.get("name") == name:
                return project
        return None

    def create_project(self, name: str, region: str, pg_version: int):
        body = {"project": {"name": name, "region_id": region, "pg_version": pg_version}}
        if self.org_id:
            body["project"]["org_id"] = self.org_id
        raw, _ = _http("POST", self._project_url(), self._headers, body)
        data = _json(raw)
        return data.get("project", {}), {
            "roles": data.get("roles", []) or [],
            "databases": data.get("databases", []) or [],
        }

    def create_database(self, project_id: str, db_name: str, owner: str) -> bool:
        url = f"{self._project_url(project_id)}/databases"
        _, status = _http("POST", url, self._headers,
                          {"database": {"name": db_name, "owner_name": owner}})
        return status in (200, 201)

    def list_databases(self, project_id: str) -> list:
        url = f"{self._project_url(project_id)}/databases"
        raw, _ = _http("GET", url, self._headers)
        return _json(raw).get("databases", [])

    def list_roles(self, project_id: str) -> list:
        url = f"{self._project_url(project_id)}/roles"
        raw, _ = _http("GET", url, self._headers)
        return [r.get("name") for r in _json(raw).get("roles", []) if r.get("name")]

    def connection_uri(self, project_id: str, database: str, role: str) -> str:
        """Return the plain ``postgresql://`` URI for a database + role."""
        qs = urllib.parse.urlencode({"database_name": database, "role_name": role})
        url = f"{self._project_url(project_id)}/connection_uri?{qs}"
        raw, _ = _http("GET", url, self._headers)
        uri = _json(raw).get("uri", "")
        if not uri.startswith("postgresql"):
            raise RuntimeError(f"Neon connection_uri returned unexpected value: {uri!r}")
        return uri

    @staticmethod
    def parse_uri(uri: str) -> dict:
        """Split ``postgresql://role:password@host:port/db`` into parts."""
        parsed = urllib.parse.urlsplit(uri)
        return {
            "host": parsed.hostname or "",
            "port": parsed.port or 5432,
            "database": (parsed.path or "/").lstrip("/"),
            "role": urllib.parse.unquote(parsed.username or ""),
            "password": urllib.parse.unquote(parsed.password or ""),
        }

    def provision(self, project_name: str, region: str, pg_version: int,
                  database_name: str) -> dict:
        existing = self.find_by_name(project_name)
        if existing:
            project_id = existing["id"]
            print(f"[neon] Reusing existing project '{project_name}' ({project_id})")
        else:
            print(f"[neon] Creating project '{project_name}' in {region} (PG {pg_version}) ...")
            project, _created = self.create_project(project_name, region, pg_version)
            project_id = project["id"]
            print(f"[neon] Created project {project_id}; waiting for compute to settle ...")
            time.sleep(8)

        roles = self.list_roles(project_id)
        if not roles:
            raise RuntimeError(f"Neon project {project_id} has no roles to connect with")
        role = roles[0]

        databases = {d.get("name") for d in self.list_databases(project_id)}
        if database_name not in databases:
            print(f"[neon] Creating database '{database_name}' owned by '{role}' ...")
            self.create_database(project_id, database_name, role)
        else:
            print(f"[neon] Database '{database_name}' already exists — reusing")

        uri = self.connection_uri(project_id, database_name, role)
        parsed = self.parse_uri(uri)
        return {
            "provider": "neon",
            "project_id": project_id,
            "project_name": project_name,
            "host": parsed["host"],
            "port": parsed["port"],
            "database": parsed["database"],
            "role": parsed["role"],
            "password": parsed["password"],
            "region": region,
            "pg_version": pg_version,
        }


# ─────────────────────────────────────────────────────────────────────────────
# Supabase provider
# ─────────────────────────────────────────────────────────────────────────────
class SupabaseProvider:
    def __init__(self, access_token: str):
        self.token = access_token
        self._headers = {"Authorization": f"Bearer {access_token}"}

    def list_organizations(self) -> list:
        raw, _ = _http("GET", f"{SUPABASE_API_BASE}/organizations", self._headers)
        data = _json(raw)
        return data if isinstance(data, list) else data.get("organizations", [])

    def list_projects(self) -> list:
        raw, _ = _http("GET", f"{SUPABASE_API_BASE}/projects", self._headers)
        data = _json(raw)
        return data if isinstance(data, list) else data.get("projects", [])

    def find_by_name(self, name: str):
        for project in self.list_projects() or []:
            if project.get("name") == name:
                return project
        return None

    def create_project(self, name: str, organization_id: str, db_pass: str,
                       region: str) -> dict:
        body = {
            "name": name,
            "organization_id": organization_id,
            "db_pass": db_pass,
            "region": region,
            "plan": "free",
        }
        raw, _ = _http("POST", f"{SUPABASE_API_BASE}/projects", self._headers, body)
        return _json(raw)

    def get_project(self, ref: str) -> dict | None:
        raw, _ = _http("GET", f"{SUPABASE_API_BASE}/projects/{ref}", self._headers)
        return _json(raw).get("project")

    def provision(self, project_name: str, organization_id: str | None,
                  db_pass: str, region: str) -> dict:
        org_id = organization_id
        if not org_id:
            orgs = self.list_organizations() or []
            if not orgs:
                raise RuntimeError(
                    "No Supabase organizations found. Pass --org <organization_id> "
                    "or create one at https://supabase.com")
            org_id = orgs[0]["id"]
            print(f"[supabase] Using organization {org_id} ({orgs[0].get('name', '')})")

        existing = self.find_by_name(project_name)
        if existing:
            ref = existing["id"]
            print(f"[supabase] Reusing existing project '{project_name}' ({ref})")
        else:
            print(f"[supabase] Creating free project '{project_name}' in {region} ...")
            created = self.create_project(project_name, org_id, db_pass, region)
            ref = created["id"]
            print(f"[supabase] Created project {ref}; waiting for provisioning ...")

        # Poll project status until the database host is reachable.
        host, pg_version, status = "", 15, "COMING_UP"
        for _ in range(40):
            project = self.get_project(ref)
            if project is None:
                raise RuntimeError(f"Supabase project {ref} disappeared during polling")
            current = project.get("status") or status
            status = str(current).upper()
            db_info = project.get("database") or {}
            if db_info.get("host"):
                host = db_info["host"]
                pg_version = db_info.get("major_version", pg_version)
            if status in ("ACTIVE", "READY"):
                break
            if status in ("FAILED", "INACTIVE"):
                raise RuntimeError(f"Supabase project {ref} entered status {status!r}")
            time.sleep(15)

        if not host:
            raise RuntimeError(
                f"Supabase project {ref} not ready after polling (status={status}). "
                "Re-run this script once provisioning completes — it is idempotent.")

        return {
            "provider": "supabase",
            "project_id": ref,
            "project_name": project_name,
            "host": host,
            "port": 5432,
            "database": "postgres",
            "role": "postgres",
            "password": db_pass,
            "region": region,
            "pg_version": pg_version,
        }


# ─────────────────────────────────────────────────────────────────────────────
# Shared state / env writer
# ─────────────────────────────────────────────────────────────────────────────
def backend_dir() -> Path:
    return Path(__file__).resolve().parents[1]


def load_state(state_file: Path | None = None) -> dict:
    path = state_file or backend_dir() / STATE_FILE_NAME
    if path.exists():
        try:
            return json.loads(path.read_text(encoding="utf-8"))
        except Exception:
            return {}
    return {}


def save_state(meta: dict, state_file: Path | None = None) -> Path:
    path = state_file or backend_dir() / STATE_FILE_NAME
    path.write_text(json.dumps(meta, indent=2, default=str), encoding="utf-8")
    return path


def write_env_file(meta: dict, env_file: Path | None = None) -> Path:
    """Write DATABASE_URL / DATABASE_URL_SYNC into Backend/.env.<env>."""
    if not meta.get("database_url"):
        raise ValueError("Cannot write env without DATABASE_URL")
    path = env_file or backend_dir() / ENV_FILE_NAME
    content = (
        "# ── Phase 4 free managed-cloud PostgreSQL (Neon/Supabase) ────────────\n"
        f"# Provider: {meta.get('provider')} | project: {meta.get('project_name', '')}\n"
        f"# Region: {meta.get('region', '')} | PG {meta.get('pg_version', '')}\n"
        "# Written by scripts/provision_free_db.py — do not hand-edit credentials.\n"
        "ENVIRONMENT=free\n"
        f"DATABASE_URL={meta['database_url']}\n"
        f"DATABASE_URL_SYNC={to_sync_url(meta['database_url'])}\n"
    )
    path.write_text(content, encoding="utf-8")
    return path


def mask(value: str) -> str:
    """Mask a secret for console output."""
    if len(value) <= 4:
        return "****"
    return value[:2] + "****" + value[-2:]


def build_records(meta: dict) -> dict:
    """Persisted state record — never stores the raw password."""
    return {
        "provider": meta["provider"],
        "project_id": meta.get("project_id", ""),
        "project_name": meta.get("project_name", ""),
        "region": meta.get("region", ""),
        "pg_version": meta.get("pg_version", ""),
        "host": meta.get("host", ""),
        "port": meta.get("port", ""),
        "database": meta.get("database", ""),
        "role": meta.get("role", ""),
        "sslmode": "require",
        "env_file": ENV_FILE_NAME,
    }
# ─────────────────────────────────────────────────────────────────────────────
# CLI
# ─────────────────────────────────────────────────────────────────────────────
def _add_common(subparser: argparse.ArgumentParser) -> None:
    subparser.add_argument("--name", default="hyperlocal-free",
                           help="Provider project name (idempotent key)")
    subparser.add_argument("--env-file", default=None,
                           help=f"Env file to write (default Backend/{ENV_FILE_NAME})")
    subparser.add_argument("--state-file", default=None,
                           help=f"State file to use (default Backend/{STATE_FILE_NAME})")


def main(argv: list | None = None) -> int:
    ap = argparse.ArgumentParser(
        prog="provision_free_db.py",
        description="Provision a free-tier managed cloud PostgreSQL (Neon/Supabase).",
    )
    sub = ap.add_subparsers(dest="provider", required=True)

    p_neon = sub.add_parser("neon", help="Provision on Neon (serverless Postgres).")
    p_neon.add_argument("--api-key", default=None,
                        help="NEON_API_KEY (default: env NEON_API_KEY)")
    p_neon.add_argument("--org", default=None,
                        help="Neon organization id (personal key + org project)")
    p_neon.add_argument("--region", default="aws-ap-south-1",
                        help="Neon region_id (default aws-ap-south-1 / Mumbai)")
    p_neon.add_argument("--pg-version", type=int, default=16,
                        help="PostgreSQL major version (14-18)")
    p_neon.add_argument("--db", default="hyperlocal", help="Database name to create")
    _add_common(p_neon)

    p_supa = sub.add_parser("supabase", help="Provision on Supabase (free plan).")
    p_supa.add_argument("--access-token", default=None,
                        help="SUPABASE_ACCESS_TOKEN (default: env)")
    p_supa.add_argument("--org", default=None, help="Supabase organization id")
    p_supa.add_argument("--db-password", default=None, dest="db_password",
                        help="Postgres password (>=8 chars); default: env "
                             "SUPABASE_DB_PASSWORD or a generated secret")
    p_supa.add_argument("--region", default="ap-south-1",
                        help="Supabase region (default ap-south-1 / Mumbai)")
    _add_common(p_supa)

    p_imp = sub.add_parser("import", help="Adopt an existing connection URL.")
    p_imp.add_argument("--url", required=True,
                       help="Existing postgres URL (async or sync, sslmode=require)")
    _add_common(p_imp)

    args = ap.parse_args(argv)

    try:
        if args.provider == "neon":
            api_key = args.api_key or os.environ.get("NEON_API_KEY", "")
            if not api_key:
                raise SystemExit(
                    "NEON_API_KEY is required.\n"
                    "Get one at https://console.neon.tech -> Account -> API keys.\n"
                    "  python scripts/provision_free_db.py neon --api-key <key> ...")
            meta = NeonProvider(api_key, org_id=args.org).provision(
                args.name, args.region, args.pg_version, args.db)
        elif args.provider == "supabase":
            token = args.access_token or os.environ.get("SUPABASE_ACCESS_TOKEN", "")
            if not token:
                raise SystemExit(
                    "SUPABASE_ACCESS_TOKEN is required.\n"
                    "Get one at https://supabase.com/dashboard/account/tokens.\n"
                    "  python scripts/provision_free_db.py supabase --access-token <token> ...")
            db_pass = args.db_password or os.environ.get("SUPABASE_DB_PASSWORD")
            if not db_pass:
                db_pass = _random_password()
                print("[supabase] No --db-password given; generated a random one "
                      "(stored in Backend/.env.free only).")
            meta = SupabaseProvider(token).provision(
                args.name, args.org, db_pass, args.region)
        else:  # import
            async_url = to_async_url(args.url)
            parsed = urllib.parse.urlsplit(async_url)
            meta = {
                "provider": "import",
                "project_name": "external",
                "region": "n/a",
                "pg_version": "n/a",
                "database_url": async_url,
                "host": parsed.hostname or "n/a",
                "port": parsed.port or 5432,
                "database": (parsed.path or "/").lstrip("/") or "n/a",
                "role": urllib.parse.unquote(parsed.username or "n/a"),
            }

        if not meta.get("database_url"):
            meta["database_url"] = build_connection_url(
                meta["host"], int(meta["port"]), meta["database"],
                meta["role"], meta["password"], driver="asyncpg")

        env_path = write_env_file(meta, Path(args.env_file) if args.env_file else None)
        state_path = save_state(
            build_records(meta), Path(args.state_file) if args.state_file else None)

        print("\n=== Free cloud PostgreSQL provisioned ===")
        print(f"  provider : {meta['provider']}")
        print(f"  project  : {meta.get('project_name', '')}")
        print(f"  host     : {meta.get('host', '')}")
        print(f"  database : {meta.get('database', '')}   role: {meta.get('role', '')}")
        if meta.get("password"):
            print(f"  password : {mask(meta['password'])} (env file only, never git)")
        print(f"  env file : {env_path}")
        print(f"  state    : {state_path}")
        print("\nNext: chained migrate -> verify -> seed is automated by "
              "scripts/dev/free_db.ps1 (or scripts/setup_free_cloud_db.py).")
        return 0

    except SystemExit:
        raise
    except RuntimeError as exc:
        print(f"\n[X] {exc}", file=sys.stderr)
        return 2
    except KeyboardInterrupt:
        print("\nAborted.", file=sys.stderr)
        return 130


def _random_password(length: int = 16) -> str:
    alphabet = string.ascii_letters + string.digits + "!@#$%^&*"
    return "".join(random.SystemRandom().choice(alphabet) for _ in range(length))


if __name__ == "__main__":
    raise SystemExit(main())