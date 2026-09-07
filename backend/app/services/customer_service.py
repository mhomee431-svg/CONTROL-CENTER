"""Customer experience service - recently viewed, favourites, product sharing.

Every payload is computed live from product masters, shop products and the
customer profile. No hardcoded values; sharing records an analytics event so
the shopkeeper dashboard can show which products customers share.
"""

from datetime import datetime, timezone
from typing import Any

from sqlalchemy.orm import Session

from app.models.customer import Customer
from app.models.customer_favorite import CustomerFavorite, FAVORITE_ITEM_TYPES
from app.models.customer_recent_product import CustomerRecentProduct
from app.models.product import ProductMaster, ShopProduct
from app.models.user import User


def _get_or_create_customer(db: Session, user: User) -> Customer:
    """Resolve the customer profile for a user, creating it on first use."""
    customer = db.query(Customer).filter(Customer.user_id == user.id).first()
    if customer is None:
        customer = Customer(user_id=user.id)
        db.add(customer)
        db.flush()
    return customer


def _primary_image(pm: ProductMaster) -> str | None:
    """Return the primary image URL for a product (or the first one)."""
    if not pm.images:
        return None
    primaries = [i for i in pm.images if i.is_primary]
    return (primaries[0].image_url if primaries else pm.images[0].image_url) or None


# ── Recently viewed ──────────────────────────────────────────────────────────
def record_recent_view(
    db: Session,
    user: User,
    product_master_id: int,
    variant_id: int | None = None,
    shop_product_id: int | None = None,
) -> dict[str, Any]:
    """Record a product view (UPSERT on customer + product) and return summary."""
    customer = _get_or_create_customer(db, user)
    row = (
        db.query(CustomerRecentProduct)
        .filter(
            CustomerRecentProduct.customer_id == customer.id,
            CustomerRecentProduct.product_master_id == product_master_id,
        )
        .first()
    )
    now = datetime.now(timezone.utc)
    if row:
        row.view_count = (row.view_count or 1) + 1
        row.last_viewed_at = now
        if variant_id:
            row.variant_id = variant_id
        if shop_product_id:
            row.shop_product_id = shop_product_id
    else:
        row = CustomerRecentProduct(
            customer_id=customer.id,
            product_master_id=product_master_id,
            variant_id=variant_id,
            shop_product_id=shop_product_id,
            first_viewed_at=now,
            last_viewed_at=now,
            view_count=1,
        )
        db.add(row)
    db.commit()
    return {"product_master_id": product_master_id, "view_count": row.view_count}


def list_recent_views(db: Session, user: User, limit: int = 20) -> list[dict[str, Any]]:
    """List the customer's recently-viewed products with product metadata."""
    customer = _get_or_create_customer(db, user)
    rows = (
        db.query(CustomerRecentProduct)
        .filter(CustomerRecentProduct.customer_id == customer.id)
        .order_by(CustomerRecentProduct.last_viewed_at.desc())
        .limit(limit)
        .all()
    )
    result = []
    for rec in rows:
        pm = db.get(ProductMaster, rec.product_master_id)
        if pm is None:
            continue
        result.append({
            "product_master_id": pm.id,
            "name": pm.name,
            "slug": pm.slug,
            "image_url": _primary_image(pm),
            "variant_id": rec.variant_id,
            "shop_product_id": rec.shop_product_id,
            "view_count": rec.view_count,
            "last_viewed_at": rec.last_viewed_at.isoformat(),
        })
    return result
# -- Favourites ----------------------------------------------------
def list_favorites(db: Session, user: User, item_type: str | None = None) -> list[dict[str, Any]]:
    """List the customer favourites (optionally filtered by item_type)."""
    customer = _get_or_create_customer(db, user)
    query = db.query(CustomerFavorite).filter(CustomerFavorite.customer_id == customer.id)
    if item_type:
        query = query.filter(CustomerFavorite.item_type == item_type)
    favs = query.order_by(CustomerFavorite.created_at.desc()).all()

    result = []
    for fav in favs:
        snapshot = None
        if fav.item_type == "PRODUCT":
            pm = db.get(ProductMaster, fav.item_id)
            if pm:
                snapshot = {
                    "id": pm.id,
                    "name": pm.name,
                    "slug": pm.slug,
                    "image_url": _primary_image(pm),
                }
        result.append({
            "id": fav.id,
            "item_type": fav.item_type,
            "item_id": fav.item_id,
            "metadata_json": fav.metadata_json,
            "created_at": fav.created_at.isoformat(),
            "item": snapshot,
        })
    return result


def toggle_favorite(db: Session, user: User, item_type: str, item_id: int,
                    metadata_json: dict | None = None) -> dict[str, Any]:
    """Add a favourite, or remove it if it already exists (toggle)."""
    if item_type not in FAVORITE_ITEM_TYPES:
        raise ValueError(f"item_type must be one of {FAVORITE_ITEM_TYPES}")
    customer = _get_or_create_customer(db, user)
    existing = (
        db.query(CustomerFavorite)
        .filter(
            CustomerFavorite.customer_id == customer.id,
            CustomerFavorite.item_type == item_type,
            CustomerFavorite.item_id == item_id,
        )
        .first()
    )
    if existing:
        db.delete(existing)
        db.commit()
        return {"favorited": False, "favorite_id": existing.id}
    fav = CustomerFavorite(
        customer_id=customer.id,
        item_type=item_type,
        item_id=item_id,
        metadata_json=metadata_json,
    )
    db.add(fav)
    db.commit()
    db.refresh(fav)
    return {"favorited": True, "favorite_id": fav.id}

# -- Product share ------------------------------------------------
def product_share_payload(db: Session, product_master_id: int) -> dict[str, Any]:
    """Build a shareable snapshot of a product: name, image, price range, shop count."""
    pm = db.get(ProductMaster, product_master_id)
    if pm is None:
        return None

    image_url = _primary_image(pm)

    # Live price range across every visible shop listing.
    shop_products = (
        db.query(ShopProduct)
        .filter(ShopProduct.product_master_id == pm.id, ShopProduct.is_available == True)  # noqa: E712
        .all()
    )
    prices = [float(sp.price) for sp in shop_products if sp.price is not None]
    price_range = None
    if prices:
        price_range = {
            "min": round(min(prices), 2),
            "max": round(max(prices), 2),
        }

    return {
        "product_master_id": pm.id,
        "name": pm.name,
        "slug": pm.slug,
        "description": pm.short_description or (pm.description or "")[:200] or None,
        "image_url": image_url,
        "shop_count": len(shop_products),
        "price_range": price_range,
        "currency": "INR",
    }


def record_share_event(db: Session, user: User | None, product_master_id: int) -> None:
    """Fire-and-forget analytics event marking a product share (never blocks)."""
    try:
        from app.services import analytics_system
        from app.services.analytics_system import sanitize_props

        event = analytics_system.AnalyticsEvent(
            event_name="product_share",
            actor_type="CUSTOMER" if user else "GUEST",
            actor_id=user.id if user else None,
            product_master_id=product_master_id,
            props=sanitize_props({"channel": "share_sheet"}),
            occurred_at=datetime.now(timezone.utc),
        )
        db.add(event)
        try:
            db.commit()
        except Exception:  # noqa: BLE001
            db.rollback()
    except Exception:  # noqa: BLE001
        db.rollback()
