# app/repositories/product_repository.py
"""Async repository for product catalog operations."""

from typing import List, Optional

from sqlalchemy import select, func, and_, or_
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.models.product import (
    ProductMaster,
    ProductStatus,
    ShopProduct,
    ShopProductStatus,
    Inventory,
    StockStatus,
    PriceHistory,
    Offer,
    OfferStatus,
    Category,
    Brand,
)
from app.models.shop import Shop, ShopStatus


class ProductRepository:
    """Async repository for product catalog operations."""

    def __init__(self, session: AsyncSession):
        self.session = session

    async def get_product_by_id(self, product_id: int) -> Optional[ProductMaster]:
        """Fetch a product master by ID with related data."""
        stmt = (
            select(ProductMaster)
            .where(
                ProductMaster.id == product_id,
                ProductMaster.is_deleted == False,  # noqa: E712
            )
            .options(
                selectinload(ProductMaster.brand),
                selectinload(ProductMaster.category),
                selectinload(ProductMaster.identifiers),
                selectinload(ProductMaster.barcode_relationships),
                selectinload(ProductMaster.variants),
            )
        )
        result = await self.session.execute(stmt)
        return result.scalar_one_or_none()

    async def get_product_by_barcode(self, barcode: str) -> Optional[ProductMaster]:
        """Fetch a product master by barcode value."""
        stmt = (
            select(ProductMaster)
            .where(
                ProductMaster.is_deleted == False,  # noqa: E712
            )
            .options(
                selectinload(ProductMaster.identifiers),
                selectinload(ProductMaster.barcode_relationships),
            )
        )
        result = await self.session.execute(stmt)
        products = result.scalars().all()

        for product in products:
            # Check identifiers
            for ident in product.identifiers:
                if ident.is_active and ident.identifier_value == barcode:
                    return product
            # Check barcode relationships
            for br in product.barcode_relationships:
                if br.is_active and br.barcode == barcode:
                    return product
        return None

    async def search_products(
        self,
        query: str,
        *,
        category_id: Optional[int] = None,
        brand_id: Optional[int] = None,
        limit: int = 20,
        offset: int = 0,
    ) -> tuple[List[ProductMaster], int]:
        """Search products by name, brand, or category with pagination."""
        search_pattern = f"%{query}%"

        # Build base query
        stmt = (
            select(ProductMaster)
            .where(
                ProductMaster.is_deleted == False,  # noqa: E712
                ProductMaster.status == ProductStatus.APPROVED,
                or_(
                    ProductMaster.name.ilike(search_pattern),
                    ProductMaster.description.ilike(search_pattern),
                ),
            )
            .options(
                selectinload(ProductMaster.brand),
                selectinload(ProductMaster.category),
            )
        )

        # Apply filters
        if category_id:
            stmt = stmt.where(ProductMaster.category_id == category_id)
        if brand_id:
            stmt = stmt.where(ProductMaster.brand_id == brand_id)

        # Get total count
        count_stmt = select(func.count()).select_from(stmt.subquery())
        count_result = await self.session.execute(count_stmt)
        total = count_result.scalar() or 0

        # Apply pagination
        stmt = stmt.offset(offset).limit(limit)
        result = await self.session.execute(stmt)
        products = list(result.scalars().all())

        return products, total

    async def get_categories(self) -> List[Category]:
        """Get all active categories."""
        stmt = (
            select(Category)
            .where(
                Category.is_active == True,  # noqa: E712
                Category.is_deleted == False,  # noqa: E712
            )
            .order_by(Category.sort_order, Category.name)
        )
        result = await self.session.execute(stmt)
        return list(result.scalars().all())

    async def get_brands(self) -> List[Brand]:
        """Get all active brands."""
        stmt = (
            select(Brand)
            .where(
                Brand.is_active == True,  # noqa: E712
                Brand.is_deleted == False,  # noqa: E712
            )
            .order_by(Brand.name)
        )
        result = await self.session.execute(stmt)
        return list(result.scalars().all())


def get_product_repository(session: AsyncSession) -> ProductRepository:
    """Factory function to create a ProductRepository instance."""
    return ProductRepository(session)
