"""Phase 3 - Lambda handler: S3 object-created media state processor.

Invoked by S3 -> EventBridge -> this Lambda on ObjectCreated. Validates each
object (magic bytes / content-type / declared-vs-stored size) and advances its
Media row through the lifecycle, quarantining corrupt or impersonating files.

Also handles a scheduled EventBridge event (`{"cron":"reconcile"}`) that
re-processes Media rows stuck in PROCESSING.

Testable without AWS/Postgres: `lambda_handler(event, context, *, db_factory=...,
provider=...)` accepts injected SQLite sessions + a fake provider.
"""
from __future__ import annotations

import json
import logging
from typing import Callable, Optional

import boto3
from botocore.exceptions import ClientError

from app.core.config import settings
from app.database.session import SessionLocal
from app.models.media import MediaState
from app.services.media_lifecycle import (
    StorageReadProvider,
    process_s3_event,
    record_upload_intent,
)
from app.services.media_reconciliation import reconcile_stale_media

logger = logging.getLogger("hyperlocal.media.lambda")


def _category_for_prefix(key: str) -> Optional[str]:
    """Derive MEDIA_CATEGORIES key from the server-minted key prefix."""
    for name, cat in _MEDIA_CATEGORIES().items():
        if key.startswith(f"{cat.prefix}/"):
            return name
    return None


def _MEDIA_CATEGORIES():
    from app.services.media_service import MEDIA_CATEGORIES

    return MEDIA_CATEGORIES


class LambdaS3Provider:
    """Sync boto3 adapter implementing StorageReadProvider."""

    def __init__(self, client=None, bucket: Optional[str] = None):
        self.client = client or boto3.client("s3", region_name=settings.S3_REGION)
        self.bucket = bucket or settings.S3_BUCKET_NAME

    def head_object(self, key: str):
        try:
            resp = self.client.head_object(Bucket=self.bucket, Key=key)
        except ClientError as exc:
            if exc.response["Error"]["Code"] == "404":
                return None
            raise
        return {
            "content_type": resp.get("ContentType"),
            "size": resp.get("ContentLength"),
        }

    def read_object_bytes(self, key: str, limit: int = 8) -> bytes:
        resp = self.client.get_object(Bucket=self.bucket, Key=key,
                                      Range=f"bytes=0-{limit - 1}")
        return resp["Body"].read()[:limit]

    def copy_object(self, src_key: str, dst_key: str) -> None:
        self.client.copy_object(Bucket=self.bucket, Key=dst_key,
                                CopySource=f"{self.bucket}/{src_key}")

    def delete_object(self, key: str) -> None:
        self.client.delete_object(Bucket=self.bucket, Key=key)


def _records_from_event(event) -> list[dict]:
    """Normalize both EventBridge and legacy S3-notification payloads to records."""
    if isinstance(event, str):
        event = json.loads(event)
    out: list[dict] = []
    if isinstance(event, dict):
        detail = event.get("detail") or {}
        if detail.get("bucket", {}).get("name"):
            bucket = detail["bucket"]["name"]
            obj = detail.get("object", {})
            out.append({"bucket": bucket, "key": obj.get("key"),
                        "size": obj.get("size")})
        for rec in event.get("Records", []):
            s3 = rec.get("s3", {})
            out.append({"bucket": s3.get("bucket", {}).get("name"),
                        "key": s3.get("object", {}).get("key"),
                        "size": s3.get("object", {}).get("size")})
    return out


def _is_scheduled(event) -> bool:
    if not isinstance(event, dict):
        return False
    if event.get("cron") == "reconcile":
        return True
    dt = event.get("detail-type", "")
    return event.get("source") == "aws.events" and dt == "Scheduled Event"


def lambda_handler(
    event,
    context=None,
    *,
    db_factory: Callable = None,
    provider: Optional[StorageReadProvider] = None,
):
    """Process S3 ObjectCreated events (or a scheduled reconcile cron).

    Defaults construct a real boto3 S3 provider + RDS session; tests inject
    `db_factory` and `provider` to run fully offline on SQLite.
    """
    if provider is None:
        provider = LambdaS3Provider()
    if db_factory is None:
        db_factory = SessionLocal

    db = db_factory()
    result = {"processed": 0, "errors": []}
    try:
        if _is_scheduled(event):
            n = reconcile_stale_media(db, provider, stale_minutes=10)
            return {"reconciled": n, "errors": []}
        for rec in _records_from_event(event):
            key = rec.get("key")
            if not key:
                continue
            try:
                process_s3_event(
                    db, key=key, provider=provider,
                    category=_category_for_prefix(key),
                    size_known=rec.get("size"),
                )
                result["processed"] += 1
            except Exception as exc:  # noqa: BLE001 - isolate per-record failures
                logger.warning("event processing failed for %s: %s", key, exc)
                result["errors"].append({"key": key, "error": str(exc)})
    finally:
        db.close()
    return result
