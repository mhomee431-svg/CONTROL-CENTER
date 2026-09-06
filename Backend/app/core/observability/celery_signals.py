"""Celery signal hooks — background-job metrics (Phase 24).

Registered from ``app/core/celery_app.py``. Hooks observe every task's
lifecycle and push into the observability metrics:

* ``task_received``    — counter event "received"
* ``task_prerun``      — gauge +1 for the task; counter "started"
* ``task_success``     — gauge -1; counter "succeeded"; histogram duration
* ``task_failure``     — gauge -1; counter "failed"; histogram duration
* ``task_retry``       — counter "retried"

Task names are truncated to a bounded label (they include dotted module
paths) to keep Prometheus series cardinality in check.
"""

from __future__ import annotations

import time
from typing import Any, Dict

from celery.signals import (
    task_failure,
    task_prerun,
    task_received,
    task_retry,
    task_success,
)

from app.core.observability import metrics
from app.core.observability.registry import get_registry

MAX_TASK_LABEL = 80

#: task-id -> short task name (populated at prerun)
_task_names: Dict[str, str] = {}
#: task-id -> monotonic start (populated at prerun)
_running: Dict[str, float] = {}
#: short task name -> active count (keeps the gauge balanced)
_active_counts: Dict[str, int] = {}


def _short_task_name(task_name: Any) -> str:
    if task_name is None:
        return "unknown"
    return str(task_name)[:MAX_TASK_LABEL]


def _resolve_task_name(kwargs: Dict[str, Any]) -> str:
    task = kwargs.get("task")
    if task is None:
        task = getattr(kwargs.get("sender"), "name", "unknown")
    return _short_task_name(task)


def _register_metrics_for(name: str) -> None:
    """Idempotently snapshot the label set for a task into the registry."""
    metrics.background_jobs_total.get(task=name, event="started")
    metrics.background_jobs_total.get(task=name, event="succeeded")
    metrics.background_jobs_total.get(task=name, event="failed")
    metrics.background_jobs_total.get(task=name, event="retried")
    metrics.background_jobs_active.get(task=name)
    metrics.background_job_duration_seconds.get(task=name, event="succeeded")
    metrics.background_job_duration_seconds.get(task=name, event="failed")


def _on_task_received(*args: Any, **kwargs: Any) -> None:
    try:
        name = _resolve_task_name(kwargs)
        _register_metrics_for(name)
        metrics.record_background_job(name, "received")
    except Exception:  # noqa: BLE001 — telemetry must never break Celery
        pass


def _on_task_prerun(*args: Any, **kwargs: Any) -> None:
    try:
        name = _resolve_task_name(kwargs)
        task_id = kwargs.get("task_id")
        _register_metrics_for(name)
        if task_id:
            _running[task_id] = time.monotonic()
            _task_names[task_id] = name
        _active_counts[name] = _active_counts.get(name, 0) + 1
        metrics.set_background_job_active(name, True)
        metrics.record_background_job(name, "started")
    except Exception:  # noqa: BLE001
        pass


def _finish_task(task_id: Any, event: str) -> None:
    try:
        name = _task_names.pop(task_id, "unknown")
        start = _running.pop(task_id, None)
        if _active_counts.get(name, 0) > 0:
            _active_counts[name] -= 1
        if _active_counts.get(name, 0) <= 0:
            metrics.set_background_job_active(name, False)
        metrics.record_background_job(name, event)
        if start is not None:
            metrics.background_job_duration_seconds.observe(
                max(0.0, time.monotonic() - start), task=name, event=event
            )
    except Exception:  # noqa: BLE001
        pass


def _on_task_success(*args: Any, **kwargs: Any) -> None:
    _finish_task(kwargs.get("task_id"), "succeeded")


def _on_task_failure(*args: Any, **kwargs: Any) -> None:
    _finish_task(kwargs.get("task_id"), "failed")


def _on_task_retry(*args: Any, **kwargs: Any) -> None:
    try:
        task_id = kwargs.get("task_id")
        name = _task_names.get(task_id, "unknown")
        metrics.record_background_job(name, "retried")
    except Exception:  # noqa: BLE001
        pass


_connected = False


def install_celery_observability() -> None:
    """Register the Celery signal hooks (idempotent)."""
    global _connected
    if _connected:
        return
    task_received.connect(_on_task_received, weak=False)
    task_prerun.connect(_on_task_prerun, weak=False)
    task_success.connect(_on_task_success, weak=False)
    task_failure.connect(_on_task_failure, weak=False)
    task_retry.connect(_on_task_retry, weak=False)
    _connected = True