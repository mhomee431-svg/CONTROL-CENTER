# app/schemas/product.py
from pydantic import BaseModel, Field
from typing import List, Optional
from enum import Enum


class AvailabilityStatus(str, Enum):
    """
    Enum for inventory availability status.
    """
    IN_STOCK = "In Stock"
    LIMITED = "Limited"
    OUT_OF_STOCK = "Out of Stock"


class ProductMaster(BaseModel):
    """
    Represents the global master details of a product.
    This is the single source of truth for a product's static information.
    """
    id: int
    name: str
    brand: str
    category: str
    barcode: str
    image_url: Optional[str] = None
    description: Optional[str] = None

    class Config:
        from_attributes = True


class ShopInventory(BaseModel):
    """
    Represents the inventory details of a product at a specific shop.
    Includes dynamic data like price, stock, and distance.
    """
    shop_id: int
    shop_name: str
    price: float = Field(..., description="The selling price of the product at this shop.")
    availability_status: AvailabilityStatus
    distance_km: float = Field(..., description="Distance of the shop from the user's location in kilometers.")

    class Config:
        from_attributes = True


class ProductComparisonResponse(BaseModel):
    """
    The final response model that combines the master product data
    with a list of shops that have it in their inventory.
    """
    product_details: ProductMaster
    shop_inventories: List[ShopInventory]

    class Config:
        from_attributes = True
