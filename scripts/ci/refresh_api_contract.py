#!/usr/bin/env python3
"""scripts/ci/refresh_api_contract.py -- regenerate the committed OpenAPI spec.

`packages/api_contracts/openapi.json` is the contract that the release pipeline
(`cicd_contract_check.py`) compares the deployed API against. It is generated
from the live FastAPI app, so it MUST be regenerated whenever a route is added
or removed -- otherwise the staging E2E gate rejects the release.

    python scripts/ci/refresh_api_contract.py            # write the file
    python scripts/ci/refresh_api_contract.py --check    # CI: fail if stale
    python scripts/ci/refresh_api_contract.py --diff     # show what changed

`--check` is what belongs in a pull request: it exits non-zero when the
committed file no longer matches the app, which is the same signal as
`check_api_contract_drift.py` but exact -- it boots the real application
instead of parsing the source, so it has no blind spots.

Requires the backend's dependencies to be importable (run from the repo root
with the backend virtualenv, or `pip install -r backend/requirements.txt`).
"""
from __future__ import annotations

import argparse
import difflib
import json
import os
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
BACKEND = REPO_ROOT / "backend"
CONTRACT = REPO_ROOT / "packages" / "api_contracts" / "openapi.json"


def build_spec() -> dict:
    """Import the FastAPI app and return its OpenAPI document."""
    # Import-time config must not require a live database or Redis.
    os.environ.setdefault("ENVIRONMENT", "test")
    os.environ.setdefault("SKIP_DB_ON_IMPORT", "1")
    os.environ.setdefault("PYTHONPATH", str(BACKEND))
    if str(BACKEND) not in sys.path:
        sys.path.insert(0, str(BACKEND))

    from app.main import app  # noqa: PLC0415 - deliberately late

    return app.openapi()


def render(spec: dict) -> str:
    """Serialise the way the committed contract already is.

    The committed file is `json.dumps(spec, indent=2)` in FastAPI's own key
    order (`openapi`, `info`, `paths`, `components`) -- NOT sorted. Sorting here
    would rewrite all ~25k lines on every refresh and bury the handful of real
    changes in a formatting-only diff, which is how contract updates stop being
    reviewed. FastAPI emits a stable order (declaration order), so an unsorted
    dump is still deterministic.
    """
    return json.dumps(spec, indent=2) + "\n"


def main() -> int:
    ap = argparse.ArgumentParser(description="Regenerate the committed OpenAPI spec")
    ap.add_argument(
        "--check",
        action="store_true",
        help="do not write; exit 1 if the committed spec is stale",
    )
    ap.add_argument("--diff", action="store_true", help="print a unified diff")
    args = ap.parse_args()

    try:
        spec = build_spec()
    except Exception as exc:  # noqa: BLE001 - report, never traceback-spam CI
        print(f"::error::Could not import the FastAPI app: {exc!r}")
        print(
            "::error::Install the backend dependencies first "
            "(pip install -r backend/requirements.txt)."
        )
        return 2

    new_text = render(spec)
    old_text = CONTRACT.read_text(encoding="utf-8") if CONTRACT.exists() else ""

    if old_text == new_text:
        print("::notice::Committed API contract is already up to date.")
        return 0

    if args.diff or args.check:
        diff = difflib.unified_diff(
            old_text.splitlines(keepends=True),
            new_text.splitlines(keepends=True),
            fromfile="committed openapi.json",
            tofile="regenerated openapi.json",
        )
        lines = list(diff)
        added = sum(1 for x in lines if x.startswith("+") and not x.startswith("+++"))
        removed = sum(1 for x in lines if x.startswith("-") and not x.startswith("---"))
        print(f"API contract drift: +{added} / -{removed} lines")
        if args.diff:
            sys.stdout.writelines(lines)
        if args.check:
            print(
                "\n::error::packages/api_contracts/openapi.json is out of date.\n"
                "Run: python scripts/ci/refresh_api_contract.py"
            )
            return 1

    CONTRACT.parent.mkdir(parents=True, exist_ok=True)
    CONTRACT.write_text(new_text, encoding="utf-8")
    print(f"::notice::Wrote {CONTRACT.relative_to(REPO_ROOT)}")
    print("Commit it together with the route change.")
    return 0


if __name__ == "__main__":
    sys.exit(main())