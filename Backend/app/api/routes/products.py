# app/api/routes/products.py
"""Customer-facing product endpoints.

`GET /products/{identifier}` resolves a master product by numeric id OR by
barcode / identifier value and returns:
  - the global **product master** (static info), and
  - **live shop inventories** (dynamic availability) sorted by distance.

This replaces the Phase-4 mock repository implementation: all data now comes
from the platform database (product_masters / shop_products / inventory).
"""
from datetime import datetime

from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session, joinedload

from app.core.dependencies import get_optional_user
from app.core.responses import error_response, success_response
from app.database.session import get_db
from app.models.product import (
    BarcodeRelationship,
    Inventory,
    ProductIdentifier,
    ProductMaster,
    ShopProduct,
)
from app.models.saved_product import SavedProduct
from app.models.shop import Shop
from app.models.user import User
from app.services.geo_service import haversine_km
from app.services.inventory_service import get_offer_text_for_shop_product

router = APIRouter(
    prefix="/products",
    tags=["products"]
)


def _resolve_product(db: Session, identifier: str) -> ProductMaster | None:
    """Resolve a path identifier to a master product.

    Numeric identifiers are treated as primary keys; anything else is looked
    up as a barcode (barcode_relationships) or a product identifier value.
    """
    if identifier.isdigit():
        product = (
            db.query(ProductMaster)
            .filter(ProductMaster.id == int(identifier), ProductMaster.is_active == True)  # noqa: E712
            .first()
        )
        if product is not None:
            return product

    # Barcode lookup
    barcode_rel = (
        db.query(BarcodeRelationship)
        .filter(
            BarcodeRelationship.barcode == identifier,
            BarcodeRelationship.is_active == True,  # noqa: E712
        )
        .first()
    )
    if barcode_rel is not None:
        return (
            db.query(ProductMaster)
            .filter(ProductMaster.id == barcode_rel.product_master_id)
            .first()
        )

    # Identifier-value lookup (EAN/UPC/SKU/MPN stored on identifiers)
    ident = (
        db.query(ProductIdentifier)
        .filter(
            ProductIdentifier.identifier_value == identifier,
            ProductIdentifier.is_active == True,  # noqa: E712
        )
        .first()
    )
    if ident is not None:
        return (
            db.query(ProductMaster)
            .filter(ProductMaster.id == ident.product_master_id)
            .first()
        )
    return None


def _product_master_payload(product: ProductMaster, is_saved: bool) -> dict:
    """Serialize the static product-master section."""
    images = sorted(product.images, key=lambda i: (not i.is_primary, i.sort_order))
    image_urls = [img.image_url for img in images if img.image_url]

    prices = [
        float(sp.price)
        for sp in product.shop_products
        if sp.is_visible and not sp.is_deleted
    ]
    price_range = None
    if prices:
        price_range = f"₹{min(prices):,.0f} - ₹{max(prices):,.0f}"

    return {
        "id": product.id,
        "name": product.name,
        "brand": product.brand.name if product.brand else "",
        "category": product.category.name if product.category else "",
        "subcategory": product.subcategory.name if product.subcategory else None,
        "description": product.description,
        "short_description": product.short_description,
        "base_unit": product.base_unit,
        "base_quantity": product.base_quantity,
        "price_range": price_range,
        "image_url": image_urls[0] if image_urls else "",
        "image_urls": image_urls,
        "variants": [
            {
                "id": v.id,
                "name": v.name,
                "sku": v.sku,
                "description": v.description,
                "attributes_json": v.attributes_json,
            }
            for v in product.variants
            if not v.is_deleted and v.is_active
        ],
        "attributes": [
            {
                "name": attr.name,
                "values": [
                    val.value for val in sorted(attr.values, key=lambda x: x.sort_order)
                ],
            }
            for attr in product.attributes
        ],
        "identifiers": [
            {
                "identifier_type": ident.identifier_type.value
                if hasattr(ident.identifier_type, "value")
                else str(ident.identifier_type),
                "identifier_value": ident.identifier_value,
                "is_primary": ident.is_primary,
            }
            for ident in product.identifiers
            if ident.is_active
        ],
        "is_saved": is_saved,
    }


def _shop_offers_payload(
    db: Session,
    product: ProductMaster,
    latitude: float | None,
    longitude: float | None,
    radius_km: float,
) -> list[dict]:
    """Serialize live availability for every visible shop that stocks this product."""
    shop_products = (
        db.query(ShopProduct)
        .join(Shop, ShopProduct.shop_id == Shop.id)
        .options(joinedload(ShopProduct.inventory))
        .filter(
            ShopProduct.product_master_id == product.id,
            ShopProduct.is_visible == True,  # noqa: E712
            ShopProduct.is_deleted == False,  # noqa: E712
            Shop.status.in_(["ACTIVE", "VERIFIED"]),
            Shop.is_deleted == False,  # noqa: E712
        )
        .all()
    )

    offers: list[dict] = []
    for sp in shop_products:
        shop: Shop | None = db.query(Shop).filter(Shop.id == sp.shop_id).first()
        if shop is None:
            continue

        distance_km = 0.0
        if latitude is not None and longitude is not None and shop.latitude and shop.longitude:
            distance_km = round(
                haversine_km(latitude, longitude, shop.latitude, shop.longitude), 2
            )
            if distance_km > radius_km:
                continue

        inv = getattr(sp, "inventory", None)
        if inv is None:
            inv = db.query(Inventory).filter(Inventory.shop_product_id == sp.id).first()

        stock_status = None
        freshness_status = None
        last_updated: datetime | None = sp.last_inventory_update
        if inv is not None:
            stock_status = (
                inv.stock_status.value
                if hasattr(inv.stock_status, "value")
                else str(inv.stock_status)
            ).lower()
            if inv.freshness_status is not None:
                freshness_status = (
                    inv.freshness_status.value
                    if hasattr(inv.freshness_status, "value")
                    else str(inv.freshness_status)
                ).lower()
            if inv.updated_at is not None:
                last_updated = inv.updated_at

        offers.append(
            {
                "shop_product_id": sp.id,
                "shop_id": shop.id,
                "shop_name": shop.name,
                "shop_image_url": shop.image_url or "",
                "price": float(sp.price),
                "mrp": float(sp.mrp) if sp.mrp is not None else None,
                "distance_km": distance_km,
                "shop_rating": float(shop.rating or 0.0),
                "is_available": bool(inv.is_available) if inv is not None else bool(sp.is_available),
                "stock_status": stock_status,
                "freshness_status": freshness_status,
                "offer_text": get_offer_text_for_shop_product(db, sp.id),
                "last_updated": last_updated.isoformat() if last_updated else None,
            }
        )

    offers.sort(key=lambda o: o["distance_km"])
    return offers


@router.get(
    "/{identifier}",
    summary="Get Master Product + Live Shop Offers",
    description=(
        "Fetch the global master product by id or barcode together with "
        "live availability across nearby shops."
    ),
)
async def get_product_detail(
    identifier: str,
    latitude: float | None = Query(None, ge=-90, le=90),
    longitude: float | None = Query(None, ge=-180, le=180),
    radius_km: float = Query(25.0, gt=0, le=100),
    db: Session = Depends(get_db),
    user: User | None = Depends(get_optional_user),
):
    """Customer product-detail payload: product master + live shop inventories."""
    product = _resolve_product(db, identifier)
    if product is None:
        return error_response(
            message=f"Product '{identifier}' not found",
            error_code="PRODUCT_NOT_FOUND",
            status_code=404,
        )

    is_saved = False
    if user is not None:
        is_saved = (
            db.query(SavedProduct)
            .filter(
                SavedProduct.user_id == user.id,
                SavedProduct.product_master_id == product.id,
            )
            .first()
            is not None
        )

    return success_response(
        data={
            "product": _product_master_payload(product, is_saved),
            "shop_inventories": _shop_offers_payload(
                db, product, latitude, longitude, radius_km
            ),
        },
        message="Product detail",
    )


@router.get(
    "/{identifier}/offers",
    summary="Compare Product Prices at Nearby Shops",
    description="Live availability and pricing for one product across nearby shops.",
)
async def compare_product_offers(
    identifier: str,
    latitude: float | None = Query(None, ge=-90, le=90),
    longitude: float | None = Query(None, ge=-180, le=180),
    radius_km: float = Query(10.0, gt=0, le=100),
    db: Session = Depends(get_db),
):
    """The core hyperlocal comparison: which nearby shops stock this product."""
    product = _resolve_product(db, identifier)
    if product is None:
        return error_response(
            message=f"Product '{identifier}' not found",
            error_code="PRODUCT_NOT_FOUND",
            status_code=404,
        )

    offers = _shop_offers_payload(db, product, latitude, longitude, radius_km)
    return success_response(
        data={
            "product_id": product.id,
            "product_name": product.name,
            "shop_inventories": offers,
        },
        message="Product comparison",
    )
