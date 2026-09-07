"""Product Master Catalog service — business logic for products, variants, brands, categories, identifiers, and approvals."""

import json
import re
from datetime import datetime, timezone
from typing import Any, Optional

from sqlalchemy import or_, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.core.logging import get_logger
from app.models.admin import ProductApproval, ApprovalStatus
from app.models.product import (
    BarcodeRelationship,
    Brand,
    Category,
    IdentifierType,
    ProductAttribute,
    ProductAttributeValue,
    ProductIdentifier,
    ProductImage,
    ProductMaster,
    ProductStatus,
    ProductVariant,
    ShopProduct,
    ShopProductStatus,
)

logger = get_logger("app.services.catalog")


# ── Helpers ────────────────────────────────────────────────────────────────
def slugify(value: str) -> str:
    """Convert a string to a URL-safe slug."""
    value = value.strip().lower()
    value = re.sub(r"[^a-z0-9]+", "-", value)
    value = re.sub(r"-+", "-", value).strip("-")
    return value


def normalize_identifier(value: str) -> str:
    """Normalize an identifier value (strip whitespace, uppercase)."""
    return value.strip().upper()


# ── Duplicate detection ─────────────────────────────────────────────────────
async def find_duplicate_product(
    db: AsyncSession,
    *,
    name: Optional[str] = None,
    brand_id: Optional[int] = None,
    identifiers: Optional[list[dict]] = None,
    exclude_product_id: Optional[int] = None,
) -> Optional[ProductMaster]:
    """
    Find an existing product that matches the given product.

    Matching rules (in priority order):
      1. Exact identifier match (EAN/UPC/GTIN/ISBN etc.)
      2. Exact name + brand match
      3. Fuzzy name match (case-insensitive, normalized)
    """
    # Rule 1: Identifier match
    if identifiers:
        for ident in identifiers:
            id_type = ident.get("identifier_type")
            id_value = normalize_identifier(ident.get("identifier_value", ""))
            if not id_value:
                continue
            stmt = (
                select(ProductMaster)
                .join(ProductIdentifier)
                .where(
                    ProductIdentifier.identifier_type == id_type,
                    ProductIdentifier.identifier_value == id_value,
                    ProductIdentifier.is_active == True,  # noqa: E712
                )
            )
            if exclude_product_id:
                stmt = stmt.where(ProductMaster.id != exclude_product_id)
            result = await db.execute(stmt)
            existing = result.scalars().first()
            if existing:
                return existing

    # Rule 2: Exact name + brand match
    if name and brand_id:
        stmt = select(ProductMaster).where(
            ProductMaster.name == name.strip(),
            ProductMaster.brand_id == brand_id,
        )
        if exclude_product_id:
            stmt = stmt.where(ProductMaster.id != exclude_product_id)
        result = await db.execute(stmt)
        existing = result.scalars().first()
        if existing:
            return existing

    # Rule 3: Fuzzy name match (normalized)
    if name:
        normalized = slugify(name)
        stmt = select(ProductMaster).where(
            ProductMaster.slug == normalized,
        )
        if exclude_product_id:
            stmt = stmt.where(ProductMaster.id != exclude_product_id)
        result = await db.execute(stmt)
        existing = result.scalars().first()
        if existing:
            return existing

    return None


# ── Category service ────────────────────────────────────────────────────────
async def create_category(db: AsyncSession, data: dict) -> Category:
    """Create a new category (or subcategory if parent_id is set)."""
    slug = data.get("slug") or slugify(data["name"])
    category = Category(
        name=data["name"],
        slug=slug,
        description=data.get("description"),
        icon_url=data.get("icon_url"),
        parent_id=data.get("parent_id"),
        sort_order=data.get("sort_order", 0),
        is_active=data.get("is_active", True),
        is_subcategory=data.get("parent_id") is not None,
    )
    db.add(category)
    await db.flush()
    return category


async def update_category(db: AsyncSession, category_id: int, data: dict) -> Optional[Category]:
    """Update a category."""
    category = await db.get(Category, category_id)
    if category is None:
        return None
    for key, value in data.items():
        if value is not None and hasattr(category, key):
            setattr(category, key, value)
    if "parent_id" in data:
        category.is_subcategory = data["parent_id"] is not None
    await db.flush()
    return category


async def get_category_tree(db: AsyncSession) -> list[Category]:
    """Return all categories with their hierarchy."""
    result = await db.execute(
        select(Category)
        .where(Category.is_deleted == False)  # noqa: E712
        .order_by(Category.sort_order, Category.name)
    )
    return list(result.scalars().all())


# ── Brand service ───────────────────────────────────────────────────────────
async def create_brand(db: AsyncSession, data: dict) -> Brand:
    """Create a new brand."""
    slug = data.get("slug") or slugify(data["name"])
    brand = Brand(
        name=data["name"],
        slug=slug,
        description=data.get("description"),
        logo_url=data.get("logo_url"),
        is_active=data.get("is_active", True),
    )
    db.add(brand)
    await db.flush()
    return brand


async def update_brand(db: AsyncSession, brand_id: int, data: dict) -> Optional[Brand]:
    """Update a brand."""
    brand = await db.get(Brand, brand_id)
    if brand is None:
        return None
    for key, value in data.items():
        if value is not None and hasattr(brand, key):
            setattr(brand, key, value)
    await db.flush()
    return brand


# ── Product Master service ──────────────────────────────────────────────────
async def create_product(db: AsyncSession, data: dict, created_by: Optional[int] = None) -> ProductMaster:
    """Create a new product master with nested variants, images, attributes, and identifiers."""
    # Check for duplicates first
    duplicate = await find_duplicate_product(
        db,
        name=data.get("name"),
        brand_id=data.get("brand_id"),
        identifiers=data.get("identifiers"),
    )
    if duplicate:
        raise ValueError(f"Duplicate product found: {duplicate.name} (id={duplicate.id})")

    slug = data.get("slug") or slugify(data["name"])

    product = ProductMaster(
        name=data["name"],
        slug=slug,
        description=data.get("description"),
        short_description=data.get("short_description"),
        category_id=data.get("category_id"),
        subcategory_id=data.get("subcategory_id"),
        brand_id=data.get("brand_id"),
        status=ProductStatus.DRAFT,
        is_active=data.get("is_active", True),
        is_featured=data.get("is_featured", False),
        is_searchable=data.get("is_searchable", True),
        base_unit=data.get("base_unit"),
        base_quantity=data.get("base_quantity"),
    )
    db.add(product)
    await db.flush()

    # Create identifiers
    for ident in data.get("identifiers", []):
        db.add(
            ProductIdentifier(
                product_master_id=product.id,
                identifier_type=ident["identifier_type"],
                identifier_value=normalize_identifier(ident["identifier_value"]),
                is_primary=ident.get("is_primary", False),
            )
        )

    # Create attributes and values
    for attr in data.get("attributes", []):
        attribute = ProductAttribute(
            product_master_id=product.id,
            name=attr["name"],
            is_variant_defining=attr.get("is_variant_defining", False),
            sort_order=attr.get("sort_order", 0),
        )
        db.add(attribute)
        await db.flush()
        for val in attr.get("values", []):
            db.add(
                ProductAttributeValue(
                    attribute_id=attribute.id,
                    value=val["value"],
                    sort_order=val.get("sort_order", 0),
                )
            )

    # Create variants
    for variant in data.get("variants", []):
        db.add(
            ProductVariant(
                product_master_id=product.id,
                sku=variant["sku"],
                name=variant["name"],
                description=variant.get("description"),
                attributes_json=variant.get("attributes_json"),
                is_active=variant.get("is_active", True),
                sort_order=variant.get("sort_order", 0),
            )
        )

    # Create images
    for img in data.get("images", []):
        db.add(
            ProductImage(
                product_master_id=product.id,
                variant_id=img.get("variant_id"),
                image_url=img["image_url"],
                thumbnail_url=img.get("thumbnail_url"),
                alt_text=img.get("alt_text"),
                sort_order=img.get("sort_order", 0),
                is_primary=img.get("is_primary", False),
            )
        )

    await db.flush()
    return product


async def update_product(db: AsyncSession, product_id: int, data: dict, updated_by: Optional[int] = None) -> Optional[ProductMaster]:
    """Update a product master."""
    product = await db.get(ProductMaster, product_id)
    if product is None:
        return None

    # Check for duplicates on update
    duplicate = await find_duplicate_product(
        db,
        name=data.get("name", product.name),
        brand_id=data.get("brand_id", product.brand_id),
        identifiers=data.get("identifiers"),
        exclude_product_id=product_id,
    )
    if duplicate:
        raise ValueError(f"Duplicate product found: {duplicate.name} (id={duplicate.id})")

    for key, value in data.items():
        if value is not None and hasattr(product, key):
            setattr(product, key, value)

    await db.flush()
    return product


async def get_product_detail(db: AsyncSession, product_id: int) -> Optional[ProductMaster]:
    """Get a product with all nested relationships loaded."""
    stmt = (
        select(ProductMaster)
        .where(ProductMaster.id == product_id, ProductMaster.is_deleted == False)  # noqa: E712
        .options(
            selectinload(ProductMaster.category),
            selectinload(ProductMaster.subcategory),
            selectinload(ProductMaster.brand),
            selectinload(ProductMaster.variants),
            selectinload(ProductMaster.images),
            selectinload(ProductMaster.attributes).selectinload(ProductAttribute.values),
            selectinload(ProductMaster.identifiers),
            selectinload(ProductMaster.barcode_relationships),
        )
    )
    result = await db.execute(stmt)
    return result.scalars().first()


async def list_products(
    db: AsyncSession,
    *,
    skip: int = 0,
    limit: int = 100,
    search: Optional[str] = None,
    category_id: Optional[int] = None,
    brand_id: Optional[int] = None,
    status: Optional[ProductStatus] = None,
    is_active: Optional[bool] = None,
) -> list[ProductMaster]:
    """List products with optional filters."""
    stmt = select(ProductMaster).where(ProductMaster.is_deleted == False)  # noqa: E712
    if search:
        pattern = f"%{search.strip()}%"
        stmt = stmt.where(
            or_(
                ProductMaster.name.ilike(pattern),
                ProductMaster.slug.ilike(pattern),
                ProductMaster.description.ilike(pattern),
            )
        )
    if category_id:
        stmt = stmt.where(ProductMaster.category_id == category_id)
    if brand_id:
        stmt = stmt.where(ProductMaster.brand_id == brand_id)
    if status:
        stmt = stmt.where(ProductMaster.status == status)
    if is_active is not None:
        stmt = stmt.where(ProductMaster.is_active == is_active)

    stmt = stmt.order_by(ProductMaster.created_at.desc()).offset(skip).limit(limit)
    result = await db.execute(stmt)
    return list(result.scalars().all())


# ── Variant service ─────────────────────────────────────────────────────────
async def create_variant(db: AsyncSession, product_master_id: int, data: dict) -> ProductVariant:
    """Create a new variant for a product."""
    variant = ProductVariant(
        product_master_id=product_master_id,
        sku=data["sku"],
        name=data["name"],
        description=data.get("description"),
        attributes_json=data.get("attributes_json"),
        is_active=data.get("is_active", True),
        sort_order=data.get("sort_order", 0),
    )
    db.add(variant)
    await db.flush()
    return variant


async def update_variant(db: AsyncSession, variant_id: int, data: dict) -> Optional[ProductVariant]:
    """Update a variant."""
    variant = await db.get(ProductVariant, variant_id)
    if variant is None:
        return None
    for key, value in data.items():
        if value is not None and hasattr(variant, key):
            setattr(variant, key, value)
    await db.flush()
    return variant


# ── Identifier service ──────────────────────────────────────────────────────
async def lookup_by_identifier(
    db: AsyncSession,
    identifier_type: IdentifierType,
    identifier_value: str,
) -> Optional[ProductMaster]:
    """Look up a product by its identifier (barcode, SKU, etc.)."""
    value = normalize_identifier(identifier_value)
    stmt = (
        select(ProductMaster)
        .join(ProductIdentifier)
        .where(
            ProductIdentifier.identifier_type == identifier_type,
            ProductIdentifier.identifier_value == value,
            ProductIdentifier.is_active == True,  # noqa: E712
            ProductMaster.is_deleted == False,  # noqa: E712
        )
        .options(
            selectinload(ProductMaster.category),
            selectinload(ProductMaster.brand),
            selectinload(ProductMaster.variants),
            selectinload(ProductMaster.images),
            selectinload(ProductMaster.identifiers),
        )
    )
    result = await db.execute(stmt)
    return result.scalars().first()


async def add_identifier(db: AsyncSession, product_master_id: int, data: dict) -> ProductIdentifier:
    """Add an identifier to a product."""
    identifier = ProductIdentifier(
        product_master_id=product_master_id,
        identifier_type=data["identifier_type"],
        identifier_value=normalize_identifier(data["identifier_value"]),
        is_primary=data.get("is_primary", False),
    )
    db.add(identifier)
    await db.flush()
    return identifier


# ── Barcode relationship service ────────────────────────────────────────────
async def create_barcode_relationship(db: AsyncSession, product_master_id: int, data: dict) -> BarcodeRelationship:
    """Create a barcode relationship (e.g., alternate barcode, parent-child)."""
    rel = BarcodeRelationship(
        product_master_id=product_master_id,
        barcode=normalize_identifier(data["barcode"]),
        relationship_type=data["relationship_type"],
        related_product_master_id=data.get("related_product_master_id"),
        notes=data.get("notes"),
    )
    db.add(rel)
    await db.flush()
    return rel


# ── Approval workflow ───────────────────────────────────────────────────────
async def submit_for_approval(
    db: AsyncSession,
    product_master_id: int,
    submitted_by: int,
    submission_data: Optional[dict] = None,
) -> ProductApproval:
    """Submit a product for approval review."""
    product = await db.get(ProductMaster, product_master_id)
    if product is None:
        raise ValueError("Product not found")

    product.status = ProductStatus.PENDING_REVIEW

    approval = ProductApproval(
        product_master_id=product_master_id,
        submitted_by=submitted_by,
        status=ApprovalStatus.PENDING,
        requested_by=submitted_by,
        submitted_at=datetime.now(timezone.utc),
        submission_data=submission_data,
    )
    db.add(approval)
    await db.flush()
    return approval


async def review_approval(
    db: AsyncSession,
    approval_id: int,
    reviewer_id: int,
    decision: str,
    review_notes: Optional[str] = None,
) -> Optional[ProductApproval]:
    """Review a product approval request."""
    approval = await db.get(ProductApproval, approval_id)
    if approval is None:
        return None

    approval.status = ApprovalStatus(decision)
    approval.reviewed_by = reviewer_id
    approval.review_notes = review_notes
    approval.reviewed_at = datetime.now(timezone.utc)

    product = await db.get(ProductMaster, approval.product_master_id)
    if product:
        if decision == ApprovalStatus.APPROVED.value:
            product.status = ProductStatus.APPROVED
            product.approved_by = reviewer_id
            product.approved_at = datetime.now(timezone.utc)
            product.rejection_reason = None
        elif decision == ApprovalStatus.REJECTED.value:
            product.status = ProductStatus.REJECTED
            product.rejected_by = reviewer_id
            product.rejected_at = datetime.now(timezone.utc)
            product.rejection_reason = review_notes

    await db.flush()
    return approval


# ── Search index preparation ────────────────────────────────────────────────
async def prepare_search_document(db: AsyncSession, product: ProductMaster) -> dict:
    """Prepare a product for search indexing (e.g., Elasticsearch, Meilisearch)."""
    # Ensure relationships are loaded
    if not product.identifiers:
        result = await db.execute(
            select(ProductIdentifier).where(ProductIdentifier.product_master_id == product.id)
        )
        product.identifiers = list(result.scalars().all())

    if not product.attributes:
        result = await db.execute(
            select(ProductAttribute)
            .where(ProductAttribute.product_master_id == product.id)
            .options(selectinload(ProductAttribute.values))
        )
        product.attributes = list(result.scalars().all())

    if not product.brand:
        product.brand = await db.get(Brand, product.brand_id) if product.brand_id else None

    if not product.category:
        product.category = await db.get(Category, product.category_id) if product.category_id else None

    if not product.subcategory:
        product.subcategory = await db.get(Category, product.subcategory_id) if product.subcategory_id else None

    # Build attributes dict
    attributes: dict[str, list[str]] = {}
    for attr in product.attributes:
        attributes[attr.name] = [v.value for v in attr.values]

    doc = {
        "id": product.id,
        "name": product.name,
        "slug": product.slug,
        "description": product.description,
        "short_description": product.short_description,
        "brand": product.brand.name if product.brand else None,
        "category": product.category.name if product.category else None,
        "subcategory": product.subcategory.name if product.subcategory else None,
        "identifiers": [i.identifier_value for i in product.identifiers],
        "attributes": attributes,
        "is_searchable": product.is_searchable,
        "status": product.status.value,
        "updated_at": product.updated_at.isoformat() if product.updated_at else None,
    }

    # Store the prepared document in search_metadata
    product.search_metadata = json.dumps(doc)
    product.search_updated_at = datetime.now(timezone.utc)
    await db.flush()

    return doc


# ── Shop Product service ────────────────────────────────────────────────────
async def create_shop_product(db: AsyncSession, data: dict) -> ShopProduct:
    """Create a shop product linking a shop to a product master."""
    shop_product = ShopProduct(
        shop_id=data["shop_id"],
        product_master_id=data["product_master_id"],
        variant_id=data.get("variant_id"),
        status=ShopProductStatus.PENDING_REVIEW,
        price=data["price"],
        mrp=data.get("mrp"),
        is_available=data.get("is_available", True),
        is_featured=data.get("is_featured", False),
        is_visible=data.get("is_visible", True),
        stock_status=data.get("stock_status", "IN_STOCK"),
    )
    db.add(shop_product)
    await db.flush()
    return shop_product


async def list_shop_products(
    db: AsyncSession,
    *,
    shop_id: Optional[int] = None,
    product_master_id: Optional[int] = None,
    skip: int = 0,
    limit: int = 100,
) -> list[ShopProduct]:
    """List shop products with optional filters."""
    stmt = select(ShopProduct).where(ShopProduct.is_deleted == False)  # noqa: E712
    if shop_id:
        stmt = stmt.where(ShopProduct.shop_id == shop_id)
    if product_master_id:
        stmt = stmt.where(ShopProduct.product_master_id == product_master_id)
    stmt = stmt.offset(skip).limit(limit)
    result = await db.execute(stmt)
    return list(result.scalars().all())