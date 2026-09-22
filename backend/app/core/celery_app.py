"""Celery background job infrastructure with production-ready config."""

import logging
import threading
from typing import Any, Callable

from celery import Celery
from celery.schedules import crontab

from app.core.config import settings

logger = logging.getLogger("app.core.celery")

celery_app = Celery(
    "hyperlocal",
    broker=settings.CELERY_BROKER_URL,
    backend=settings.CELERY_RESULT_BACKEND,
    include=[
        "app.core.tasks",
        "app.services.tasks",
        "app.services.notification_tasks",
    ],
)

celery_app.conf.update(
    # Serialization
    task_serializer="json",
    accept_content=["json"],
    result_serializer="json",
    # Timezone
    timezone=settings.CELERY_TIMEZONE,
    enable_utc=True,
    # Task behaviour
    task_track_started=True,
    task_time_limit=settings.CELERY_TASK_TIME_LIMIT,
    task_soft_time_limit=settings.CELERY_TASK_SOFT_TIME_LIMIT,
    task_acks_late=True,
    task_reject_on_worker_lost=True,
    # Worker behaviour
    worker_max_tasks_per_child=1000,
    worker_prefetch_multiplier=1,
    # Result backend
    result_expires=3600,
    result_extended=True,
    # Retry policy
    task_default_retry_delay=30,
    task_max_retries=3,
    # Queues (explicit routing for clarity)
    task_routes={
        "app.core.tasks.*": {"queue": "default"},
        "app.services.tasks.*": {"queue": "background"},
    },
)

# ── Periodic beat schedule ─────────────────────────────────────────────────
celery_app.conf.beat_schedule = {
    # Incremental search-index sync every 5 minutes
    "search-index-incremental-sync": {
        "task": "app.services.tasks.sync_search_index",
        "schedule": 300.0,  # seconds
        "args": [300],      # look back 5 minutes
    },
    # Hourly full search-index reconciliation (catches missed changes)
    "search-index-reconcile": {
        "task": "app.services.tasks.sync_search_index",
        "schedule": 3600.0,
        "args": [3600],  # look back 1 hour
    },
    # Daily popular-searches aggregation
    "daily-popular-searches": {
        "task": "app.services.tasks.aggregate_popular_searches_task",
        "schedule": crontab(hour=2, minute=30),
    },
    # Phase 27 — retry failed notification deliveries every 5 minutes
    "notification-retry-sweep": {
        "task": "app.services.notification_tasks.retry_failed_notifications",
        "schedule": 300.0,
        "kwargs": {"limit": 100},
    },
    # Phase 24 — evaluate observability alert rules every minute
    "observe.evaluate-alerts": {
        "task": "app.core.tasks.evaluate_alert_rules",
        "schedule": 60.0,
    },
    # Phase 24 — keep resource-usage gauges fresh
    "observe.sample-resource-usage": {
        "task": "app.core.tasks.sample_resource_usage",
        "schedule": 30.0,
    },
    # Daily token & session cleanup (runs at 3:00 AM)
    "daily-token-cleanup": {
        "task": "app.services.tasks.cleanup_expired_tokens",
        "schedule": crontab(hour=3, minute=0),
    },
}

# ── Phase 24 — observability: Celery task-metrics signals ───────────────────
try:
    from app.core.observability.celery_signals import install_celery_observability

    install_celery_observability()
except Exception:  # noqa: BLE001 — telemetry is best-effort, never fatal
    pass

# Export commonly needed helpers
def get_celery_app() -> Celery:
    return celery_app


# ── Non-blocking task publish ───────────────────────────────────────────────
# Celery's ``send_task`` can block the CALLING thread for minutes when the
# broker / result backend is unreachable: the Redis result backend's
# ``on_task_call`` hook reconnects through kombu's ``retry_over_time``
# (20 retries with backoff) before it finally gives up. Every fire-and-forget
# publisher in the service layer must therefore publish on a short-lived daemon
# thread with a hard time budget, so a degraded broker can never stall a
# request thread. Abandoned publishes are converged by the periodic sweeps
# (search-index sync, notification retry, scheduled POS sync).
_TASK_PUBLISH_TIMEOUT_SECONDS = 1.0


def publish_task_nonblocking(
    publish: Callable[[], Any],
    *,
    label: str,
    timeout: float = _TASK_PUBLISH_TIMEOUT_SECONDS,
) -> bool:
    """Run a Celery publish (``task.delay(...)`` / ``send_task(...)``) with a cap.

    ``publish`` executes on a daemon thread that is joined for at most
    ``timeout`` seconds. Returns ``True`` when the publish completed inside the
    budget, ``False`` when it was abandoned or failed. NEVER raises: enqueuing
    a background job must not break the request that triggered it.
    """
    outcome: dict[str, bool] = {"published": False}

    def _publish() -> None:
        try:
            publish()
            outcome["published"] = True
        except Exception:  # noqa: BLE001 — the worker thread must never crash
            logger.debug("Celery publish failed: %s", label, exc_info=True)

    try:
        worker = threading.Thread(
            target=_publish,
            name=f"celery-publish-{label}",
            daemon=True,
        )
        worker.start()
        worker.join(timeout=timeout)
    except Exception:  # noqa: BLE001 — publish must never break the caller
        logger.exception("Could not publish Celery task %s", label)
        return False

    if worker.is_alive():
        logger.warning(
            "Celery publish timed out (broker degraded) after %ss: %s",
            timeout,
            label,
        )
        return False
    return outcome["published"]
