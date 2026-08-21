"""Product Master Catalog API routes — products, variants, brands, categories, identifiers, approvals."""

from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.responses import error_response, success_response
from app.database.session import get_async_db
from app.models.product import (
    Brand,
    Category,
    IdentifierType,
    ProductStatus,
    ProductVariant,
)
from app.schemas.catalog import (
    BarcodeRelationshipCreate,
    BarcodeRelationshipResponse,
    BrandCreate,
    BrandResponse,
    BrandUpdate,
    CategoryCreate,
    CategoryResponse,
    CategoryTreeResponse,
    CategoryUpdate,
    IdentifierLookupResponse,
    ProductApprovalCreate,
    ProductApprovalResponse,
    ProductApprovalReview,
    ProductDetailResponse,
    ProductIdentifierCreate,
    ProductIdentifierResponse,
    ProductImageCreate,
    ProductImageResponse,
    ProductMasterCreate,
    ProductMasterResponse,
    ProductMasterUpdate,
    ProductSearchDocument,
    ProductVariantCreate,
    ProductVariantResponse,
    ProductVariantUpdate,
    ShopProductCreate,
    ShopProductResponse,
)
from app.services import catalog_service

router = APIRouter(prefix="/catalog", tags=["catalog"])


# ── Categories ──────────────────────────────────────────────────────────────
@router.get("/categories")
async def list_categories(
    include_subcategories: bool = Query(True, description="Include subcategories in the tree"),
    db: AsyncSession = Depends(get_async_db),
):
    """List all categories with hierarchy."""
    categories = await catalog_service.get_category_tree(db)
    return success_response(
        data=[CategoryResponse.model_validate(c).model_dump() for c in categories]
    )


@router.get("/categories/tree")
async def get_category_tree(
    db: AsyncSession = Depends(get_async_db),
):
    """Get the full category hierarchy as a tree."""
    categories = await catalog_service.get_category_tree(db)

    # Build tree
    by_id = {c.id: CategoryTreeResponse.model_validate(c).model_dump() for c in categories}
    roots = []
    for cat in categories:
        node = by_id[cat.id]
        node["children"] = []
        if cat.parent_id and cat.parent_id in by_id:
            by_id[cat.parent_id]["children"].append(node)
        else:
            roots.append(node)
    return success_response(data=roots)


@router.post("/categories")
async def create_category(
    payload: CategoryCreate,
    db: AsyncSession = Depends(get_async_db),
):
    """Create a new category or subcategory."""
    try:
        category = await catalog_service.create_category(db, payload.model_dump())
        await db.commit()
        return success_response(
            data=CategoryResponse.model_validate(category).model_dump(),
            message="Category created",
            status_code=201,
        )
    except Exception as exc:  # noqa: BLE001
        await db.rollback()
        return error_response(message=str(exc), error_code="CATEGORY_CREATE_FAILED", status_code=400)


@router.get("/categories/{category_id}")
async def get_category(
    category_id: int,
    db: AsyncSession = Depends(get_async_db),
):
    """Get a single category by ID."""
    category = await db.get(Category, category_id)
    if category is None or category.is_deleted:
        return error_response(message="Category not found", error_code="CATEGORY_NOT_FOUND", status_code=404)
    return success_response(data=CategoryResponse.model_validate(category).model_dump())


@router.put("/categories/{category_id}")
async def update_category(
    category_id: int,
    payload: CategoryUpdate,
    db: AsyncSession = Depends(get_async_db),
):
    """Update a category."""
    category = await catalog_service.update_category(db, category_id, payload.model_dump(exclude_unset=True))
    if category is None:
        return error_response(message="Category not found", error_code="CATEGORY_NOT_FOUND", status_code=404)
    await db.commit()
    return success_response(data=CategoryResponse.model_validate(category).model_dump(), message="Category updated")


# ── Brands ──────────────────────────────────────────────────────────────────
@router.get("/brands")
async def list_brands(
    is_active: Optional[bool] = Query(None),
    db: AsyncSession = Depends(get_async_db),
):
    """List all brands."""
    from sqlalchemy import select

    stmt = select(Brand).where(Brand.is_deleted == False)  # noqa: E712
    if is_active is not None:
        stmt = stmt.where(Brand.is_active == is_active)
    result = await db.execute(stmt.order_by(Brand.name))
    brands = list(result.scalars().all())
    return success_response(data=[BrandResponse.model_validate(b).model_dump() for b in brands])


@router.post("/brands")
async def create_brand(
    payload: BrandCreate,
    db: AsyncSession = Depends(get_async_db),
):
    """Create a new brand."""
    try:
        brand = await catalog_service.create_brand(db, payload.model_dump())
        await db.commit()
        return success_response(
            data=BrandResponse.model_validate(brand).model_dump(),
            message="Brand created",
            status_code=201,
        )
    except Exception as exc:  # noqa: BLE001
        await db.rollback()
        return error_response(message=str(exc), error_code="BRAND_CREATE_FAILED", status_code=400)


@router.get("/brands/{brand_id}")
async def get_brand(
    brand_id: int,
    db: AsyncSession = Depends(get_async_db),
):
    """Get a single brand by ID."""
    brand = await db.get(Brand, brand_id)
    if brand is None or brand.is_deleted:
        return error_response(message="Brand not found", error_code="BRAND_NOT_FOUND", status_code=404)
    return success_response(data=BrandResponse.model_validate(brand).model_dump())


@router.put("/brands/{brand_id}")
async def update_brand(
    brand_id: int,
    payload: BrandUpdate,
    db: AsyncSession = Depends(get_async_db),
):
    """Update a brand."""
    brand = await catalog_service.update_brand(db, brand_id, payload.model_dump(exclude_unset=True))
    if brand is None:
        return error_response(message="Brand not found", error_code="BRAND_NOT_FOUND", status_code=404)
    await db.commit()
    return success_response(data=BrandResponse.model_validate(brand).model_dump(), message="Brand updated")


# ── Products ────────────────────────────────────────────────────────────────
@router.get("/products")
async def list_products(
    search: Optional[str] = Query(None, max_length=200),
    category_id: Optional[int] = Query(None),
    brand_id: Optional[int] = Query(None),
    status: Optional[ProductStatus] = Query(None),
    is_active: Optional[bool] = Query(None),
    page: int = Query(1, ge=1),
    limit: int = Query(20, ge=1, le=100),
    db: AsyncSession = Depends(get_async_db),
):
    """List products with optional filters."""
    skip = (page - 1) * limit
    products = await catalog_service.list_products(
        db,
        skip=skip,
        limit=limit,
        search=search,
        category_id=category_id,
        brand_id=brand_id,
        status=status,
        is_active=is_active,
    )
    return success_response(
        data={
            "items": [ProductMasterResponse.model_validate(p).model_dump() for p in products],
            "page": page,
            "limit": limit,
        }
    )


@router.post("/products")
async def create_product(
    payload: ProductMasterCreate,
    db: AsyncSession = Depends(get_async_db),
):
    """Create a new product master with nested variants, images, attributes, and identifiers."""
    try:
        product = await catalog_service.create_product(db, payload.model_dump())
        await db.commit()
        return success_response(
            data=ProductMasterResponse.model_validate(product).model_dump(),
            message="Product created",
            status_code=201,
        )
    except ValueError as exc:
        await db.rollback()
        return error_response(message=str(exc), error_code="DUPLICATE_PRODUCT", status_code=409)
    except Exception as exc:  # noqa: BLE001
        await db.rollback()
        return error_response(message=str(exc), error_code="PRODUCT_CREATE_FAILED", status_code=400)


@router.get("/products/{product_id}")
async def get_product(
    product_id: int,
    db: AsyncSession = Depends(get_async_db),
):
    """Get a product by ID with full details."""
    product = await catalog_service.get_product_detail(db, product_id)
    if product is None:
        return error_response(message="Product not found", error_code="PRODUCT_NOT_FOUND", status_code=404)
    return success_response(data=ProductDetailResponse.model_validate(product).model_dump())


@router.put("/products/{product_id}")
async def update_product(
    product_id: int,
    payload: ProductMasterUpdate,
    db: AsyncSession = Depends(get_async_db),
):
    """Update a product master."""
    try:
        product = await catalog_service.update_product(db, product_id, payload.model_dump(exclude_unset=True))
        if product is None:
            return error_response(message="Product not found", error_code="PRODUCT_NOT_FOUND", status_code=404)
        await db.commit()
        return success_response(data=ProductMasterResponse.model_validate(product).model_dump(), message="Product updated")
    except ValueError as exc:
        await db.rollback()
        return error_response(message=str(exc), error_code="DUPLICATE_PRODUCT", status_code=409)


# ── Product Variants ────────────────────────────────────────────────────────
@router.post("/products/{product_id}/variants")
async def create_variant(
    product_id: int,
    payload: ProductVariantCreate,
    db: AsyncSession = Depends(get_async_db),
):
    """Create a new variant for a product."""
    try:
        variant = await catalog_service.create_variant(db, product_id, payload.model_dump())
        await db.commit()
        return success_response(
            data=ProductVariantResponse.model_validate(variant).model_dump(),
            message="Variant created",
            status_code=201,
        )
    except Exception as exc:  # noqa: BLE001
        await db.rollback()
        return error_response(message=str(exc), error_code="VARIANT_CREATE_FAILED", status_code=400)


@router.get("/variants/{variant_id}")
async def get_variant(
    variant_id: int,
    db: AsyncSession = Depends(get_async_db),
):
    """Get a variant by ID."""
    variant = await db.get(ProductVariant, variant_id)
    if variant is None or variant.is_deleted:
        return error_response(message="Variant not found", error_code="VARIANT_NOT_FOUND", status_code=404)
    return success_response(data=ProductVariantResponse.model_validate(variant).model_dump())


@router.put("/variants/{variant_id}")
async def update_variant(
    variant_id: int,
    payload: ProductVariantUpdate,
    db: AsyncSession = Depends(get_async_db),
):
    """Update a variant."""
    variant = await catalog_service.update_variant(db, variant_id, payload.model_dump(exclude_unset=True))
    if variant is None:
        return error_response(message="Variant not found", error_code="VARIANT_NOT_FOUND", status_code=404)
    await db.commit()
    return success_response(data=ProductVariantResponse.model_validate(variant).model_dump(), message="Variant updated")


# ── Identifiers ─────────────────────────────────────────────────────────────
@router.get("/identifiers/lookup")
async def lookup_identifier(
    identifier_type: IdentifierType = Query(..., description="Type of identifier (EAN, UPC, ISBN, etc.)"),
    identifier_value: str = Query(..., min_length=1, max_length=100),
    db: AsyncSession = Depends(get_async_db),
):
    """Look up a product by its identifier (barcode, SKU, etc.)."""
    product = await catalog_service.lookup_by_identifier(db, identifier_type, identifier_value)
    if product is None:
        return error_response(
            message=f"No product found for {identifier_type} '{identifier_value}'",
            error_code="IDENTIFIER_NOT_FOUND",
            status_code=404,
        )
    return success_response(
        data=IdentifierLookupResponse(
            product=ProductMasterResponse.model_validate(product).model_dump(),
            identifier_type=identifier_type,
            identifier_value=identifier_value,
            is_primary=True,
        ).model_dump()
    )


@router.post("/products/{product_id}/identifiers")
async def add_identifier(
    product_id: int,
    payload: ProductIdentifierCreate,
    db: AsyncSession = Depends(get_async_db),
):
    """Add an identifier to a product."""
    try:
        identifier = await catalog_service.add_identifier(db, product_id, payload.model_dump())
        await db.commit()
        return success_response(
            data=identifier.id,
            message="Identifier added",
            status_code=201,
        )
    except Exception as exc:  # noqa: BLE001
        await db.rollback()
        return error_response(message=str(exc), error_code="IDENTIFIER_ADD_FAILED", status_code=400)


# ── Barcode Relationships ───────────────────────────────────────────────────
@router.post("/products/{product_id}/barcodes")
async def create_barcode_relationship(
    product_id: int,
    payload: BarcodeRelationshipCreate,
    db: AsyncSession = Depends(get_async_db),
):
    """Create a barcode relationship for a product."""
    try:
        rel = await catalog_service.create_barcode_relationship(db, product_id, payload.model_dump())
        await db.commit()
        return success_response(
            data=BarcodeRelationshipResponse.model_validate(rel).model_dump(),
            message="Barcode relationship created",
            status_code=201,
        )
    except Exception as exc:  # noqa: BLE001
        await db.rollback()
        return error_response(message=str(exc), error_code="BARCODE_RELATIONSHIP_CREATE_FAILED", status_code=400)


# ── Approval Workflow ───────────────────────────────────────────────────────
@router.post("/approvals")
async def submit_for_approval(
    payload: ProductApprovalCreate,
    db: AsyncSession = Depends(get_async_db),
):
    """Submit a product for approval review."""
    try:
        approval = await catalog_service.submit_for_approval(
            db,
            product_master_id=payload.product_master_id,
            submitted_by=1,  # TODO: get from auth context
            submission_data=payload.submission_data,
        )
        await db.commit()
        return success_response(
            data=ProductApprovalResponse.model_validate(approval).model_dump(),
            message="Product submitted for approval",
            status_code=201,
        )
    except ValueError as exc:
        await db.rollback()
        return error_response(message=str(exc), error_code="PRODUCT_NOT_FOUND", status_code=404)


@router.post("/approvals/{approval_id}/review")
async def review_approval(
    approval_id: int,
    payload: ProductApprovalReview,
    db: AsyncSession = Depends(get_async_db),
):
    """Review a product approval request."""
    try:
        approval = await catalog_service.review_approval(
            db,
            approval_id=approval_id,
            reviewer_id=1,  # TODO: get from auth context
            decision=payload.status,
            review_notes=payload.review_notes,
        )
        if approval is None:
            return error_response(message="Approval not found", error_code="APPROVAL_NOT_FOUND", status_code=404)
        await db.commit()
        return success_response(
            data=ProductApprovalResponse.model_validate(approval).model_dump(),
            message="Approval reviewed",
        )
    except Exception as exc:  # noqa: BLE001
        await db.rollback()
        return error_response(message=str(exc), error_code="APPROVAL_REVIEW_FAILED", status_code=400)


# ── Search Index ────────────────────────────────────────────────────────────
@router.get("/products/{product_id}/search-document")
async def get_search_document(
    product_id: int,
    db: AsyncSession = Depends(get_async_db),
):
    """Prepare a product for search indexing."""
    product = await catalog_service.get_product_detail(db, product_id)
    if product is None:
        return error_response(message="Product not found", error_code="PRODUCT_NOT_FOUND", status_code=404)
    doc = await catalog_service.prepare_search_document(db, product)
    await db.commit()
    return success_response(data=doc, message="Search document prepared")


# ── Shop Products ───────────────────────────────────────────────────────────
@router.post("/shop-products")
async def create_shop_product(
    payload: ShopProductCreate,
    db: AsyncSession = Depends(get_async_db),
):
    """Create a shop product linking a shop to a product master."""
    try:
        shop_product = await catalog_service.create_shop_product(db, payload.model_dump())
        await db.commit()
        return success_response(
            data=ShopProductResponse.model_validate(shop_product).model_dump(),
            message="Shop product created",
            status_code=201,
        )
    except Exception as exc:  # noqa: BLE001
        await db.rollback()
        return error_response(message=str(exc), error_code="SHOP_PRODUCT_CREATE_FAILED", status_code=400)


@router.get("/shop-products")
async def list_shop_products(
    shop_id: Optional[int] = Query(None),
    product_master_id: Optional[int] = Query(None),
    page: int = Query(1, ge=1),
    limit: int = Query(20, ge=1, le=100),
    db: AsyncSession = Depends(get_async_db),
):
    """List shop products with optional filters."""
    skip = (page - 1) * limit
    shop_products = await catalog_service.list_shop_products(
        db,
        shop_id=shop_id,
        product_master_id=product_master_id,
        skip=skip,
        limit=limit,
    )
    return success_response(
        data={
            "items": [ShopProductResponse.model_validate(sp).model_dump() for sp in shop_products],
            "page": page,
            "limit": limit,
        }
    )