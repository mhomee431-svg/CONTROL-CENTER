from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session

from app.core.dependencies import get_current_user
from app.core.responses import error_response, success_response
from app.database.session import get_db
from app.models.saved_shop import SavedShop
from app.models.shop import Shop
from app.models.user import User
from app.schemas.saved import SavedShopResponse
from app.services.geo_service import haversine_km, resolve_shop_coordinates
from app.services.shop_service import is_shop_open

router = APIRouter(prefix="/saved-shops", tags=["saved-shops"])


@router.get("")
async def list_saved_shops(
    latitude: float | None = Query(None, ge=-90, le=90),
    longitude: float | None = Query(None, ge=-180, le=180),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Return all shops saved by the current user.

    Coordinates are optional and only affect `distance_km`: the list still works
    without them, which matters because a saved shop is exactly the thing a
    customer wants to find again from anywhere — including with location off.

    The open/closed verdict comes from the SAME `is_shop_open` helper the shop
    profile and nearby feed use. Recomputing it here would let the same shop be
    "Open" in one row and "Closed" in another.
    """
    saved = (
        db.query(SavedShop)
        .filter(SavedShop.user_id == current_user.id)
        .order_by(SavedShop.created_at.desc())
        .all()
    )

    items = []
    for s in saved:
        shop = db.query(Shop).filter(Shop.id == s.shop_id).first()
        if shop is None:
            continue

        # Distance only when BOTH ends are known: a missing shop coordinate must
        # not become a confident "0.0 km away" (which reads as "you are here").
        distance_km: float | None = None
        if latitude is not None and longitude is not None:
            shop_longitude, shop_latitude = resolve_shop_coordinates(shop)
            if shop_longitude is not None and shop_latitude is not None:
                distance_km = round(
                    haversine_km(latitude, longitude, shop_latitude, shop_longitude), 2
                )

        items.append(
            SavedShopResponse(
                shop_id=shop.id,
                name=shop.name,
                address=shop.address,
                image_url=shop.image_url,
                rating=shop.rating,
                saved_at=s.created_at,
                distance_km=distance_km,
                is_verified=bool(shop.is_verified),
                is_open_now=bool(is_shop_open(shop)),
                is_accepting_orders=bool(shop.is_accepting_orders),
            ).model_dump()
        )

    return success_response(data={"items": items})


@router.post("/{shop_id}")
async def save_shop(
    shop_id: int,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Save a shop for the current user."""
    shop = db.query(Shop).filter(Shop.id == shop_id).first()
    if shop is None:
        return error_response(message="Shop not found", error_code="SHOP_NOT_FOUND", status_code=404)

    exists = (
        db.query(SavedShop)
        .filter(SavedShop.user_id == current_user.id, SavedShop.shop_id == shop_id)
        .first()
    )
    if exists is None:
        db.add(SavedShop(user_id=current_user.id, shop_id=shop_id))
        db.commit()

    return success_response(data=None, message="Shop saved")


@router.delete("/{shop_id}")
async def unsave_shop(
    shop_id: int,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Remove a shop from the current user's saved list."""
    saved = (
        db.query(SavedShop)
        .filter(SavedShop.user_id == current_user.id, SavedShop.shop_id == shop_id)
        .first()
    )
    if saved is None:
        return error_response(message="Shop not in saved list", error_code="NOT_SAVED", status_code=404)

    db.delete(saved)
    db.commit()
    return success_response(data=None, message="Shop removed from saved")
