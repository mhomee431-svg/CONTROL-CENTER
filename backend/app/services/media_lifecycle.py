"""Phase 2/3 - Media state-machine lifecycle (Synchronous; Lambda + tests).

Driven by backend/lambda_function.py. Storage-agnostic: tests inject a
dict-backed fake implementing StorageReadProvider; production injects a boto3
adapter. Sync by design (Lambda handler is sync).

State machine: PENDING -> UPLOADED -> PROCESSING -> READY | FAILED(quarantine)

Idempotency: process_s3_event / confirm_media no-op once a row is READY/FAILED.
"""
from __future__ import annotations

import uuid
from datetime import datetime, timezone
from typing import Optional, Protocol

from sqlalchemy.orm import Session

from app.core.exceptions import NotFoundError
from app.core.logging import get_logger
from app.core.upload_security import sniff_media_content_type
from app.models.media import Media, MediaState

logger = get_logger("app.media_lifecycle")


class StorageReadProvider(Protocol):
    """Sync storage surface used by the Lambda + lifecycle service."""

    def head_object(self, key: str) -> Optional[dict]:
        """{'content_type': str, 'size': int} | None if missing."""

    def read_object_bytes(self, key: str, limit: int = 8) -> bytes: ...

    def copy_object(self, src_key: str, dst_key: str) -> None: ...

    def delete_object(self, key: str) -> None: ...


def _allowed_content_types(category: Optional[str]) -> Optional[tuple]:
    if not category:
        return None
    from app.services.media_service import MEDIA_CATEGORIES

    return MEDIA_CATEGORIES.get(category).content_types if MEDIA_CATEGORIES.get(category) else None


def _uuid8() -> str:
    return uuid.uuid4().hex[:8]


def _upsert(db: Session, key: str) -> Media:
    media = db.query(Media).filter(Media.key == key).first()
    if media is None:
        media = Media(key=key)  # state defaults to PENDING
        db.add(media)
        db.flush()
    return media


def record_upload_intent(
    db: Session, *, key: str, category: Optional[str] = None,
    scope: Optional[str] = None, content_type: Optional[str] = None,
    size_bytes: Optional[int] = None, shop_id: Optional[int] = None,
    user_id: Optional[int] = None,
) -> Media:
    media = Media(
        key=key, category=category, scope=scope, content_type=content_type,
        declared_size_bytes=size_bytes, size_bytes=size_bytes,
        shop_id=shop_id, user_id=user_id, state=MediaState.PENDING,
    )
    db.add(media)
    db.commit()
    db.refresh(media)
    return media


def get_media_status(db: Session, key: str) -> Optional[Media]:
    return db.query(Media).filter(Media.key == key).first()


def _head(provider: StorageReadProvider, key: str) -> Optional[dict]:
    try:
        return provider.head_object(key)
    except Exception as exc:  # noqa: BLE001 - storage errors must not crash the worker
        logger.warning("head_object failed for %s: %s", key, exc)
        return None


def confirm_media(db: Session, *, key: str, provider: StorageReadProvider) -> Media:
    """Idempotent confirm: HEAD -> UPLOADED; repeats return the row unchanged."""
    media = _upsert(db, key)
    meta = _head(provider, key)
    if meta is None:
        if media.state == MediaState.READY:
            return media
        media.state = MediaState.FAILED
        media.error_code = "NOT_FOUND"
        media.error_message = "Object missing at confirm"
        db.commit()
        db.refresh(media)
        raise NotFoundError("Upload not found - complete the upload before confirming")
    media.content_type = meta.get("content_type") or media.content_type
    if media.size_bytes is None:
        media.size_bytes = meta.get("size")
    if media.state == MediaState.PENDING:
        media.state = MediaState.UPLOADED
    db.commit()
    db.refresh(media)
    return media


def _quarantine(db, media, provider, code, message, key):
    """Move a corrupt/impersonating object to a quarantine prefix and mark FAILED."""
    qkey = f"{key}.quarantine/{_uuid8()}"
    try:
        provider.copy_object(key, qkey)
        provider.delete_object(key)
    except Exception as exc:  # noqa: BLE001 - quarantine is best-effort
        logger.warning("quarantine copy failed for %s: %s", key, exc)
    media.quarantine_key = qkey
    media.state = MediaState.FAILED
    media.error_code = code
    media.error_message = message
    media.processed_at = datetime.now(timezone.utc)
    db.commit()
    db.refresh(media)
    return media


def process_s3_event(
    db: Session, *, key: str, provider: StorageReadProvider,
    content_type_known: Optional[str] = None, size_known: Optional[int] = None,
    category: Optional[str] = None,
) -> Media:
    """Lambda entry point: validate a created object and advance its state."""
    media = _upsert(db, key)
    if category and not media.category:
        media.category = category

    meta = _head(provider, key)
    if meta is None:
        media.state = MediaState.FAILED
        media.error_code = "OBJECT_MISSING"
        media.error_message = "Object not present at processing time"
        media.processed_at = datetime.now(timezone.utc)
        db.commit()
        db.refresh(media)
        return media

    if media.state in (MediaState.READY, MediaState.FAILED):
        return media  # idempotency: finalized rows are not reprocessed

    ctype = meta.get("content_type") or content_type_known
    size = meta.get("size") or size_known
    media.content_type = ctype
    media.size_bytes = size

    # Declared-vs-stored size guard (blocks truncated/oversized uploads).
    if media.declared_size_bytes and size and media.declared_size_bytes != size:
        return _quarantine(db, media, provider, "SIZE_MISMATCH",
                           f"declared {media.declared_size_bytes} != stored {size}", key)

    media.state = MediaState.PROCESSING
    db.commit()

    # Magic-byte validation (defense-in-depth: blocks renamed executables /
    # polyglots the signed-upload policy could not detect, since the backend
    # never sees bytes at upload-intent time).
    data = provider.read_object_bytes(key, limit=8)
    detected = sniff_media_content_type(data)
    allowed = _allowed_content_types(media.category)

    if not data:
        return _quarantine(db, media, provider, "EMPTY_FILE", "object has no bytes", key)
    if detected is None:
        return _quarantine(db, media, provider, "CONTENT_TYPE_MISMATCH",
                           "magic-byte sniff could not identify the file", key)
    if ctype and detected != ctype:
        return _quarantine(db, media, provider, "CONTENT_TYPE_MISMATCH",
                           f"declared {ctype} != detected {detected}", key)
    if allowed and detected not in allowed:
        return _quarantine(db, media, provider, "CONTENT_TYPE_NOT_ALLOWED",
                           f"{detected} not in allow-list {allowed}", key)

    media.state = MediaState.READY
    media.error_code = None
    media.error_message = None
    media.processed_at = datetime.now(timezone.utc)
    db.commit()
    db.refresh(media)
    logger.info("media ready key=%s category=%s", media.key, media.category)
    return media
