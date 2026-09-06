"""Deployment identity + status metrics.

Populates ``hl_deployment_info{commit,build_id,version,environment}``,
``hl_deployment_timestamp_seconds`` and ``hl_deployments_total`` from the
runtime environment:

* commit   — ``GIT_COMMIT`` / ``COMMIT_SHA`` env, else ``git rev-parse``
             when a checkout is present, else ``unknown``
* build_id — ``BUILD_ID`` / ``DEPLOYMENT_ID`` / ``BUILD_NUMBER`` env, else
             ``manual``
* version  — ``settings.APP_VERSION``
* environment — ``settings.ENVIRONMENT``

Called once at application startup (``app/main.py`` lifespan).
"""

from __future__ import annotations

import os
import subprocess
import time
from functools import lru_cache
from typing import Dict

from app.core.config import settings
from app.core.logging import get_logger
from app.core.observability import metrics

logger = get_logger("app.observability.deployment")


def _read_commit_from_env() -> str:
    for key in ("GIT_COMMIT", "COMMIT_SHA", "CI_COMMIT_SHA", "SOURCE_VERSION"):
        value = os.getenv(key)
        if value:
            return value[:12]
    return ""


@lru_cache(maxsize=1)
def detect_commit() -> str:
    env_commit = _read_commit_from_env()
    if env_commit:
        return env_commit
    try:
        result = subprocess.run(
            ["git", "rev-parse", "--short", "HEAD"],
            capture_output=True,
            text=True,
            timeout=2,
            check=False,
        )
        if result.returncode == 0 and result.stdout.strip():
            return result.stdout.strip()[:12]
    except Exception:  # noqa: BLE001 — no git available in the container
        pass
    return "unknown"


@lru_cache(maxsize=1)
def detect_build_id() -> str:
    for key in ("BUILD_ID", "DEPLOYMENT_ID", "BUILD_NUMBER"):
        value = os.getenv(key)
        if value:
            return value
    return "manual"


def deployment_metadata() -> Dict[str, str]:
    """Return the full deployment identity dict for /health + gauges."""
    return {
        "commit": detect_commit(),
        "build_id": detect_build_id(),
        "version": settings.APP_VERSION,
        "environment": settings.ENVIRONMENT,
    }


def register_deployment(result: str = "starting") -> Dict[str, str]:
    """Record the current deployment into gauges/counters and return metadata.

    ``result`` is one of ``starting`` | ``success`` | ``failure`` and is
    added to ``hl_deployments_total`` (a process restart naturally fires a
    new ``starting`` event).
    """
    meta = deployment_metadata()
    metrics.deployment_info.set(1, **meta)
    metrics.deployment_timestamp_seconds.set(time.time())
    metrics.deployments_total.inc(environment=meta["environment"], result=result)
    logger.info(
        "Deployment registered result=%s commit=%s build_id=%s env=%s version=%s",
        result,
        meta["commit"],
        meta["build_id"],
        meta["environment"],
        meta["version"],
    )
    return meta