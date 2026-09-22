"""Phase 2/3 - Read-only Media state endpoints.

`GET /media/status` lets the Flutter shopkeeper UI observe the lifecycle state
of a server-minted object key (PENDING/UPLOADED/PROCESSING/READY/FAILED) plus,
on failure, the error diagnostics and the quarantine key for forensic review.
"""
from __future__ import annotations

from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session

from app.core.dependencies import get_current_user  # reuse the existing auth deps
from app.core.exceptions import NotFoundError
from app.core.responses import success_response
from app.database.session import get_db
from app.models.user import User
from app.services.media_lifecycle import get_media_status
# Reconciliation is driven by the scheduled Lambda (backend/lambda_function.py)
# and exercised directly via reconcile_stale_media in tests -- the FastAPI media
# surface stays auth-only reads, avoiding an async-provider adapter.

router = APIRouter(prefix="/media", tags=["media"])


@router.get("/status")
async def media_status(
    key: str = Query(..., min_length=8, max_length=512),
    db: Session = Depends(get_db),
    _current_user: User = Depends(get_current_user),
):
    """Return the lifecycle state of a media key (auth required)."""
    media = get_media_status(db, key)
    if media is None:
        raise NotFoundError("Media not found")
    return success_response(
        data={
            "key": media.key,
            "state": media.state.value,
            "content_type": media.content_type,
            "size_bytes": media.size_bytes,
            "error_code": media.error_code,
            "error_message": media.error_message,
            "quarantine_key": media.quarantine_key,
            "processed_at": media.processed_at.isoformat() if media.processed_at else None,
            "created_at": media.created_at.isoformat() if getattr(media, "created_at", None) else None,
        }
    )



# Reconciliation is cron-driven via the Phase 3 Lambda (backend/lambda_function.py),
# tested through reconcile_stale_media directly.
