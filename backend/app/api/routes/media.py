"""Phase 7 — Media / S3 object-storage routes.

Secure upload architecture (no AWS credentials ever reach the client):

    POST   /media/upload-url     authorize → validate → signed upload policy
    POST   /media/direct-upload  dev-only backend-streamed upload (local disk)
    POST   /media/confirm        HEAD object → verify → short-lived read URL
    GET    /media/url            authorized short-lived read URL
    DELETE /media/objects        authorized deletion

All object keys are server-minted (``{prefix}/{scope}/{YYYY}/{MM}/{uuid8}_
{safe-name}.{ext}``) and re-validated on every confirm/read/delete, so a
client can never address another tenant's objects — the scope encoded in the
key is checked against the caller's shop association or user id.
"""

from fastapi import APIRouter, Depends, Query, UploadFile
from sqlalchemy.orm import Session

from app.core.config import settings
from app.core.dependencies import get_current_user
from app.core.exceptions import AppError
from app.core.responses import error_response, success_response
from app.core.upload_security import UploadValidationError
from app.database.session import get_db
from app.models.user import User
from app.schemas.media import MediaAttachRequest, MediaConfirmRequest, MediaUploadURLRequest
from app.services import media_service

router = APIRouter(prefix="/media", tags=["media"])

# Validation, size caps and content-type allow-lists live in
# app/core/upload_security.py + app/services/media_service.py (defense in
# depth: declared-type checks at intent time, magic-byte checks on direct
# uploads, stored-object checks at confirm time).


async def _read_capped(file: UploadFile, cap: int) -> bytes:
    """Read a streamed upload into memory WITHOUT unbounded allocation.

    Reads in 64 KB chunks and stops as soon as the cumulative size exceeds
    ``cap`` bytes (the largest per-category limit). The media service still
    enforces the exact per-category cap + magic bytes; this bound only
    protects the worker process from OOM on multi-GB uploads.
    """
    chunks: list[bytes] = []
    total = 0
    while True:
        chunk = await file.read(1024 * 64)
        if not chunk:
            break
        total += len(chunk)
        if total > cap:
            err = UploadValidationError(
                f"File exceeds the {cap // (1024 * 1024)} MB limit"
            )
            err.reason_code = "FILE_TOO_LARGE"  # type: ignore[attr-defined]
            raise err
        chunks.append(chunk)
    return b"".join(chunks)


def _app_error(exc: AppError):
    return error_response(
        message=exc.message,
        error_code=exc.error_code,
        status_code=exc.status_code,
        data=getattr(exc, "data", None),
    )


@router.post("/upload-url")
async def create_upload_url(
    payload: MediaUploadURLRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Authorize the caller and mint a short-lived signed upload policy.

    Returns ``mode: "post"`` with ``url`` + ``fields`` for a direct-to-S3
    multipart POST (credentials never leave the backend), or ``mode:
    "direct"`` when the storage provider is the local development disk.
    """
    try:
        grant = await media_service.create_upload_intent(
            db,
            current_user,
            category_name=payload.category,
            filename=payload.filename,
            content_type=payload.content_type,
            size_bytes=payload.size_bytes,
            shop_id=payload.shop_id,
        )
    except AppError as exc:
        return _app_error(exc)
    return success_response(data=grant, message="Upload URL created")


@router.post("/direct-upload")
async def direct_upload(
    category: str = Query(..., max_length=32),
    shop_id: int | None = Query(None, ge=1),
    file: UploadFile = None,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Development convenience: backend-streamed upload with full validation
    (extension + magic bytes + size cap). Production uses signed URLs."""
    if file is None:
        return error_response("file is required", error_code="VALIDATION_ERROR", status_code=422)
    # Bound memory before validation: never buffer more than the largest
    # permitted upload (15 MB documents; images are capped lower in the
    # service layer).
    content = await _read_capped(file, settings.MEDIA_MAX_DOCUMENT_BYTES)
    try:
        result = await media_service.direct_upload(
            db,
            current_user,
            category_name=category,
            filename=file.filename or "",
            content=content,
            shop_id=shop_id,
        )
    except UploadValidationError as exc:
        return error_response(
            message=str(exc),
            error_code=getattr(exc, "reason_code", "INVALID_FILE"),
            status_code=422,
        )
    except AppError as exc:
        return _app_error(exc)
    return success_response(data=result, message="Upload complete")


@router.post("/confirm")
async def confirm_upload(
    payload: MediaConfirmRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Verify the object landed (content-type + size re-checked) and return a
    short-lived read URL. Failure recovery: if the object is missing, the
    client simply re-requests an upload URL — nothing partial is stored."""
    try:
        result = await media_service.confirm_upload(db, current_user, payload.key)
    except AppError as exc:
        return _app_error(exc)
    return success_response(data=result, message="Upload confirmed")


@router.get("/url")
async def get_media_url(
    key: str = Query(..., min_length=8, max_length=512),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Authorized read access — presigned GET URL (private objects)."""
    try:
        result = await media_service.get_media_url(db, current_user, key)
    except AppError as exc:
        return _app_error(exc)
    return success_response(data=result)


@router.post("/attach")
async def attach_media(
    payload: MediaAttachRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Attach an uploaded media key to a product image or a shop image field.

    Product attach requires ``product:update`` on the target shop and a
    ``products/{shop_id}/...`` key; shop attach requires ``shop:update`` and a
    ``shops/{shop_id}/...`` key. The object must exist (verified via HEAD).
    """
    if payload.shop_id is None:
        return error_response("shop_id is required", error_code="VALIDATION_ERROR", status_code=422)
    if payload.target_type == "product" and payload.product_master_id is None:
        return error_response(
            "product_master_id is required for product attach",
            error_code="VALIDATION_ERROR",
            status_code=422,
        )
    try:
        if payload.target_type == "product":
            result = await media_service.attach_to_product(
                db,
                current_user,
                shop_id=payload.shop_id,
                product_master_id=payload.product_master_id,
                key=payload.key,
            )
        else:
            result = await media_service.attach_to_shop(
                db,
                current_user,
                shop_id=payload.shop_id,
                key=payload.key,
                field=payload.field,
            )
    except AppError as exc:
        return _app_error(exc)
    db.commit()
    return success_response(data=result, message="Media attached")


@router.delete("/objects")
async def delete_media_object(
    key: str = Query(..., min_length=8, max_length=512),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Authorized deletion — only the object's owner scope (or an admin)."""
    try:
        result = await media_service.delete_media(db, current_user, key)
    except AppError as exc:
        return _app_error(exc)
    return success_response(data=result, message="Object deleted")
