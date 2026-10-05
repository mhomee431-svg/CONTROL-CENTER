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
from app.models.inventory_import import (
    ImportJobStatus,
    InventoryImportJob,
    InventoryImportRow,
)
from app.models.product import (
    BarcodeRelationship,
    IdentifierType,  # noqa: F401 - registers the product_identifiers type enum on Base.metadata
    InventorySource,
    ProductIdentifier,
    ProductMaster,
    ProductVariant,
)
from app.core.field_limits import FIELD_LIMITS
from app.services import product_convergence, xlsx_lite
from app.services.inventory_service import derive_stock_status

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
    # Spec's optional columns. The header words a shopkeeper types are whatever
    # they call them in a spreadsheet, so the aliases cover the ordinary spellings
    # ("Dept" / "Sub-category"); `_normalize_header` has already folded case,
    # underscores and dashes into one word before this lookup.
    "category": {"category", "category name", "department", "dept"},
    "subcategory": {"subcategory", "sub category", "type"},
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


def propose_columns(header_row: list[Any]) -> list[dict[str, Any]]:
    """Describe every column of the sheet and how far we trust the match.

    One entry per non-empty header cell:

        {"column_index": 0, "header": "Item Name",
         "suggested_field": "product_name",   # None when we will not guess
         "candidates": ["product_name"],     # every field that could match
         "status": "matched" | "ambiguous" | "unmatched",
         "reason": "MULTIPLE_COLUMNS_CLAIM_THIS_FIELD" | None}

    The rule this exists for: **a column is auto-mapped only when exactly one
    field claims it.** Two ways that fails, and both used to pass silently:

    * The header text itself matches several fields — picking the first means
      the sheet's "Price" lands in whichever field happens to be declared
      first, which changes the moment someone reorders the alias table.
    * **Two columns claim the same field** — a sheet with both "Price" and
      "Selling Price" took whichever came first and threw the other away
      without a word. The shopkeeper's real data was in the discarded column
      and the import looked clean.

    So every column with a contested claim comes back with
    `suggested_field: None` and a reason. Nothing is dropped silently: the
    shopkeeper decides, in the Column Mapping step.
    """
    proposals: list[dict[str, Any]] = []
    for idx, raw in enumerate(header_row):
        header = _normalize_header(raw)
        if not header:
            continue  # a blank spacer column is not a column
        candidates = [
            field for field, aliases in FIELD_ALIASES.items() if header in aliases
        ]
        proposals.append(
            {
                "column_index": idx,
                "header": str(raw or "").strip(),
                "suggested_field": candidates[0] if len(candidates) == 1 else None,
                "candidates": candidates,
                "status": (
                    "matched" if len(candidates) == 1
                    else "ambiguous" if candidates
                    else "unmatched"
                ),
                "reason": (
                    "HEADER_MATCHES_SEVERAL_FIELDS" if len(candidates) > 1 else None
                ),
            }
        )

    # A field claimed by more than one column is ambiguous for ALL of them.
    # Resolving it by "first column wins" is exactly the silent choice this
    # function exists to refuse.
    claimed: dict[str, list[int]] = {}
    for p in proposals:
        if p["suggested_field"]:
            claimed.setdefault(p["suggested_field"], []).append(p["column_index"])
    for field, indexes in claimed.items():
        if len(indexes) < 2:
            continue
        for p in proposals:
            if p["column_index"] in indexes:
                p["suggested_field"] = None
                p["candidates"] = [field]
                p["status"] = "ambiguous"
                p["reason"] = "MULTIPLE_COLUMNS_CLAIM_THIS_FIELD"
    return proposals


def resolve_mapping(
    proposals: list[dict[str, Any]],
    overrides: dict[str, int] | None = None,
) -> dict[str, int]:
    """Canonical field -> column index, from the proposal plus any corrections.

    With no `overrides` this is the automatic mapping, which is only ever the
    unambiguous columns. With overrides the shopkeeper's word is final — but the
    shape is still validated by the caller (`validate_mapping`) before it is
    trusted, because a corrected mapping is user input like any other.
    """
    if overrides:
        return {
            field: int(index)
            for field, index in overrides.items()
            if field in FIELD_ALIASES
        }
    mapping: dict[str, int] = {}
    for p in proposals:
        field = p["suggested_field"]
        if field and field not in mapping:
            mapping[field] = p["column_index"]
    return mapping


def validate_mapping(
    mapping: dict[str, int], header_row: list[Any]
) -> list[str]:
    """Reasons a submitted mapping cannot be used, in shopkeeper-facing words.

    Returns an empty list when the mapping is usable. Kept separate from the
    check that RAISES so the Column Mapping screen can show every problem at
    once instead of making the shopkeeper resubmit to discover the next one.
    """
    problems: list[str] = []
    width = len(header_row)
    seen_columns: dict[int, str] = {}
    for field, index in sorted(mapping.items()):
        if field not in FIELD_ALIASES:
            problems.append(f"'{field}' is not a field HyperLocal can import.")
            continue
        if index < 0 or index >= width:
            problems.append(
                f"'{field}' points at column {index + 1}, but this file only "
                f"has {width} columns."
            )
            continue
        if index in seen_columns:
            # Two fields reading one column is unresolvable: the cell would
            # have to be both, and validate_row would silently let one win.
            problems.append(
                f"'{field}' and '{seen_columns[index]}' both point at column "
                f"{index + 1}. Give each its own column."
            )
            continue
        seen_columns[index] = field
    if not any(field in mapping for field in IDENTIFIER_FIELDS):
        problems.append(
            "Map at least one of Barcode / SKU / Product Name so each row can "
            "be identified."
        )
    return problems


def map_headers(header_row: list[Any]) -> dict[str, int]:
    """Map spreadsheet columns to canonical field names.

    Only the unambiguous columns (see [propose_columns]). Behaviour change from
    the original first-match-wins loop: a contested column is left unmapped and
    reported, because a wrong-but-plausible mapping is worse than an obviously
    missing one.
    """
    return resolve_mapping(propose_columns(header_row))


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

    # ── Field length ───────────────────────────────────────────────────
    # Checked here rather than left to the database: an over-long value would
    # otherwise fail at INSERT with "value too long for type character
    # varying(255)" — a 500 that names neither the field nor the limit.
    from app.core.field_limits import text_length_problems

    for field, message in text_length_problems(values):
        _err(field, "FIELD_TOO_LONG", message)

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
        # Fall back to a usable value rather than leaving `quantity` as None.
        # The row is already rejected either way, but `max(quantity, 0)` further
        # down raised TypeError on None -- which failed the ENTIRE upload with a
        # 500 instead of reporting one bad cell. A spreadsheet with a single
        # fractional stock entry must not cost the shopkeeper the whole import.
        quantity = 0
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
        "category": str(values.get("category") or "").strip() or None,
        "subcategory": str(values.get("subcategory") or "").strip() or None,
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
                ProductIdentifier.is_active == True,
            )
            .first()
        )
        if identifier is not None:
            master = (
                db.query(ProductMaster)
                .filter(
                    ProductMaster.id == identifier.product_master_id,
                    ProductMaster.is_deleted == False,
                )
                .first()
            )
        if master is None:
            rel = (
                db.query(BarcodeRelationship)
                .filter(
                    BarcodeRelationship.barcode == barcode,
                    BarcodeRelationship.is_active == True,
                )
                .first()
            )
            if rel is not None:
                master = (
                    db.query(ProductMaster)
                    .filter(
                        ProductMaster.id == rel.product_master_id,
                        ProductMaster.is_deleted == False,
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
                    ProductMaster.is_deleted == False,
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

    # ── Category / subcategory ────────────────────────────────────────
    # Resolved against the backend catalog like every other reference: an
    # unknown category in a spreadsheet is a row error, and the import never
    # invents catalog entries. This is also the spec's "rules come from the
    # backend-supported import schema" — the vocabulary the row is checked
    # against is the one this table already holds, not a list in the client.
    category_name = clean.get("category")
    if category_name:
        found = _find_category(db, category_name, want_subcategory=False)
        if found is None:
            return None, None, (
                "category", "UNKNOWN_CATEGORY",
                f"'{category_name}' is not a category in the catalog",
            )
        clean["category_id"] = found.id

    # Brand: match it when the catalog already has it, otherwise carry the text
    # through for the preview and leave the master's brand untouched. Brand
    # names come from suppliers, so refusing unknown ones would reject the
    # ordinary case (and the sample sheet itself) — the import refuses nothing
    # here, it just does not invent a Brand row.
    brand_name = clean.get("brand")
    if brand_name:
        from app.models.product import Brand

        wanted = _normalize_name(brand_name)
        for candidate in db.query(Brand).filter(
            Brand.is_deleted == False
        ).all():
            if _normalize_name(candidate.name) == wanted:
                clean["brand_id"] = candidate.id
                break

    subcategory_name = clean.get("subcategory")
    if subcategory_name:
        found = _find_category(
            db,
            subcategory_name,
            want_subcategory=True,
            parent_id=clean.get("category_id"),
        )
        if found is None:
            return None, None, (
                "subcategory", "UNKNOWN_SUBCATEGORY",
                f"'{subcategory_name}' is not a subcategory"
                + (f" of '{category_name}'" if category_name else " in the catalog"),
            )
        clean["subcategory_id"] = found.id

    return master, variant, None


def _find_category(
    db: Session, name: str, *, want_subcategory: bool, parent_id: int | None = None
):
    """Match one category by name at the level the caller asked for.

    The level rule is applied in Python rather than as SQL branches: a root
    lookup only considers root rows and a subcategory lookup only subcategory
    rows, so a name that exists at the other level is reported as unknown
    instead of being quietly accepted at the wrong level. Keeping that rule in
    one place is also what makes it testable — split across separate queries it
    could only be observed through a real engine.

    The category table is a few hundred rows at most, so one fetch per staged
    row is far cheaper than a wrong level passing silently.
    """
    from app.models.product import Category

    wanted = _normalize_name(name)
    for candidate in db.query(Category).all():
        if bool(getattr(candidate, "is_deleted", False)):
            continue
        if bool(getattr(candidate, "is_subcategory", False)) != want_subcategory:
            continue
        if want_subcategory and parent_id is not None and candidate.parent_id != parent_id:
            continue
        if _normalize_name(candidate.name) == wanted:
            return candidate
    return None


# ── Upload → Validate File → Parse → Validate Rows ────────────────────────


# Spec: "Category and field rules must come from backend-supported import
# schema." The Column Mapping step is rendered from THIS, not from a second
# hand-maintained list in the client — a rule that exists in two places is a
# rule that eventually disagrees with itself.
#
# `required_any_of` rather than `required` per column: the import needs at
# least ONE identifier, which is exactly the check `create_import` makes, so a
# spreadsheet with only a SKU and no barcode is valid.
FIELD_DEFINITIONS: dict[str, str] = {
    "product_name": "Text; the catalog is matched by this name when no barcode or SKU is given",
    "brand": "Text; applied when the catalog already has a brand of that name, otherwise left alone",
    "category": "Must match a top-level category in the catalog",
    "subcategory": "Must match a subcategory — of Category when Category is also supplied",
    "variant": "Must be a variant of the resolved product",
    "barcode": "Scannable retail barcode; the check digit is verified",
    "sku": "Matched against the catalog's variant SKUs",
    "price": "Required; a number, 0 or more",
    "mrp": "Optional; 0 or more, and never below Price",
    "quantity": "Whole number, 0 or more; a blank cell counts as 0",
    "availability": "yes / no (true, 1 and available are accepted)",
}

# Display order for the mapping step — the spec's list, so the panel reads the
# way the shopkeeper's sheet does.
FIELD_ORDER = (
    "product_name", "brand", "category", "subcategory", "variant",
    "barcode", "sku", "price", "mrp", "quantity", "availability",
)

FIELD_LABELS: dict[str, str] = {
    "product_name": "Product Name",
    "brand": "Brand",
    "category": "Category",
    "subcategory": "Subcategory",
    "variant": "Variant",
    "barcode": "Barcode",
    "sku": "SKU",
    "price": "Price",
    "mrp": "MRP",
    "quantity": "Stock",
    "availability": "Availability",
}


def import_schema() -> dict[str, Any]:
    """The vocabulary a spreadsheet is judged against, for the client.

    Deliberately a plain dict: the mapping panel shows label + accepted
    synonyms + rule, and the sample download sits beside them so the two can
    never describe different sets of columns.
    """
    # Derived from the sample itself rather than restated, so "which columns
    # does the template have" and "which columns does the schema declare" are
    # the same answer by construction.
    sample_columns = set(map_headers(list(_SAMPLE_HEADER)))

    fields = [
        {
            "name": name,
            "label": FIELD_LABELS[name],
            "aliases": sorted(FIELD_ALIASES[name]),
            "rules": FIELD_DEFINITIONS.get(name, ""),
            "in_sample": name in sample_columns,
        }
        for name in FIELD_ORDER
    ]
    return {
        "sample_file": SAMPLE_FILE_NAME,
        "required_any_of": [
            FIELD_LABELS[name] for name in IDENTIFIER_FIELDS
        ],
        "max_rows": MAX_ROWS,
        "max_file_size_bytes": MAX_FILE_SIZE_BYTES,
        # Published so the client validates against the SAME numbers the server
        # enforces. A client-side copy of these limits would drift, and the drift
        # would surface as "your file was rejected" with no visible cause.
        "limits": dict(FIELD_LIMITS),
        "fields": fields,
    }


# ── Download Sample (Import Center) ────────────────────────────────────────

SAMPLE_FILE_NAME = "inventory-import-sample.xlsx"

# The canonical column order — exactly the names `map_headers` resolves, so a
# shopkeeper who fills this file in never fights the validator.
_SAMPLE_HEADER = [
    "Barcode", "Product Name", "Brand", "Variant",
    "SKU", "Price", "MRP", "Quantity", "Availability",
    "Category", "Subcategory",
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
     "AAS-SALT-1KG", 28.5, 32, 24, "yes", "", ""],
    ["", "Farm Fresh Milk 500ml", "", "500 ml",
     "FF-MILK-500", 26, "", 12, "yes", "", ""],
    ["8901234567883", "India Gate Basmati 5kg", "India Gate", "5 kg",
     "IG-RICE-5KG", 480, 540, 0, "no", "", ""],
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
    access: Any, db: Session, user: Any, filename: str, content: bytes
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
        result = {**_serialize_job(existing), **_mapping_payload(existing)}
        result["idempotent_replay"] = True
        logger.info("Idempotent import replay: job=%s shop=%s", existing.id, access.shop.id)
        return result

    # ── File-level validation ──────────────────────────────────────────
    from app.core.upload_security import (
        XLSX_MAGIC,
        UploadValidationError,
        validate_upload,
    )

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

    header = grid[0]
    proposals = propose_columns(header)
    header_map = resolve_mapping(proposals)
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
        # Kept verbatim so the Column Mapping step can show the shopkeeper their
        # own headers and so a submitted mapping can be checked against the
        # real column count.
        header_row=json.dumps(header, default=str),
        column_mapping=json.dumps(header_map),
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
                raw_data=json.dumps(list(raw_row), default=str),
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
        # The Column Mapping step renders this: one entry per column of THEIR
        # sheet, what we think it is, and where we refused to guess.
        "column_proposal": proposals,
        "header_row": header,
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
        "category": clean.get("category"),
        "subcategory": clean.get("subcategory"),
        "product_master_id": clean.get("product_master_id"),
        "variant_id": clean.get("variant_id"),
        "category_id": clean.get("category_id"),
        "subcategory_id": clean.get("subcategory_id"),
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
    return {
        **_serialize_job(job),
        **_mapping_payload(job),
        "rows": [_preview_row(r) for r in ordered],
    }


def _mapping_payload(job: InventoryImportJob) -> dict[str, Any]:
    """Header, per-column proposal, and the mapping ACTUALLY applied.

    The applied mapping is read back off the job rather than re-derived, because
    it may differ from the automatic one: once the shopkeeper has corrected an
    ambiguous column, re-deriving would silently undo their correction and put
    the same question back to them on every reload.
    """
    header = json.loads(job.header_row) if job.header_row else []
    proposals = propose_columns(header)
    applied = (
        json.loads(job.column_mapping)
        if job.column_mapping
        else resolve_mapping(proposals)
    )
    return {
        "header_row": header,
        "column_proposal": proposals,
        "column_mapping": applied,
    }


def _get_scoped_job(access, db: Session, job_id: int) -> InventoryImportJob:
    job = db.query(InventoryImportJob).filter(InventoryImportJob.id == int(job_id)).first()
    if job is None:
        raise NotFoundError("Import job not found")
    if job.shop_id != access.shop.id:
        raise NotFoundError("Import job not found")  # cross-shop access is hidden
    return job


def _row_cells(row: InventoryImportRow) -> list[Any]:
    """The row's cells by position.

    Raises on a legacy (field-keyed) row rather than returning something that
    looks usable: those rows cannot be re-indexed, and an empty list here would
    turn "cannot remap" into "every row is empty".
    """
    try:
        cells = json.loads(row.raw_data or "[]")
    except (TypeError, ValueError) as exc:
        raise ValidationError(
            "This import's rows are not stored by column and cannot be "
            "remapped. Upload the file again.",
            data={"reason_code": "MAPPING_UNSUPPORTED"},
        ) from exc
    if not isinstance(cells, list):
        raise ValidationError(
            "This import's rows are not stored by column and cannot be "
            "remapped. Upload the file again.",
            data={"reason_code": "MAPPING_UNSUPPORTED"},
        )
    return cells


def _cell_at(cells: list[Any], index: int) -> Any:
    return cells[index] if 0 <= index < len(cells) else None


def remap_import(
    access: Any,
    db: Session,
    job_id: int,
    column_mapping: dict[str, Any] | None,
) -> dict[str, Any]:
    """Re-stage a job under a corrected column mapping, before anything applies.

    The rows are re-validated rather than patched. Changing which column holds
    the price changes which rows are valid, so a row VALID under the old mapping
    can be an ERROR under the new one and vice versa; re-running the same
    validation path is what keeps the preview, the report and the applied import
    telling the same story.

    Refuses a job that has already been applied: the mapping is a pre-import
    decision, and re-staging applied rows would rewrite inventory the shopkeeper
    has already seen as done.
    """
    access.require("inventory", "update")
    job = _get_scoped_job(access, db, job_id)

    if job.status != ImportJobStatus.AWAITING_CONFIRMATION:
        raise ValidationError(
            "This import has already been applied, so its columns can no "
            "longer be remapped. Upload the file again to change the mapping.",
            data={"reason_code": "IMPORT_ALREADY_APPLIED"},
        )
    if not job.header_row:
        # Staged before the header was stored: its rows hold field-keyed values,
        # so there is nothing to re-index against and pretending otherwise would
        # import blanks.
        raise ValidationError(
            "This import was staged before column mapping was supported and "
            "cannot be remapped. Upload the file again.",
            data={"reason_code": "MAPPING_UNSUPPORTED"},
        )

    header = json.loads(job.header_row)
    # A null value is the shopkeeper saying "don't import this column", which is
    # a legitimate answer — not an error to reject.
    submitted = {
        field: int(index)
        for field, index in (column_mapping or {}).items()
        if field in FIELD_ALIASES and index is not None and str(index).strip() != ""
    }
    problems = validate_mapping(submitted, header)
    if problems:
        raise ValidationError(
            problems[0],
            data={"reason_code": "INVALID_COLUMN_MAPPING", "problems": problems},
        )

    rows = (
        db.query(InventoryImportRow)
        .filter(InventoryImportRow.job_id == job.id)
        .all()
    )
    seen_keys: set[tuple] = set()
    valid_count = error_count = 0

    for row in rows:
        cells = _row_cells(row)
        values = {field: _cell_at(cells, index) for field, index in submitted.items()}
        clean, errors = validate_row(db, values, seen_keys)

        primary = errors[0] if errors else None
        row.status = "ERROR" if errors else "VALID"
        valid_count += 0 if errors else 1
        error_count += 1 if errors else 0
        row.normalized_data = json.dumps(clean, default=str)
        row.error_code = primary["code"] if primary else None
        row.error_field = primary["field"] if primary else None
        row.error_message = (
            "; ".join(f"{e['field']}: {e['message']}" for e in errors)
            if errors
            else None
        )
        # Re-resolution can move the row onto a different product, so the old
        # ids must not survive into the applied import.
        row.product_master_id = clean.get("product_master_id")
        row.variant_id = clean.get("variant_id")

    job.valid_rows = valid_count
    job.error_rows = error_count
    job.column_mapping = json.dumps(submitted)
    db.flush()

    logger.info(
        "Excel import remapped: shop=%s job=%s fields=%s valid=%s errors=%s",
        access.shop.id, job.id, len(submitted), valid_count, error_count,
    )
    return {
        **_serialize_job(job),
        **_mapping_payload(job),
        "rows": [_preview_row(r) for r in sorted(rows, key=lambda r: r.row_number)],
    }
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
    except Exception:
        logger.warning("Import notification failed", exc_info=True)
    return {
        **_serialize_job(job),
        "processed_this_run": processed,
        "failed_this_run": failed,
    }


def _apply_catalog_classification(db, master, data: dict[str, Any]) -> None:
    """File a resolved row onto a SHARED master — only where it is empty.

    The master is shared across shops, so a bulk import must not silently
    re-file a product another shop already placed: fill-if-empty is the same
    rule the manual create path uses.

    Brand behaves differently on purpose. It resolves when the catalog already
    has a brand of that name, and is left alone otherwise — brand words come
    from suppliers, and refusing unknown ones would reject a normal export (and
    the sample sheet itself). A brandless master beats a wrong one.
    """
    category_id = data.get("category_id")
    if category_id and master.category_id is None:
        master.category_id = int(category_id)
    subcategory_id = data.get("subcategory_id")
    if subcategory_id and master.subcategory_id is None:
        master.subcategory_id = int(subcategory_id)
    brand_id = data.get("brand_id")
    if brand_id and master.brand_id is None:
        master.brand_id = int(brand_id)


def _apply_row(db: Session, job, user_id, row, now):
    """Upsert one import row onto the canonical ShopProduct + Inventory."""
    import app.models.product as product_models

    data = json.loads(row.normalized_data) if row.normalized_data else {}
    master_id = row.product_master_id or data.get("product_master_id")
    if master_id is None:
        raise ValidationError("Row has no resolved catalog product")

    master = (
        db.query(ProductMaster)
        .filter(
            ProductMaster.id == int(master_id),
            ProductMaster.is_deleted == False,
        )
        .first()
    )
    if master is None:
        raise NotFoundError(f"Catalog product {master_id} no longer exists")

    # Catalog classification arrives with the row; see
    # `_apply_catalog_classification` for why this is fill-if-empty.
    _apply_catalog_classification(db, master, data)
    db.add(master)

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

    # CREATE + UPDATE both go through the shared convergence service, which
    # returns the listing whether it already exists or not. That is what makes
    # re-importing the same sheet idempotent instead of additive — one path, one
    # meaning, no branch where a first import and a re-import differ.
    sp = product_convergence.attach_product_to_shop(
        db,
        shop_id=job.shop_id,
        master=master,
        variant=variant,
        sku=data.get("sku"),
        source=InventorySource.EXCEL_UPLOAD,
        price=price,
        mrp=mrp,
        publish=True,
        is_available=bool(is_available) and quantity > 0,
        stock_status=stock_enum,
    )

    product_convergence.set_price(db, sp, price=price, mrp=mrp, now=now)
    sp.is_available = bool(is_available) and quantity > 0
    sp.stock_status = stock_enum
    sp.source = InventorySource.EXCEL_UPLOAD
    sp.last_inventory_update = now
    db.add(sp)

    inv = product_convergence.set_inventory(
        db,
        sp,
        quantity=quantity,
        low_stock_threshold=threshold,
        source=InventorySource.EXCEL_UPLOAD,
        is_available=bool(is_available) and quantity > 0,
        stock_status=stock_enum,
        user_id=user_id,
        reference_type="EXCEL_UPLOAD",
        reference_id=job.id,
        notes=f"Row {row.row_number} of import #{job.id}",
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
