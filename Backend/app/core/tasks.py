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


# ── Phase 24 — observability beat tasks ─────────────────────────────────────
@celery_app.task(name="app.core.tasks.evaluate_alert_rules")
def evaluate_alert_rules() -> dict:
    """Evaluate every alert rule and emit firing/resolved events.

    Runs on a fixed beat cadence (see the ``observe.evaluate-alerts`` entry
    in ``celery_app.conf.beat_schedule``). Never raises — alerting must not
    take down the beat scheduler.
    """
    try:
        from app.core.observability.alerting import evaluate_alerts

        events = evaluate_alerts()
        for event in events:
            logger.warning(
                "Alert %s %s: %s",
                event.status.upper(),
                event.rule,
                event.message,
            )
        return {"evaluated": True, "events": [e.to_dict() for e in events]}
    except Exception as exc:  # noqa: BLE001
        logger.exception("Alert rule evaluation failed: %s", exc)
        return {"evaluated": False, "error": str(exc)}


@celery_app.task(name="app.core.tasks.sample_resource_usage")
def sample_resource_usage() -> dict:
    """Sample process/OS resource gauges on a fixed cadence.

    Keeps long-running resource time-series alive even when nothing scrapes
    ``GET /metrics`` for a while.
    """
    try:
        from app.core.observability.resource_usage import collect_snapshot, refresh_resource_gauges

        snap = refresh_resource_gauges()
        return {"sampled": True, "snapshot": {k: v for k, v in snap.items() if v is not None}}
    except Exception as exc:  # noqa: BLE001
        logger.exception("Resource sampling failed: %s", exc)
        return {"sampled": False, "error": str(exc)}