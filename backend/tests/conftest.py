"""Pytest shared configuration and fixtures."""

import os
import sys
from pathlib import Path

# Ensure `app` package is importable from the Backend directory
BACKEND_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BACKEND_DIR))

# Force test environment for all tests
os.environ.setdefault("ENVIRONMENT", "test")
os.environ.setdefault("HYPERLOCAL_ENV", "test")

import pytest  # noqa: E402


@pytest.fixture(autouse=True)
def _isolate_app_dependency_overrides():
    """Snapshot/restore FastAPI dependency overrides around every test.

    Several test modules install overrides at import time (or in fixtures) while
    others call ``app.dependency_overrides.clear()`` on teardown. Without
    isolation that clear() leaks across modules: the next module silently falls
    through to the real PostgreSQL/async engines, which stall for ~2 minutes per
    request when no local server is running. Restoring the pre-test snapshot
    keeps every test's view of the app exactly as its own module configured it.

    Runs only when ``app.main`` is already imported, so pure unit-test modules
    (which never touch the FastAPI app) are completely unaffected.
    """
    app_main = sys.modules.get("app.main")
    app = getattr(app_main, "app", None) if app_main is not None else None
    if app is None:
        yield
        return

    previous_overrides = dict(app.dependency_overrides)
    try:
        yield
    finally:
        app.dependency_overrides.clear()
        app.dependency_overrides.update(previous_overrides)