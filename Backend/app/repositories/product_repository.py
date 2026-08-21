# app/repositories/product_repository.py
from typing import List, Dict, Optional
from app.schemas.product import ProductMaster, ShopInventory, ProductComparisonResponse, AvailabilityStatus

# --- MOCK DATABASE ---
# In a real application, this data would come from a PostgreSQL database.
# Products would be in a 'products' table.
# Shops would be in a 'shops' table.
# Inventory would be in a 'shop_inventory' join table with shop_id, product_id, price, etc.

MOCK_PRODUCTS: Dict[int, ProductMaster] = {
    1: ProductMaster(
        id=1,
        name="Dove Shampoo (1L)",
        brand="Dove",
        category="Hair Care",
        barcode="8901030634213",
        description="Dove Intense Repair Shampoo for damaged hair.",
        image_url="https://example.com/images/dove_shampoo.jpg",
    ),
    2: ProductMaster(
        id=2,
        name="Maggi Noodles (Family Pack)",
        brand="Maggi",
        category="Instant Foods",
        barcode="8901058861614",
        description="2-minute instant noodles, family pack of 4.",
        image_url="https://example.com/images/maggi_noodles.jpg",
    ),
}

MOCK_INVENTORY: List[Dict] = [
    # Inventories for Product 1 (Dove Shampoo)
    {"product_id": 1, "shop_id": 101, "shop_name": "All-in-One Supermarket", "price": 250.00, "status": AvailabilityStatus.IN_STOCK, "distance": 1.2},
    {"product_id": 1, "shop_id": 102, "shop_name": "QuickMart", "price": 240.00, "status": AvailabilityStatus.OUT_OF_STOCK, "distance": 0.8},
    {"product_id": 1, "shop_id": 103, "shop_name": "GreenLeaf Organics", "price": 265.00, "status": AvailabilityStatus.LIMITED, "distance": 2.5},

    # Inventories for Product 2 (Maggi Noodles)
    {"product_id": 2, "shop_id": 101, "shop_name": "All-in-One Supermarket", "price": 95.00, "status": AvailabilityStatus.IN_STOCK, "distance": 1.2},
    {"product_id": 2, "shop_id": 102, "shop_name": "QuickMart", "price": 100.00, "status": AvailabilityStatus.IN_STOCK, "distance": 0.8},
]

class MockProductRepository:
    """
    A mock repository for fetching product and inventory data.
    This simulates the behavior of a real database repository.
    """

    def __init__(self):
        # In a real scenario, this would hold a database session (e.g., self.db: AsyncSession).
        pass

    async def get_product_by_barcode(self, barcode: str) -> Optional[ProductMaster]:
        """
        Fetches a master product by its barcode.
        
        SQLALCHEMY+POSTGIS TRANSITION:
        - This method would perform an async query:
          `result = await self.db.execute(select(ProductModel).where(ProductModel.barcode == barcode))`
        - It would return the first result, which Pydantic would then use to serialize the response.
        """
        print(f"Mock DB: Searching for barcode {barcode}")
        for product in MOCK_PRODUCTS.values():
            if product.barcode == barcode:
                return product
        return None

    async def get_product_comparison(self, product_id: int) -> Optional[ProductComparisonResponse]:
        """
        Fetches product details and its availability in nearby shops, sorted by distance.

        SQLALCHEMY+POSTGIS TRANSITION:
        - The `product_id` would be used to fetch the master product details.
        - A much more complex geospatial query would be run to find nearby shops with the product.
        - Using PostGIS `ST_DWithin`, we would query the `shop_inventory` and `shops` tables:
          `SELECT si.*, s.name, ST_Distance(s.location, :user_location) as distance
           FROM shop_inventory si JOIN shops s ON si.shop_id = s.id
           WHERE si.product_id = :product_id AND ST_DWithin(s.location, :user_location, :radius_meters)
           ORDER BY distance;`
        - The results of this query would be used to build the `ShopInventory` list.
        """
        print(f"Mock DB: Comparing prices for product_id {product_id}")
        master_product = MOCK_PRODUCTS.get(product_id)
        if not master_product:
            return None

        shop_inventories: List[ShopInventory] = []
        for inv in MOCK_INVENTORY:
            if inv["product_id"] == product_id:
                shop_inventories.append(
                    ShopInventory(
                        shop_id=inv["shop_id"],
                        shop_name=inv["shop_name"],
                        price=inv["price"],
                        availability_status=inv["status"],
                        distance_km=inv["distance"]
                    )
                )
        
        # Sort by distance (as a default behavior)
        shop_inventories.sort(key=lambda x: x.distance_km)

        return ProductComparisonResponse(
            product_details=master_product,
            shop_inventories=shop_inventories,
        )

# Dependency for FastAPI
# In a real app, we might have a more complex dependency system
# to switch between Mock and real (e.g., based on an environment variable).
def get_product_repository() -> MockProductRepository:
    return MockProductRepository()
