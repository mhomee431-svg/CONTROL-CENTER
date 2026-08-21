# app/api/routes/products.py
from fastapi import APIRouter, Depends, HTTPException, status
from typing import Optional

from app.schemas.product import ProductMaster, ProductComparisonResponse
from app.repositories.product_repository import MockProductRepository, get_product_repository

# In a real application, the router prefix would be defined once in main.py
# but for module clarity, we can restate it.
router = APIRouter(
    prefix="/products",
    tags=["products"]
)

@router.get(
    "/{barcode}",
    response_model=ProductMaster,
    summary="Get Master Product via Barcode",
    description="Fetch the master details of a product by scanning its barcode.",
)
async def get_product_by_barcode(
    barcode: str,
    repo: MockProductRepository = Depends(get_product_repository)
):
    """
    Retrieves the global master details of a product using its barcode.
    This is typically used when a user scans a physical product.

    - **barcode**: The EAN or UPC barcode of the product.
    """
    # The dependency injection system provides the repository instance.
    # In a real setup, `get_product_repository` might return a `DatabaseProductRepository`
    # which requires an `AsyncSession`. `Depends()` would handle that.
    product = await repo.get_product_by_barcode(barcode)

    if not product:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Product with barcode '{barcode}' not found in the global master.",
        )
    return product


@router.get(
    "/{product_id}/compare",
    response_model=ProductComparisonResponse,
    summary="Compare Product Prices at Nearby Shops",
    description="Get master product details along with a list of nearby shops that sell it, sorted by distance or price.",
)
async def compare_product_prices(
    product_id: int,
    repo: MockProductRepository = Depends(get_product_repository)
):
    """
    Performs the core "hyperlocal" comparison. It fetches the master product
    and then finds all nearby shops in the inventory that stock this product,
    returning their prices, stock status, and distance.

    - **product_id**: The unique identifier for the master product.
    """
    # The repository abstracts away the complex logic of joining Products,
    # Inventories, and Shops tables, and running geospatial queries.
    comparison_data = await repo.get_product_comparison(product_id)

    if not comparison_data:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Product with id '{product_id}' not found for comparison.",
        )

    # The response model `ProductComparisonResponse` automatically structures the data.
    return comparison_data
