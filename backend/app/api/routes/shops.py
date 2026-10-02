"""Shop Management System API routes — registration, ownership, verification, management, and customer-facing profiles."""

from typing import Optional

from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session

from app.core.dependencies import get_current_user, require_admin
from app.core.responses import error_response, success_response
from app.database.session import get_db
from app.models.product import Inventory, ProductMaster, ShopProduct
from app.models.shop import (
    Shop,
    ShopAddress,
    ShopCategory,
    ShopDocument,
    ShopHoliday,
    ShopHour,
    ShopManager,
    ShopOwner,
    ShopStatus,
    ShopVerification,
    VerificationStatus,
)
from app.models.user import User
from app.schemas.shop import (
    NearbyShopResponse,
    ShopAddressCreate,
    ShopAddressResponse,
    ShopAddressUpdate,
    ShopCreate,
    ShopDetailResponse,
    ShopDocumentCreate,
    ShopDocumentResponse,
    ShopHolidayCreate,
    ShopHolidayResponse,
    ShopHourCreate,
    ShopHourResponse,
    ShopManagerCreate,
    ShopManagerResponse,
    ShopOwnerResponse,
    ShopProductSummarySchema,
    ShopPublicResponse,
    ShopResponse,
    ShopStatusUpdate,
    ShopUpdate,
    ShopVerificationResponse,
    ShopVerificationReview,
)
from app.services import shop_service
from app.services.geo_service import haversine_km

router = APIRouter(prefix="/shops", tags=["shops"])


# ── Customer-facing endpoints ──────────────────────────────────────────────
@router.get("/nearby")
async def get_nearby_shops(
    latitude: float = Query(..., ge=-90, le=90),
    longitude: float = Query(..., ge=-180, le=180),
    radius_km: float = Query(5.0, gt=0, le=100),
    db: Session = Depends(get_db),
):
    """Return verified active shops near the user within the given radius."""
    try:
        results = shop_service.nearby_shops(db, latitude=latitude, longitude=longitude, radius_km=radius_km)
        return success_response(data=results)
    except Exception as exc:  # noqa: BLE001
        return error_response(message=str(exc), error_code="NEARBY_SHOPS_FAILED", status_code=400)


@router.get("/public/{shop_id}")
async def get_public_shop(
    shop_id: int,
    db: Session = Depends(get_db),
):
    """Customer-facing shop profile. Only visible/verified shops are returned."""
    shop = shop_service.get_shop_detail(db, shop_id)
    if shop is None:
        return error_response(message="Shop not found", error_code="SHOP_NOT_FOUND", status_code=404)

    # Visibility rule: only ACTIVE/VERIFIED shops are visible to customers
    if shop.status not in (ShopStatus.ACTIVE, ShopStatus.VERIFIED) or not shop.is_verified:
        return error_response(message="Shop not found", error_code="SHOP_NOT_FOUND", status_code=404)

    data = ShopPublicResponse.model_validate(shop).model_dump()
    data["is_open_now"] = shop_service.is_shop_open(shop)
    data["subcategories"] = shop_service.parse_subcategories(shop.subcategories)
    # Business type + capabilities: what the customer may be shown for THIS
    # business. Resolved server-side so a restaurant or a service provider can
    # never be rendered with product-style price/stock UI by a client guess.
    data.update(shop_service.customer_facing_business(db, shop))
    return success_response(data=data)


@router.get("/{shop_id}")
async def get_shop(
    shop_id: int,
    latitude: float | None = Query(None, ge=-90, le=90),
    longitude: float | None = Query(None, ge=-180, le=180),
    db: Session = Depends(get_db),
):
    """Return full shop profile including inventory and distance."""
    shop = shop_service.get_shop_detail(db, shop_id)
    if shop is None:
        return error_response(message="Shop not found", error_code="SHOP_NOT_FOUND", status_code=404)

    distance_km = 0.0
    if latitude is not None and longitude is not None and shop.latitude and shop.longitude:
        distance_km = haversine_km(latitude, longitude, shop.latitude, shop.longitude)

    # Fetch shop products + inventory
    shop_products = (
        db.query(ShopProduct)
        .filter(ShopProduct.shop_id == shop_id, ShopProduct.is_visible == True)  # noqa: E712
        .all()
    )

    available_products = []
    last_updated = None
    for sp in shop_products:
        inv = db.query(Inventory).filter(Inventory.shop_product_id == sp.id).first()
        if inv is None:
            continue
        product = db.query(ProductMaster).filter(ProductMaster.id == sp.product_master_id).first()
        if product is None:
            continue
        image_url = ""
        if product.images:
            primary = [img for img in product.images if img.is_primary]
            image_url = (primary[0].image_url if primary else product.images[0].image_url) or ""
        available_products.append(
            ShopProductSummarySchema(
                product_id=product.id,
                name=product.name,
                image_url=image_url,
                price=float(sp.price),
                is_available=inv.is_available,
                stock_status=inv.stock_status.value if hasattr(inv.stock_status, "value") else str(inv.stock_status),
            )
        )
        if last_updated is None or inv.updated_at > last_updated:
            last_updated = inv.updated_at

    data = ShopDetailResponse.model_validate(shop).model_dump()
    data["distance_km"] = round(distance_km, 2)
    data["is_open_now"] = shop_service.is_shop_open(shop)
    data["last_inventory_update"] = last_updated
    data["available_products"] = [p.model_dump() for p in available_products]
    data["subcategories"] = shop_service.parse_subcategories(shop.subcategories)
    # Public contact surface only: primary phone, alternate phone, and email.
    # Ownership, verification workflow, and internal flags stay server-side.
    data["secondary_phone"] = shop.alternate_phone
    # Business type + capabilities, resolved from the merchant category (or the
    # legacy category / business type as fallback). This is what drives the
    # customer app's capability-based rendering of the shop profile.
    data.update(shop_service.customer_facing_business(db, shop))
    return success_response(data=data)


@router.get("/{shop_id}/products")
async def get_shop_products(
    shop_id: int,
    db: Session = Depends(get_db),
):
    """Return all products available at the given shop."""
    shop = db.query(Shop).filter(Shop.id == shop_id).first()
    if shop is None:
        return error_response(message="Shop not found", error_code="SHOP_NOT_FOUND", status_code=404)

    shop_products = (
        db.query(ShopProduct)
        .filter(ShopProduct.shop_id == shop_id, ShopProduct.is_visible == True)  # noqa: E712
        .all()
    )
    products = []
    for sp in shop_products:
        inv = db.query(Inventory).filter(Inventory.shop_product_id == sp.id).first()
        product = db.query(ProductMaster).filter(ProductMaster.id == sp.product_master_id).first()
        if product is None:
            continue
        image_url = ""
        if product.images:
            primary = [img for img in product.images if img.is_primary]
            image_url = (primary[0].image_url if primary else product.images[0].image_url) or ""
        products.append(
            {
                "product_id": product.id,
                "name": product.name,
                "brand": product.brand.name if product.brand else "",
                "image_url": image_url,
                "price": float(sp.price),
                "is_available": inv.is_available if inv else sp.is_available,
                "stock_status": (inv.stock_status.value if inv and hasattr(inv.stock_status, "value") else "UNKNOWN"),
            }
        )

    return success_response(data=products)


# ── Shop registration (Shopkeeper-facing) ─────────────────────────────────
@router.post("")
async def register_shop(
    payload: ShopCreate,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Register a new shop. The current user becomes the primary owner."""
    try:
        shop = shop_service.register_shop(db, payload.model_dump(), owner_user_id=current_user.id)
        db.commit()
        return success_response(
            data=ShopResponse.model_validate(shop).model_dump(),
            message="Shop registered successfully",
            status_code=201,
        )
    except ValueError as exc:
        db.rollback()
        return error_response(message=str(exc), error_code="SHOP_REGISTRATION_FAILED", status_code=400)
    except Exception as exc:  # noqa: BLE001
        db.rollback()
        return error_response(message=str(exc), error_code="SHOP_REGISTRATION_FAILED", status_code=400)


@router.get("/my/shops")
async def get_my_shops(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Return all shops the current user owns or manages."""
    shop_ids = shop_service.user_shop_ids(db, current_user.id)
    shops = db.query(Shop).filter(Shop.id.in_(shop_ids), Shop.is_deleted == False).all()  # noqa: E712
    return success_response(data=[ShopResponse.model_validate(s).model_dump() for s in shops])


@router.get("/my/shops/{shop_id}")
async def get_my_shop(
    shop_id: int,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Return full detail of a shop the current user owns/manages."""
    if not shop_service.has_shop_access(db, current_user, shop_id):
        return error_response(message="Access denied", error_code="FORBIDDEN", status_code=403)

    shop = shop_service.get_shop_detail(db, shop_id)
    if shop is None:
        return error_response(message="Shop not found", error_code="SHOP_NOT_FOUND", status_code=404)

    data = ShopDetailResponse.model_validate(shop).model_dump()
    data["subcategories"] = shop_service.parse_subcategories(shop.subcategories)
    return success_response(data=data)


@router.put("/my/shops/{shop_id}")
async def update_my_shop(
    shop_id: int,
    payload: ShopUpdate,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Update shop profile (owner/manager only)."""
    if not shop_service.has_shop_access(db, current_user, shop_id):
        return error_response(message="Access denied", error_code="FORBIDDEN", status_code=403)

    try:
        shop = shop_service.update_shop(db, shop_id, payload.model_dump(exclude_unset=True))
        if shop is None:
            return error_response(message="Shop not found", error_code="SHOP_NOT_FOUND", status_code=404)
        db.commit()
        return success_response(data=ShopResponse.model_validate(shop).model_dump(), message="Shop updated")
    except ValueError as exc:
        db.rollback()
        return error_response(message=str(exc), error_code="SHOP_UPDATE_FAILED", status_code=400)


# ── Address management ─────────────────────────────────────────────────────
@router.post("/my/shops/{shop_id}/addresses")
async def add_address(
    shop_id: int,
    payload: ShopAddressCreate,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Add a new address to the shop."""
    if not shop_service.has_shop_access(db, current_user, shop_id):
        return error_response(message="Access denied", error_code="FORBIDDEN", status_code=403)

    try:
        addr = shop_service.add_shop_address(db, shop_id, payload.model_dump())
        db.commit()
        return success_response(
            data=ShopAddressResponse.model_validate(addr).model_dump(),
            message="Address added",
            status_code=201,
        )
    except ValueError as exc:
        db.rollback()
        return error_response(message=str(exc), error_code="ADDRESS_ADD_FAILED", status_code=400)


@router.put("/my/shops/addresses/{address_id}")
async def update_address(
    address_id: int,
    payload: ShopAddressUpdate,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Update a shop address."""
    addr = db.query(ShopAddress).filter(ShopAddress.id == address_id).first()
    if addr is None:
        return error_response(message="Address not found", error_code="ADDRESS_NOT_FOUND", status_code=404)

    if not shop_service.has_shop_access(db, current_user, addr.shop_id):
        return error_response(message="Access denied", error_code="FORBIDDEN", status_code=403)

    addr = shop_service.update_shop_address(db, address_id, payload.model_dump(exclude_unset=True))
    db.commit()
    return success_response(data=ShopAddressResponse.model_validate(addr).model_dump(), message="Address updated")


@router.delete("/my/shops/addresses/{address_id}")
async def delete_address(
    address_id: int,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Delete a shop address."""
    addr = db.query(ShopAddress).filter(ShopAddress.id == address_id).first()
    if addr is None:
        return error_response(message="Address not found", error_code="ADDRESS_NOT_FOUND", status_code=404)

    if not shop_service.has_shop_access(db, current_user, addr.shop_id):
        return error_response(message="Access denied", error_code="FORBIDDEN", status_code=403)

    shop_service.delete_shop_address(db, address_id)
    db.commit()
    return success_response(data=None, message="Address deleted")


# ── Hours management ───────────────────────────────────────────────────────
@router.put("/my/shops/{shop_id}/hours")
async def set_hours(
    shop_id: int,
    payload: list[ShopHourCreate],
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Replace all opening hours for a shop."""
    if not shop_service.has_shop_access(db, current_user, shop_id):
        return error_response(message="Access denied", error_code="FORBIDDEN", status_code=403)

    try:
        hours = shop_service.set_shop_hours(db, shop_id, [h.model_dump() for h in payload])
        db.commit()
        return success_response(
            data=[ShopHourResponse.model_validate(h).model_dump() for h in hours],
            message="Opening hours updated",
        )
    except ValueError as exc:
        db.rollback()
        return error_response(message=str(exc), error_code="HOURS_UPDATE_FAILED", status_code=400)


# ── Holidays management ────────────────────────────────────────────────────
@router.post("/my/shops/{shop_id}/holidays")
async def add_holiday(
    shop_id: int,
    payload: ShopHolidayCreate,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Add a holiday to the shop's schedule."""
    if not shop_service.has_shop_access(db, current_user, shop_id):
        return error_response(message="Access denied", error_code="FORBIDDEN", status_code=403)

    holiday = shop_service.add_shop_holiday(db, shop_id, payload.model_dump())
    db.commit()
    return success_response(
        data=ShopHolidayResponse.model_validate(holiday).model_dump(),
        message="Holiday added",
        status_code=201,
    )


@router.delete("/my/shops/holidays/{holiday_id}")
async def delete_holiday(
    holiday_id: int,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Delete a holiday from the shop's schedule."""
    holiday = db.query(ShopHoliday).filter(ShopHoliday.id == holiday_id).first()
    if holiday is None:
        return error_response(message="Holiday not found", error_code="HOLIDAY_NOT_FOUND", status_code=404)

    if not shop_service.has_shop_access(db, current_user, holiday.shop_id):
        return error_response(message="Access denied", error_code="FORBIDDEN", status_code=403)

    shop_service.remove_shop_holiday(db, holiday_id)
    db.commit()
    return success_response(data=None, message="Holiday deleted")


# ── Documents management ───────────────────────────────────────────────────
@router.post("/my/shops/{shop_id}/documents")
async def submit_document(
    shop_id: int,
    payload: ShopDocumentCreate,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Submit a verification document for the shop."""
    if not shop_service.has_shop_access(db, current_user, shop_id):
        return error_response(message="Access denied", error_code="FORBIDDEN", status_code=403)

    doc = shop_service.submit_shop_document(db, shop_id, payload.model_dump())
    db.commit()
    return success_response(
        data=ShopDocumentResponse.model_validate(doc).model_dump(),
        message="Document submitted",
        status_code=201,
    )


# ── Verification workflow ──────────────────────────────────────────────────
@router.post("/my/shops/{shop_id}/submit-verification")
async def submit_verification(
    shop_id: int,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Submit shop for admin verification."""
    if not shop_service.has_shop_access(db, current_user, shop_id):
        return error_response(message="Access denied", error_code="FORBIDDEN", status_code=403)

    verification = shop_service.submit_for_verification(db, shop_id, submitted_by=current_user.id)
    if verification is None:
        return error_response(message="Shop not found", error_code="SHOP_NOT_FOUND", status_code=404)
    db.commit()
    return success_response(
        data=ShopVerificationResponse.model_validate(verification).model_dump(),
        message="Shop submitted for verification",
    )


# ── Admin endpoints ────────────────────────────────────────────────────────
@router.get("/admin/shops")
async def admin_list_shops(
    status: Optional[ShopStatus] = Query(None),
    category: Optional[ShopCategory] = Query(None),
    search: Optional[str] = Query(None, max_length=200),
    page: int = Query(1, ge=1),
    limit: int = Query(20, ge=1, le=100),
    _admin: User = Depends(require_admin),
    db: Session = Depends(get_db),
):
    """Admin: list all shops with filters."""

    skip = (page - 1) * limit
    shops = shop_service.list_shops(
        db,
        status=status,
        category=category,
        search=search,
        skip=skip,
        limit=limit,
    )
    return success_response(
        data={
            "items": [ShopResponse.model_validate(s).model_dump() for s in shops],
            "page": page,
            "limit": limit,
        }
    )


@router.post("/admin/shops/{shop_id}/review")
async def admin_review_shop(
    shop_id: int,
    payload: ShopVerificationReview,
    _admin: User = Depends(require_admin),
    db: Session = Depends(get_db),
):
    """Admin: review shop verification (APPROVE/REJECT/SUSPEND/REACTIVATE)."""

    try:
        verification = shop_service.review_verification(
            db,
            shop_id=shop_id,
            reviewer_id=_admin.id,
            decision=payload.decision,
            review_notes=payload.review_notes,
        )
        if verification is None:
            return error_response(message="Shop not found", error_code="SHOP_NOT_FOUND", status_code=404)
        db.commit()
        return success_response(
            data=ShopVerificationResponse.model_validate(verification).model_dump(),
            message=f"Shop {payload.decision.lower()}d",
        )
    except ValueError as exc:
        db.rollback()
        return error_response(message=str(exc), error_code="REVIEW_FAILED", status_code=400)


@router.put("/admin/shops/{shop_id}/status")
async def admin_update_status(
    shop_id: int,
    payload: ShopStatusUpdate,
    _admin: User = Depends(require_admin),
    db: Session = Depends(get_db),
):
    """Admin: update shop status directly."""

    shop = shop_service.update_shop_status(db, shop_id, payload.status, reason=payload.reason)
    if shop is None:
        return error_response(message="Shop not found", error_code="SHOP_NOT_FOUND", status_code=404)
    db.commit()
    return success_response(data=ShopResponse.model_validate(shop).model_dump(), message="Shop status updated")


@router.post("/admin/shops/{shop_id}/documents/{document_id}/verify")
async def admin_verify_document(
    shop_id: int,
    document_id: int,
    is_verified: bool = Query(True),
    rejection_reason: Optional[str] = Query(None),
    _admin: User = Depends(require_admin),
    db: Session = Depends(get_db),
):
    """Admin: verify or reject a shop document."""

    doc = shop_service.verify_document(
        db,
        document_id=document_id,
        reviewer_id=_admin.id,
        is_verified=is_verified,
        rejection_reason=rejection_reason,
    )
    if doc is None:
        return error_response(message="Document not found", error_code="DOCUMENT_NOT_FOUND", status_code=404)
    db.commit()
    return success_response(
        data=ShopDocumentResponse.model_validate(doc).model_dump(),
        message="Document verified" if is_verified else "Document rejected",
    )


# ── Owner / Manager management ─────────────────────────────────────────────
@router.post("/my/shops/{shop_id}/owners")
async def add_owner(
    shop_id: int,
    user_id: int = Query(..., description="User ID to add as owner"),
    is_primary: bool = Query(False),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Add an owner to the shop (owner only)."""
    if not shop_service.is_user_owner(db, current_user.id, shop_id):
        return error_response(message="Only shop owners can add owners", error_code="FORBIDDEN", status_code=403)

    try:
        owner = shop_service.add_owner(db, shop_id, user_id, is_primary=is_primary)
        db.commit()
        return success_response(
            data=ShopOwnerResponse.model_validate(owner).model_dump(),
            message="Owner added",
            status_code=201,
        )
    except ValueError as exc:
        db.rollback()
        return error_response(message=str(exc), error_code="OWNER_ADD_FAILED", status_code=400)


@router.delete("/my/shops/{shop_id}/owners/{user_id}")
async def remove_owner(
    shop_id: int,
    user_id: int,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Remove an owner from the shop (owner only)."""
    if not shop_service.is_user_owner(db, current_user.id, shop_id):
        return error_response(message="Only shop owners can remove owners", error_code="FORBIDDEN", status_code=403)

    if shop_service.remove_owner(db, shop_id, user_id):
        db.commit()
        return success_response(data=None, message="Owner removed")
    return error_response(message="Owner not found", error_code="OWNER_NOT_FOUND", status_code=404)


@router.post("/my/shops/{shop_id}/managers")
async def add_manager(
    shop_id: int,
    payload: ShopManagerCreate,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Add a manager to the shop (owner only)."""
    if not shop_service.is_user_owner(db, current_user.id, shop_id):
        return error_response(message="Only shop owners can add managers", error_code="FORBIDDEN", status_code=403)

    try:
        manager = shop_service.add_manager(db, shop_id, payload.user_id, permissions=payload.permissions)
        db.commit()
        return success_response(
            data=ShopManagerResponse.model_validate(manager).model_dump(),
            message="Manager added",
            status_code=201,
        )
    except ValueError as exc:
        db.rollback()
        return error_response(message=str(exc), error_code="MANAGER_ADD_FAILED", status_code=400)


@router.delete("/my/shops/{shop_id}/managers/{user_id}")
async def remove_manager(
    shop_id: int,
    user_id: int,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Remove a manager from the shop (owner only)."""
    if not shop_service.is_user_owner(db, current_user.id, shop_id):
        return error_response(message="Only shop owners can remove managers", error_code="FORBIDDEN", status_code=403)

    if shop_service.remove_manager(db, shop_id, user_id):
        db.commit()
        return success_response(data=None, message="Manager removed")
    return error_response(message="Manager not found", error_code="MANAGER_NOT_FOUND", status_code=404)