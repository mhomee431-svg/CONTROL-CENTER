"""Celery background job infrastructure with production-ready config."""

from celery import Celery
from celery.schedules import crontab

from app.core.config import settings

celery_app = Celery(
    "hyperlocal",
    broker=settings.CELERY_BROKER_URL,
    backend=settings.CELERY_RESULT_BACKEND,
    include=[
        "app.core.tasks",
        "app.services.tasks",
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

# ── Periodic beat schedule (optional — enable when needed) ──────────────────
celery_app.conf.beat_schedule = {
    # "cleanup-old-logs": {
    #     "task": "app.services.tasks.cleanup_old_logs",
    #     "schedule": crontab(hour=3, minute=0),
    # },
    # "daily-popular-searches": {
    #     "task": "app.services.tasks.compute_popular_searches",
    #     "schedule": crontab(hour=2, minute=30),
    # },
}

# Export commonly needed helpers
def get_celery_app() -> Celery:
    return celery_app