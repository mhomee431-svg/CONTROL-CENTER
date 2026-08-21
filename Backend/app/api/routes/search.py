from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session
from sqlalchemy import or_

from app.core.responses import success_response
from app.database.session import get_db
from app.models.product import ProductMaster, ShopProduct, Inventory
from app.models.shop import Shop
from app.schemas.search import SearchResponse, ShopProductResultSchema
from app.services import inventory_service

router = APIRouter(prefix="/search", tags=["search"])


@router.get("/products")
async def search_products(
    q: str = Query("", max_length=200, description="Search query"),
    latitude: float | None = Query(None, ge=-90, le=90),
    longitude: float | None = Query(None, ge=-180, le=180),
    radius_km: float = Query(10.0, gt=0, le=100),
    category: int | None = Query(None, description="Category ID filter"),
    min_price: float | None = Query(None, ge=0),
    max_price: float | None = Query(None, ge=0),
    in_stock: bool = Query(False, description="Only show in-stock items"),
    sort: str = Query("nearest", pattern="^(nearest|lowest_price|highest_rated|recently_updated)$"),
    page: int = Query(1, ge=1),
    limit: int = Query(10, ge=1, le=50),
    db: Session = Depends(get_db),
):
    """
    Search products across nearby shops.

    Returns a paginated list of product-shop matches including price,
    availability, stock status, and distance.
    """
    # Master product base query
    product_query = db.query(ProductMaster)
    if q:
        search = f"%{q.strip()}%"
        product_query = product_query.filter(
            or_(ProductMaster.name.ilike(search), ProductMaster.slug.ilike(search))
        )
    if category is not None:
        product_query = product_query.filter(ProductMaster.category_id == category)

    products = product_query.all()

    results = []
    for product in products:
        # Find all shop products for this master product
        shop_products = (
            db.query(ShopProduct)
            .filter(
                ShopProduct.product_master_id == product.id,
                ShopProduct.is_visible == True,
            )
            .all()
        )
        for sp in shop_products:
            # Price filter (sp.price is the current price)
            if min_price is not None and float(sp.price) < min_price:
                continue
            if max_price is not None and float(sp.price) > max_price:
                continue

            shop = db.query(Shop).filter(Shop.id == sp.shop_id).first()
            if shop is None:
                continue

            # Distance (PostGIS in later phase)
            distance_km = 0.0

            # Stock filter using inventory
            inv = db.query(Inventory).filter(Inventory.shop_product_id == sp.id).first()
            is_available = inv.is_available if inv else sp.is_available
            if in_stock and not is_available:
                continue

            image_url = ""
            if product.images:
                primary = [img for img in product.images if img.is_primary]
                image_url = (primary[0].image_url if primary else product.images[0].image_url) or ""

            # Determine stock status (customer-facing)
            if inv is not None and hasattr(inv.stock_status, "value"):
                stock_status = inventory_service.map_to_customer_stock_status(inv.stock_status, inv.quantity).value
            else:
                stock_status = "UNKNOWN"

            # Freshness
            freshness_status = None
            if inv is not None and inv.freshness_status:
                freshness_status = inv.freshness_status.value
            elif sp.freshness_status:
                freshness_status = sp.freshness_status.value

            # Offer text
            offer_text = inventory_service.get_offer_text_for_shop_product(db, sp.id)

            results.append(
                ShopProductResultSchema(
                    id=f"res_{sp.id}",
                    product_id=product.id,
                    product_name=product.name,
                    product_image_url=image_url,
                    shop_id=shop.id,
                    shop_name=shop.name,
                    price=float(sp.price),
                    mrp=float(sp.mrp) if sp.mrp is not None else None,
                    is_available=is_available,
                    stock_status=stock_status,
                    freshness_status=freshness_status,
                    distance_km=round(distance_km, 2),
                    shop_rating=shop.rating,
                    last_updated=inv.updated_at if inv else sp.updated_at,
                    offer_text=offer_text,
                )
            )

    # Sort
    if sort == "nearest":
        results.sort(key=lambda r: r.distance_km)
    elif sort == "lowest_price":
        results.sort(key=lambda r: r.price)
    elif sort == "highest_rated":
        results.sort(key=lambda r: r.shop_rating, reverse=True)
    elif sort == "recently_updated":
        results.sort(key=lambda r: r.last_updated, reverse=True)

    # Paginate
    total = len(results)
    start = (page - 1) * limit
    end = start + limit
    paged_results = results[start:end]
    has_more = end < total

    return success_response(
        data=SearchResponse(
            results=paged_results,
            page=page,
            limit=limit,
            has_more=has_more,
            total=total,
        ).model_dump()
    )


@router.get("/suggestions")
async def get_search_suggestions(
    q: str = Query(..., min_length=1, max_length=100),
    db: Session = Depends(get_db),
):
    """Return search suggestions based on product names and brands."""
    search = f"%{q.strip()}%"
    products = (
        db.query(ProductMaster)
        .filter(ProductMaster.name.ilike(search))
        .limit(8)
        .all()
    )

    suggestions = []
    for p in products:
        if p.name and q.lower() in p.name.lower():
            suggestions.append({"text": p.name, "is_category": False, "is_brand": False})
        if p.brand and p.brand.name and q.lower() in p.brand.name.lower() and not any(s["text"] == p.brand.name for s in suggestions):
            suggestions.append({"text": p.brand.name, "is_category": False, "is_brand": True})

    return success_response(data=suggestions)