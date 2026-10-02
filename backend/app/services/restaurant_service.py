"""Restaurant Discovery service — Master Spec §27 (Rule 4: discovery-only domain)."""

from datetime import datetime, timezone
from typing import Optional

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.logging import get_logger
from app.models.restaurant import Restaurant, RestaurantMenuCategory, RestaurantMenuItem
from app.models.shop import Shop, ShopCategory, ShopOwner
from app.schemas.restaurant import (
    RestaurantCreate,
    RestaurantUpdate,
    RestaurantMenuCategoryCreate,
    RestaurantMenuItemCreate,
)
from app.services.geo_service import haversine_km

logger = get_logger("app.services.restaurant")


def nearby_restaurants(
    db: Session,
    latitude: float,
    longitude: float,
    radius_km: float = 5.0,
    cuisine: Optional[str] = None,
) -> list[dict]:
    """Find verified active restaurants within radius, ordered by distance."""
    stmt = (
        select(Shop, Restaurant)
        .join(Restaurant, Restaurant.shop_id == Shop.id)
        .where(
            Shop.category == ShopCategory.RESTAURANT,
            Shop.is_verified == True,  # noqa: E712
            Shop.is_deleted == False,  # noqa: E712
            Restaurant.is_deleted == False,  # noqa: E712
        )
    )
    results = db.execute(stmt).all()

    restaurants = []
    for shop, restaurant in results:
        dist = haversine_km(latitude, longitude, shop.latitude or 0, shop.longitude or 0)
        if dist <= radius_km:
            if cuisine and restaurant.cuisine_types:
                if cuisine.lower() not in [c.lower() for c in restaurant.cuisine_types]:
                    continue
            restaurants.append({
                "id": restaurant.id,
                "shop_id": shop.id,
                "name": shop.name,
                "cuisine_types": restaurant.cuisine_types,
                "dining_available": restaurant.dining_available,
                "takeaway_available": restaurant.takeaway_available,
                "avg_cost_for_two": float(restaurant.avg_cost_for_two) if restaurant.avg_cost_for_two else None,
                "rating": float(shop.rating) if shop.rating else 0.0,
                "review_count": shop.review_count or 0,
                "veg_only": restaurant.veg_only,
                "distance_km": round(dist, 2),
            })

    restaurants.sort(key=lambda x: x["distance_km"])
    return restaurants


def get_restaurant_detail(db: Session, restaurant_id: int) -> Optional[dict]:
    """Get full restaurant detail with menu."""
    restaurant = db.get(Restaurant, restaurant_id)
    if not restaurant or restaurant.is_deleted:
        return None

    shop = db.get(Shop, restaurant.shop_id)
    if not shop:
        return None

    categories = (
        db.execute(
            select(RestaurantMenuCategory)
            .where(
                RestaurantMenuCategory.restaurant_id == restaurant_id,
                RestaurantMenuCategory.is_active == True,  # noqa: E712
            )
            .order_by(RestaurantMenuCategory.sort_order)
        )
        .scalars()
        .all()
    )

    menu_categories = []
    for cat in categories:
        items = (
            db.execute(
                select(RestaurantMenuItem)
                .where(
                    RestaurantMenuItem.menu_category_id == cat.id,
                    RestaurantMenuItem.is_active == True,  # noqa: E712
                    RestaurantMenuItem.is_deleted == False,  # noqa: E712
                )
                .order_by(RestaurantMenuItem.sort_order)
            )
            .scalars()
            .all()
        )
        menu_categories.append({
            "id": cat.id,
            "name": cat.name,
            "description": cat.description,
            "sort_order": cat.sort_order,
            "items": [
                {
                    "id": item.id,
                    "name": item.name,
                    "description": item.description,
                    "price": float(item.price) if item.price else None,
                    "veg": item.veg,
                    "spicy": item.spicy,
                    "is_available_today": item.is_available_today,
                }
                for item in items
            ],
        })

    return {
        "id": restaurant.id,
        "shop_id": shop.id,
        "name": shop.name,
        "description": shop.description,
        "cuisine_types": restaurant.cuisine_types,
        "dining_available": restaurant.dining_available,
        "takeaway_available": restaurant.takeaway_available,
        "avg_cost_for_two": float(restaurant.avg_cost_for_two) if restaurant.avg_cost_for_two else None,
        "rating": float(shop.rating) if shop.rating else 0.0,
        "review_count": shop.review_count or 0,
        "veg_only": restaurant.veg_only,
        "licence_fssai": restaurant.licence_fssai,
        "phone": shop.phone,
        "address": shop.addresses[0].address_line1 if shop.addresses else None,
        "latitude": float(shop.latitude) if shop.latitude else None,
        "longitude": float(shop.longitude) if shop.longitude else None,
        "menu_categories": menu_categories,
    }

def get_restaurant_detail_by_shop(db: Session, shop_id: int) -> Optional[dict]:
    """Restaurant profile for a SHOP — the lookup a customer shop profile needs.

    A restaurant is a 1:1 discovery profile over a ``shops`` row, so the customer
    app knows a shop id (from search, a saved shop, or a nearby list) and not a
    restaurant id. Without this it would have to guess an id, which is exactly
    how the wrong restaurant's menu gets shown.

    Returns None when the shop has no restaurant profile — the caller then shows
    no menu rather than an empty one.
    """
    restaurant = (
        db.execute(
            select(Restaurant).where(
                Restaurant.shop_id == shop_id,
                Restaurant.is_deleted == False,  # noqa: E712
            )
        )
        .scalars()
        .first()
    )
    if restaurant is None:
        return None
    return get_restaurant_detail(db, restaurant.id)


def get_restaurant_menu(db: Session, restaurant_id: int) -> Optional[list[dict]]:
    """Get restaurant menu categories with items."""
    restaurant = db.get(Restaurant, restaurant_id)
    if not restaurant or restaurant.is_deleted:
        return None

    categories = (
        db.execute(
            select(RestaurantMenuCategory)
            .where(
                RestaurantMenuCategory.restaurant_id == restaurant_id,
                RestaurantMenuCategory.is_active == True,  # noqa: E712
            )
            .order_by(RestaurantMenuCategory.sort_order)
        )
        .scalars()
        .all()
    )

    result = []
    for cat in categories:
        items = (
            db.execute(
                select(RestaurantMenuItem)
                .where(
                    RestaurantMenuItem.menu_category_id == cat.id,
                    RestaurantMenuItem.is_active == True,  # noqa: E712
                    RestaurantMenuItem.is_deleted == False,  # noqa: E712
                )
                .order_by(RestaurantMenuItem.sort_order)
            )
            .scalars()
            .all()
        )
        result.append({
            "id": cat.id,
            "name": cat.name,
            "description": cat.description,
            "items": [
                {
                    "id": item.id,
                    "name": item.name,
                    "description": item.description,
                    "price": float(item.price) if item.price else None,
                    "veg": item.veg,
                    "spicy": item.spicy,
                    "is_available_today": item.is_available_today,
                }
                for item in items
            ],
        })
    return result


def create_restaurant(db: Session, user_id: int, data: RestaurantCreate) -> Restaurant:
    """Create a restaurant profile for an existing shop."""
    shop_owner = (
        db.execute(
            select(ShopOwner).where(
                ShopOwner.shop_id == data.shop_id,
                ShopOwner.user_id == user_id,
            )
        )
        .scalars()
        .first()
    )
    if not shop_owner:
        raise ValueError("Shop not found or you are not the owner")

    shop = db.get(Shop, data.shop_id)
    if not shop:
        raise ValueError("Shop not found")

    if shop.category != ShopCategory.RESTAURANT:
        raise ValueError("Shop must be of RESTAURANT category")

    existing = (
        db.execute(select(Restaurant).where(Restaurant.shop_id == data.shop_id))
        .scalars()
        .first()
    )
    if existing:
        raise ValueError("Restaurant profile already exists for this shop")

    restaurant = Restaurant(
        shop_id=data.shop_id,
        cuisine_types=data.cuisine_types,
        dining_available=data.dining_available,
        takeaway_available=data.takeaway_available,
        avg_cost_for_two=data.avg_cost_for_two,
        veg_only=data.veg_only,
        licence_fssai=data.licence_fssai,
    )
    db.add(restaurant)
    db.commit()
    db.refresh(restaurant)
    return restaurant


def update_restaurant(
    db: Session, user_id: int, restaurant_id: int, data: RestaurantUpdate
) -> Optional[Restaurant]:
    """Update restaurant profile (owner only)."""
    restaurant = db.get(Restaurant, restaurant_id)
    if not restaurant or restaurant.is_deleted:
        return None

    shop_owner = (
        db.execute(
            select(ShopOwner).where(
                ShopOwner.shop_id == restaurant.shop_id,
                ShopOwner.user_id == user_id,
            )
        )
        .scalars()
        .first()
    )
    if not shop_owner:
        raise PermissionError("You are not the owner of this restaurant")

    update_data = data.model_dump(exclude_unset=True)
    for field, value in update_data.items():
        setattr(restaurant, field, value)

    db.commit()
    db.refresh(restaurant)
    return restaurant

def create_menu_category(
    db: Session, user_id: int, restaurant_id: int, data: RestaurantMenuCategoryCreate
) -> Optional[RestaurantMenuCategory]:
    """Add a menu category (owner only)."""
    restaurant = db.get(Restaurant, restaurant_id)
    if not restaurant or restaurant.is_deleted:
        return None

    shop_owner = (
        db.execute(
            select(ShopOwner).where(
                ShopOwner.shop_id == restaurant.shop_id,
                ShopOwner.user_id == user_id,
            )
        )
        .scalars()
        .first()
    )
    if not shop_owner:
        raise PermissionError("You are not the owner of this restaurant")

    category = RestaurantMenuCategory(
        restaurant_id=restaurant_id,
        name=data.name,
        description=data.description,
        sort_order=data.sort_order,
    )
    db.add(category)
    db.commit()
    db.refresh(category)
    return category


def create_menu_item(
    db: Session, user_id: int, restaurant_id: int, data: RestaurantMenuItemCreate
) -> Optional[RestaurantMenuItem]:
    """Add a menu item (owner only)."""
    restaurant = db.get(Restaurant, restaurant_id)
    if not restaurant or restaurant.is_deleted:
        return None

    shop_owner = (
        db.execute(
            select(ShopOwner).where(
                ShopOwner.shop_id == restaurant.shop_id,
                ShopOwner.user_id == user_id,
            )
        )
        .scalars()
        .first()
    )
    if not shop_owner:
        raise PermissionError("You are not the owner of this restaurant")

    item = RestaurantMenuItem(
        restaurant_id=restaurant_id,
        menu_category_id=data.menu_category_id,
        name=data.name,
        description=data.description,
        price=data.price,
        veg=data.veg,
        spicy=data.spicy,
        is_available_today=data.is_available_today,
        sort_order=data.sort_order,
    )
    db.add(item)
    db.commit()
    db.refresh(item)
    return item


def update_menu_item(
    db: Session, user_id: int, restaurant_id: int, item_id: int, data: RestaurantMenuItemCreate
) -> Optional[RestaurantMenuItem]:
    """Update a menu item (owner only)."""
    item = db.get(RestaurantMenuItem, item_id)
    if not item or item.is_deleted or item.restaurant_id != restaurant_id:
        return None

    restaurant = db.get(Restaurant, restaurant_id)
    shop_owner = (
        db.execute(
            select(ShopOwner).where(
                ShopOwner.shop_id == restaurant.shop_id,
                ShopOwner.user_id == user_id,
            )
        )
        .scalars()
        .first()
    )
    if not shop_owner:
        raise PermissionError("You are not the owner of this restaurant")

    update_data = data.model_dump(exclude_unset=True)
    for field, value in update_data.items():
        setattr(item, field, value)

    db.commit()
    db.refresh(item)
    return item


def delete_menu_item(db: Session, user_id: int, restaurant_id: int, item_id: int) -> bool:
    """Soft-delete a menu item (owner only)."""
    item = db.get(RestaurantMenuItem, item_id)
    if not item or item.is_deleted or item.restaurant_id != restaurant_id:
        return False

    restaurant = db.get(Restaurant, restaurant_id)
    shop_owner = (
        db.execute(
            select(ShopOwner).where(
                ShopOwner.shop_id == restaurant.shop_id,
                ShopOwner.user_id == user_id,
            )
        )
        .scalars()
        .first()
    )
    if not shop_owner:
        raise PermissionError("You are not the owner of this restaurant")

    item.is_deleted = True
    item.deleted_at = datetime.now(timezone.utc)
    db.commit()
    return True
