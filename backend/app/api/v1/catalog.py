"""Products, categories, brands and identifiers."""

# Owns the whole catalog governance surface: product management (list and
# moderate), product detail drill-downs, product quality control findings, and
# the high-risk product merge workflow. Merges never happen silently — every one
# requires an operator-written reason and lands in the audit trail.

from fastapi import APIRouter, Depends, HTTPException
import re

from pydantic import BaseModel, field_validator
from sqlalchemy import func, or_, select
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.core.pagination import Pagination, pagination
from app.core.responses import ok, paged
from app.core.serializers import to_dict
from app.core.security import get_current_admin, require_capability
from app.models import AdminUser, AuditLog, Brand, Category, Product, ProductVariant, ShopInventory

router = APIRouter(prefix="/admin", tags=["catalog"])

PRODUCT_FIELDS = [
    "id", "name", "brand_id", "brand_name", "category_id", "category_name",
    "subcategory_id", "barcode", "status", "shop_count",
    "image_url", "images", "description", "mrp", "unit", "created_at", "updated_at",
]


# --- Products --------------------------------------------------------------


@router.get("/products")
def list_products(
    page: Pagination = Depends(pagination),
    shop_id: int | None = None,
    status: str | None = None,
    brand_id: int | None = None,
    category_id: int | None = None,
    db: Session = Depends(get_db),
    _: AdminUser = Depends(get_current_admin),
):
    """Product listing.

    `shop_id` scopes the list to one business, which is how the business
    drill-down's Products tab reads it.
    """
    stmt = select(Product)
    if shop_id is not None:
        stmt = stmt.join(ShopInventory, ShopInventory.product_id == Product.id).where(
            ShopInventory.shop_id == shop_id
        )
    if page.search:
        like = f"%{page.search}%"
        stmt = stmt.where(
            or_(Product.name.ilike(like), Product.barcode.ilike(like), Product.brand_name.ilike(like))
        )
    if status:
        stmt = stmt.where(Product.status == status)
    if brand_id is not None:
        stmt = stmt.where(Product.brand_id == brand_id)
    if category_id is not None:
        stmt = stmt.where(Product.category_id == category_id)

    stmt = stmt.distinct()
    total = db.scalar(select(func.count()).select_from(stmt.subquery())) or 0
    start, end = page.window()
    rows = db.scalars(stmt.order_by(Product.id).offset(start).limit(end - start)).all()
    return ok(paged([to_dict(r, PRODUCT_FIELDS) for r in rows], total))


@router.get("/products/barcode-search")
def barcode_search(
    barcode: str,
    db: Session = Depends(get_db),
    _: AdminUser = Depends(get_current_admin),
):
    product = db.scalar(select(Product).where(Product.barcode == barcode))
    variants = db.scalars(
        select(ProductVariant).where(ProductVariant.barcode == barcode)
    ).all()
    return ok(
        {
            "product": to_dict(product, PRODUCT_FIELDS) if product else None,
            "variants": [
                to_dict(v, ["id", "product_id", "name", "sku", "barcode", "price", "mrp"])
                for v in variants
            ],
        }
    )


@router.get("/products/approvals")
def product_approvals(
    page: Pagination = Depends(pagination),
    db: Session = Depends(get_db),
    _: AdminUser = Depends(get_current_admin),
):
    stmt = select(Product).where(Product.status == "PENDING")
    total = db.scalar(select(func.count()).select_from(stmt.subquery())) or 0
    start, end = page.window()
    rows = db.scalars(stmt.order_by(Product.id).offset(start).limit(end - start)).all()
    return ok(paged([to_dict(r, PRODUCT_FIELDS) for r in rows], total))


# NOTE: static /products/* paths (quality, merge/*, bulk, listings/*) are
# declared BEFORE /products/{product_id} below — FastAPI matches in order,
# so the dynamic route must come last or it swallows every static path
# ("quality" parsed as a product id -> 404/422 instead of the real surface).


# Server-computed hygiene signals for the Quality Control surface. The frontend
# `qualityChecks.ts` mirrors these client-side; this route is the paginated,
# authoritative source so large catalogs never pull every row to find breakage.
#
# Declared here, above /products/{product_id}: FastAPI matches in registration
# order, so a GET /products/quality declared after the dynamic route would be
# eaten as product_id="quality" (422) and the whole Quality Control page would
# report a validation error instead of its findings.
@router.get("/products/quality")
def product_quality(
    check: str | None = None,
    page: Pagination = Depends(pagination),
    db: Session = Depends(get_db),
    _: AdminUser = Depends(get_current_admin),
):
    """Findings across the nine quality checks, oldest product first."""
    rows = db.scalars(select(Product).order_by(Product.id)).all()
    barcodes: dict[str, list[int]] = {}
    for r in rows:
        if r.barcode:
            barcodes.setdefault(str(r.barcode).strip().lower(), []).append(r.id)
    names: dict[str, list[int]] = {}
    for r in rows:
        key = (r.name or "").lower().strip()
        if key:
            names.setdefault(key, []).append(r.id)

    def _row(pid: int, check_id: str, title: str, detail: str) -> dict:
        p = next((x for x in rows if x.id == pid), None)
        return {
            "key": f"{check_id}:{pid}",
            "check": check_id,
            "title": title,
            "product_id": pid,
            "product_name": p.name if p else f"Product #{pid}",
            "detail": detail,
        }

    findings: list[dict] = []
    for r in rows:
        lname = (r.name or "").lower().strip()
        if lname and len(names.get(lname, [])) > 1:
            others = sorted(i for i in names[lname] if i != r.id)
            findings.append(_row(r.id, "duplicates", "Duplicate candidates",
                                 f"Same name as product(s): {', '.join(map(str, others))}"))
        if not (r.image_url or (r.images or [])):
            findings.append(_row(r.id, "missing-images", "Missing images",
                                 "No master image and no image list reported"))
        if r.brand_id is None and not (r.brand_name or "").strip():
            findings.append(_row(r.id, "missing-brand", "Missing brand",
                                 "No brand linkage reported"))
        if r.category_id is None and not (r.category_name or "").strip():
            findings.append(_row(r.id, "missing-category", "Missing category",
                                 "No category linkage reported"))
        if r.barcode:
            digits = "".join(ch for ch in str(r.barcode) if ch.isdigit())
            has_letters = any(ch.isalpha() for ch in str(r.barcode))
            if not digits or has_letters:
                findings.append(_row(r.id, "invalid-barcode", "Invalid barcode",
                                     f"Barcode {r.barcode!r} is not numeric"))
            elif len(digits) not in {8, 12, 13, 14}:
                findings.append(_row(r.id, "invalid-barcode", "Invalid barcode",
                                     f"Barcode {r.barcode!r} has an implausible length"))
            else:
                key = str(r.barcode).strip().lower()
                others = sorted(i for i in barcodes.get(key, []) if i != r.id)
                if others:
                    findings.append(_row(r.id, "unmatched-identifiers", "Unmatched identifiers",
                                         f"Barcode shared with product(s): {', '.join(map(str, others))}"))
        if (r.status or "").upper() in {"INACTIVE", "ARCHIVED"}:
            findings.append(_row(r.id, "inactive", "Inactive products",
                                 f"Status is {r.status}"))
        if (r.shop_count or 0) <= 0:
            findings.append(_row(r.id, "no-shop", "Products with no shop",
                                 "No stocking shop reported"))
        mrp = float(r.mrp) if r.mrp is not None else None
        if mrp is not None and mrp <= 0:
            findings.append(_row(r.id, "suspicious", "Suspicious data",
                                 f"MRP is {mrp}, expected a positive amount"))
        if not (r.name or "").strip():
            findings.append(_row(r.id, "suspicious", "Suspicious data",
                                 "Product name is blank"))
    if check:
        findings = [f for f in findings if f["check"] == check]
    total = len(findings)
    start, end = page.window()
    return ok(paged(findings[start:end], total))


@router.get("/products/{product_id}")
def product_detail(
    product_id: int, db: Session = Depends(get_db), _: AdminUser = Depends(get_current_admin)
):
    product = db.get(Product, product_id)
    if product is None:
        raise HTTPException(status_code=404, detail=f"Product {product_id} not found")
    return ok(to_dict(product, PRODUCT_FIELDS))



# --- Product moderation: bulk + single update --------------------------------
#
# The products grid posts APPROVE / REJECT / ARCHIVE here with a mandatory
# operator reason; the approvals queue posts listing reviews to
# `/products/listings/{id}/review`. Every mutation lands in the audit trail.


class ProductBulkAction(BaseModel):
    """Bulk moderation over the master catalog."""

    action: str
    product_ids: list[int]
    reason: str

    @field_validator("action")
    @classmethod
    def _action_known(cls, v: str) -> str:
        allowed = {"APPROVE", "REJECT", "ARCHIVE", "ACTIVE", "PENDING"}
        upper = (v or "").upper()
        if upper not in allowed:
            raise ValueError(f"Unknown bulk action: {v}")
        return upper

    @field_validator("reason")
    @classmethod
    def _reason_required(cls, v: str) -> str:
        if not (v or "").strip():
            raise ValueError("A reason is required — it is recorded in the audit log")
        return v.strip()


BULK_ACTION_TO_STATUS = {
    "APPROVE": "APPROVED",
    "REJECT": "REJECTED",
    "ARCHIVE": "ARCHIVED",
    "ACTIVE": "ACTIVE",
    "PENDING": "PENDING",
}


@router.post("/products/bulk")
def bulk_moderate_products(
    payload: ProductBulkAction,
    db: Session = Depends(get_db),
    admin: AdminUser = Depends(require_capability("products.update")),
):
    """Approve / reject / archive many master products at once."""
    if not payload.product_ids:
        raise HTTPException(status_code=422, detail="Select at least one product")
    target = BULK_ACTION_TO_STATUS[payload.action]
    rows = db.scalars(select(Product).where(Product.id.in_(payload.product_ids))).all()
    found = {r.id for r in rows}
    missing = sorted(set(payload.product_ids) - found)
    if missing:
        raise HTTPException(status_code=404, detail=f"Products not found: {missing}")
    for r in rows:
        r.status = target
        db.add(
            AuditLog(
                action=f"product.{target.lower()}",
                entity_type="product",
                entity_id=r.id,
                user_id=admin.id,
                admin_user=admin.name or admin.username,
                details={"bulk_action": payload.action, "reason": payload.reason},
            )
        )
    db.commit()
    return ok(
        {"updated": len(rows), "status": target},
        message=f"{len(rows)} product(s) moved to {target}",
    )


class ProductUpdate(BaseModel):
    """Partial update of one master product. Only supplied fields are written."""

    name: str | None = None
    brand_id: int | None = None
    brand_name: str | None = None
    category_id: int | None = None
    category_name: str | None = None
    subcategory_id: int | None = None
    barcode: str | None = None
    description: str | None = None
    mrp: float | None = None
    unit: str | None = None
    image_url: str | None = None
    status: str | None = None


@router.patch("/products/{product_id}")
def update_product(
    product_id: int,
    payload: ProductUpdate,
    db: Session = Depends(get_db),
    admin: AdminUser = Depends(require_capability("products.update")),
):
    """Audited partial update of one master product."""
    product = db.get(Product, product_id)
    if product is None:
        raise HTTPException(status_code=404, detail=f"Product {product_id} not found")
    changes = payload.model_dump(exclude_unset=True)
    if not changes:
        raise HTTPException(status_code=422, detail="No fields supplied to update")
    for field, value in changes.items():
        setattr(product, field, value)
    db.add(
        AuditLog(
            action="product.updated",
            entity_type="product",
            entity_id=product_id,
            user_id=admin.id,
            admin_user=admin.name or admin.username,
            details={"fields": sorted(changes)},
        )
    )
    db.commit()
    db.refresh(product)
    return ok(to_dict(product, PRODUCT_FIELDS), message="Product updated")


class ListingReview(BaseModel):
    """Review one pending listing from the approvals queue."""

    decision: str
    review_notes: str | None = None
    reason: str | None = None

    @field_validator("decision")
    @classmethod
    def _decision_known(cls, v: str) -> str:
        allowed = {"APPROVE", "REJECT", "NEEDS_INFO", "APPROVED", "REJECTED"}
        upper = (v or "").upper()
        if upper not in allowed:
            raise ValueError(f"Unknown review decision: {v}")
        return upper


@router.post("/products/listings/{listing_id}/review")
def review_listing(
    listing_id: int,
    payload: ListingReview,
    db: Session = Depends(get_db),
    admin: AdminUser = Depends(require_capability("products.approve")),
):
    """Approve / reject / request-info on one pending product listing."""
    reason = (payload.reason or payload.review_notes or "").strip()
    if not reason:
        raise HTTPException(
            status_code=422,
            detail="A reason is required — it is recorded in the audit log",
        )
    product = db.get(Product, listing_id)
    if product is None:
        raise HTTPException(status_code=404, detail=f"Listing {listing_id} not found")
    decision = payload.decision.upper()
    if decision in {"APPROVE", "APPROVED"}:
        target = "APPROVED"
    elif decision in {"REJECT", "REJECTED"}:
        target = "REJECTED"
    else:
        target = "PENDING"
    previous = product.status
    product.status = target
    db.add(
        AuditLog(
            action=f"product.listing.{target.lower()}",
            entity_type="product",
            entity_id=product.id,
            user_id=admin.id,
            admin_user=admin.name or admin.username,
            details={"from": previous, "to": target, "decision": decision, "reason": reason},
        )
    )
    db.commit()
    db.refresh(product)
    return ok(to_dict(product, PRODUCT_FIELDS), message=f"Listing {target.lower()}")


# --- Product merge workflow (HIGH-RISK) --------------------------------------
# Candidate A + Candidate B -> compare -> Review -> Confirm Merge.
# The merge keeps the winner row, re-points variants + inventory at it, and
# archives the loser. Nothing is deleted silently: a reason is mandatory and
# every merge is an audit row naming both products.


class MergeCandidates(BaseModel):
    product_a_id: int
    product_b_id: int


class ProductMerge(BaseModel):
    winner_id: int
    loser_id: int
    reason: str

    @field_validator("reason")
    @classmethod
    def _reason_required(cls, v: str) -> str:
        if not (v or "").strip():
            raise ValueError("A reason is required — merges are never silent")
        return v.strip()


def _serialise_merge_candidate(p: Product) -> dict:
    return {
        **to_dict(p, PRODUCT_FIELDS),
        "variants": [
            to_dict(v, ["id", "name", "variant_name", "sku", "barcode", "price", "mrp", "status"])
            for v in (p.variants or [])
        ],
    }


@router.post("/products/merge/compare")
def merge_compare(
    payload: MergeCandidates,
    db: Session = Depends(get_db),
    _: AdminUser = Depends(get_current_admin),
):
    """Side-by-side compare of two merge candidates (Review step)."""
    if payload.product_a_id == payload.product_b_id:
        raise HTTPException(status_code=422, detail="Pick two different products to compare")
    a = db.get(Product, payload.product_a_id)
    b = db.get(Product, payload.product_b_id)
    if a is None or b is None:
        raise HTTPException(status_code=404, detail="One or both products not found")
    return ok({"candidate_a": _serialise_merge_candidate(a), "candidate_b": _serialise_merge_candidate(b)})


@router.post("/products/merge/confirm")
def merge_confirm(
    payload: ProductMerge,
    db: Session = Depends(get_db),
    admin: AdminUser = Depends(require_capability("products.merge")),
):
    """Confirm the merge: re-point children at the winner, archive the loser."""
    if payload.winner_id == payload.loser_id:
        raise HTTPException(status_code=422, detail="Winner and loser must differ")
    winner = db.get(Product, payload.winner_id)
    loser = db.get(Product, payload.loser_id)
    if winner is None or loser is None:
        raise HTTPException(status_code=404, detail="One or both products not found")
    moved_variants = 0
    for v in list(loser.variants or []):
        v.product_id = winner.id
        moved_variants += 1
    moved_inventory = 0
    inv_rows = db.scalars(select(ShopInventory).where(ShopInventory.product_id == loser.id)).all()
    for row in inv_rows:
        row.product_id = winner.id
        row.product_name = winner.name
        moved_inventory += 1
    winner.shop_count = (winner.shop_count or 0) + (loser.shop_count or 0)
    if not winner.image_url and loser.image_url:
        winner.image_url = loser.image_url
    loser.status = "ARCHIVED"
    db.add(
        AuditLog(
            action="product.merged",
            entity_type="product",
            entity_id=winner.id,
            user_id=admin.id,
            admin_user=admin.name or admin.username,
            details={
                "winner_id": winner.id,
                "loser_id": loser.id,
                "moved_variants": moved_variants,
                "moved_inventory": moved_inventory,
                "reason": payload.reason,
            },
        )
    )
    db.commit()
    db.refresh(winner)
    return ok(
        {
            "winner": to_dict(winner, PRODUCT_FIELDS),
            "loser_id": loser.id,
            "moved_variants": moved_variants,
            "moved_inventory": moved_inventory,
        },
        message=f"Product {loser.id} merged into {winner.id}",
    )


# --- Product quality control findings ----------------------------------------
@router.get("/products/{product_id}/variants")
def product_variants(
    product_id: int, db: Session = Depends(get_db), _: AdminUser = Depends(get_current_admin)
):
    if db.get(Product, product_id) is None:
        raise HTTPException(status_code=404, detail=f"Product {product_id} not found")
    rows = db.scalars(
        select(ProductVariant).where(ProductVariant.product_id == product_id)
    ).all()
    fields = [
        "id", "product_id", "name", "variant_name", "sku", "barcode",
        "mrp", "price", "unit", "status", "image_url", "created_at", "updated_at",
    ]
    return ok(paged([to_dict(r, fields) for r in rows], len(rows)))


# --- Categories ------------------------------------------------------------


@router.get("/categories")
def list_categories(
    page: Pagination = Depends(pagination),
    parent_id: int | None = None,
    db: Session = Depends(get_db),
    _: AdminUser = Depends(get_current_admin),
):
    stmt = select(Category)
    if page.search:
        stmt = stmt.where(Category.name.ilike(f"%{page.search}%"))
    if parent_id is not None:
        stmt = stmt.where(Category.parent_id == parent_id)
    total = db.scalar(select(func.count()).select_from(stmt.subquery())) or 0
    start, end = page.window()
    rows = db.scalars(stmt.order_by(Category.sort_order, Category.id).offset(start).limit(end - start)).all()
    fields = [
        "id", "name", "slug", "description", "icon_url", "parent_id",
        "sort_order", "is_active", "is_subcategory", "created_at",
        # Category configuration (Section: CATEGORY CONFIGURATION) — the
        # listing template and feature switches travel with every list row so
        # the taxonomy table and the configuration dialog see the same data.
        "required_fields", "optional_fields", "feature_capabilities",
    ]
    return ok(paged([to_dict(r, fields) for r in rows], total))


# --- Brands ----------------------------------------------------------------


CATEGORY_FIELDS = [
    "id", "name", "slug", "description", "icon_url", "parent_id",
    "sort_order", "is_active", "is_subcategory", "created_at",
    "required_fields", "optional_fields", "feature_capabilities",
]


# Canonical feature-capability keys a category can switch on. This is the
# authoritative vocabulary: the frontend renders it as a picker and the API
# rejects anything outside it, so "category rules" are defined once, on the
# server, and never only in the frontend.
FEATURE_CAPABILITY_CATALOG: list[dict[str, str]] = [
    {"key": "delivery", "label": "Delivery",
     "description": "Products in this category can be delivered to the shopper."},
    {"key": "pickup", "label": "Pickup",
     "description": "Shoppers can reserve and collect in person."},
    {"key": "installation", "label": "Installation",
     "description": "Merchants offer on-site installation for this category."},
    {"key": "prescription_required", "label": "Prescription required",
     "description": "Listings require a valid prescription reference (pharmacy)."},
    {"key": "barcode_scan", "label": "Barcode scan",
     "description": "Listings are expected to carry a scannable trade identifier."},
    {"key": "warranty", "label": "Warranty",
     "description": "Products may declare a warranty period."},
    {"key": "serial_tracking", "label": "Serial tracking",
     "description": "Each unit carries a unique serial the platform tracks."},
    {"key": "age_restricted", "label": "Age restricted",
     "description": "Purchase is limited to verified adults."},
    {"key": "bulk_pricing", "label": "Bulk pricing",
     "description": "Quantity-tier pricing is supported for this category."},
    {"key": "custom_order", "label": "Custom order",
     "description": "Shoppers may place made-to-order requests."},
]

FEATURE_CAPABILITY_KEYS: set[str] = {entry["key"] for entry in FEATURE_CAPABILITY_CATALOG}

# Sensible starting suggestions for the field pickers. Not a whitelist — a
# merchant attribute name is free-form snake_case — but the console offers these
# as one-click presets so operators converge on one vocabulary instead of
# inventing expiry vs expiry_date per category.
FIELD_PRESET_CATALOG: list[dict[str, str]] = [
    {"key": "expiry_date", "label": "Expiry date"},
    {"key": "batch_number", "label": "Batch number"},
    {"key": "brand", "label": "Brand"},
    {"key": "material", "label": "Material"},
    {"key": "dimensions", "label": "Dimensions"},
    {"key": "size", "label": "Size"},
    {"key": "shade", "label": "Shade"},
    {"key": "colour", "label": "Colour"},
    {"key": "warranty_months", "label": "Warranty months"},
    {"key": "compatibility", "label": "Compatibility"},
    {"key": "shelf_life", "label": "Shelf life"},
    {"key": "author", "label": "Author"},
    {"key": "isbn", "label": "ISBN"},
    {"key": "language", "label": "Language"},
    {"key": "cuisine", "label": "Cuisine"},
    {"key": "veg_only", "label": "Veg only"},
    {"key": "fssai_license", "label": "FSSAI licence"},
    {"key": "vehicle_type", "label": "Vehicle type"},
    {"key": "permit_number", "label": "Permit number"},
    {"key": "seating_capacity", "label": "Seating capacity"},
]


def _normalise_identifier_list(value: list[str] | None) -> list[str] | None:
    """Lowercase snake_case identifiers, de-duplicated, order preserved.

    Shared by create + update so a field list written on POST is byte-for-byte
    the same as one written on PATCH — the frontend diffing two configs must not
    see a phantom change caused by two normalisation code paths.
    """
    if value is None:
        return None
    normalised: list[str] = []
    for raw in value:
        if not isinstance(raw, str):
            raise ValueError("list entries must be strings")
        token = raw.strip().lower().replace(" ", "_").replace("-", "_")
        if not token:
            continue
        if not re.fullmatch(r"[a-z0-9_]{1,64}", token):
            raise ValueError(f"invalid entry {raw!r}: use letters, digits, underscores (max 64)")
        if token not in normalised:
            normalised.append(token)
    return normalised


class CategoryCreate(BaseModel):
    """Create one taxonomy node, including its listing template.

    The create route accepts the same configuration surface as PATCH so a
    category can be born fully specified (required/optional fields, feature
    capabilities, parent, status, sort order) rather than created blank and
    immediately edited.
    """

    name: str
    slug: str
    description: str | None = None
    parent_id: int | None = None
    sort_order: int = 0
    is_active: bool = True
    is_subcategory: bool = False
    required_fields: list[str] | None = None
    optional_fields: list[str] | None = None
    feature_capabilities: list[str] | None = None

    @field_validator("required_fields", "optional_fields", "feature_capabilities")
    @classmethod
    def _normalise_lists(cls, value: list[str] | None) -> list[str] | None:
        return _normalise_identifier_list(value)

    @field_validator("feature_capabilities")
    @classmethod
    def _known_capabilities(cls, value: list[str] | None) -> list[str] | None:
        if value is None:
            return None
        unknown = [v for v in value if v not in FEATURE_CAPABILITY_KEYS]
        if unknown:
            raise ValueError(f"unknown feature capabilities: {', '.join(unknown)}")
        return value


@router.get("/categories/config-catalog")
def category_config_catalog(_: AdminUser = Depends(get_current_admin)):
    """The server-authoritative vocabulary for category configuration.

    Declared BEFORE `/categories/{category_id}` for the same reason the product
    static routes are: FastAPI matches in registration order, so a later
    declaration would be parsed as category_id="config-catalog".

    The console reads this to populate its feature-capability picker and field
    presets instead of hardcoding the lists in the frontend.
    """
    return ok(
        {
            "feature_capabilities": FEATURE_CAPABILITY_CATALOG,
            "field_presets": FIELD_PRESET_CATALOG,
            "identifier_pattern": "^[a-z0-9_]{1,64}$",
        }
    )


@router.post("/categories")
def create_category(
    payload: CategoryCreate,
    db: Session = Depends(get_db),
    admin: AdminUser = Depends(require_capability("taxonomy.manage")),
):
    """Create one taxonomy node (Section 33 rules enforced server-side)."""
    # The forbidden-category rule lives here, not only in the UI: an admin
    # console could be bypassed by a direct API call, and the spec explicitly
    # forbids implementing category rules only in the frontend. "Grocery" and
    # "General Food" stay out of the catalog unless a future product decision
    # explicitly changes it.
    lowered = (payload.name or "").lower()
    if "grocery" in lowered or "general food" in lowered:
        raise HTTPException(
            status_code=422,
            detail="Grocery and General Food are excluded from the platform taxonomy by product decision.",
        )
    data = payload.model_dump()
    # A parent_id turns the node into a subcategory; keep the flag honest even
    # if the client forgot to send it. A root node is never a subcategory.
    if data.get("parent_id") is not None:
        if db.get(Category, data["parent_id"]) is None:
            raise HTTPException(status_code=422, detail="Parent category not found")
        data["is_subcategory"] = True
    else:
        data["is_subcategory"] = False
    row = Category(**data)
    db.add(row)
    db.commit()
    db.refresh(row)
    db.add(
        AuditLog(
            action="category.created",
            entity_type="category",
            entity_id=row.id,
            user_id=admin.id,
            admin_user=admin.name or admin.username,
            details={"name": row.name},
        )
    )
    db.commit()
    return ok(to_dict(row, CATEGORY_FIELDS), message="Category created")


@router.delete("/categories/{category_id}")
def delete_category(
    category_id: int,
    db: Session = Depends(get_db),
    admin: AdminUser = Depends(require_capability("taxonomy.manage")),
):
    row = db.get(Category, category_id)
    if row is None:
        raise HTTPException(status_code=404, detail=f"Category {category_id} not found")
    name = row.name
    db.delete(row)
    db.add(
        AuditLog(
            action="category.deleted",
            entity_type="category",
            entity_id=category_id,
            user_id=admin.id,
            admin_user=admin.name or admin.username,
            details={"name": name},
        )
    )
    db.commit()
    return ok({"id": category_id, "deleted": True}, message="Category deleted")


class CategoryUpdate(BaseModel):
    """Partial update of a taxonomy node's configuration.

    Category configuration is server-managed (spec: do not implement category
    rules only in the frontend) — the frontend sends the fields the operator
    changed and this model decides what is writable. `is_active` is the
    category's status; `sort_order` controls display ordering.

    The list fields configure the listing template for this category:
      - required_fields: attributes a merchant MUST provide (e.g. expiry_date
        for Pharmacy). Enforced server-side where the backend validates
        listings, not just displayed here.
      - optional_fields: attributes a merchant MAY provide.
      - feature_capabilities: platform features switched on for this category
        (e.g. "prescription_required", "delivery", "barcode_scan").
    Entries are normalised to lowercase snake_case identifiers, duplicates
    removed, and values are validated server-side below.
    """

    name: str | None = None
    slug: str | None = None
    description: str | None = None
    icon_url: str | None = None
    parent_id: int | None = None
    sort_order: int | None = None
    is_active: bool | None = None
    is_subcategory: bool | None = None
    required_fields: list[str] | None = None
    optional_fields: list[str] | None = None
    feature_capabilities: list[str] | None = None

    @field_validator("required_fields", "optional_fields", "feature_capabilities")
    @classmethod
    def _normalise_lists(cls, value: list[str] | None) -> list[str] | None:
        """Normalize identifier-style strings and reject bad entries early.

        Each entry must be a short identifier: lowercase letters, digits and
        underscores (spaces/hyphens are converted). Empty lists are valid —
        they clear the configuration.
        """
        return _normalise_identifier_list(value)

    @field_validator("feature_capabilities")
    @classmethod
    def _known_capabilities(cls, value: list[str] | None) -> list[str] | None:
        """Reject feature keys outside the server vocabulary.

        The console picks from `config-catalog`; enforcing the same set here
        means a direct API call cannot store a capability the platform does not
        understand. `_normalise_lists` runs first, so comparison is on tokens.
        """
        if value is None:
            return None
        unknown = [v for v in value if v not in FEATURE_CAPABILITY_KEYS]
        if unknown:
            raise ValueError(f"unknown feature capabilities: {', '.join(unknown)}")
        return value


@router.get("/categories/{category_id}")
def category_detail(
    category_id: int, db: Session = Depends(get_db), _: AdminUser = Depends(get_current_admin)
):
    """One taxonomy node. The product drill-down's Category/Subcategory tabs
    read this route; until now they borrowed the PATCH endpoint as a reader,
    which a deployment without PATCH permission served as 405."""
    row = db.get(Category, category_id)
    if row is None:
        raise HTTPException(status_code=404, detail=f"Category {category_id} not found")
    return ok(to_dict(row, CATEGORY_FIELDS))


@router.patch("/categories/{category_id}")
def update_category(
    category_id: int,
    payload: CategoryUpdate,
    db: Session = Depends(get_db),
    admin: AdminUser = Depends(require_capability("taxonomy.manage")),
):
    """Audited partial update: only the supplied fields are written."""
    row = db.get(Category, category_id)
    if row is None:
        raise HTTPException(status_code=404, detail=f"Category {category_id} not found")
    changes = payload.model_dump(exclude_unset=True)
    if not changes:
        raise HTTPException(status_code=422, detail="No fields to update")
    if "name" in changes and not (changes["name"] or "").strip():
        raise HTTPException(status_code=422, detail="Category name cannot be blank")
    if "slug" in changes and not (changes["slug"] or "").strip():
        raise HTTPException(status_code=422, detail="Category slug cannot be blank")
    # Parent / subcategory integrity: a node cannot parent itself, the parent
    # must exist, and the is_subcategory flag is derived from parent_id so the
    # two can never disagree. Reparenting to a root clears the flag.
    if "parent_id" in changes:
        parent_id = changes["parent_id"]
        if parent_id is not None:
            if parent_id == category_id:
                raise HTTPException(status_code=422, detail="A category cannot be its own parent")
            if db.get(Category, parent_id) is None:
                raise HTTPException(status_code=422, detail="Parent category not found")
            changes["is_subcategory"] = True
        else:
            changes["is_subcategory"] = False
    for field, value in changes.items():
        setattr(row, field, value)
    db.add(
        AuditLog(
            action="category.updated",
            entity_type="category",
            entity_id=row.id,
            user_id=admin.id,
            admin_user=admin.name or admin.username,
            details={"fields": list(changes.keys())},
        )
    )
    db.commit()
    db.refresh(row)
    return ok(to_dict(row, CATEGORY_FIELDS), message="Category updated")


BRAND_FIELDS = ["id", "name", "slug", "description", "logo_url", "is_active", "product_count", "created_at"]


class BrandCreate(BaseModel):
    name: str
    slug: str
    description: str | None = None
    is_active: bool = True


@router.post("/brands")
def create_brand(
    payload: BrandCreate,
    db: Session = Depends(get_db),
    admin: AdminUser = Depends(require_capability("taxonomy.manage")),
):
    row = Brand(**payload.model_dump())
    db.add(row)
    db.commit()
    db.refresh(row)
    db.add(
        AuditLog(
            action="brand.created",
            entity_type="brand",
            entity_id=row.id,
            user_id=admin.id,
            admin_user=admin.name or admin.username,
            details={"name": row.name},
        )
    )
    db.commit()
    return ok(to_dict(row, BRAND_FIELDS), message="Brand created")


@router.get("/brands/{brand_id}")
def brand_detail(
    brand_id: int, db: Session = Depends(get_db), _: AdminUser = Depends(get_current_admin)
):
    """One brand record. The product drill-down's Brand tab reads this route;
    until now it borrowed the create route as a reader."""
    row = db.get(Brand, brand_id)
    if row is None:
        raise HTTPException(status_code=404, detail=f"Brand {brand_id} not found")
    return ok(to_dict(row, BRAND_FIELDS))


class BrandUpdate(BaseModel):
    """Partial update of a brand's configuration (spec: manage name,
    description, status)."""

    name: str | None = None
    description: str | None = None
    logo_url: str | None = None
    is_active: bool | None = None


@router.patch("/brands/{brand_id}")
def update_brand(
    brand_id: int,
    payload: BrandUpdate,
    db: Session = Depends(get_db),
    admin: AdminUser = Depends(require_capability("taxonomy.manage")),
):
    """Audited partial update: only the supplied fields are written."""
    row = db.get(Brand, brand_id)
    if row is None:
        raise HTTPException(status_code=404, detail=f"Brand {brand_id} not found")
    changes = payload.model_dump(exclude_unset=True)
    if not changes:
        raise HTTPException(status_code=422, detail="No fields to update")
    if "name" in changes and not (changes["name"] or "").strip():
        raise HTTPException(status_code=422, detail="Brand name cannot be blank")
    for field, value in changes.items():
        setattr(row, field, value)
    db.add(
        AuditLog(
            action="brand.updated",
            entity_type="brand",
            entity_id=row.id,
            user_id=admin.id,
            admin_user=admin.name or admin.username,
            details={"fields": list(changes.keys())},
        )
    )
    db.commit()
    db.refresh(row)
    return ok(to_dict(row, BRAND_FIELDS), message="Brand updated")


@router.delete("/brands/{brand_id}")
def delete_brand(
    brand_id: int,
    db: Session = Depends(get_db),
    admin: AdminUser = Depends(require_capability("taxonomy.manage")),
):
    row = db.get(Brand, brand_id)
    if row is None:
        raise HTTPException(status_code=404, detail=f"Brand {brand_id} not found")
    db.add(
        AuditLog(
            action="brand.deleted",
            entity_type="brand",
            entity_id=brand_id,
            user_id=admin.id,
            admin_user=admin.name or admin.username,
            details={"name": row.name},
        )
    )
    db.delete(row)
    db.commit()
    return ok(None, message="Brand deleted")


@router.get("/brands")
def list_brands(
    page: Pagination = Depends(pagination),
    db: Session = Depends(get_db),
    _: AdminUser = Depends(get_current_admin),
):
    stmt = select(Brand)
    if page.search:
        stmt = stmt.where(Brand.name.ilike(f"%{page.search}%"))
    total = db.scalar(select(func.count()).select_from(stmt.subquery())) or 0
    start, end = page.window()
    rows = db.scalars(stmt.order_by(Brand.name).offset(start).limit(end - start)).all()
    fields = ["id", "name", "slug", "description", "logo_url", "is_active", "product_count", "created_at"]
    return ok(paged([to_dict(r, fields) for r in rows], total))


# --- Identifiers -----------------------------------------------------------


@router.get("/identifiers")
def list_identifiers(
    page: Pagination = Depends(pagination),
    db: Session = Depends(get_db),
    _: AdminUser = Depends(get_current_admin),
):
    """Barcodes that claim to point at a product, for catalog-hygiene checks."""
    stmt = select(Product).where(Product.barcode.isnot(None))
    if page.search:
        stmt = stmt.where(Product.barcode.ilike(f"%{page.search}%"))
    total = db.scalar(select(func.count()).select_from(stmt.subquery())) or 0
    start, end = page.window()
    rows = db.scalars(stmt.order_by(Product.id).offset(start).limit(end - start)).all()
    items = [
        {
            "id": r.id,
            "barcode": r.barcode,
            "product_id": r.id,
            "product_name": r.name,
            "status": r.status,
        }
        for r in rows
    ]
    return ok(paged(items, total))
