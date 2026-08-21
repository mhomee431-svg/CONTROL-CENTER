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