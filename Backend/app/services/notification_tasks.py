"""Notification background jobs — Phase 27.

Delivery is always asynchronous: business events create the notification rows
and enqueue :func:`deliver_notification_task`; transient provider failures are
retried with exponential backoff by Celery and swept periodically by
:func:`retry_failed_notifications_task`.
"""

import logging

from app.core.celery_app import celery_app
from app.database.session import SessionLocal

logger = logging.getLogger("app.services.notification_tasks")


@celery_app.task(
    name="app.services.notification_tasks.deliver_notification",
    bind=True,
    max_retries=3,
    autoretry_for=(Exception,),
    retry_backoff=30,       # 30s → 60s → 120s
    retry_jitter=True,
)
def deliver_notification_task(self, notification_id: int) -> dict:
    """Deliver one notification to all of its owner's active devices."""
    from app.services.notification_service import deliver_notification

    try:
        with SessionLocal() as db:
            result = deliver_notification(db, notification_id)
            db.commit()
        logger.info("deliver_notification id=%s → %s", notification_id, result.get("status"))
        return {"notification_id": notification_id, **result}
    except Exception as exc:  # noqa: BLE001
        logger.warning("deliver_notification id=%s failed: %s", notification_id, exc)
        raise self.retry(exc=exc)


@celery_app.task(name="app.services.notification_tasks.retry_failed_notifications")
def retry_failed_notifications_task(limit: int = 100) -> dict:
    """Periodic sweep — give failed/pending notifications another attempt."""
    from app.services.notification_service import retry_failed_notifications

    with SessionLocal() as db:
        summary = retry_failed_notifications(db, limit=limit)
        db.commit()
    logger.info("retry sweep processed=%s", summary.get("retried"))
    return summary


@celery_app.task(name="app.services.notification_tasks.deliver_batch")
def deliver_batch_task(notification_ids: list[int]) -> dict:
    """Deliver a batch (used after broadcasts instead of one task per row)."""
    from app.services.notification_service import deliver_notification

    outcomes = {}
    with SessionLocal() as db:
        for nid in notification_ids:
            outcomes[nid] = deliver_notification(db, nid)
        db.commit()
    return {
        "processed": len(outcomes),
        "outcomes": {str(k): v["status"] for k, v in outcomes.items()},
    }