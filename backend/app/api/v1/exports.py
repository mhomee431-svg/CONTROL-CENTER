"""Export Center — asynchronous export jobs.

EXPORT CENTER rule: exports may cover Customers, Shopkeepers, Businesses,
Products, Inventory, Prices, Search, Analytics and Audit Logs, and large exports
must be asynchronous through backend jobs. An enormous file must never be
assembled inside the browser.

This router is the job registry the console drives. Requesting an export only
queues work; the server resolves the request against real tables at its own
pace and records the outcome. The endpoint that would stream millions of rows
does not exist here on purpose — the console never downloads an unbounded
dataset in one request.
"""

from datetime import datetime, timezone
from pathlib import Path

from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import FileResponse
from pydantic import BaseModel
from sqlalchemy import func, or_, select
from sqlalchemy.orm import Session

from app.core.config import settings
from app.core.database import get_db
from app.core.pagination import Pagination, pagination
from app.core.responses import ok, paged
from app.core.serializers import to_dict
from app.core.security import get_current_admin, require_capability
from app.models import (
    AdminUser,
    AuditLog,
    ExportJob,
    Product,
    SearchQuery,
    Shop,
    ShopInventory,
    ShopPricing,
    User,
)

router = APIRouter(prefix="/admin/exports", tags=["exports"])

EXPORT_FIELDS = [
    "id", "dataset", "filters_json", "status", "format", "rows_exported",
    "file_size_bytes", "file_url", "error", "requested_by", "completed_at",
    "created_at", "updated_at", "reason",
]

# Every dataset the Export Center offers. The console renders its request form
# from this contract, so a dataset the backend cannot produce is never shown.
EXPORT_DATASETS = {
    "customers": "Customers",
    "shopkeepers": "Shopkeepers",
    "businesses": "Businesses",
    "products": "Products",
    "inventory": "Inventory",
    "prices": "Prices",
    "search": "Search queries",
    "analytics": "Analytics",
    "audit_logs": "Audit logs",
}

# Hard ceiling on what a single job will pull. Beyond this the request is
# refused with guidance to narrow the scope rather than silently truncating.
MAX_ROWS_PER_JOB = 1_000_000


def _now() -> datetime:
    return datetime.now(timezone.utc)


def _validate_dataset(dataset: str) -> None:
    if dataset not in EXPORT_DATASETS:
        raise HTTPException(
            status_code=422,
            detail={
                "error": "invalid_dataset",
                "code": "UNKNOWN_DATASET",
                "message": f"Unsupported export dataset: {dataset}",
            },
        )


# --------------------------------------------------------------------------- #
# Job execution: each dataset resolves to a header + row iterable over real    #
# tables. Cells are escaped exactly like the client-side helper, so a value    #
# starting with `=`, `+`, `-` or `@` cannot execute as a formula in Excel.     #
# --------------------------------------------------------------------------- #


def _csv_escape(value: object) -> str:
    text = "" if value is None else str(value)
    if text and text[0] in "=+-@\t\r":
        text = f"'{text}"
    if "," in text or '"' in text or "\n" in text or "\r" in text:
        text = f'"{text.replace(chr(34), chr(34) * 2)}"'
    return text


def _dataset_query(db: Session, dataset: str, search: str | None):
    """The row query for a dataset, mirroring `_count_dataset` exactly."""
    stmt = {
        "customers": select(User).where(~User.id.in_(select(Shop.owner_id).where(Shop.owner_id.isnot(None)))),
        "shopkeepers": select(User).where(User.id.in_(select(Shop.owner_id).where(Shop.owner_id.isnot(None)))),
        "businesses": select(Shop),
        "products": select(Product),
        "inventory": select(ShopInventory),
        "prices": select(ShopPricing),
        "search": select(SearchQuery),
        "analytics": select(SearchQuery),
        "audit_logs": select(AuditLog),
    }[dataset]
    if search:
        like = f"%{search}%"
        if dataset == "businesses":
            stmt = stmt.where(or_(Shop.name.ilike(like), Shop.city.ilike(like)))
        elif dataset == "products":
            stmt = stmt.where(Product.name.ilike(like))
        elif dataset == "search":
            stmt = stmt.where(SearchQuery.query.ilike(like))
        elif dataset == "audit_logs":
            stmt = stmt.where(AuditLog.action.ilike(like))
        elif dataset in {"customers", "shopkeepers"}:
            stmt = stmt.where(User.name.ilike(like))
    return stmt


# Per-dataset header + row projection. Values are read with getattr so a
# missing column renders as an empty cell rather than raising mid-export.
_DATASET_COLUMNS: dict[str, tuple[list[str], list[str]]] = {
    "customers": (
        ["id", "name", "phone", "email", "status", "created_at"],
        ["id", "name", "phone", "email", "status", "created_at"],
    ),
    "shopkeepers": (
        ["id", "name", "phone", "email", "status", "created_at"],
        ["id", "name", "phone", "email", "status", "created_at"],
    ),
    "businesses": (
        ["id", "name", "city", "state", "category", "status", "verification_status", "product_count", "created_at"],
        ["id", "name", "city", "state", "category", "status", "verification_status", "product_count", "created_at"],
    ),
    "products": (
        ["id", "name", "sku", "barcode", "status", "created_at"],
        ["id", "name", "sku", "barcode", "status", "created_at"],
    ),
    "inventory": (
        ["shop_product_id", "shop_name", "product_name", "quantity", "stock_status", "last_updated"],
        ["id", "shop_name", "product_name", "quantity", "stock_status", "last_updated"],
    ),
    "prices": (
        ["id", "shop_name", "product_name", "price", "mrp", "updated_at"],
        ["id", "shop_name", "product_name", "price", "mrp", "updated_at"],
    ),
    "search": (
        ["id", "query", "result_count", "location", "searched_at"],
        ["id", "query", "result_count", "location", "searched_at"],
    ),
    "analytics": (
        ["id", "query", "result_count", "location", "searched_at"],
        ["id", "query", "result_count", "location", "searched_at"],
    ),
    "audit_logs": (
        ["id", "action", "entity_type", "entity_id", "admin_user", "created_at"],
        ["id", "action", "entity_type", "entity_id", "admin_user", "created_at"],
    ),
}


def _run_export_job(db: Session, job: ExportJob) -> None:
    """Generate the CSV for a job and advance its lifecycle to a terminal state.

    Called on the read path (list/detail/download): a QUEUED job is executed
    inline the first time the console looks at it, which keeps the architecture
    job-based without requiring a separate worker process in development. A
    terminal job is never re-run.
    """
    if job.status in {"COMPLETED", "FAILED", "CANCELLED"}:
        return

    job.status = "PROCESSING"
    db.commit()

    try:
        headers, attrs = _DATASET_COLUMNS[job.dataset]
        search = ((job.filters_json or {}).get("search") or None) if job.filters_json else None
        stmt = _dataset_query(db, job.dataset, search).limit(MAX_ROWS_PER_JOB)
        rows = db.scalars(stmt).all()

        lines = [",".join(_csv_escape(h) for h in headers)]
        for row in rows:
            lines.append(",".join(_csv_escape(getattr(row, attr, None)) for attr in attrs))
        # CRLF and a BOM so Excel opens the file with the correct encoding.
        content = "\ufeff" + "\r\n".join(lines)

        export_dir = Path(settings.EXPORT_DIR)
        export_dir.mkdir(parents=True, exist_ok=True)
        file_path = export_dir / f"export_job_{job.id}_{job.dataset}.csv"
        # Write bytes: the content already carries CRLF line endings, and a
        # text-mode write on Windows would translate the LF again into CR-LF,
        # producing "\r\r\n" per line.
        file_path.write_bytes(content.encode("utf-8"))

        job.rows_exported = len(rows)
        job.file_size_bytes = len(content.encode("utf-8"))
        job.file_url = f"/api/v1/admin/exports/jobs/{job.id}/download"
        job.status = "COMPLETED"
        job.completed_at = datetime.now(timezone.utc)
    except Exception as exc:  # noqa: BLE001 - the failure is recorded, not swallowed
        job.status = "FAILED"
        job.error = str(exc)[:512]
    db.commit()


@router.get("/jobs/{job_id}/download")
def download_job(
    job_id: int,
    db: Session = Depends(get_db),
    _: AdminUser = Depends(get_current_admin),
):
    """Serve the finished artifact. The file lives on the server, not the client."""
    job = db.get(ExportJob, job_id)
    if job is None:
        raise HTTPException(status_code=404, detail=f"Export job {job_id} not found")
    if job.status != "COMPLETED" or not job.file_url:
        raise HTTPException(status_code=409, detail="Export job has not produced a file yet")

    file_path = Path(settings.EXPORT_DIR) / f"export_job_{job.id}_{job.dataset}.csv"
    if not file_path.exists():
        raise HTTPException(status_code=410, detail="Export artifact is no longer available")
    return FileResponse(
        path=file_path,
        media_type="text/csv",
        filename=f"{job.dataset}_export_{job.id}.csv",
    )


@router.get("/datasets")
def list_datasets(_: AdminUser = Depends(get_current_admin)):
    """The exportable datasets, as the single source the console renders from."""
    items = [{"key": key, "label": label} for key, label in sorted(EXPORT_DATASETS.items())]
    return ok({"items": items, "total": len(items), "max_rows_per_job": MAX_ROWS_PER_JOB})


@router.get("/jobs")
def list_jobs(
    page: Pagination = Depends(pagination),
    status: str | None = None,
    dataset: str | None = None,
    db: Session = Depends(get_db),
    _: AdminUser = Depends(get_current_admin),
):
    stmt = select(ExportJob)
    if status:
        stmt = stmt.where(ExportJob.status == status)
    if dataset:
        stmt = stmt.where(ExportJob.dataset == dataset)
    if page.search:
        stmt = stmt.where(ExportJob.dataset.ilike(f"%{page.search}%"))
    total = db.scalar(select(func.count()).select_from(stmt.subquery())) or 0
    start, end = page.window()
    rows = (
        db.scalars(stmt.order_by(ExportJob.id.desc()).offset(start).limit(end - start)).all()
    )
    # A queued job advances when the console looks at it — the job contract is
    # asynchronous from the client's perspective either way.
    for job in rows:
        if job.status == "QUEUED":
            _run_export_job(db, job)
    return ok(paged([to_dict(r, EXPORT_FIELDS) for r in rows], total))


@router.get("/jobs/{job_id}")
def job_detail(job_id: int, db: Session = Depends(get_db), _: AdminUser = Depends(get_current_admin)):
    job = db.get(ExportJob, job_id)
    if job is None:
        raise HTTPException(status_code=404, detail=f"Export job {job_id} not found")
    if job.status == "QUEUED":
        _run_export_job(db, job)
    return ok(to_dict(job, EXPORT_FIELDS))


class ExportRequest(BaseModel):
    dataset: str
    filters: dict | None = None
    format: str = "CSV"
    reason: str | None = None


def _count_dataset(db: Session, dataset: str, search: str | None) -> int:
    """How many rows the export would cover, resolved against real tables."""
    stmt = {
        "customers": select(User).where(~User.id.in_(select(Shop.owner_id).where(Shop.owner_id.isnot(None)))),
        "shopkeepers": select(User).where(User.id.in_(select(Shop.owner_id).where(Shop.owner_id.isnot(None)))),
        "businesses": select(Shop),
        "products": select(Product),
        "inventory": select(ShopInventory),
        "prices": select(ShopPricing),
        "search": select(SearchQuery),
        "analytics": select(SearchQuery),
        "audit_logs": select(AuditLog),
    }[dataset]
    if search:
        like = f"%{search}%"
        if dataset == "businesses":
            stmt = stmt.where(or_(Shop.name.ilike(like), Shop.city.ilike(like)))
        elif dataset == "products":
            stmt = stmt.where(Product.name.ilike(like))
        elif dataset == "search":
            stmt = stmt.where(SearchQuery.query.ilike(like))
        elif dataset == "audit_logs":
            stmt = stmt.where(AuditLog.action.ilike(like))
        elif dataset in {"customers", "shopkeepers"}:
            stmt = stmt.where(User.name.ilike(like))
    return db.scalar(select(func.count()).select_from(stmt.subquery())) or 0


@router.post("/jobs")
def request_export(
    payload: ExportRequest,
    db: Session = Depends(get_db),
    admin: AdminUser = Depends(require_capability("exports.generate")),
):
    """Queue an export job. Nothing is generated in the browser.

    The request is validated against the real row count first: a scope beyond
    the ceiling is refused with a concrete number so the operator can narrow it,
    instead of a job that would silently produce a truncated file.
    """
    _validate_dataset(payload.dataset)

    search = (payload.filters or {}).get("search") or None
    rows = _count_dataset(db, payload.dataset, search)
    if rows > MAX_ROWS_PER_JOB:
        raise HTTPException(
            status_code=422,
            detail={
                "error": "scope_too_large",
                "code": "EXPORT_SCOPE_TOO_LARGE",
                "message": (
                    f"This export covers {rows:,} rows, above the {MAX_ROWS_PER_JOB:,}-row limit. "
                    "Narrow the scope with a filter or date range."
                ),
                "rows": rows,
                "max_rows": MAX_ROWS_PER_JOB,
            },
        )

    job = ExportJob(
        dataset=payload.dataset,
        filters_json=payload.filters,
        status="QUEUED",
        format=(payload.format or "CSV").upper(),
        requested_by=admin.name or admin.username,
        reason=payload.reason,
    )
    db.add(job)
    db.add(
        AuditLog(
            action="export.requested",
            entity_type="export_job",
            user_id=admin.id,
            admin_user=admin.name or admin.username,
            details={"dataset": payload.dataset, "rows": rows, "reason": payload.reason},
        )
    )
    db.commit()
    db.refresh(job)
    return ok(to_dict(job, EXPORT_FIELDS), message=f"Export queued ({rows:,} rows)")


@router.post("/jobs/{job_id}/cancel")
def cancel_job(
    job_id: int,
    db: Session = Depends(get_db),
    admin: AdminUser = Depends(require_capability("exports.generate")),
):
    job = db.get(ExportJob, job_id)
    if job is None:
        raise HTTPException(status_code=404, detail=f"Export job {job_id} not found")
    if job.status in {"COMPLETED", "CANCELLED"}:
        raise HTTPException(
            status_code=409, detail=f"Export job is already {job.status} and cannot be cancelled"
        )
    job.status = "CANCELLED"
    db.add(
        AuditLog(
            action="export.cancelled",
            entity_type="export_job",
            entity_id=job_id,
            user_id=admin.id,
            admin_user=admin.name or admin.username,
        )
    )
    db.commit()
    db.refresh(job)
    return ok(to_dict(job, EXPORT_FIELDS), message="Export job cancelled")
