"""Phase 24 Part B — Excel workbook → canonical shop inventory import.

Implements the full pipeline:

    Upload → Validate File → Parse → Validate Rows → Detect Errors → Preview
    → Confirm → Process → Update Inventory → Generate Import Report

Design rules:

  - Excel values are NEVER trusted blindly: every cell passes through
    normalization + field-level validation before touching the catalog.
  - Row-level errors are persisted (code + field + message) so the
    shopkeeper gets actionable feedback per spreadsheet row.
  - Imports are IDEMPOTENT: rows upsert onto the canonical ShopProduct +
    Inventory pair keyed by (shop, product master, variant); re-running a
    job (or re-uploading the same file) updates rather than duplicates.
  - Large imports are processed by a background Celery job.
"""

from __future__ import annotations

import hashlib
import json
from datetime import datetime, timezone
from typing import Any

from sqlalchemy.orm import Session

from app.core.exceptions import ConflictError, NotFoundError, ValidationError
from app.core.logging import get_logger
from app.models.inventory_import import ImportJobStatus, InventoryImportJob, InventoryImportRow
from app.models.product import (
    BarcodeRelationship,
    IdentifierType,  # noqa: F401 - registers the product_identifiers type enum on Base.metadata
    Inventory,
    InventoryMovement,
    InventorySource,
    ProductIdentifier,
    ProductMaster,
    ProductVariant,
    ShopProduct,
)
from app.services.inventory_service import compute_freshness, derive_stock_status
from app.services import xlsx_lite

logger = get_logger("app.services.excel_import")

MAX_FILE_SIZE_BYTES = 5 * 1024 * 1024   # 5 MB
MAX_ROWS = 10_000
ASYNC_ROW_THRESHOLD = 200               # above this, confirm → background job

# ── Header mapping (flexible, case/space insensitive aliases) ────────────
FIELD_ALIASES: dict[str, set[str]] = {
    "barcode": {"barcode", "bar code", "ean", "upc", "gtin", "barcode no", "barcode number"},
    "product_name": {"product name", "product", "name", "item name", "item"},
    "brand": {"brand", "brand name"},
    "variant": {"variant", "variant name", "pack size", "size"},
    "sku": {"sku", "sku code", "item code", "code"},
    "price": {"price", "selling price", "sale price", "our price"},
    "mrp": {"mrp", "m r p", "max retail price", "maximum retail price", "marked price", "list price"},
    "quantity": {"quantity", "qty", "stock", "stock qty", "stock quantity", "count"},
    "availability": {"availability", "available", "is available", "in stock", "status"},
}

# A row must carry at least one identifier so we can resolve a product.
IDENTIFIER_FIELDS = ("barcode", "sku", "product_name")

_TRUTHY = {"true", "yes", "y", "1", "in stock", "available"}
_FALSY = {"false", "no", "n", "0", "out of stock", "unavailable"}


class ImportError_(Exception):
    """Internal sentinel carrying a row-level error code."""


# ── Normalization helpers ─────────────────────────────────────────────────


def _normalize_header(value: Any) -> str:
    return " ".join(str(value or "").lower().replace("_", " ").replace("-", " ").split())


def map_headers(header_row: list[Any]) -> dict[str, int]:
    """Map spreadsheet columns to canonical field names."""
    mapping: dict[str, int] = {}
    for idx, raw in enumerate(header_row):
        header = _normalize_header(raw)
        if not header:
            continue
        for field, aliases in FIELD_ALIASES.items():
            if header in aliases and field not in mapping:
                mapping[field] = idx
                break
    return mapping


def normalize_barcode_value(raw: Any) -> str:
    cleaned = str(raw or "").strip().replace(" ", "").replace("-", "")
    if cleaned.endswith(".0"):  # Excel numeric cells read as floats
        cleaned = cleaned[:-2]
    return cleaned


def _parse_decimal(raw: Any) -> float | None:
    """Parse a money-ish cell; strips currency marks and thousands separators."""
    if raw is None or str(raw).strip() == "":
        return None
    text = str(raw).strip().replace(",", "").replace("₹", "").replace("$", "").replace(" ", "")
    try:
        return round(float(text), 2)
    except ValueError:
        return None


def _parse_quantity(raw: Any) -> int | None:
    parsed = _parse_decimal(raw)
    if parsed is None:
        return None
    if abs(parsed - round(parsed)) > 1e-9:
        return None  # fractional stock makes no sense
    return int(round(parsed))


def _parse_availability(raw: Any) -> bool | None:
    if raw is None or str(raw).strip() == "":
        return None
    text = str(raw).strip().lower()
    if text in _TRUTHY:
        return True
    if text in _FALSY:
        return False
    return None


def idempotency_key_for(shop_id: int, filename: str, content: bytes) -> str:
    digest = hashlib.sha256(content).hexdigest()
    return hashlib.sha256(f"{shop_id}:{filename}:{digest}".encode()).hexdigest()[:64]


def _normalize_name(value: Any) -> str:
    return " ".join(str(value or "").lower().split())


# ── Row validation (never trust Excel values) ─────────────────────────────


def validate_row(
    db: Session,
    values: dict[str, Any],
    seen_keys: set[tuple],
) -> tuple[dict[str, Any], list[dict[str, str]]]:
    """Validate one normalized row.

    Returns ``(clean_values, errors)`` where each error is
    ``{"field", "code", "message"}``. A row is importable only when
    ``errors`` is empty.
    """
    errors: list[dict[str, str]] = []

    def _err(field: str, code: str, message: str) -> None:
        errors.append({"field": field, "code": code, "message": message})

    # ── Required fields ───────────────────────────────────────────────
    if not any(str(values.get(f) or "").strip() for f in IDENTIFIER_FIELDS):
        _err("product_name", "MISSING_REQUIRED_FIELD",
             "Row needs at least one of: barcode, sku, product name")

    product_name = str(values.get("product_name") or "").strip()
    if values.get("product_name") is not None and not product_name:
        _err("product_name", "MISSING_REQUIRED_FIELD", "Product name cannot be blank")

    # ── Barcode format (GS1 check-digit aware) ────────────────────────
    barcode = normalize_barcode_value(values.get("barcode"))
    if barcode:
        from app.services.barcode_intake_service import validate_barcode_format

        ok, reason = validate_barcode_format(barcode)
        if not ok:
            _err("barcode", "INVALID_BARCODE", f"Barcode format invalid ({reason})")

    # ── Numeric fields ────────────────────────────────────────────────
    price_raw = values.get("price")
    price = _parse_decimal(price_raw)
    if price is None and str(price_raw or "").strip() != "":
        _err("price", "INVALID_NUMBER", f"'{price_raw}' is not a valid number")
    elif price is None:
        _err("price", "MISSING_REQUIRED_FIELD", "Price is required")
    elif price < 0:
        _err("price", "NEGATIVE_PRICE", "Price cannot be negative")

    mrp_raw = values.get("mrp")
    mrp = _parse_decimal(mrp_raw)
    if mrp is None and str(mrp_raw or "").strip() != "":
        _err("mrp", "INVALID_NUMBER", f"'{mrp_raw}' is not a valid number")
    elif mrp is not None and mrp < 0:
        _err("mrp", "NEGATIVE_PRICE", "MRP cannot be negative")

    if price is not None and mrp is not None and mrp < price:
        _err("mrp", "PRICE_EXCEEDS_MRP", "Selling price cannot exceed MRP")

    qty_raw = values.get("quantity")
    quantity = _parse_quantity(qty_raw)
    if quantity is None and str(qty_raw or "").strip() != "":
        _err("quantity", "INVALID_QUANTITY", f"'{qty_raw}' is not a valid whole number")
    elif quantity is None:
        quantity = 0  # column absent/blank defaults to zero
    elif quantity < 0:
        _err("quantity", "NEGATIVE_QUANTITY", "Quantity cannot be negative")

    availability_raw = values.get("availability")
    availability = _parse_availability(availability_raw)
    if availability is None and str(availability_raw or "").strip() != "":
        _err("availability", "INVALID_AVAILABILITY",
             f"'{availability_raw}' is not a recognised availability value")

    clean: dict[str, Any] = {
        "barcode": barcode,
        "product_name": product_name,
        "brand": str(values.get("brand") or "").strip() or None,
        "variant": str(values.get("variant") or "").strip() or None,
        "sku": str(values.get("sku") or "").strip() or None,
        "price": price,
        "mrp": mrp,
        "quantity": max(quantity, 0),
        "is_available": availability,
    }

    # ── Duplicate rows within the same file ───────────────────────────
    dup_key = (
        clean["barcode"] or None,
        _normalize_name(clean["sku"]) or None,
        _normalize_name(clean["product_name"]) or None,
        _normalize_name(clean["variant"]) or None,
    )
    if any(dup_key):
        if dup_key in seen_keys:
            errors.append({
                "field": "row", "code": "DUPLICATE_ROW",
                "message": "Duplicate of an earlier row in this file (same barcode/sku/product+variant)",
            })
        else:
            seen_keys.add(dup_key)

    if errors:
        return clean, errors

    # ── Catalog resolution (unknown products / variants) ──────────────
    master, variant, resolve_err = _resolve_catalog_entry(db, clean)
    if resolve_err is not None:
        field, code, message = resolve_err
        _err(field, code, message)
        return clean, errors

    clean["product_master_id"] = master.id if master else None
    clean["variant_id"] = variant.id if variant else None
    return clean, errors


def _resolve_catalog_entry(
    db: Session, clean: dict[str, Any]
) -> tuple[ProductMaster | None, ProductVariant | None, tuple | None]:
    """Resolve the row to a catalog master (+ optional variant).

    Returns ``(master, variant, error_tuple)``. Unknown products/variants are
    row-level errors — the import never invents catalog entries.
    """
    barcode = clean.get("barcode")
    master: ProductMaster | None = None

    if barcode:
        identifier = (
            db.query(ProductIdentifier)
            .filter(
                ProductIdentifier.identifier_value == barcode,
                ProductIdentifier.is_active == True,  # noqa: E712
            )
            .first()
        )
        if identifier is not None:
            master = (
                db.query(ProductMaster)
                .filter(
                    ProductMaster.id == identifier.product_master_id,
                    ProductMaster.is_deleted == False,  # noqa: E712
                )
                .first()
            )
        if master is None:
            rel = (
                db.query(BarcodeRelationship)
                .filter(
                    BarcodeRelationship.barcode == barcode,
                    BarcodeRelationship.is_active == True,  # noqa: E712
                )
                .first()
            )
            if rel is not None:
                master = (
                    db.query(ProductMaster)
                    .filter(
                        ProductMaster.id == rel.product_master_id,
                        ProductMaster.is_deleted == False,  # noqa: E712
                    )
                    .first()
                )
        if master is None:
            return None, None, (
                "barcode", "UNKNOWN_PRODUCT",
                "No catalog product registered for this barcode",
            )
    elif clean.get("sku"):
        variant_match = (
            db.query(ProductVariant)
            .filter(ProductVariant.sku == str(clean["sku"]).strip())
            .first()
        )
        if variant_match is not None:
            master = (
                db.query(ProductMaster)
                .filter(
                    ProductMaster.id == variant_match.product_master_id,
                    ProductMaster.is_deleted == False,  # noqa: E712
                )
                .first()
            )
        if master is None:
            return None, None, ("sku", "UNKNOWN_PRODUCT", "No catalog product with this SKU")
    elif clean.get("product_name"):
        from app.services.shopkeeper_service import find_matching_master

        master = find_matching_master(db, str(clean["product_name"]))
        if master is None:
            return None, None, (
                "product_name", "UNKNOWN_PRODUCT",
                "No catalog product matches this name",
            )

    # Variant validation against the resolved master.
    variant: ProductVariant | None = None
    variant_label = clean.get("variant")
    if variant_label and master is not None:
        wanted = _normalize_name(variant_label)
        variant = next(
            (v for v in (master.variants or []) if _normalize_name(v.name) == wanted),
            None,
        )
        if variant is None:
            return master, None, (
                "variant", "UNKNOWN_VARIANT",
                f"'{variant_label}' is not a variant of '{master.name}'",
            )
    if not variant_label and clean.get("variant_id") and master is not None:
        candidate_id = int(clean["variant_id"])
        variant = next((v for v in (master.variants or []) if v.id == candidate_id), None)

    return master, variant, None


# ── Upload → Validate File → Parse → Validate Rows ────────────────────────


# ── Download Sample (Import Center) ────────────────────────────────────────

SAMPLE_FILE_NAME = "inventory-import-sample.xlsx"

# The canonical column order — exactly the names `map_headers` resolves, so a
# shopkeeper who fills this file in never fights the validator.
_SAMPLE_HEADER = [
    "Barcode", "Product Name", "Brand", "Variant",
    "SKU", "Price", "MRP", "Quantity", "Availability",
]

# Three example rows, each individually format-valid (`validate_row` passes
# them once the catalog resolves):
#   1. every column filled
#   2. minimal — no barcode, identified by SKU instead
#   3. an out-of-stock row (quantity 0 / availability "no")
# Barcodes carry correct GS1 check digits — a bad one would teach the wrong
# format. Unfilled catalog references are expected: the import never invents
# catalog entries, so rows that name unknown products are reported, not guessed.
_SAMPLE_ROWS = [
    ["8901234567890", "Aashirvaad Salt 1kg", "Aashirvaad", "1 kg",
     "AAS-SALT-1KG", 28.5, 32, 24, "yes"],
    ["", "Farm Fresh Milk 500ml", "", "500 ml",
     "FF-MILK-500", 26, "", 12, "yes"],
    ["8901234567883", "India Gate Basmati 5kg", "India Gate", "5 kg",
     "IG-RICE-5KG", 480, 540, 0, "no"],
]


def build_sample_workbook() -> bytes:
    """Build the Import Center's downloadable sample workbook.

    Written by the same `xlsx_lite` writer the parser reads, so the two can
    never drift apart.
    """
    return xlsx_lite.write_workbook([_SAMPLE_HEADER] + _SAMPLE_ROWS)



def _serialize_job(job: InventoryImportJob) -> dict[str, Any]:
    status = getattr(job.status, "value", str(job.status))
    return {
        "id": job.id,
        "shop_id": job.shop_id,
        "filename": job.filename,
        "status": status,
        "total_rows": int(job.total_rows or 0),
        "valid_rows": int(job.valid_rows or 0),
        "error_rows": int(job.error_rows or 0),
        "processed_rows": int(job.processed_rows or 0),
        "failed_rows": int(job.failed_rows or 0),
        "error_message": job.error_message,
        # created_at (TimestampMixin) is the upload instant. It is always set,
        # unlike started_at which stays null until row processing begins — the
        # Import history list needs a date for unconfirmed uploads too.
        "created_at": (
            job.created_at.isoformat() if job.created_at else None
        ),
        "started_at": job.started_at.isoformat() if job.started_at else None,
        "completed_at": job.completed_at.isoformat() if job.completed_at else None,
    }


def create_import(
    access, db: Session, user, filename: str, content: bytes
) -> dict[str, Any]:
    """Upload + validate an Excel inventory file.

    Performs file-level validation (extension/size/parse), maps headers,
    validates every data row and persists the job with row-level outcomes.
    Returns a preview payload; nothing has touched inventory yet.
    """
    access.require("inventory", "update")

    # Idempotency: same shop uploading a byte-identical file replays the
    # original job instead of creating duplicate work.
    key = idempotency_key_for(access.shop.id, filename or "", content or b"")
    existing = (
        db.query(InventoryImportJob)
        .filter(
            InventoryImportJob.shop_id == access.shop.id,
            InventoryImportJob.idempotency_key == key,
        )
        .first()
    )
    if existing is not None and getattr(existing, "status", None) != ImportJobStatus.FAILED:
        result = _serialize_job(existing)
        result["idempotent_replay"] = True
        logger.info("Idempotent import replay: job=%s shop=%s", existing.id, access.shop.id)
        return result

    # ── File-level validation ──────────────────────────────────────────
    from app.core.upload_security import XLSX_MAGIC, UploadValidationError, validate_upload

    try:
        safe_name = validate_upload(
            filename,
            content,
            allowed_extensions=(xlsx_lite.SUPPORTED_EXTENSION,),
            max_bytes=MAX_FILE_SIZE_BYTES,
            expected_magic=XLSX_MAGIC,
        )
    except UploadValidationError as exc:
        raise ValidationError(
            str(exc),
            data={"reason_code": getattr(exc, "reason_code", "UNSUPPORTED_FILE")},
        ) from exc

    try:
        grid = xlsx_lite.read_workbook(content)
    except xlsx_lite.UnsupportedFileError as exc:
        raise ValidationError(str(exc), data={"reason_code": "UNSUPPORTED_FILE"}) from exc

    grid = [row for row in grid if any(str(c or "").strip() for c in row)]
    if len(grid) < 1:
        raise ValidationError("File has no header row", data={"reason_code": "EMPTY_FILE"})
    if len(grid) < 2:
        raise ValidationError("File has no data rows", data={"reason_code": "EMPTY_FILE"})

    header_map = map_headers(grid[0])
    if not any(field in header_map for field in IDENTIFIER_FIELDS):
        raise ValidationError(
            "Missing required columns — need at least one of Barcode / SKU / Product Name",
            data={"reason_code": "MISSING_REQUIRED_COLUMN"},
        )

    data_rows = grid[1:]
    if len(data_rows) > MAX_ROWS:
        raise ValidationError(
            f"File exceeds the maximum of {MAX_ROWS} data rows",
            data={"reason_code": "TOO_MANY_ROWS"},
        )

    def _cell(row: list[Any], field: str) -> Any:
        idx = header_map.get(field)
        return row[idx] if idx is not None and idx < len(row) else None

    # ── Row-level validation ───────────────────────────────────────────
    job = InventoryImportJob(
        shop_id=access.shop.id,
        uploaded_by=user.id,
        filename=safe_name[:255],
        file_size_bytes=len(content),
        idempotency_key=key,
        status=ImportJobStatus.VALIDATING,
        total_rows=len(data_rows),
    )
    db.add(job)
    db.flush()

    seen_keys: set[tuple] = set()
    valid_count = 0
    error_count = 0
    rows: list[InventoryImportRow] = []

    for offset, raw_row in enumerate(data_rows):
        values = {field: _cell(raw_row, field) for field in FIELD_ALIASES}
        clean, errors = validate_row(db, values, seen_keys)

        primary = errors[0] if errors else None
        status = "ERROR" if errors else "VALID"
        valid_count += 0 if errors else 1
        error_count += 1 if errors else 0

        rows.append(
            InventoryImportRow(
                job_id=job.id,
                row_number=offset + 1,
                status=status,
                raw_data=json.dumps(values, default=str),
                normalized_data=json.dumps(clean, default=str),
                error_code=primary["code"] if primary else None,
                error_field=primary["field"] if primary else None,
                error_message=(
                    "; ".join(f"{e['field']}: {e['message']}" for e in errors)
                    if errors
                    else None
                ),
                product_master_id=clean.get("product_master_id"),
                variant_id=clean.get("variant_id"),
            )
        )

    db.add_all(rows)
    job.valid_rows = valid_count
    job.error_rows = error_count
    job.status = ImportJobStatus.AWAITING_CONFIRMATION
    db.flush()

    logger.info(
        "Excel import staged: shop=%s job=%s total=%s valid=%s errors=%s",
        access.shop.id, job.id, job.total_rows, valid_count, error_count,
    )
    return {
        **_serialize_job(job),
        "column_mapping": dict(header_map),
        "preview": [_preview_row(r) for r in rows],
        "idempotent_replay": False,
    }


def _preview_row(row: InventoryImportRow) -> dict[str, Any]:
    clean = json.loads(row.normalized_data) if row.normalized_data else {}
    return {
        "row_number": row.row_number,
        "status": row.status,
        "barcode": clean.get("barcode"),
        "product_name": clean.get("product_name"),
        "brand": clean.get("brand"),
        "variant": clean.get("variant"),
        "sku": clean.get("sku"),
        "price": clean.get("price"),
        "mrp": clean.get("mrp"),
        "quantity": clean.get("quantity"),
        "availability": clean.get("is_available"),
        "product_master_id": clean.get("product_master_id"),
        "variant_id": clean.get("variant_id"),
        "error_code": row.error_code,
        "error_field": row.error_field,
        "error_message": row.error_message,
    }


def get_import_preview(access, db: Session, job_id: int) -> dict[str, Any]:
    """Preview a staged import job with its full row-level report."""
    access.require("inventory", "read")
    job = _get_scoped_job(access, db, job_id)
    rows = (
        db.query(InventoryImportRow)
        .filter(InventoryImportRow.job_id == job.id)
        .all()
    )
    ordered = sorted(rows, key=lambda r: r.row_number)
    return {**_serialize_job(job), "rows": [_preview_row(r) for r in ordered]}


def _get_scoped_job(access, db: Session, job_id: int) -> InventoryImportJob:
    job = db.query(InventoryImportJob).filter(InventoryImportJob.id == int(job_id)).first()
    if job is None:
        raise NotFoundError("Import job not found")
    if job.shop_id != access.shop.id:
        raise NotFoundError("Import job not found")  # cross-shop access is hidden
    return job


# ── Confirm → Process → Update Inventory ─────────────────────────────────


def _enqueue_processing(job_id: int) -> None:
    """Hand a large import to the background worker.

    Published with a hard time budget (see ``publish_task_nonblocking``): a
    degraded broker must not stall the confirm request. The job row already
    exists, so an abandoned publish can be requeued.
    """
    from app.core.celery_app import publish_task_nonblocking
    from app.services.tasks import process_inventory_import

    publish_task_nonblocking(
        lambda: process_inventory_import.delay(int(job_id)),
        label=f"process_inventory_import({job_id})",
    )


def confirm_import(
    access, db: Session, user, job_id: int
) -> dict[str, Any]:
    """Shopkeeper confirms the preview → apply valid rows to inventory.

    Large imports (> ``ASYNC_ROW_THRESHOLD`` valid rows) are queued for
    background processing instead.
    """
    access.require("inventory", "update")
    job = _get_scoped_job(access, db, job_id)

    status = getattr(job, "status", None)
    if status not in (ImportJobStatus.AWAITING_CONFIRMATION, ImportJobStatus.VALIDATING):
        raise ConflictError(f"Import job is not awaiting confirmation (status: {status})")

    rows = (
        db.query(InventoryImportRow)
        .filter(InventoryImportRow.job_id == job.id)
        .all()
    )
    valid_count = sum(1 for r in rows if r.status == "VALID")
    if valid_count == 0:
        raise ValidationError("No valid rows to import — fix the reported errors first")

    if valid_count > ASYNC_ROW_THRESHOLD:
        job.status = ImportJobStatus.QUEUED
        db.flush()
        _enqueue_processing(job.id)
        logger.info("Large import queued: job=%s valid=%s", job.id, valid_count)
        return {
            **_serialize_job(job),
            "queued": True,
            "message": f"Large import ({valid_count} rows) queued for background processing",
        }

    job.status = ImportJobStatus.PROCESSING
    job.started_at = datetime.now(timezone.utc)
    db.flush()
    summary = process_import_job(db, job.id, user_id=user.id)
    return {**summary, "queued": False}


# ── Processing engine (idempotent upserts onto canonical inventory) ──────


def process_import_job(
    db: Session,
    job_id: int,
    user_id: int | None = None,
    include_failed: bool = False,
) -> dict[str, Any]:
    """Apply the import job's valid rows to the canonical inventory system.

    Idempotent by construction:
      - rows already ``PROCESSED`` are skipped on re-runs;
      - each row upserts onto (shop, product master, variant) — re-applying
        sets absolute price/quantity values rather than adding deltas.

    ``include_failed=True`` retries rows previously marked ERROR.
    """
    # Mapper side effects: guarantees every product table is registered before
    # the upsert below resolves relationships on this session.
    import app.models.product as product_models  # noqa: F401

    job = db.query(InventoryImportJob).filter(InventoryImportJob.id == int(job_id)).first()
    if job is None:
        raise NotFoundError("Import job not found")

    status = getattr(job, "status", None)
    if status == ImportJobStatus.FAILED:
        raise ConflictError("Import job failed at file level and cannot be processed")
    if status == ImportJobStatus.QUEUED and not include_failed:
        # Re-processing is otherwise SAFE (idempotent upserts below).
        raise ConflictError("Import job is queued for background processing")

    rows = (
        db.query(InventoryImportRow)
        .filter(InventoryImportRow.job_id == job.id)
        .all()
    )
    eligible = [
        r for r in sorted(rows, key=lambda r: r.row_number)
        if r.status == "VALID" or r.status == "PENDING"
        or (include_failed and r.status == "ERROR")
    ]

    processed = 0
    failed = 0
    now = datetime.now(timezone.utc)

    for row in eligible:
        try:
            sp = _apply_row(db, job, user_id or job.uploaded_by, row, now)
            row.status = "PROCESSED"
            row.shop_product_id = sp.id
            row.error_code = None
            row.error_message = None
            processed += 1
        except Exception as exc:  # noqa: BLE001 — per-row failure isolation
            failed += 1
            row.status = "ERROR"
            code = getattr(exc, "error_code", None) or "ROW_PROCESSING_FAILED"
            row.error_code = str(code)
            row.error_message = str(getattr(exc, "message", None) or exc)

    remaining_errors = sum(1 for r in rows if r.status == "ERROR")
    job.processed_rows = processed
    job.failed_rows = failed
    # error_rows = rows still outstanding (validation errors never processed,
    # plus processing failures awaiting retry)
    job.error_rows = remaining_errors
    if remaining_errors:
        job.status = ImportJobStatus.PARTIAL
    else:
        job.status = ImportJobStatus.COMPLETED
    job.completed_at = datetime.now(timezone.utc)
    db.flush()

    logger.info(
        "Excel import processed: shop=%s job=%s processed=%s failed=%s",
        job.shop_id, job.id, processed, failed,
    )
    # Import receipt — a completion/partial/failure notice for the shopkeeper
    # who uploaded the file. Side-effect only: never blocks the import result.
    try:
        from app.services import notification_service as notification_service

        notification_service.notify_import_event(
            db,
            shopkeeper_user_id=job.uploaded_by,
            job_id=job.id,
            status=(
                job.status.value
                if hasattr(job.status, "value")
                else str(job.status)
            ),
            filename=job.filename,
            processed_rows=processed,
            failed_rows=failed,
        )
    except Exception:  # noqa: BLE001 — side-effect isolation
        logger.warning("Import notification failed", exc_info=True)
    return {
        **_serialize_job(job),
        "processed_this_run": processed,
        "failed_this_run": failed,
    }


def _apply_row(db: Session, job, user_id, row, now):
    """Upsert one import row onto the canonical ShopProduct + Inventory."""
    import app.models.product as product_models
    from app.models.product import ShopProductStatus

    data = json.loads(row.normalized_data) if row.normalized_data else {}
    master_id = row.product_master_id or data.get("product_master_id")
    if master_id is None:
        raise ValidationError("Row has no resolved catalog product")

    master = (
        db.query(ProductMaster)
        .filter(
            ProductMaster.id == int(master_id),
            ProductMaster.is_deleted == False,  # noqa: E712
        )
        .first()
    )
    if master is None:
        raise NotFoundError(f"Catalog product {master_id} no longer exists")

    variant = None
    variant_id = row.variant_id or data.get("variant_id")
    if variant_id:
        variant = next(
            (v for v in (master.variants or []) if v.id == int(variant_id)), None
        )
        if variant is None:
            raise ValidationError("Resolved variant does not belong to this product")

    price = float(data["price"])
    mrp = float(data["mrp"]) if data.get("mrp") is not None else None
    quantity = max(int(data.get("quantity") or 0), 0)
    is_available = data.get("is_available")
    if is_available is None:
        is_available = quantity > 0
    threshold = 5
    stock_enum = product_models.StockStatus[derive_stock_status(quantity, threshold).value]

    existing_sp = (
        db.query(ShopProduct)
        .filter(
            ShopProduct.shop_id == job.shop_id,
            ShopProduct.product_master_id == master.id,
            ShopProduct.variant_id == (variant.id if variant else None),
            ShopProduct.is_deleted == False,  # noqa: E712
        )
        .first()
    )

    if existing_sp is None:
        # CREATE path — a new listing sourced from EXCEL_UPLOAD.
        sp = ShopProduct(
            shop_id=job.shop_id,
            product_master_id=master.id,
            variant_id=variant.id if variant else None,
            sku=data.get("sku"),
            status=ShopProductStatus.ACTIVE,
            price=price,
            mrp=mrp,
            is_active=True,
            is_available=bool(is_available) and quantity > 0,
            stock_status=stock_enum,
            source=InventorySource.EXCEL_UPLOAD,
            last_inventory_update=now,
            last_price_update=now,
        )
        sp.product_master = master
        if variant is not None:
            sp.variant = variant
        db.add(sp)
        db.flush()

        inv = Inventory(
            shop_product_id=sp.id,
            quantity=quantity,
            reserved_quantity=0,
            available_quantity=quantity,
            is_available=bool(is_available) and quantity > 0,
            stock_status=stock_enum,
            low_stock_threshold=threshold,
            last_updated_by=user_id,
            last_updated_source=InventorySource.EXCEL_UPLOAD,
            last_synced_at=now,
            freshness_status=compute_freshness(now, InventorySource.EXCEL_UPLOAD),
            freshness_checked_at=now,
        )
        db.add(inv)
        db.flush()
        db.add(
            InventoryMovement(
                inventory_id=inv.id,
                quantity_change=quantity,
                quantity_before=0,
                quantity_after=quantity,
                movement_type="INITIAL",
                source=InventorySource.EXCEL_UPLOAD,
                reference_type="EXCEL_UPLOAD",
                reference_id=job.id,
                notes=f"Row {row.row_number} of import #{job.id}",
                created_by=user_id,
            )
        )
        sp.inventory = inv
        return sp

    # UPDATE path — absolute set (idempotent), never a delta add.
    sp = existing_sp
    inv = (
        db.query(Inventory)
        .filter(Inventory.shop_product_id == sp.id)
        .first()
    )
    previous_quantity = int(inv.quantity) if inv is not None else 0

    sp.price = price
    sp.mrp = mrp
    sp.is_available = bool(is_available) and quantity > 0
    sp.stock_status = stock_enum
    sp.source = InventorySource.EXCEL_UPLOAD
    sp.last_inventory_update = now
    sp.last_price_update = now

    if inv is None:
        inv = Inventory(
            shop_product_id=sp.id,
            quantity=quantity,
            reserved_quantity=0,
            available_quantity=quantity,
            is_available=sp.is_available,
            stock_status=stock_enum,
            low_stock_threshold=threshold,
            last_updated_by=user_id,
            last_updated_source=InventorySource.EXCEL_UPLOAD,
            last_synced_at=now,
            freshness_status=compute_freshness(now, InventorySource.EXCEL_UPLOAD),
            freshness_checked_at=now,
        )
        db.add(inv)
        db.flush()
        previous_quantity = 0
    else:
        inv.quantity = quantity
        inv.available_quantity = max(quantity - int(inv.reserved_quantity or 0), 0)
        inv.is_available = sp.is_available
        inv.stock_status = stock_enum
        inv.last_updated_by = user_id
        inv.last_updated_source = InventorySource.EXCEL_UPLOAD
        inv.last_synced_at = now
        inv.freshness_status = compute_freshness(now, InventorySource.EXCEL_UPLOAD)
        inv.freshness_checked_at = now

    delta = quantity - previous_quantity
    db.add(
        InventoryMovement(
            inventory_id=inv.id,
            quantity_change=delta,
            quantity_before=previous_quantity,
            quantity_after=quantity,
            movement_type="RESTOCK" if delta >= 0 else "ADJUSTMENT",
            source=InventorySource.EXCEL_UPLOAD,
            reference_type="EXCEL_UPLOAD",
            reference_id=job.id,
            notes=f"Row {row.row_number} of import #{job.id}",
            created_by=user_id,
        )
    )

    sp.inventory = inv
    return sp


# ── Retry + Report ────────────────────────────────────────────────────────


def retry_failed(access, db: Session, user, job_id: int) -> dict[str, Any]:
    """Retry rows that errored during processing (e.g. transient failures)."""
    access.require("inventory", "update")
    job = _get_scoped_job(access, db, job_id)

    if getattr(job, "status", None) != ImportJobStatus.PARTIAL:
        raise ConflictError("Only partially-failed imports can be retried")

    return process_import_job(db, job.id, user_id=user.id, include_failed=True)


def build_report(access, db: Session, job_id: int) -> dict[str, Any]:
    """Generate the post-import report (counts + per-row outcomes)."""
    access.require("inventory", "read")
    job = _get_scoped_job(access, db, job_id)
    rows = (
        db.query(InventoryImportRow)
        .filter(InventoryImportRow.job_id == job.id)
        .all()
    )
    ordered = sorted(rows, key=lambda r: r.row_number)

    error_summary: dict[str, int] = {}
    for r in ordered:
        if r.status == "ERROR" and r.error_code:
            error_summary[r.error_code] = error_summary.get(r.error_code, 0) + 1

    return {
        **_serialize_job(job),
        "report": {
            "total_rows": int(job.total_rows or 0),
            "processed": int(job.processed_rows or 0),
            "failed": sum(1 for r in ordered if r.status == "ERROR"),
            "error_summary": error_summary,
            "rows": [_preview_row(r) for r in ordered],
        },
    }
