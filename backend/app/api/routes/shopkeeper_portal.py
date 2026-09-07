"""Phase 22 — Shopkeeper App business routes (/shopkeeper/*).

Every endpoint resolves a ShopAccess context first: only active owners,
managers (with granted permissions) and admins may touch a shop's data.
Unauthorized shop access always yields 403.
"""

from fastapi import APIRouter, Depends, Query, Request
from sqlalchemy.orm import Session

from app.core.dependencies import get_current_user
from app.core.exceptions import ForbiddenError, ValidationError
from app.core.responses import success_response
from app.database.session import get_db
from app.models.user import User
from app.schemas.shopkeeper import (
    ShopkeeperAddFromMaster,
    ShopkeeperBulkOperation,
    ShopkeeperOfferAssign,
    ShopkeeperProductCreate,
    ShopkeeperProductUpdate,
    ShopkeeperProfileUpdate,
    ShopkeeperSettingsUpdate,
    ShopkeeperShopCreate,
    ShopkeeperShopLocationUpdate,
    ShopkeeperStockAdjustment,
)
from app.services import media_service, shopkeeper_service

router = APIRouter(prefix="/shopkeeper", tags=["shopkeeper"])


async def _resolve_image_key(db: Session, user: User, key: str, category: str, shop_id: int) -> str:
    """Phase 7 — resolve a confirmed media key into a durable storage ref.

    Validates key shape, category match (PRODUCT_IMAGE vs SHOP_IMAGE), scope
    (the key must have been minted for THIS shop) and object existence, then
    returns ``s3://{bucket}/{key}`` for persistence in DB columns. The media
    service raises typed AppErrors which the handlers already translate.
    """
    attachment = await media_service.attach_media(
        db, user, key=key, expected_category=category, shop_id=shop_id,
    )
    return attachment["storage_ref"]


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
    data = payload.model_dump(exclude_none=True)
    if data.get("image_key"):
        # Phase 7 — attach the uploaded shop image to the shop profile.
        data["image_url"] = await _resolve_image_key(
            db, current_user, data.pop("image_key"), "SHOP_IMAGE", shop_id,
        )
    if data.get("logo_key"):
        # Phase 7 — attach the uploaded shop logo (same SHOP_IMAGE rules).
        data["logo_url"] = await _resolve_image_key(
            db, current_user, data.pop("logo_key"), "SHOP_IMAGE", shop_id,
        )
    result = shopkeeper_service.update_shop_profile(access, db, data)
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


@router.patch("/shops/{shop_id}/location")
async def update_shop_location(
    shop_id: int,
    payload: ShopkeeperShopLocationUpdate,
    request: Request,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Controlled shop-location update (Edit Location workflow).

    The target shop is resolved from the PATH ``shop_id`` only — a body-supplied
    id is never trusted — so cross-tenant (IDOR) updates are impossible.
    Managers without ``update:shop`` are rejected (403). Every change is
    appended to the hash-chained audit trail with old/new coordinates,
    accuracies and the acting user.
    """
    from app.core.exceptions import AppError
    from app.core.responses import error_response

    access = shopkeeper_service.resolve_shop_access(db, current_user, shop_id)
    try:
        result = shopkeeper_service.update_shop_location_for_shopkeeper(
            access,
            db,
            current_user,
            latitude=payload.latitude,
            longitude=payload.longitude,
            meta=(
                payload.location.model_dump(exclude_none=True)
                if payload.location
                else None
            ),
            request_meta={
                "ip_address": request.client.host if request.client else None,
                "user_agent": request.headers.get("user-agent"),
            },
        )
    except AppError as exc:
        db.rollback()
        return error_response(
            message=exc.message,
            error_code=exc.error_code,
            status_code=exc.status_code,
        )
    db.commit()
    return success_response(data=result, message="Shop location updated")


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
async def get_inventory(
    shop_id: int,
    search: str | None = Query(None, max_length=120),
    stock_status: str | None = Query(None, max_length=30),
    availability: bool | None = Query(None),
    is_active: bool | None = Query(None),
    sort_by: str = Query("updated_at", max_length=30),
    sort_order: str = Query("desc", max_length=4),
    view: str = Query("overview", max_length=20),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Inventory overview (default) or a filterable/sortable/searchable list
    (``view=list``) — items include last-updated time and inventory source."""
    access = shopkeeper_service.resolve_shop_access(db, current_user, shop_id)
    if str(view).lower() == "list":
        access.require("inventory", "read")
        listing = shopkeeper_service.list_inventory(
            access,
            db,
            search=search,
            stock_filter=stock_status,
            availability_filter=availability,
            active_filter=is_active,
            sort_by=sort_by,
            sort_order=sort_order,
        )
        return success_response(data=listing)
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
    data = payload.model_dump(exclude_none=True)
    if data.get("image_key"):
        # Phase 7 — attach the uploaded product image to the new listing.
        data["image_url"] = await _resolve_image_key(
            db, current_user, data.pop("image_key"), "PRODUCT_IMAGE", shop_id,
        )
    try:
        product = shopkeeper_service.create_product(access, db, current_user, data)
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
    data = payload.model_dump(exclude_none=True)
    if data.get("image_key"):
        # Phase 7 — replace the product image with a newly confirmed upload.
        data["image_url"] = await _resolve_image_key(
            db, current_user, data.pop("image_key"), "PRODUCT_IMAGE", shop_id,
        )
    try:
        product = shopkeeper_service.update_product(
            access, db, current_user, shop_product_id, data
        )
    except AppError as exc:
        return error_response(message=exc.message, error_code=exc.error_code, status_code=exc.status_code)
    db.commit()
    return success_response(data=product, message="Product updated")


# ── Phase 23 — Inventory management ──────────────────────────────────────
@router.get("/shops/{shop_id}/catalog/search")
async def search_catalog(
    shop_id: int,
    q: str | None = Query(None, max_length=120),
    limit: int = Query(20, ge=1, le=50),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Search the shared product-master catalog (with variants) so the
    shopkeeper can SELECT a known product instead of re-creating it."""
    access = shopkeeper_service.resolve_shop_access(db, current_user, shop_id)
    access.require("product", "read")
    results = shopkeeper_service.search_product_masters(db, q, limit=limit)
    return success_response(data={"results": results, "count": len(results)})


@router.post("/shops/{shop_id}/inventory/products", status_code=201)
async def add_product_from_master(
    shop_id: int,
    payload: ShopkeeperAddFromMaster,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Add an EXISTING product-master (optionally a variant) to the shop with
    shop-level price / MRP / availability / quantity."""
    from app.core.exceptions import AppError
    from app.core.responses import error_response

    access = shopkeeper_service.resolve_shop_access(db, current_user, shop_id)
    try:
        product = shopkeeper_service.add_product_from_master(
            access, db, current_user, payload.model_dump(exclude_none=True)
        )
    except AppError as exc:
        return error_response(message=exc.message, error_code=exc.error_code, status_code=exc.status_code)
    db.commit()
    return success_response(data=product, message="Product added to inventory", status_code=201)


@router.post("/shops/{shop_id}/products/{shop_product_id}/stock-adjustments")
async def create_stock_adjustment(
    shop_id: int,
    shop_product_id: int,
    payload: ShopkeeperStockAdjustment,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Apply a delta stock adjustment (restock/damage/correction) with a full
    audit trail; updates propagate to the platform inventory system."""
    from app.core.exceptions import AppError
    from app.core.responses import error_response

    access = shopkeeper_service.resolve_shop_access(db, current_user, shop_id)
    try:
        result = shopkeeper_service.adjust_stock(
            access, db, current_user, shop_product_id, payload.model_dump(exclude_none=True)
        )
    except AppError as exc:
        return error_response(message=exc.message, error_code=exc.error_code, status_code=exc.status_code)
    db.commit()
    return success_response(data=result, message="Stock adjusted")


@router.delete("/shops/{shop_id}/products/{shop_product_id}")
async def remove_product(
    shop_id: int,
    shop_product_id: int,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Remove/deactivate a shop product listing (soft delete)."""
    from app.core.exceptions import AppError
    from app.core.responses import error_response

    access = shopkeeper_service.resolve_shop_access(db, current_user, shop_id)
    try:
        result = shopkeeper_service.remove_product(access, db, current_user, shop_product_id)
    except AppError as exc:
        return error_response(message=exc.message, error_code=exc.error_code, status_code=exc.status_code)
    db.commit()
    return success_response(data=result, message="Product removed")


@router.get("/shops/{shop_id}/products/{shop_product_id}/history")
async def get_product_history(
    shop_id: int,
    shop_product_id: int,
    limit: int = Query(50, ge=1, le=200),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Inventory history for one product: movements, adjustments and price changes."""
    from app.core.exceptions import AppError
    from app.core.responses import error_response

    access = shopkeeper_service.resolve_shop_access(db, current_user, shop_id)
    try:
        result = shopkeeper_service.product_history(
            access, db, current_user, shop_product_id, limit=limit
        )
    except AppError as exc:
        return error_response(message=exc.message, error_code=exc.error_code, status_code=exc.status_code)
    return success_response(data=result)


@router.post("/shops/{shop_id}/inventory/bulk")
async def bulk_inventory_operation(
    shop_id: int,
    payload: ShopkeeperBulkOperation,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Bulk operations foundation: price_update / stock_set / availability."""
    from app.core.exceptions import AppError
    from app.core.responses import error_response

    access = shopkeeper_service.resolve_shop_access(db, current_user, shop_id)
    try:
        result = shopkeeper_service.bulk_operation(
            access, db, current_user, payload.model_dump(exclude_none=True)
        )
    except AppError as exc:
        return error_response(message=exc.message, error_code=exc.error_code, status_code=exc.status_code)
    db.commit()
    return success_response(data=result, message="Bulk operation processed")


@router.post("/shops/{shop_id}/offers/assign", status_code=201)
async def assign_offer_to_products(
    shop_id: int,
    payload: ShopkeeperOfferAssign,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Assign (create + link) an offer to selected shop products."""
    from app.core.exceptions import AppError
    from app.core.responses import error_response

    access = shopkeeper_service.resolve_shop_access(db, current_user, shop_id)
    try:
        result = shopkeeper_service.assign_offer(
            access, db, current_user, payload.model_dump(exclude_none=True)
        )
    except AppError as exc:
        return error_response(message=exc.message, error_code=exc.error_code, status_code=exc.status_code)
    db.commit()
    return success_response(data=result, message="Offer assigned", status_code=201)

@router.get("/leads")
async def shopkeeper_leads(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """All verified customer leads (call views, messages, ratings) tied to the
    shops this user owns/manages. Read-only — customer submissions are
    immutable and cannot be edited or deleted through the API.
    """
    from app.services import interaction_service

    leads = interaction_service.list_shopkeeper_leads(db, current_user)
    return success_response(
        data={"leads": leads, "count": len(leads)}, message="OK"
    )
