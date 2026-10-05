"""Restaurant Discovery API routes — Master Spec §27 (Rule 4: discovery-only domain).

Restaurants are a separate discovery domain. The customer discovers nearby
restaurants, views their menu (display-only prices), and visits offline.
NO inventory, cart, checkout, or delivery semantics exist.
"""

from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session

from app.core.dependencies import get_current_user
from app.core.responses import error_response, success_response
from app.database.session import get_db
from app.models.restaurant import Restaurant, RestaurantMenuCategory, RestaurantMenuItem
from app.schemas.restaurant import (
    RestaurantCreate,
    RestaurantDetailResponse,
    RestaurantListResponse,
    RestaurantMenuCategoryCreate,
    RestaurantMenuCategoryResponse,
    RestaurantMenuItemCreate,
    RestaurantMenuItemResponse,
    RestaurantUpdate,
)
from app.services import restaurant_service

router = APIRouter(prefix="/restaurants", tags=["restaurants"])


# ── Customer-facing endpoints ──────────────────────────────────────────────
@router.get("/nearby")
async def get_nearby_restaurants(
    latitude: float = Query(..., ge=-90, le=90),
    longitude: float = Query(..., ge=-180, le=180),
    radius_km: float = Query(5.0, gt=0, le=50),
    cuisine: str | None = None,
    db: Session = Depends(get_db),
):
    """Return verified active restaurants near the user within the given radius."""
    try:
        results = restaurant_service.nearby_restaurants(
            db, latitude=latitude, longitude=longitude, radius_km=radius_km, cuisine=cuisine
        )
        return success_response(data=results)
    except Exception as exc:  # noqa: BLE001
        return error_response(message=str(exc), error_code="NEARBY_RESTAURANTS_FAILED", status_code=400)


@router.get("/by-shop/{shop_id}")
async def get_restaurant_detail_by_shop(
    shop_id: int,
    db: Session = Depends(get_db),
):
    """Restaurant profile (with menu) for a SHOP, for the customer shop profile.

    Declared BEFORE ``/{restaurant_id}`` so ``by-shop`` is never parsed as an id.
    A 404 here is a normal answer — it means the shop has no restaurant profile,
    and the customer app then shows no menu rather than an empty one.
    """
    restaurant = restaurant_service.get_restaurant_detail_by_shop(db, shop_id)
    if restaurant is None:
        return error_response(message="Restaurant not found", error_code="RESTAURANT_NOT_FOUND", status_code=404)
    return success_response(data=restaurant)


@router.get("/{restaurant_id}")
async def get_restaurant_detail(
    restaurant_id: int,
    db: Session = Depends(get_db),
):
    """Get restaurant detail with menu categories and items."""
    restaurant = restaurant_service.get_restaurant_detail(db, restaurant_id)
    if restaurant is None:
        return error_response(message="Restaurant not found", error_code="RESTAURANT_NOT_FOUND", status_code=404)
    return success_response(data=restaurant)


@router.get("/{restaurant_id}/menu")
async def get_restaurant_menu(
    restaurant_id: int,
    db: Session = Depends(get_db),
):
    """Get the full menu for a restaurant (categories + items)."""
    menu = restaurant_service.get_restaurant_menu(db, restaurant_id)
    if menu is None:
        return error_response(message="Restaurant not found", error_code="RESTAURANT_NOT_FOUND", status_code=404)
    return success_response(data=menu)

# -- Shopkeeper endpoints (restaurant owner) --------------------------------
@router.get("/by-shop/{shop_id}")
async def get_my_restaurant(
    shop_id: int,
    db: Session = Depends(get_db),
    current_user=Depends(get_current_user),
):
    """Resolve the caller's own restaurant profile from their shop id.

    The menu routes are keyed on `restaurant_id`, and a shopkeeper only knows
    their `shop_id`. This is the lookup that lets the app reach its own menu
    without ever showing an internal id it never received.

    Answers 404 when the shop has no restaurant profile yet, which is the honest
    answer — the caller creates one rather than this route inventing a row.
    """
    try:
        profile = restaurant_service.get_restaurant_by_shop(db, shop_id)
        if profile is None:
            return error_response(
                message="This shop has no restaurant profile yet",
                error_code="RESTAURANT_NOT_FOUND",
                status_code=404,
            )
        return success_response(data=profile)
    except Exception as exc:  # noqa: BLE001
        return error_response(
            message=str(exc), error_code="RESTAURANT_LOOKUP_FAILED", status_code=500
        )


@router.post("/")
async def create_restaurant(
    data: RestaurantCreate,
    db: Session = Depends(get_db),
    current_user=Depends(get_current_user),
):
    """Register a restaurant profile for an existing shop (must be RESTAURANT category)."""
    try:
        restaurant = restaurant_service.create_restaurant(db, user_id=current_user.id, data=data)
        return success_response(data=restaurant, message="Restaurant created successfully")
    except ValueError as exc:
        return error_response(message=str(exc), error_code="RESTAURANT_CREATE_FAILED", status_code=400)
    except Exception as exc:  # noqa: BLE001
        return error_response(message=str(exc), error_code="RESTAURANT_CREATE_FAILED", status_code=500)


@router.put("/{restaurant_id}")
async def update_restaurant(
    restaurant_id: int,
    data: RestaurantUpdate,
    db: Session = Depends(get_db),
    current_user=Depends(get_current_user),
):
    """Update restaurant profile (owner only)."""
    try:
        restaurant = restaurant_service.update_restaurant(
            db, user_id=current_user.id, restaurant_id=restaurant_id, data=data
        )
        if restaurant is None:
            return error_response(message="Restaurant not found", error_code="RESTAURANT_NOT_FOUND", status_code=404)
        return success_response(data=restaurant, message="Restaurant updated successfully")
    except PermissionError as exc:
        return error_response(message=str(exc), error_code="FORBIDDEN", status_code=403)
    except Exception as exc:  # noqa: BLE001
        return error_response(message=str(exc), error_code="RESTAURANT_UPDATE_FAILED", status_code=500)


@router.post("/{restaurant_id}/menu-categories")
async def create_menu_category(
    restaurant_id: int,
    data: RestaurantMenuCategoryCreate,
    db: Session = Depends(get_db),
    current_user=Depends(get_current_user),
):
    """Add a menu category to a restaurant (owner only)."""
    try:
        category = restaurant_service.create_menu_category(
            db, user_id=current_user.id, restaurant_id=restaurant_id, data=data
        )
        if category is None:
            return error_response(message="Restaurant not found", error_code="RESTAURANT_NOT_FOUND", status_code=404)
        return success_response(data=category, message="Menu category created")
    except PermissionError as exc:
        return error_response(message=str(exc), error_code="FORBIDDEN", status_code=403)
    except Exception as exc:  # noqa: BLE001
        return error_response(message=str(exc), error_code="MENU_CATEGORY_CREATE_FAILED", status_code=500)


@router.post("/{restaurant_id}/menu-items")
async def create_menu_item(
    restaurant_id: int,
    data: RestaurantMenuItemCreate,
    db: Session = Depends(get_db),
    current_user=Depends(get_current_user),
):
    """Add a menu item to a restaurant (owner only)."""
    try:
        item = restaurant_service.create_menu_item(
            db, user_id=current_user.id, restaurant_id=restaurant_id, data=data
        )
        if item is None:
            return error_response(message="Restaurant not found", error_code="RESTAURANT_NOT_FOUND", status_code=404)
        return success_response(data=item, message="Menu item created")
    except PermissionError as exc:
        return error_response(message=str(exc), error_code="FORBIDDEN", status_code=403)
    except Exception as exc:  # noqa: BLE001
        return error_response(message=str(exc), error_code="MENU_ITEM_CREATE_FAILED", status_code=500)


@router.put("/{restaurant_id}/menu-items/{item_id}")
async def update_menu_item(
    restaurant_id: int,
    item_id: int,
    data: RestaurantMenuItemCreate,
    db: Session = Depends(get_db),
    current_user=Depends(get_current_user),
):
    """Update a menu item (owner only)."""
    try:
        item = restaurant_service.update_menu_item(
            db, user_id=current_user.id, restaurant_id=restaurant_id, item_id=item_id, data=data
        )
        if item is None:
            return error_response(message="Menu item not found", error_code="MENU_ITEM_NOT_FOUND", status_code=404)
        return success_response(data=item, message="Menu item updated")
    except PermissionError as exc:
        return error_response(message=str(exc), error_code="FORBIDDEN", status_code=403)
    except Exception as exc:  # noqa: BLE001
        return error_response(message=str(exc), error_code="MENU_ITEM_UPDATE_FAILED", status_code=500)


@router.delete("/{restaurant_id}/menu-items/{item_id}")
async def delete_menu_item(
    restaurant_id: int,
    item_id: int,
    db: Session = Depends(get_db),
    current_user=Depends(get_current_user),
):
    """Soft-delete a menu item (owner only)."""
    try:
        result = restaurant_service.delete_menu_item(
            db, user_id=current_user.id, restaurant_id=restaurant_id, item_id=item_id
        )
        if not result:
            return error_response(message="Menu item not found", error_code="MENU_ITEM_NOT_FOUND", status_code=404)
        return success_response(message="Menu item deleted")
    except PermissionError as exc:
        return error_response(message=str(exc), error_code="FORBIDDEN", status_code=403)
    except Exception as exc:  # noqa: BLE001
        return error_response(message=str(exc), error_code="MENU_ITEM_DELETE_FAILED", status_code=500)
