#!/usr/bin/env python3
"""scripts/ci/check_api_contract_drift.py -- API contract drift gate (PR-time).

WHY THIS EXISTS
---------------
`packages/api_contracts/openapi.json` is the committed contract that
`cicd_contract_check.py` compares the DEPLOYED API against. That check only
runs on `develop`/`main` pushes, i.e. AFTER a deploy. When the committed spec
falls behind the code, the release pipeline stops at the staging E2E gate --
correct, but only after the whole deploy cycle has been spent.

This check answers the same question at PULL-REQUEST time, in seconds, and
without installing the backend's dependency tree (PostGIS / psycopg2 / redis
wheels are heavy and brittle on a CI runner). It parses the FastAPI route
decorators straight out of the source and compares them with the contract.

DIRECTIONS
----------
1. `source_not_in_contract` -- a real route the committed contract does not
   document. **HARD FAILURE.** This is the direction that actually blocks a
   release: `cicd_contract_check.py` compares the deployed spec against the
   committed one and rejects any extra path, so each of these would stop the
   staging deploy. Catching it at PR time saves the whole deploy cycle.

2. `contract_not_in_source` -- a documented path the static parser could not
   find in the source. **REPORTED, NEVER A FAILURE.** Absence here proves
   nothing: the parser reads `@router.<verb>` decorators, so a path declared
   through a sub-router, a mounted sub-application, a root route (`""`) or a
   non-literal prefix is simply invisible to it. Treating "not found" as
   "deleted" would fail the build on routes that demonstrably still exist, and
   a gate that cries wolf gets ignored within a week. The release E2E stays the
   authority for this direction.

SCOPE / FALSE-POSITIVE CONTROL
-----------------------------
Only routers that `main.py` mounts with `prefix=API_PREFIX` are considered, and
internal/admin surfaces are excluded, so a route deliberately kept out of the
public contract cannot fail the build.

Usage:
    python scripts/ci/check_api_contract_drift.py
    python scripts/ci/check_api_contract_drift.py --json --verbose
Exit codes: 0 in sync, 1 release-blocking drift, 2 could not evaluate.
"""
from __future__ import annotations

import argparse
import ast
import json
import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
ROUTES_DIR = REPO_ROOT / "backend" / "app" / "api" / "routes"
MAIN_PY = REPO_ROOT / "backend" / "app" / "main.py"
CONTRACT = REPO_ROOT / "packages" / "api_contracts" / "openapi.json"

# Surfaces intentionally not part of the public contract.
EXCLUDED_PREFIXES = (
    "/api/v1/admin",
    "/api/v1/health",
    "/api/v1/version",
    "/api/v1/webhooks",
    "/api/v1/internal",
)

_PARAM_RE = re.compile(r"\{[^}]+\}")


def canonical(path: str) -> str:
    """Normalise so `/a/{x}` and `/a/{y}` compare equal."""
    return _PARAM_RE.sub("{}", path.rstrip("/") or "/")


def api_prefix() -> str:
    """API_PREFIX, as applied by main.py when mounting the versioned routers."""
    text = MAIN_PY.read_text(encoding="utf-8")
    if re.search(r"API_PREFIX\s*=\s*settings\.API_PREFIX", text):
        return "/api/v1"
    return "/api/v1"


def _routes_alias_map(tree: ast.AST) -> dict[str, str]:
    """`from app.api.routes import orders as order_routes` -> {order_routes: orders}.

    main.py imports most route modules under an ALIAS that does not match the
    file name (`orders` -> `order_routes`, `reviews` -> `review_routes`,
    `webhooks` -> `webhook_routes`), so the alias has to be resolved from the
    import itself rather than guessed from a suffix.
    """
    aliases: dict[str, str] = {}
    for node in ast.walk(tree):
        if not isinstance(node, ast.ImportFrom):
            continue
        if not (node.module or "").startswith("app.api.routes"):
            continue
        for alias in node.names:
            if alias.name == "*":
                continue
            aliases[alias.asname or alias.name] = alias.name
    return aliases


def mounted_route_modules() -> set[str]:
    """Route modules main.py mounts under the /api/v1 prefix.

    `google_auth`, `health`, `version` and `observability` are mounted without
    it, so they are out of scope for the public contract.
    """
    tree = ast.parse(MAIN_PY.read_text(encoding="utf-8"))
    aliases = _routes_alias_map(tree)
    wanted: set[str] = set()
    for node in ast.walk(tree):
        if not (isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute)):
            continue
        if node.func.attr != "include_router" or not node.args:
            continue
        target = node.args[0]
        # `include_router(auth.router, ...)` -> the module is `auth`, because
        # `.attr` here is literally "router".
        if isinstance(target, ast.Attribute) and target.attr == "router":
            inner = target.value
            alias = inner.id if isinstance(inner, ast.Name) else None
        elif isinstance(target, ast.Name):
            alias = target.id
        else:
            alias = None
        if not alias:
            continue
        prefixed = any(
            kw.arg == "prefix"
            and isinstance(kw.value, ast.Name)
            and kw.value.id == "API_PREFIX"
            for kw in node.keywords
        )
        if prefixed:
            wanted.add(aliases.get(alias, alias).split(".")[0])
    return wanted
def source_paths(prefix: str) -> tuple[set[str], list[str]]:
    """Every route the FastAPI app exposes, plus any parse notes."""
    stems = mounted_route_modules()
    found: set[str] = set()
    notes: list[str] = []

    for path in sorted(ROUTES_DIR.glob("*.py")):
        if path.stem not in stems:
            notes.append(f"skipped (not mounted under {prefix}): {path.name}")
            continue
        try:
            tree = ast.parse(path.read_text(encoding="utf-8"))
        except SyntaxError as exc:  # pragma: no cover - defensive
            notes.append(f"could not parse {path.name}: {exc}")
            continue

        # Module-level `router = APIRouter(prefix="/shopkeeper", ...)`
        router_prefix = ""
        for node in tree.body:
            if not isinstance(node, ast.Assign):
                continue
            if not any(
                isinstance(t, ast.Name) and t.id == "router" for t in node.targets
            ):
                continue
            if isinstance(node.value, ast.Call):
                for kw in node.value.keywords:
                    if kw.arg == "prefix" and isinstance(kw.value, ast.Constant):
                        router_prefix = str(kw.value.value)
            break

        # @router.get("/path") -- path may be the first positional arg.
        # FastAPI handlers are `async def`, which is a DIFFERENT AST node type
        # from `def`; both must be walked or every route is missed.
        for node in ast.walk(tree):
            if not isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
                continue
            for deco in node.decorator_list:
                if not (
                    isinstance(deco, ast.Call)
                    and isinstance(deco.func, ast.Attribute)
                    and isinstance(deco.func.value, ast.Name)
                    and deco.func.value.id == "router"
                ):
                    continue
                if not deco.args or not isinstance(deco.args[0], ast.Constant):
                    continue
                route = str(deco.args[0].value)
                if route.startswith("/"):
                    found.add(canonical(f"{prefix}{router_prefix}{route}"))

    return found, notes


def contract_paths() -> set[str]:
    data = json.loads(CONTRACT.read_text(encoding="utf-8"))
    return {
        canonical(p)
        for p in (data.get("paths") or {})
        if not p.startswith(EXCLUDED_PREFIXES)
    }


def main() -> int:
    ap = argparse.ArgumentParser(description="API contract drift gate")
    ap.add_argument("--json", action="store_true", help="machine-readable output")
    ap.add_argument("--verbose", action="store_true", help="list skipped modules")
    args = ap.parse_args()

    for path, what in ((CONTRACT, "contract"), (ROUTES_DIR, "routes dir")):
        if not path.exists():
            print(f"::error::{what} not found: {path}")
            return 2

    prefix = api_prefix()
    source, notes = source_paths(prefix)
    contract = contract_paths()

    # Direction 1 — release blocking.
    missing_in_contract = sorted(
        p for p in source - contract if not p.startswith(EXCLUDED_PREFIXES)
    )
    # Direction 2 — informational only (see module docstring).
    unverified = sorted(contract - source)

    if args.json:
        print(
            json.dumps(
                {
                    "prefix": prefix,
                    "source_route_count": len(source),
                    "contract_path_count": len(contract),
                    "release_blocking": missing_in_contract,
                    "unverified_by_static_parse": unverified,
                    "notes": notes if args.verbose else [],
                },
                indent=2,
            )
        )
        return 1 if missing_in_contract else 0

    print(f"API contract drift check (prefix {prefix})")
    print(f"  routes parsed from source : {len(source)}")
    print(f"  paths in committed spec  : {len(contract)}")

    if missing_in_contract:
        print(
            f"\n::error::{len(missing_in_contract)} backend route(s) are missing "
            f"from packages/api_contracts/openapi.json:"
        )
        for p in missing_in_contract:
            print(f"  + {p}")
        print(
            "\nThe release E2E gate rejects any extra path, so this WILL block "
            "the\nstaging deploy (and therefore production). Fix it with:\n"
            "  python scripts/ci/refresh_api_contract.py"
        )
    else:
        print("\n::notice::Every backend route is documented in the committed contract.")

    if unverified:
        print(
            f"\n::debug::{len(unverified)} documented path(s) could not be "
            f"confirmed by static analysis\n(not a failure -- the parser only sees "
            f"literal `@router.<verb>` decorators)."
        )
        if args.verbose:
            for p in unverified:
                print(f"  ? {p}")

    if args.verbose:
        print("\nskipped modules:")
        for n in notes:
            print(f"  {n}")

    if missing_in_contract:
        print("\n::error::API contract is out of sync with the backend.")
        return 1

    print("\n::notice::No release-blocking contract drift.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
