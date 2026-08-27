"""Phase 24 — Shopkeeper inventory intake routes (barcode + Excel import).

Registered under the existing ``/shopkeeper`` prefix alongside the portal
router. Every endpoint is association-checked via ``resolve_shop_access``.
"""

from fastapi import APIRouter, Depends, Query, UploadFile
from sqlalchemy.orm import Session

from app.core.dependencies import get_current_user
from app.core.exceptions import AppError
from app.core.responses import error_response, success_response
from app.database.session import get_db
from app.models.user import User
from app.schemas.inventory_intake import BarcodeSaveRequest
from app.services import barcode_intake_service, excel_import_service, shopkeeper_service

router = APIRouter(prefix="/shopkeeper", tags=["shopkeeper-inventory-intake"])

# Phase 30 — barcode input hardening: scannable retail barcodes are digits
# (EAN-8/UPC-A/EAN-13/GTIN-14); anything else is rejected before it can hit
# the catalog query layer.
MAX_BARCODE_LENGTH = 32


def _validate_barcode_input(barcode: str) -> str:
    normalized = str(barcode or "").strip().replace(" ", "").replace("-", "")
    if not normalized or len(normalized) > MAX_BARCODE_LENGTH:
        raise AppError("Invalid barcode", status_code=400, error_code="INVALID_BARCODE")
    if not normalized.isdigit():
        raise AppError(
            "Barcode must contain digits only",
            status_code=400,
            error_code="INVALID_BARCODE_FORMAT",
        )
    return normalized


def _app_error(exc: AppError):
    return error_response(
        message=exc.message,
        error_code=exc.error_code,
        status_code=exc.status_code,
        data=getattr(exc, "data", None),
    )


def _resolve(shop_id: int, current_user: User, db: Session):
    return shopkeeper_service.resolve_shop_access(db, current_user, shop_id)


# ── Part A — Barcode scan flow ────────────────────────────────────────────


@router.get("/barcodes/{barcode}/resolve")
async def resolve_barcode(
    barcode: str,
    shop_id: int | None = Query(None),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Scan Barcode → Identify Identifier → Find Product → Show Product."""
    # Phase 30 — input hardening: reject malformed barcodes before any
    # catalog query; reject oversized inputs before any processing.
    try:
        barcode = _validate_barcode_input(barcode)
    except AppError as exc:
        return _app_error(exc)

    # Phase 30 — anti-attribution guard: only attribute the scan event to a
    # shop the caller is actually associated with (prevents polluting another
    # shop's analytics / scan history by passing arbitrary shop_id values).
    verified_shop_id = None
    if shop_id is not None:
        try:
            access = _resolve(shop_id, current_user, db)
            verified_shop_id = access.shop.id
        except AppError:
            verified_shop_id = None

    try:
        result = barcode_intake_service.resolve_barcode(db, barcode)
    except AppError as exc:
        return _app_error(exc)

    # Record the scan event (matched or not).
    matched_id = result["matches"][0]["product_master_id"] if result["matches"] else None
    try:
        barcode_intake_service.record_scan_event(
            db,
            barcode,
            is_match_found=bool(result["matches"]),
            product_master_id=matched_id,
            shop_id=verified_shop_id,
            user_id=current_user.id,
        )
        db.commit()
    except Exception:  # noqa: BLE001 — analytics must never break lookups
        db.rollback()

    if result["status"] == "FOUND":
        return success_response(data=result, message="Barcode resolved")
    if result["status"] == "MULTIPLE_MATCHES":
        return error_response(
            message=result["message"],
            error_code=result["error_code"],
            status_code=300,  # Multiple Choices — caller must disambiguate
            data={"barcode": result["barcode"], "matches": result["matches"]},
        )
    return error_response(
        message=result["message"],
        error_code=result["error_code"],
        status_code=404,
        data={"barcode": result["barcode"], "matches": []},
    )


@router.post("/shops/{shop_id}/products/from-barcode")
async def save_product_from_barcode(
    shop_id: int,
    payload: BarcodeSaveRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Confirm Shop Product → Price → Availability/Quantity → Save → Publish."""
    try:
        access = _resolve(shop_id, current_user, db)
        result = barcode_intake_service.save_from_scan(
            access, db, current_user, payload.model_dump(exclude_none=False)
        )
    except AppError as exc:
        db.rollback()
        return _app_error(exc)
    except Exception:  # noqa: BLE001 — infra/network failure mid-save
        db.rollback()
        return error_response(
            message="Could not save the scanned product. Please retry.",
            error_code="BARCODE_SAVE_FAILED",
            status_code=503,
        )
    db.commit()
    return success_response(data=result, message="Product saved from barcode scan", status_code=201)


# ── Part B — Excel import flow ────────────────────────────────────────────


@router.post("/shops/{shop_id}/inventory-imports")
async def upload_inventory_import(
    shop_id: int,
    file: UploadFile,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Upload → Validate File → Parse → Validate Rows → Preview."""
    content = await file.read()
    try:
        access = _resolve(shop_id, current_user, db)
        result = excel_import_service.create_import(
            access, db, current_user, file.filename or "", content
        )
    except AppError as exc:
        db.rollback()
        return _app_error(exc)
    db.commit()
    message = (
        "Duplicate upload — returning existing import job"
        if result.get("idempotent_replay")
        else "Import validated — preview ready for confirmation"
    )
    return success_response(data=result, message=message, status_code=201)


@router.get("/shops/{shop_id}/inventory-imports")
async def list_inventory_imports(
    shop_id: int,
    limit: int = Query(20, ge=1, le=100),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """List this shop's import jobs (newest first)."""
    from app.models.inventory_import import InventoryImportJob

    try:
        access = _resolve(shop_id, current_user, db)
    except AppError as exc:
        return _app_error(exc)

    jobs = (
        db.query(InventoryImportJob)
        .filter(InventoryImportJob.shop_id == access.shop.id)
        .all()
    )
    ordered = sorted(jobs, key=lambda j: j.id, reverse=True)[:limit]
    items = [
        {
            "id": job.id,
            "filename": job.filename,
            "status": getattr(job.status, "value", str(job.status)),
            "total_rows": int(job.total_rows or 0),
            "valid_rows": int(job.valid_rows or 0),
            "error_rows": int(job.error_rows or 0),
        }
        for job in ordered
    ]
    return success_response(data={"items": items, "count": len(items)})


@router.get("/inventory-imports/{job_id}")
async def get_inventory_import(
    job_id: int,
    shop_id: int = Query(...),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Preview / detail a staged or processed import job."""
    try:
        access = _resolve(shop_id, current_user, db)
        result = excel_import_service.get_import_preview(access, db, job_id)
    except AppError as exc:
        return _app_error(exc)
    return success_response(data=result)


@router.post("/inventory-imports/{job_id}/confirm")
async def confirm_inventory_import(
    job_id: int,
    shop_id: int = Query(...),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Confirm → Process → Update Inventory (large imports run in background)."""
    try:
        access = _resolve(shop_id, current_user, db)
        result = excel_import_service.confirm_import(access, db, current_user, job_id)
    except AppError as exc:
        db.rollback()
        return _app_error(exc)
    db.commit()
    queued = bool(result.pop("queued", False))
    return success_response(
        data=result,
        message="Import queued for background processing" if queued else "Import processed",
    )


@router.post("/inventory-imports/{job_id}/retry")
async def retry_inventory_import(
    job_id: int,
    shop_id: int = Query(...),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Retry rows that failed during processing."""
    try:
        access = _resolve(shop_id, current_user, db)
        result = excel_import_service.retry_failed(access, db, current_user, job_id)
    except AppError as exc:
        db.rollback()
        return _app_error(exc)
    db.commit()
    result.pop("queued", None)
    return success_response(data=result, message="Retry complete")


@router.get("/inventory-imports/{job_id}/report")
async def inventory_import_report(
    job_id: int,
    shop_id: int = Query(...),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Generate Import Report — totals + row-level outcomes."""
    try:
        access = _resolve(shop_id, current_user, db)
        result = excel_import_service.build_report(access, db, job_id)
    except AppError as exc:
        return _app_error(exc)
    return success_response(data=result)
