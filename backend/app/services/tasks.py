"""Service-layer background tasks — domain-specific job orchestration."""

import logging
from datetime import datetime, timedelta, timezone

from app.core.celery_app import celery_app
from app.database.session import SessionLocal
from app.search import indexer
from app.search.engine import aggregate_popular_searches

logger = logging.getLogger("app.services.tasks")


@celery_app.task(name="app.services.tasks.dispatch_email")
def dispatch_email(to_email: str, subject: str, template_name: str, context: dict) -> dict:
    """Dispatch an email via the configured email provider.

    The actual delivery is delegated to the email abstraction so the provider
    can be swapped (SMTP / SendGrid / AWS SES) without touching this task.
    """
    logger.info(
        "dispatch_email to=%s subject=%s template=%s",
        to_email,
        subject,
        template_name,
    )
    # TODO: import EmailService and call send here.
    return {
        "status": "queued",
        "to_email": to_email,
        "template": template_name,
        "queued_at": datetime.now(timezone.utc).isoformat(),
    }


@celery_app.task(name="app.services.tasks.dispatch_sms")
def dispatch_sms(phone_number: str, template_name: str, context: dict) -> dict:
    """Dispatch an SMS via the configured SMS provider.

    The actual delivery is delegated to the SMS abstraction so the provider
    can be swapped (Mock / Twilio / AWS SNS) without touching this task.
    """
    logger.info(
        "dispatch_sms to=%s template=%s",
        phone_number,
        template_name,
    )
    # TODO: import SmsService and call send here.
    return {
        "status": "queued",
        "phone_number": phone_number,
        "template": template_name,
        "queued_at": datetime.now(timezone.utc).isoformat(),
    }


# ── Search index propagation ───────────────────────────────────────────────
@celery_app.task(name="app.services.tasks.process_inventory_import")
def process_inventory_import(job_id: int) -> dict:
    """Background task — apply an Excel inventory-import job's valid rows.

    Large imports are confirmed into QUEUED state by the API and processed
    here so request handlers never block on thousands of row upserts.
    """
    from app.services import excel_import_service

    with SessionLocal() as db:
        try:
            summary = excel_import_service.process_import_job(db, job_id)
            db.commit()
            return {
                "status": "success",
                "job_id": job_id,
                "processed": summary.get("processed_this_run"),
                "failed": summary.get("failed_this_run"),
                "executed_at": datetime.now(timezone.utc).isoformat(),
            }
        except Exception as exc:  # noqa: BLE001
            db.rollback()
            logger.exception("process_inventory_import failed for job %s", job_id)
            return {
                "status": "error",
                "job_id": job_id,
                "error": str(exc),
                "executed_at": datetime.now(timezone.utc).isoformat(),
            }


@celery_app.task(name="app.services.tasks.index_shop_product")
def index_shop_product(shop_product_id: int) -> dict:
    """Background task — index or re-index a single shop product."""
    from app.search.indexer import upsert_shop_product

    with SessionLocal() as db:
        try:
            entry = upsert_shop_product(db, shop_product_id)
            db.commit()
            return {
                "status": "success",
                "shop_product_id": shop_product_id,
                "indexed": entry.id if entry else None,
                "executed_at": datetime.now(timezone.utc).isoformat(),
            }
        except Exception as exc:  # noqa: BLE001
            db.rollback()
            logger.exception("index_shop_product failed for %s", shop_product_id)
            return {"status": "error", "shop_product_id": shop_product_id, "error": str(exc)}


@celery_app.task(name="app.services.tasks.index_product")
def index_product(product_id: int) -> dict:
    """Index (or re-index) all shop products of a product master."""
    with SessionLocal() as db:
        try:
            entries = indexer.upsert_product_index(db, product_id)
            db.commit()
            return {"status": "success", "product_id": product_id, "entries": len(entries)}
        except Exception as exc:  # noqa: BLE001
            db.rollback()
            logger.exception("index_product failed for %s", product_id)
            return {"status": "error", "product_id": product_id, "error": str(exc)}


@celery_app.task(name="app.services.tasks.index_shop")
def index_shop(shop_id: int) -> dict:
    """Index (or re-index) all products of a shop."""
    with SessionLocal() as db:
        try:
            entries = indexer.upsert_shop_index(db, shop_id)
            db.commit()
            return {"status": "success", "shop_id": shop_id, "entries": len(entries)}
        except Exception as exc:  # noqa: BLE001
            db.rollback()
            logger.exception("index_shop failed for %s", shop_id)
            return {"status": "error", "shop_id": shop_id, "error": str(exc)}


@celery_app.task(name="app.services.tasks.sync_search_index")
def sync_search_index(since_seconds: int = 300) -> dict:
    """Incremental sync — re-index shop products updated in the last N seconds."""
    since = datetime.now(timezone.utc) - timedelta(seconds=since_seconds)
    with SessionLocal() as db:
        try:
            run = indexer.incremental_sync(db, since=since)
            db.commit()
            return {
                "status": run.status.value,
                "run_id": run.id,
                "processed": run.total_processed,
                "created": run.total_created,
                "updated": run.total_updated,
                "removed": run.total_removed,
                "errors": run.error_count,
            }
        except Exception as exc:  # noqa: BLE001
            db.rollback()
            logger.exception("sync_search_index failed")
            return {"status": "error", "error": str(exc)}


@celery_app.task(name="app.services.tasks.full_rebuild_search_index")
def full_rebuild_search_index() -> dict:
    """Full rebuild of the entire search index."""
    with SessionLocal() as db:
        try:
            run = indexer.full_rebuild(db)
            db.commit()
            return {
                "status": run.status.value,
                "run_id": run.id,
                "processed": run.total_processed,
                "created": run.total_created,
                "errors": run.error_count,
            }
        except Exception as exc:  # noqa: BLE001
            db.rollback()
            logger.exception("full_rebuild_search_index failed")
            return {"status": "error", "error": str(exc)}


@celery_app.task(name="app.services.tasks.aggregate_popular_searches_task")
def aggregate_popular_searches_task() -> dict:
    """Aggregate popular searches from search events (foundation for trending)."""
    with SessionLocal() as db:
        try:
            updated = aggregate_popular_searches(db)
            db.commit()
            return {"status": "success", "updated": updated}
        except Exception as exc:  # noqa: BLE001
            db.rollback()
            logger.exception("aggregate_popular_searches_task failed")
            return {"status": "error", "error": str(exc)}


# ── Phase 25 — POS integration platform background jobs ─────────────────────
@celery_app.task(name="app.services.tasks.run_pos_sync_job")
def run_pos_sync_job(job_id: int) -> dict:
    """Background task — execute a queued POS sync job."""
    from app.services import pos_sync_service

    with SessionLocal() as db:
        try:
            result = pos_sync_service.run_sync_job(db, job_id)
            db.commit()
            return {
                "status": "success",
                "job_id": job_id,
                "result": result,
                "executed_at": datetime.now(timezone.utc).isoformat(),
            }
        except Exception as exc:  # noqa: BLE001
            db.rollback()
            logger.exception("run_pos_sync_job failed for job %s", job_id)
            return {
                "status": "error",
                "job_id": job_id,
                "error": str(exc),
                "executed_at": datetime.now(timezone.utc).isoformat(),
            }


@celery_app.task(name="app.services.tasks.dispatch_scheduled_pos_syncs")
def dispatch_scheduled_pos_syncs() -> dict:
    """Periodic scheduler tick — enqueue sync jobs for cadence-due integrations.

    ``find_due_integrations`` already guards against double-dispatch (open-job
    check), and each job carries a unique idempotency key so even a race
    between two ticks cannot create duplicate work.
    """
    from app.services import pos_sync_service

    dispatched: list[dict] = []
    with SessionLocal() as db:
        for integration in pos_sync_service.find_due_integrations(db):
            sync_type = "INCREMENTAL" if integration.incremental_cursor else "FULL"
            idempotency_key = f"sched-{integration.id}-{int(datetime.now(timezone.utc).timestamp())}"
            try:
                job, created = pos_sync_service.trigger_manual_sync(
                    db,
                    integration.id,
                    sync_type=sync_type,
                    trigger="SCHEDULED",
                    idempotency_key=idempotency_key,
                )
                if created:
                    db.commit()
                    run_pos_sync_job.delay(job.id)
                    dispatched.append(
                        {"integration_id": integration.id, "job_id": job.id, "sync_type": sync_type}
                    )
                else:
                    db.rollback()
            except Exception as exc:  # noqa: BLE001 — one bad shop must not stop the sweep
                db.rollback()
                logger.warning("Scheduled POS sync skipped integration %s: %s", integration.id, exc)
    return {
        "status": "success",
        "dispatched": dispatched,
        "executed_at": datetime.now(timezone.utc).isoformat(),
    }


# ── Token & Session Cleanup ────────────────────────────────────────────────
@celery_app.task(name="app.services.tasks.cleanup_expired_tokens")
def cleanup_expired_tokens() -> dict:
    """Periodic task — clean expired tokens, sessions, and OTPs.
    
    Scheduled to run daily via Celery Beat. Removes:
    - Expired blacklisted JWT tokens
    - Expired auth sessions
    - Expired OTP records
    - Expired password reset tokens
    """
    with SessionLocal() as db:
        try:
            from app.services.token_cleanup_service import cleanup_expired_tokens as _cleanup

            results = _cleanup(db)
            return {
                "status": "success",
                "cleaned": results,
                "executed_at": datetime.now(timezone.utc).isoformat(),
            }
        except Exception as exc:  # noqa: BLE001
            logger.exception("cleanup_expired_tokens failed")
            return {
                "status": "error",
                "error": str(exc),
                "executed_at": datetime.now(timezone.utc).isoformat(),
            }
