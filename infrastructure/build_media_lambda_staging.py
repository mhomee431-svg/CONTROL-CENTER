#!/usr/bin/env python3
"""Build the Lambda deployment staging dir for the media processor (Phase 3).

The Terraform ``data "archive_file"`` in
``infrastructure/terraform/media_processor.tf`` packages THIS staging dir into the
Lambda zip. The staging dir contains ONLY the application source
(``lambda_function.py`` + ``app/``) so the resulting zip has no ``.env`` files,
tests, alembic history, scripts, docs, or bytecode — i.e. no secrets and no
non-deployment clutter.

Python *dependencies* (sqlalchemy, pydantic, asyncpg, boto3, ...) are
INTENTIONALLY NOT included here: they must be provided as a separate Lambda Layer
(or a bundled deps zip) before the function can execute. See the packaging note
in ``infrastructure/terraform/media_processor.tf``. The authoritative dependency
list is ``backend/requirements.txt`` (the same file used to build the EC2 app
container); a Layer built from it will contain everything the verified test suite
needs.
"""
from __future__ import annotations

import shutil
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent          # infrastructure/
STAGING = SCRIPT_DIR / "lambda_staging"                # infrastructure/lambda_staging
BACKEND = SCRIPT_DIR.parent / "backend"               # backend/

LAMBDA_FILE = BACKEND / "lambda_function.py"
APP_DIR = BACKEND / "app"

IGNORE = shutil.ignore_patterns(
    "__pycache__", "*.pyc", "*.pyo",
    ".pytest_cache", ".ruff_cache", ".mypy_cache",
    ".env", ".env.*", "*.env",
    ".git", ".tox", "venv", ".venv", "node_modules",
    "alembic", "tests", "scripts", "docs",
    "*.log", "lambda.zip",
)


def main() -> int:
    if not LAMBDA_FILE.exists():
        print(f"ERROR: {LAMBDA_FILE} not found", file=sys.stderr)
        return 2
    if not APP_DIR.exists():
        print(f"ERROR: {APP_DIR} not found", file=sys.stderr)
        return 2

    if STAGING.exists():
        shutil.rmtree(STAGING)
    STAGING.mkdir(parents=True, exist_ok=True)

    # lambda_function.py at the zip root so the handler resolves:
    #   handler = "lambda_function.lambda_handler"
    shutil.copy2(LAMBDA_FILE, STAGING / "lambda_function.py")

    # app/ package at the zip root (import app.* resolves).
    # Copy the whole tree in one call so the IGNORE patterns (especially
    # __pycache__) are evaluated at the top level of backend/app/ — this
    # prevents empty __pycache__ directories from appearing in the staging dir.
    dest_app = STAGING / "app"
    shutil.copytree(APP_DIR, dest_app, ignore=IGNORE, dirs_exist_ok=True)

    n_app = len([e for e in dest_app.iterdir() if e.name != "__pycache__"])
    print(f"Staging dir ready: {STAGING}")
    print(f"  lambda_function.py : {(STAGING / 'lambda_function.py').exists()}")
    print(f"  app/               : {(STAGING / 'app').exists()}  (entries: {n_app})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
