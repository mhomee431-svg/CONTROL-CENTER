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
    """Deliver a test push to every active device of ``user_id``.

    Uses the same delivery contract as the notification engine: the real push
    provider (mock in dev/test, FCM in production) is invoked per device token
    and permanently-invalid tokens are deactivated so later sweeps do not keep
    retrying them. Users without a registered device are reported, not failed —
    a test push must never raise.
    """
    from app.database.session import SessionLocal
    from app.models.notification import DeviceToken
    from app.services.push_service import PushMessage, get_push_service

    try:
        with SessionLocal() as db:
            tokens = (
                db.query(DeviceToken)
                .filter(
                    DeviceToken.user_id == user_id,
                    DeviceToken.is_active == True,  # noqa: E712
                )
                .all()
            )
            if not tokens:
                logger.info(
                    "send_test_notification user=%s has no active devices", user_id
                )
                return {
                    "user_id": user_id,
                    "delivered": False,
                    "reason": "no_active_devices",
                }

            provider = get_push_service()
            results = [
                provider.send(
                    PushMessage(
                        token=device_token.token,
                        title="Test notification",
                        body=message,
                        deep_link="/",
                    )
                )
                for device_token in tokens
            ]

            # Same deactivation contract as notification_service.deliver_notification.
            for device_token, result in zip(tokens, results):
                if result.permanent_failure:
                    device_token.is_active = False
                    device_token.failure_count = (device_token.failure_count or 0) + 1
            db.commit()

        delivered = sum(1 for result in results if result.delivered)
        logger.info(
            "send_test_notification user=%s delivered=%s/%s",
            user_id,
            delivered,
            len(results),
        )
        return {
            "user_id": user_id,
            "delivered": delivered > 0,
            "sent": delivered,
            "total": len(results),
        }
    except Exception as exc:  # noqa: BLE001 — a test push must never crash a worker
        logger.exception("send_test_notification failed for user %s", user_id)
        return {"user_id": user_id, "delivered": False, "error": str(exc)}


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