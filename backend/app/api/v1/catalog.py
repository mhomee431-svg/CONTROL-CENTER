"""Products, categories, brands and identifiers."""

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import func, or_, select
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.core.pagination import Pagination, pagination
from app.core.responses import ok, paged
from app.core.serializers import to_dict
from app.core.security import get_current_admin
from app.models import AdminUser, Brand, Category, Product, ProductVariant

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
        from app.models import ShopInventory

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


@router.get("/products/{product_id}")
def product_detail(
    product_id: int, db: Session = Depends(get_db), _: AdminUser = Depends(get_current_admin)
):
    product = db.get(Product, product_id)
    if product is None:
        raise HTTPException(status_code=404, detail=f"Product {product_id} not found")
    return ok(to_dict(product, PRODUCT_FIELDS))


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
    ]
    return ok(paged([to_dict(r, fields) for r in rows], total))


# --- Brands ----------------------------------------------------------------


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
