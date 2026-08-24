"""Phase 22 — Shopkeeper App business routes (/shopkeeper/*).

Every endpoint resolves a ShopAccess context first: only active owners,
managers (with granted permissions) and admins may touch a shop's data.
Unauthorized shop access always yields 403.
"""

from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session

from app.core.dependencies import get_current_user
from app.core.exceptions import ForbiddenError, ValidationError
from app.core.responses import success_response
from app.database.session import get_db
from app.models.user import User
from app.schemas.shopkeeper import (
    ShopkeeperProductCreate,
    ShopkeeperProductUpdate,
    ShopkeeperProfileUpdate,
    ShopkeeperSettingsUpdate,
    ShopkeeperShopCreate,
)
from app.services import shopkeeper_service

router = APIRouter(prefix="/shopkeeper", tags=["shopkeeper"])


def shop_access_dependency(shop_id: int):
    """FastAPI dependency factory resolving ShopAccess for a path shop_id."""

    def resolver(
        current_user: User = Depends(get_current_user),
        db: Session = Depends(get_db),
    ):
        return shopkeeper_service.resolve_shop_access(db, current_user, shop_id)

    return resolver


@router.get("/shops")
async def list_my_shops(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """All shops the signed-in user owns or manages."""
    shops = shopkeeper_service.list_authorized_shops(db, current_user)
    return success_response(
        data={"shops": shops, "count": len(shops)}, message="OK"
    )


@router.post("/shops", status_code=201)
async def register_shop(
    payload: ShopkeeperShopCreate,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Register a new shop; the caller becomes its primary owner."""
    from app.core.exceptions import AppError
    from app.core.responses import error_response

    data = payload.model_dump(exclude_none=True)
    try:
        shop = shopkeeper_service.register_shop_for_shopkeeper(db, current_user, data)
    except (ValidationError, AppError) as exc:
        return error_response(
            message=exc.message,
            error_code=exc.error_code,
            status_code=exc.status_code,
            data=exc.data if hasattr(exc, "data") else None,
        )
    db.commit()
    access = shopkeeper_service.resolve_shop_access(db, current_user, shop.id)
    return success_response(
        data=shopkeeper_service.shop_detail_payload(access, db),
        message="Shop registered successfully",
        status_code=201,
    )


def _validation_error(exc: ValidationError):
    from app.core.responses import error_response

    return error_response(
        message=exc.message, error_code=exc.error_code, status_code=exc.status_code
    )



@router.get("/shops/{shop_id}")
async def get_shop(
    shop_id: int,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Shop profile + verification + subscription (authorized members only)."""
    access = shopkeeper_service.resolve_shop_access(db, current_user, shop_id)
    return success_response(data=shopkeeper_service.shop_detail_payload(access, db))


@router.put("/shops/{shop_id}/profile")
async def update_shop_profile(
    shop_id: int,
    payload: ShopkeeperProfileUpdate,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    access = shopkeeper_service.resolve_shop_access(db, current_user, shop_id)
    result = shopkeeper_service.update_shop_profile(
        access, db, payload.model_dump(exclude_none=True)
    )
    db.commit()
    return success_response(data=result, message="Shop profile updated")


@router.put("/shops/{shop_id}/settings")
async def update_shop_settings(
    shop_id: int,
    payload: ShopkeeperSettingsUpdate,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    access = shopkeeper_service.resolve_shop_access(db, current_user, shop_id)
    result = shopkeeper_service.update_shop_settings(
        access, db, payload.model_dump(exclude_none=True)
    )
    db.commit()
    return success_response(data=result, message="Shop settings updated")


@router.get("/shops/{shop_id}/dashboard")
async def get_dashboard(
    shop_id: int,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Operational dashboard for one authorized shop."""
    access = shopkeeper_service.resolve_shop_access(db, current_user, shop_id)
    access.require("dashboard", "read")
    return success_response(data=shopkeeper_service.dashboard_payload(access, db))


@router.get("/shops/{shop_id}/inventory")
async def get_inventory_overview(
    shop_id: int,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    access = shopkeeper_service.resolve_shop_access(db, current_user, shop_id)
    access.require("inventory", "read")
    overview = shopkeeper_service.inventory_overview(access, db)
    return success_response(data=overview)


@router.get("/shops/{shop_id}/products")
async def list_products(
    shop_id: int,
    search: str | None = Query(None, max_length=120),
    status: str | None = Query(None, max_length=30),
    stock_status: str | None = Query(None, max_length=30),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    access = shopkeeper_service.resolve_shop_access(db, current_user, shop_id)
    access.require("product", "read")
    products = shopkeeper_service.list_products(
        access, db, search=search, status_filter=status, stock_filter=stock_status
    )
    return success_response(data={"products": products, "count": len(products)})


@router.post("/shops/{shop_id}/products", status_code=201)
async def create_product(
    shop_id: int,
    payload: ShopkeeperProductCreate,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    from app.core.exceptions import AppError
    from app.core.responses import error_response

    access = shopkeeper_service.resolve_shop_access(db, current_user, shop_id)
    access.require("product", "create")
    try:
        product = shopkeeper_service.create_product(
            access, db, current_user, payload.model_dump(exclude_none=True)
        )
    except AppError as exc:
        return error_response(message=exc.message, error_code=exc.error_code, status_code=exc.status_code)
    db.commit()
    return success_response(data=product, message="Product created", status_code=201)


@router.patch("/shops/{shop_id}/products/{shop_product_id}")
async def update_product(
    shop_id: int,
    shop_product_id: int,
    payload: ShopkeeperProductUpdate,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    from app.core.exceptions import AppError
    from app.core.responses import error_response

    access = shopkeeper_service.resolve_shop_access(db, current_user, shop_id)
    access.require("product", "update")
    try:
        product = shopkeeper_service.update_product(
            access, db, current_user, shop_product_id, payload.model_dump(exclude_none=True)
        )
    except AppError as exc:
        return error_response(message=exc.message, error_code=exc.error_code, status_code=exc.status_code)
    db.commit()
    return success_response(data=product, message="Product updated")

