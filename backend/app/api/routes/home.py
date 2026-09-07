from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session, joinedload

from app.core.responses import success_response
from app.database.session import get_db
from app.models.product import (
    Category,
    ProductMaster,
    ShopProduct,
)
from app.models.shop import Shop, ShopStatus
from app.search import engine as search_engine
from app.services.geo_service import haversine_km, resolve_shop_coordinates
from app.services.media_service import resolve_media_url

router = APIRouter(prefix="/home", tags=["home"])


def _shop_distance_km(
    shop: Shop,
    latitude: float | None,
    longitude: float | None,
) -> float:
    """Haversine distance (km) from the customer to a shop.

    Returns ``0.0`` when the customer or the shop coordinates are missing —
    matching the shape contract the customer app expects (``distance`` is a
    non-null float). Phase 15 wires real coordinates from the device GPS.
    """
    if (
        latitude is not None
        and longitude is not None
    ):
        shop_longitude, shop_latitude = resolve_shop_coordinates(shop)
        if shop_longitude is not None and shop_latitude is not None:
            return haversine_km(latitude, longitude, shop_latitude, shop_longitude)
    return  0.0


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
            image_url = resolve_media_url(
                (primary[0].image_url if primary else p.images[0].image_url)
            ) or ""
        product_data.append(
            {
                "id": str(p.id),
                "name": p.name,
                "brand": p.brand.name if p.brand else "",
                "image_url": image_url,
                "price_range": f"₹{min_price:,.0f} - ₹{max_price:,.0f}",
            }
        )

    # Nearby shops - visible, verified shops within the customer's radius.
    # Coordinates are resolved through the shared PostGIS/fallback resolver (so
    # shops storing coords only in the ``location`` Geography column still work).
    shops = (
        db.query(Shop)
        .filter(
            Shop.is_deleted == False,   # noqa: E712
            Shop.status.in_([ShopStatus.ACTIVE, ShopStatus.VERIFIED]),
            Shop.is_verified == True,    # noqa: E712
            Shop.is_accepting_orders == True,   # noqa: E712
        )
        .all()
    )
    shop_data = []
    for s in shops:
        shop_longitude, shop_latitude = resolve_shop_coordinates(s)
        if latitude is not None and longitude is not None:
            if shop_longitude is None or shop_latitude is None:
                continue
            distance = haversine_km(latitude, longitude, shop_latitude, shop_longitude)
            if distance > radius_km:
                continue
        else:
            distance =  0.0
        shop_data.append(
            {
                "id": str(s.id),
                "name": s.name,
                "image_url": resolve_media_url(s.image_url) or "",
                "distance": round(distance, 2),
                "rating": s.rating,
                "is_verified": s.is_verified,
                "latitude": shop_latitude,
                "longitude": shop_longitude,
            }
        )
    shop_data.sort(key=lambda s: s["distance"])

    # Dynamic recent searches from the platform's popular search analytics.
    # Falls back to an empty list when the platform has no search history yet
    # (fresh database / new deployment) — never hardcoded static values.
    recent_searches: list[str] = []
    try:
        popular = search_engine.popular_searches(db, limit=5)
        recent_searches = [item["query"] for item in popular if item.get("query")]
    except Exception:  # noqa: BLE001
        recent_searches = []

    return success_response(
        data={
            "categories": category_data,
            "popular_products": product_data,
            "nearby_shops": shop_data,
            "recent_searches": recent_searches,
        }
    )
