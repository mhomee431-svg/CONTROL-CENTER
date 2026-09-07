from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from app.core.dependencies import get_current_user
from app.core.responses import error_response, success_response
from app.database.session import get_db
from app.models.saved_shop import SavedShop
from app.models.shop import Shop
from app.models.user import User
from app.schemas.saved import SavedShopResponse

router = APIRouter(prefix="/saved-shops", tags=["saved-shops"])


@router.get("")
async def list_saved_shops(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Return all shops saved by the current user."""
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
        items.append(
            SavedShopResponse(
                shop_id=shop.id,
                name=shop.name,
                address=shop.address,
                image_url=shop.image_url,
                rating=shop.rating,
                saved_at=s.created_at,
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
