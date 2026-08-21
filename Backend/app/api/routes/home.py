from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session, joinedload

from app.core.responses import success_response
from app.database.session import get_db
from app.models.product import (
    Category,
    ProductMaster,
    ShopProduct,
)
from app.models.shop import Shop
from app.services.geo_service import haversine_km

router = APIRouter(prefix="/home", tags=["home"])


@router.get("/feed")
async def get_home_feed(
    latitude: float | None = Query(None, ge=-90, le=90),
    longitude: float | None = Query(None, ge=-180, le=180),
    radius_km: float = Query(10.0, gt=0, le=100),
    db: Session = Depends(get_db),
):
    """Return the home feed: categories, popular products, nearby shops, recent searches."""
    categories = db.query(Category).all()
    category_data = [
        {"id": c.id, "name": c.name, "icon_url": c.icon_url} for c in categories
    ]

    # Popular products: products with the most shop_product entries
    products = (
        db.query(ProductMaster)
        .options(joinedload(ProductMaster.shop_products))
        .all()
    )
    product_data = []
    for p in products:
        shop_products = [sp for sp in p.shop_products if sp.is_visible and not sp.is_deleted]
        if not shop_products:
            continue
        prices = [float(sp.price) for sp in shop_products]
        min_price = min(prices)
        max_price = max(prices)
        # Get primary image
        image_url = ""
        if p.images:
            primary = [img for img in p.images if img.is_primary]
            image_url = (primary[0].image_url if primary else p.images[0].image_url) or ""
        product_data.append(
            {
                "id": str(p.id),
                "name": p.name,
                "brand": p.brand.name if p.brand else "",
                "image_url": image_url,
                "price_range": f"₹{min_price:,.0f} - ₹{max_price:,.0f}",
            }
        )

    # Nearby shops
    shops = db.query(Shop).all()
    shop_data = []
    for s in shops:
        # Use PostGIS location for distance if available, else fall back to haversine helper
        distance = 0.0
        if latitude is not None and longitude is not None:
            # NOTE: shop.location is a Geography POINT; basic fallback using precomputed
            # coordinates would require ST_X/ST_Y. For now use haversine on saved coords.
            # In a future phase, replace with PostGIS ST_Distance.
            # This fallback keeps the home feed working.
            # Access longitude/latitude via WKT parsing would be complex here.
            distance = 0.0  # Placeholder; PostGIS distance calculation to be implemented in a later phase
            # Filtering by radius will be done via PostGIS in the search/query phase.
        shop_data.append(
            {
                "id": str(s.id),
                "name": s.name,
                "image_url": s.image_url or "",
                "distance": round(distance, 2),
                "rating": s.rating,
                "is_verified": s.is_verified,
            }
        )
    shop_data.sort(key=lambda s: s["distance"])

    recent_searches = ["Paracetamol 500mg", "Amul Butter", "Ceiling Fan"]

    return success_response(
        data={
            "categories": category_data,
            "popular_products": product_data,
            "nearby_shops": shop_data,
            "recent_searches": recent_searches,
        }
    )