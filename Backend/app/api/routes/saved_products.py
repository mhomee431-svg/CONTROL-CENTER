from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from app.core.dependencies import get_current_user
from app.core.responses import error_response, success_response
from app.database.session import get_db
from app.models.product import ProductMaster, ShopProduct, Inventory
from app.models.saved_product import SavedProduct
from app.models.user import User
from app.schemas.saved import SavedProductResponse

router = APIRouter(prefix="/saved-products", tags=["saved-products"])


@router.get("")
async def list_saved_products(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Return all products saved by the current user."""
    saved = (
        db.query(SavedProduct)
        .filter(SavedProduct.user_id == current_user.id)
        .order_by(SavedProduct.created_at.desc())
        .all()
    )

    items = []
    for s in saved:
        product = db.query(ProductMaster).filter(ProductMaster.id == s.product_master_id).first()
        if product is None:
            continue
        # Find the lowest price across all shop_products for this master product
        lowest_price_item = (
            db.query(ShopProduct)
            .filter(ShopProduct.product_master_id == product.id, ShopProduct.is_visible == True)
            .order_by(ShopProduct.price.asc())
            .first()
        )
        image_url = ""
        if product.images:
            primary = [img for img in product.images if img.is_primary]
            image_url = (primary[0].image_url if primary else product.images[0].image_url) or ""
        items.append(
            SavedProductResponse(
                product_id=product.id,
                name=product.name,
                brand=product.brand.name if product.brand else None,
                lowest_price=float(lowest_price_item.price) if lowest_price_item else None,
                image_url=image_url,
                saved_at=s.created_at,
            ).model_dump()
        )

    return success_response(data={"items": items})


@router.post("/{product_id}")
async def save_product(
    product_id: int,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Save a product for the current user."""
    product = db.query(ProductMaster).filter(ProductMaster.id == product_id).first()
    if product is None:
        return error_response(message="Product not found", error_code="PRODUCT_NOT_FOUND", status_code=404)

    exists = (
        db.query(SavedProduct)
        .filter(SavedProduct.user_id == current_user.id, SavedProduct.product_master_id == product_id)
        .first()
    )
    if exists is None:
        db.add(SavedProduct(user_id=current_user.id, product_master_id=product_id))
        db.commit()

    return success_response(data=None, message="Product saved")


@router.delete("/{product_id}")
async def unsave_product(
    product_id: int,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Remove a product from the current user's saved list."""
    saved = (
        db.query(SavedProduct)
        .filter(SavedProduct.user_id == current_user.id, SavedProduct.product_master_id == product_id)
        .first()
    )
    if saved is None:
        return error_response(message="Product not in saved list", error_code="NOT_SAVED", status_code=404)

    db.delete(saved)
    db.commit()
    return success_response(data=None, message="Product removed from saved")