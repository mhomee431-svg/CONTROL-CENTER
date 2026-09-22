"""Phase 3 - Reconciliation cron for media stuck in PROCESSING.

An S3-event delivery can be lost (DLQ redrive, network blip), leaving a media
row stuck at PROCESSING after the object is actually safe. The EventBridge cron
in `infrastructure/terraform/foundation` invokes the FastAPI reconcile endpoint,
which re-runs the same validation the Lambda would have -- idempotent, so a
reconciled READY row is not re-validated.
"""
from __future__ import annotations

from datetime import datetime, timedelta, timezone
from typing import Protocol

from sqlalchemy.orm import Session

from app.core.logging import get_logger
from app.models.media import Media, MediaState

logger = get_logger("app.media_reconciliation")


class _ProviderLike(Protocol):
    def head_object(self, key: str): ...
    def read_object_bytes(self, key: str, limit: int = 8) -> bytes: ...
    def copy_object(self, src_key: str, dst_key: str) -> None: ...
    def delete_object(self, key: str) -> None: ...


def reconcile_stale_media(
    db: Session,
    provider: _ProviderLike,
    *,
    stale_minutes: int = 10,
) -> int:
    """Re-process media rows stuck in PROCESSING past the staleness window.

    Returns the number of rows finalized. Safe to run concurrently: each row
    re-enters `process_s3_event`, which no-ops on READY/FAILED and guards
    finalized state via the row's current value.
    """
    from app.services.media_lifecycle import process_s3_event

    cutoff = datetime.now(timezone.utc) - timedelta(minutes=stale_minutes)
    stale = (
        db.query(Media)
        .filter(Media.state == MediaState.PROCESSING, Media.updated_at <= cutoff)
        .all()
    )
    finalized = 0
    for media in stale:
        try:
            process_s3_event(db, key=media.key, provider=provider)
            finalized += 1
        except Exception as exc:  # noqa: BLE001 - one bad row must not block the batch
            logger.warning("reconcile failed for %s: %s", media.key, exc)
    return finalized
