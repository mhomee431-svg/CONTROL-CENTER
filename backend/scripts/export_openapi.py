#!/usr/bin/env python
"""Export the FastAPI OpenAPI spec to packages/api_contracts/openapi.json.

Usage (from repo root or anywhere):

    python backend/scripts/export_openapi.py

The spec is the generated source of truth for the HTTP contract consumed by
the customer app, shopkeeper app and (future) admin panel. CI re-runs this
script and fails if the committed file is stale.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
BACKEND_DIR = REPO_ROOT / "backend"
OUT_PATH = REPO_ROOT / "packages" / "api_contracts" / "openapi.json"


def main() -> int:
    if str(BACKEND_DIR) not in sys.path:
        sys.path.insert(0, str(BACKEND_DIR))

    from app.main import app  # noqa: E402  (needs backend/ on sys.path)

    spec = app.openapi()
    OUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    OUT_PATH.write_text(
        json.dumps(spec, indent=2, sort_keys=False, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )
    paths = len(spec.get("paths", {}))
    schemas = len(spec.get("components", {}).get("schemas", {}))
    print(f"openapi.json written: {OUT_PATH}")
    print(f"  paths: {paths} | schemas: {schemas}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
