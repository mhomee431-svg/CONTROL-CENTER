"""Celery background tasks — core infrastructure tasks."""

import logging
from datetime import datetime, timezone

from app.core.celery_app import celery_app

logger = logging.getLogger("app.core.tasks")


@celery_app.task(name="app.core.tasks.sample_background_task")
def sample_background_task(arg: str) -> dict:
    """Generic background task placeholder for testing job execution."""
    logger.info("Executing sample_background_task with arg=%s", arg)
    return {
        "status": "success",
        "arg": arg,
        "executed_at": datetime.now(timezone.utc).isoformat(),
    }


@celery_app.task(name="app.core.tasks.send_test_notification")
def send_test_notification(user_id: int, message: str) -> dict:
    """Placeholder for push/email notification delivery."""
    logger.info("send_test_notification user=%s message=%s", user_id, message)
    # TODO: Integrate with notifications service + FCM/apns provider
    return {"user_id": user_id, "delivered": True}


@celery_app.task(name="app.core.tasks.health_check_task")
def health_check_task() -> dict:
    """Task executed to verify Celery workers/queue are operational."""
    return {
        "status": "ok",
        "checked_at": datetime.now(timezone.utc).isoformat(),
    }