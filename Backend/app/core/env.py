"""
Environment profile selection.

Settings are loaded from the correct `.env.<environment>` file automatically
by `app.core.config.Settings`.  This module provides a simple helper to inspect
the active profile and validate it against the known set.

Known environment names:
    development   → `development` (default)
    test          → `test`
    staging       → `staging`
    production    → `production`
"""
import os

from app.core.config import settings, get_settings

VALID_ENVIRONMENTS = ("development", "test", "staging", "production")


def get_active_environment() -> str:
    """Return the currently active environment name (lower-cased)."""
    return settings.ENVIRONMENT


def is_valid_environment(name: str) -> bool:
    return name in VALID_ENVIRONMENTS


def resolve_profile() -> str:
    """Alias for get_active_environment — used by scripts / CLI tooling."""
    return get_active_environment()


def get_environment_settings():
    """Return the active Settings instance (cached)."""
    return get_settings()


def reload_settings_for_environment(environment: str):
    """
    Force-reload settings for a given environment (test helper).
    Clears the lru_cache and re-reads the .env.<environment> file.
    """
    if not is_valid_environment(environment):
        raise ValueError(f"Unknown environment: {environment}")
    os.environ["ENVIRONMENT"] = environment
    get_settings.cache_clear()
    return get_settings()