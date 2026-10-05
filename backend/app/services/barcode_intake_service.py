"""Phase 24 Part A — Barcode scan → shop inventory intake.

Implements the shopkeeper phone-barcode flow:

    Scan Barcode → Identify Identifier → Find Product/Variant → Show Product
    → Confirm Shop Product → Enter Price → Set Availability/Quantity
    → Review → Save → Publish

Every step that can fail has an explicit, typed outcome:

  - invalid barcode format      -> ``ValidationError`` / status INVALID
  - barcode not in catalog      -> status NOT_FOUND (scan event still recorded)
  - duplicate barcode rows      -> flagged in resolution result
  - multiple catalog matches    -> status MULTIPLE_MATCHES (shopkeeper chooses)
  - lookup infrastructure error -> ``ServiceUnavailableError`` (network failure)
  - product unavailable         -> ``ValidationError`` on confirm
  - variant mismatch            -> ``ValidationError`` on confirm

Saved listings go through the SAME canonical inventory system as manual and
Excel flows: ``ShopProduct`` + ``Inventory`` with
``InventorySource.BARCODE_SCAN`` and a full audit movement.
"""

from __future__ import annotations

from datetime import datetime, timezone
from typing import Any

from sqlalchemy.orm import Session

from app.core.exceptions import (
    ConflictError,
    NotFoundError,
    ServiceUnavailableError,
    ValidationError,
)
from app.core.logging import get_logger
from app.models.product import (
    BarcodeRelationship,
    IdentifierType,
    Inventory,
    InventoryMovement,
    InventorySource,
    ProductIdentifier,
    ProductMaster,
    ProductStatus,
    ShopProduct,
)
from app.services.inventory_service import compute_freshness, derive_stock_status
from app.services import product_convergence

logger = get_logger("app.services.barcode_intake")

# Identifier types that represent scannable retail barcodes.
BARCODE_IDENTIFIER_TYPES = {
    IdentifierType.EAN,
    IdentifierType.UPC,
    IdentifierType.GTIN,
    IdentifierType.JAN,
    IdentifierType.ITF,
}

VALID_BARCODE_LENGTHS = {8, 12, 13, 14}  # EAN-8, UPC-A, EAN-13, GTIN-14

# Catalog statuses that make a master product un-sellable.
_UNAVAILABLE_STATUSES = {
    ProductStatus.INACTIVE,
    ProductStatus.ARCHIVED,
    ProductStatus.REJECTED,
}

SCAN_SOURCE_SHOPKEEPER = "SHOPKEEPER_APP"


# ── Format validation ─────────────────────────────────────────────────────


def normalize_barcode(barcode: str | None) -> str:
    """Strip whitespace/separators commonly printed around barcodes."""
    return str(barcode or "").strip().replace(" ", "").replace("-", "")


def validate_barcode_format(barcode: str | None) -> tuple[bool, str | None]:
    """Validate a scanned code. Returns ``(ok, reason)``."""
    cleaned = normalize_barcode(barcode)
    if not cleaned:
        return False, "empty"
    if not cleaned.isdigit():
        return False, "non_numeric"
    if len(cleaned) not in VALID_BARCODE_LENGTHS:
        return False, "invalid_length"

    # GS1 check digit: rightmost data digit weighted 3, alternating 3/1.
    data_digits = [int(ch) for ch in reversed(cleaned[:-1])]
    expected_check = int(cleaned[-1])
    total = sum(
        weight * digit
        for weight, digit in zip((3, 1) * len(data_digits), data_digits)
    )
    if (10 - total % 10) % 10 != expected_check:
        return False, "bad_check_digit"
    return True, None


def barcode_type_for(length: int) -> str:
    return {8: "EAN-8", 12: "UPC-A", 13: "EAN-13", 14: "GTIN-14"}.get(length, "UNKNOWN")


def is_barcode_identifier(identifier_type: Any) -> bool:
    try:
        enum_value = getattr(identifier_type, "value", identifier_type)
        return IdentifierType(str(enum_value)) in BARCODE_IDENTIFIER_TYPES
    except ValueError:
        return False


# ── Scan-event recording ──────────────────────────────────────────────────


def record_scan_event(
    db: Session,
    barcode: str,
    *,
    is_match_found: bool,
    product_master_id: int | None = None,
    shop_id: int | None = None,
    user_id: int | None = None,
) -> None:
    """Persist a ``BarcodeScan`` analytics row (SHOPKEEPER_APP source)."""
    from app.models.search import BarcodeScan

    cleaned = normalize_barcode(barcode)
    ok, _reason = validate_barcode_format(cleaned)
    db.add(
        BarcodeScan(
            barcode=cleaned[:100],
            barcode_type=barcode_type_for(len(cleaned)) if ok else None,
            user_id=user_id,
            shop_id=shop_id,
            product_master_id=product_master_id,
            scan_source=SCAN_SOURCE_SHOPKEEPER,
            is_match_found=bool(is_match_found),
        )
    )


# ── Resolution (Identify → Find Product → Show Product) ──────────────────


def _serialize_match(master: ProductMaster, match_type: str) -> dict[str, Any]:
    variants = [
        {"id": v.id, "name": v.name, "sku": v.sku}
        for v in (getattr(master, "variants", None) or [])
    ]
    status_value = getattr(master.status, "value", str(master.status)) if master.status else None
    unavailable = (not getattr(master, "is_active", True)) or (
        master.status in _UNAVAILABLE_STATUSES
    )
    return {
        "product_master_id": master.id,
        "name": master.name,
        "brand_id": getattr(master, "brand_id", None),
        "brand_name": _relationship_value(master, "brand", "name"),
        "image_url": _primary_image_url(master),
        "status": status_value,
        "is_available_in_catalog": not unavailable,
        "match_type": match_type,
        "variants": variants,
    }


def _relationship_value(master: ProductMaster, attr: str, leaf: str) -> Any:
    """Read ``master.<attr>.<leaf>`` tolerating detached ORM instances.

    Test fixtures construct masters outside a session, so a lazy load of an
    unset relationship raises ``DetachedInstanceError``; a session-bound
    instance (production) loads it normally. Either way this never blocks
    the resolution response.
    """
    try:
        related = getattr(master, attr, None)
    except Exception:  # noqa: BLE001 — DetachedInstanceError and friends
        return None
    return getattr(related, leaf, None)


def _primary_image_url(master: ProductMaster) -> str | None:
    """Primary product image URL — first primary image, else the first."""
    try:
        images = getattr(master, "images", None) or []
    except Exception:  # noqa: BLE001 — DetachedInstanceError and friends
        return None
    if not images:
        return None
    primaries = [img for img in images if getattr(img, "is_primary", False)]
    chosen = primaries[0] if primaries else images[0]
    return getattr(chosen, "image_url", None)


def resolve_barcode(db: Session, barcode: str) -> dict[str, Any]:
    """Identify a scanned code against the shared product catalog.

    Returns::

        {"status": "FOUND" | "MULTIPLE_MATCHES" | "NOT_FOUND",
         "barcode": ..., "barcode_type": ..., "matches": [...], ...}

    Invalid formats raise ``ValidationError``; infrastructure failures raise
    ``ServiceUnavailableError`` so callers can offer a retry.
    """
    cleaned = normalize_barcode(barcode)
    ok, reason = validate_barcode_format(cleaned)
    if not ok:
        raise ValidationError(
            f"Invalid barcode ({reason})",
            data={"status": "INVALID", "reason": reason},
        )

    try:
        identifiers = (
            db.query(ProductIdentifier)
            .filter(
                ProductIdentifier.identifier_value == cleaned,
                ProductIdentifier.is_active == True,  # noqa: E712
            )
            .all()
        )
        relationships = (
            db.query(BarcodeRelationship)
            .filter(
                BarcodeRelationship.barcode == cleaned,
                BarcodeRelationship.is_active == True,  # noqa: E712
            )
            .all()
        )
    except Exception as exc:  # network / DB outage during lookup
        logger.warning("Barcode lookup infrastructure failure: %s", exc)
        raise ServiceUnavailableError(
            "Barcode lookup is temporarily unavailable. Please retry."
        ) from exc

    ordered_master_ids: list[int] = []
    seen: set[int] = set()
    match_types: dict[int, str] = {}

    def _remember(master_id: int | None, match_type: str) -> None:
        if master_id is None or master_id in seen:
            return
        seen.add(master_id)
        ordered_master_ids.append(master_id)
        match_types[master_id] = match_type

    for ident in identifiers:
        if is_barcode_identifier(ident.identifier_type):
            _remember(ident.product_master_id, "IDENTIFIER")
    for rel in relationships:
        _remember(rel.product_master_id, rel.relationship_type or "ALTERNATE")

    masters: list[dict[str, Any]] = []
    for master_id in ordered_master_ids:
        master = (
            db.query(ProductMaster)
            .filter(
                ProductMaster.id == master_id,
                ProductMaster.is_deleted == False,  # noqa: E712
            )
            .first()
        )
        if master is not None:
            masters.append(_serialize_match(master, match_types.get(master_id, "IDENTIFIER")))

    if not masters:
        return {
            "status": "NOT_FOUND",
            "barcode": cleaned,
            "barcode_type": barcode_type_for(len(cleaned)),
            "matches": [],
            "error_code": "BARCODE_NOT_FOUND",
            "message": "No catalog product is registered for this barcode",
        }
    if len(masters) > 1:
        # Duplicate barcode registered to several products — ambiguous;
        # the shopkeeper must disambiguate explicitly.
        return {
            "status": "MULTIPLE_MATCHES",
            "barcode": cleaned,
            "barcode_type": barcode_type_for(len(cleaned)),
            "matches": masters,
            "error_code": "MULTIPLE_BARCODE_MATCHES",
            "message": f"{len(masters)} catalog products share this barcode",
        }
    return {
        "status": "FOUND",
        "barcode": cleaned,
        "barcode_type": barcode_type_for(len(cleaned)),
        "matches": masters,
    }


# ── Confirm + Save (Confirm → Price → Availability → Save → Publish) ─────


def save_from_scan(access, db: Session, user, data: dict[str, Any]) -> dict[str, Any]:
    """Create/refresh the shop listing for a confirmed barcode scan.

    Reuses the canonical ShopProduct + Inventory rows — never a parallel
    inventory store. Source and audit references are BARCODE_SCAN.
    """
    import app.models.product as product_models
    from app.models.product import ShopProductStatus

    access.require("product", "create")

    master = (
        db.query(ProductMaster)
        .filter(
            ProductMaster.id == int(data["product_master_id"]),
            ProductMaster.is_deleted == False,  # noqa: E712
        )
        .first()
    )
    if master is None:
        raise NotFoundError("Scanned product not found in catalog")

    # Product-unavailable guard (inactive / archived / rejected masters).
    if (not getattr(master, "is_active", True)) or (master.status in _UNAVAILABLE_STATUSES):
        raise ValidationError(
            "This product is currently unavailable in the catalog",
            data={"reason_code": "PRODUCT_UNAVAILABLE"},
        )

    # Variant-mismatch guard.
    variant = None
    variant_id = data.get("variant_id")
    if variant_id is not None:
        variant = next(
            (v for v in (master.variants or []) if v.id == int(variant_id)),
            None,
        )
        if variant is None:
            raise ValidationError(
                "Selected variant does not belong to this product",
                data={"reason_code": "VARIANT_MISMATCH"},
            )

    price = float(data["price"])
    if price < 0:
        raise ValidationError("Price cannot be negative")
    mrp = float(data["mrp"]) if data.get("mrp") is not None else None
    if mrp is not None:
        if mrp < 0:
            raise ValidationError("MRP cannot be negative")
        if mrp < price:
            raise ValidationError("MRP cannot be lower than selling price")

    duplicate = (
        db.query(ShopProduct)
        .filter(
            ShopProduct.shop_id == access.shop.id,
            ShopProduct.product_master_id == master.id,
            ShopProduct.variant_id == (variant.id if variant else None),
            ShopProduct.is_deleted == False,  # noqa: E712
        )
        .first()
    )
    if duplicate is not None:
        raise ConflictError(
            "This product is already in your inventory — update it instead"
        )

    quantity = max(int(data.get("quantity", 0)), 0)
    threshold = int(data.get("low_stock_threshold", 5))
    publish = bool(data.get("publish", True))
    available = bool(data.get("is_available", True)) and quantity > 0
    stock_enum = product_models.StockStatus[derive_stock_status(quantity, threshold).value]
    now = datetime.now(timezone.utc)

    sp = product_convergence.attach_product_to_shop(
        db,
        shop_id=access.shop.id,
        master=master,
        variant=variant,
        sku=data.get("sku"),
        source=InventorySource.BARCODE_SCAN,
        price=price,
        mrp=mrp,
        publish=publish,
        is_available=available and publish,
        stock_status=stock_enum,
    )

    inv = product_convergence.set_inventory(
        db,
        sp,
        quantity=quantity,
        low_stock_threshold=threshold,
        source=InventorySource.BARCODE_SCAN,
        is_available=available,
        stock_status=stock_enum,
        user_id=user.id,
        reference_type="BARCODE_SCAN",
        notes=f"Added via barcode scan {data.get('barcode') or ''}".strip(),
    )

    record_scan_event(
        db,
        str(data.get("barcode") or ""),
        is_match_found=True,
        product_master_id=master.id,
        shop_id=access.shop.id,
        user_id=user.id,
    )

    sp.inventory = inv
    logger.info(
        "Barcode-scan product saved: shop=%s shop_product=%s master=%s by user=%s",
        access.shop.id, sp.id, master.id, user.id,
    )
    return {
        "id": sp.id,
        "shop_id": sp.shop_id,
        "name": master.name,
        "sku": sp.sku,
        "status": getattr(sp.status, "value", str(sp.status)),
        "price": float(sp.price),
        "mrp": float(sp.mrp) if sp.mrp is not None else None,
        "quantity": quantity,
        "is_active": sp.is_active,
        "is_available": sp.is_available,
        "stock_status": stock_enum.value,
        "source": InventorySource.BARCODE_SCAN.value,
        "last_inventory_update": now.isoformat(),
    }
