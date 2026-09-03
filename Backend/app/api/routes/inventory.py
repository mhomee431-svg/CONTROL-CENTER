"""Inventory and Pricing Engine API routes — inventory, price history, offers, and freshness."""

from typing import Optional

from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session

from app.core.dependencies import require_admin
from app.core.responses import error_response, success_response
from app.database.session import get_db
from app.models.user import User
from app.models.product import (
    Inventory,
    InventoryAdjustment,
    InventoryMovement,
    Offer,
    OfferStatus,
    PriceHistory,
    ShopProduct,
)
from app.schemas.inventory import (
    InventoryAdjustmentCreate,
    InventoryAdjustmentResponse,
    InventoryCreate,
    InventoryMovementCreate,
    InventoryMovementResponse,
    InventoryResponse,
    InventoryUpdate,
    OfferConditionResponse,
    OfferCreate,
    OfferDetailResponse,
    OfferProductResponse,
    OfferResponse,
    OfferUpdate,
    PriceHistoryResponse,
    PriceUpdate,
)
from app.services import inventory_service

router = APIRouter(prefix="/inventory", tags=["inventory"])


# ── Inventory CRUD ──────────────────────────────────────────────────────────
@router.post("")
async def create_inventory(
    payload: InventoryCreate,
    db: Session = Depends(get_db),
    _admin: User = Depends(require_admin),
):
    """Create a new inventory record for a shop product (admin only)."""
    try:
        inv = inventory_service.create_inventory(db, payload.model_dump())
        db.commit()
        return success_response(
            data=InventoryResponse.model_validate(inv).model_dump(),
            message="Inventory created",
            status_code=201,
        )
    except ValueError as exc:
        db.rollback()
        return error_response(message=str(exc), error_code="INVENTORY_CREATE_FAILED", status_code=400)


# ── Inventory movements ─────────────────────────────────────────────────────
@router.post("/movements")
async def create_movement(
    payload: InventoryMovementCreate,
    db: Session = Depends(get_db),
    _admin: User = Depends(require_admin),
):
    """Record an inventory movement (sale, restock, return, damage, etc.) — admin only."""
    try:
        movement = inventory_service.record_movement(db, payload.model_dump())
        db.commit()
        return success_response(
            data=InventoryMovementResponse.model_validate(movement).model_dump(),
            message="Movement recorded",
            status_code=201,
        )
    except ValueError as exc:
        db.rollback()
        return error_response(message=str(exc), error_code="MOVEMENT_FAILED", status_code=400)


# ── Inventory adjustments ───────────────────────────────────────────────────
@router.post("/adjustments")
async def create_adjustment(
    payload: InventoryAdjustmentCreate,
    db: Session = Depends(get_db),
    _admin: User = Depends(require_admin),
):
    """Create an inventory adjustment (stock count, damage, expiry, theft) — admin only."""
    try:
        adjustment = inventory_service.create_adjustment(db, payload.model_dump())
        db.commit()
        return success_response(
            data=InventoryAdjustmentResponse.model_validate(adjustment).model_dump(),
            message="Adjustment created",
            status_code=201,
        )
    except ValueError as exc:
        db.rollback()
        return error_response(message=str(exc), error_code="ADJUSTMENT_FAILED", status_code=400)


# ── Price history ───────────────────────────────────────────────────────────
@router.post("/shop-products/{shop_product_id}/price")
async def update_price(
    shop_product_id: int,
    payload: PriceUpdate,
    db: Session = Depends(get_db),
    _admin: User = Depends(require_admin),
):
    """Update the selling price (and optionally MRP) of a shop product, preserving history (admin only)."""
    history = inventory_service.update_price(db, shop_product_id, payload.model_dump())
    if history is None:
        return error_response(message="Shop product not found", error_code="SHOP_PRODUCT_NOT_FOUND", status_code=404)
    db.commit()
    return success_response(
        data=PriceHistoryResponse.model_validate(history).model_dump(),
        message="Price updated",
    )


@router.get("/shop-products/{shop_product_id}/price-history")
async def get_price_history(
    shop_product_id: int,
    limit: int = Query(50, ge=1, le=200),
    db: Session = Depends(get_db),
):
    """Return price history for a shop product."""
    history = inventory_service.list_price_history(db, shop_product_id, limit=limit)
    return success_response(data=[PriceHistoryResponse.model_validate(h).model_dump() for h in history])


# ── Offers ──────────────────────────────────────────────────────────────────
@router.post("/offers")
async def create_offer(
    payload: OfferCreate,
    db: Session = Depends(get_db),
    _admin: User = Depends(require_admin),
):
    """Create a new offer with product mappings and conditions (admin only)."""
    try:
        offer = inventory_service.create_offer(db, payload.model_dump())
        db.commit()
        return success_response(
            data=OfferResponse.model_validate(offer).model_dump(),
            message="Offer created",
            status_code=201,
        )
    except ValueError as exc:
        db.rollback()
        return error_response(message=str(exc), error_code="OFFER_CREATE_FAILED", status_code=400)


@router.get("/offers")
async def list_offers(
    shop_id: Optional[int] = Query(None),
    status: Optional[OfferStatus] = Query(None),
    active_only: bool = Query(False),
    page: int = Query(1, ge=1),
    limit: int = Query(20, ge=1, le=100),
    db: Session = Depends(get_db),
):
    """List offers with optional filters."""
    skip = (page - 1) * limit
    offers = inventory_service.list_offers(
        db,
        shop_id=shop_id,
        status=status,
        active_only=active_only,
        skip=skip,
        limit=limit,
    )
    return success_response(
        data={
            "items": [OfferResponse.model_validate(o).model_dump() for o in offers],
            "page": page,
            "limit": limit,
        }
    )


@router.get("/offers/{offer_id}")
async def get_offer(
    offer_id: int,
    db: Session = Depends(get_db),
):
    """Get an offer with product mappings and conditions."""
    offer = inventory_service.get_offer_detail(db, offer_id)
    if offer is None:
        return error_response(message="Offer not found", error_code="OFFER_NOT_FOUND", status_code=404)
    return success_response(
        data=OfferDetailResponse(
            **OfferResponse.model_validate(offer).model_dump(),
            product_mappings=[OfferProductResponse.model_validate(op).model_dump() for op in offer.offer_products],
            conditions=[OfferConditionResponse.model_validate(c).model_dump() for c in offer.conditions],
        ).model_dump()
    )


@router.put("/offers/{offer_id}")
async def update_offer(
    offer_id: int,
    payload: OfferUpdate,
    db: Session = Depends(get_db),
    _admin: User = Depends(require_admin),
):
    """Update an offer (admin only)."""
    try:
        offer = inventory_service.update_offer(db, offer_id, payload.model_dump(exclude_unset=True))
        if offer is None:
            return error_response(message="Offer not found", error_code="OFFER_NOT_FOUND", status_code=404)
        db.commit()
        return success_response(data=OfferResponse.model_validate(offer).model_dump(), message="Offer updated")
    except ValueError as exc:
        db.rollback()
        return error_response(message=str(exc), error_code="OFFER_UPDATE_FAILED", status_code=400)


@router.post("/offers/{offer_id}/activate")
async def activate_offer(
    offer_id: int,
    db: Session = Depends(get_db),
    _admin: User = Depends(require_admin),
):
    """Activate an offer (admin only)."""
    offer = inventory_service.activate_offer(db, offer_id)
    if offer is None:
        return error_response(message="Offer not found", error_code="OFFER_NOT_FOUND", status_code=404)
    db.commit()
    return success_response(data=OfferResponse.model_validate(offer).model_dump(), message="Offer activated")


@router.post("/offers/{offer_id}/expire")
async def expire_offer(
    offer_id: int,
    db: Session = Depends(get_db),
    _admin: User = Depends(require_admin),
):
    """Expire an offer (admin only)."""
    offer = inventory_service.expire_offer(db, offer_id)
    if offer is None:
        return error_response(message="Offer not found", error_code="OFFER_NOT_FOUND", status_code=404)
    db.commit()
    return success_response(data=OfferResponse.model_validate(offer).model_dump(), message="Offer expired")


# ── Freshness engine ────────────────────────────────────────────────────────
@router.post("/freshness/refresh")
async def refresh_freshness(
    inventory_id: Optional[int] = Query(None),
    db: Session = Depends(get_db),
    _admin: User = Depends(require_admin),
):
    """Recompute freshness status for all (or one) inventory records (admin only)."""
    count = inventory_service.refresh_freshness(db, inventory_id)
    db.commit()
    return success_response(data={"updated": count}, message="Freshness refreshed")


# ── Customer-facing queries ─────────────────────────────────────────────────
@router.get("/product/{product_master_id}")
async def get_product_inventory(
    product_master_id: int,
    latitude: Optional[float] = Query(None, ge=-90, le=90),
    longitude: Optional[float] = Query(None, ge=-180, le=180),
    radius_km: float = Query(10.0, gt=0, le=100),
    db: Session = Depends(get_db),
):
    """Return customer-facing inventory for a product across nearby shops."""
    items = inventory_service.get_customer_inventory_for_product(
        db,
        product_master_id,
        latitude=latitude,
        longitude=longitude,
        radius_km=radius_km,
    )
    return success_response(data={"product_id": product_master_id, "items": items})


@router.get("/shop/{shop_id}")
async def shop_inventory(
    shop_id: int,
    db: Session = Depends(get_db),
):
    """Return all inventory entries for a shop with product details."""
    from app.models.shop import Shop

    shop = db.query(Shop).filter(Shop.id == shop_id).first()
    if shop is None:
        return error_response(message="Shop not found", error_code="SHOP_NOT_FOUND", status_code=404)

    items = inventory_service.get_shop_inventory(db, shop_id)
    return success_response(data={"shop_id": shop_id, "items": items})


# ── Inventory by ID (must be last to avoid route conflicts) ─────────────────
@router.get("/{inventory_id}")
async def get_inventory(
    inventory_id: int,
    db: Session = Depends(get_db),
):
    """Get a single inventory record."""
    inv = db.query(Inventory).filter(Inventory.id == inventory_id).first()
    if inv is None:
        return error_response(message="Inventory not found", error_code="INVENTORY_NOT_FOUND", status_code=404)
    return success_response(data=InventoryResponse.model_validate(inv).model_dump())


@router.put("/{inventory_id}")
async def update_inventory(
    inventory_id: int,
    payload: InventoryUpdate,
    db: Session = Depends(get_db),
    _admin: User = Depends(require_admin),
):
    """Update inventory quantity and related fields (admin only)."""
    inv = inventory_service.update_inventory(db, inventory_id, payload.model_dump(exclude_unset=True))
    if inv is None:
        return error_response(message="Inventory not found", error_code="INVENTORY_NOT_FOUND", status_code=404)
    db.commit()
    return success_response(data=InventoryResponse.model_validate(inv).model_dump(), message="Inventory updated")


@router.delete("/{inventory_id}")
async def remove_inventory(
    inventory_id: int,
    db: Session = Depends(get_db),
    _admin: User = Depends(require_admin),
):
    """Remove inventory (sets quantity to 0, marks unavailable) — admin only."""
    removed = inventory_service.remove_inventory(db, inventory_id)
    if not removed:
        return error_response(message="Inventory not found", error_code="INVENTORY_NOT_FOUND", status_code=404)
    db.commit()
    return success_response(message="Inventory removed")


@router.get("/{inventory_id}/movements")
async def list_movements(
    inventory_id: int,
    limit: int = Query(50, ge=1, le=200),
    db: Session = Depends(get_db),
):
    """List movements for an inventory record."""
    movements = (
        db.query(InventoryMovement)
        .filter(InventoryMovement.inventory_id == inventory_id)
        .order_by(InventoryMovement.created_at.desc())
        .limit(limit)
        .all()
    )
    return success_response(data=[InventoryMovementResponse.model_validate(m).model_dump() for m in movements])


@router.get("/{inventory_id}/adjustments")
async def list_adjustments(
    inventory_id: int,
    limit: int = Query(50, ge=1, le=200),
    db: Session = Depends(get_db),
):
    """List adjustments for an inventory record."""
    adjustments = (
        db.query(InventoryAdjustment)
        .filter(InventoryAdjustment.inventory_id == inventory_id)
        .order_by(InventoryAdjustment.created_at.desc())
        .limit(limit)
        .all()
    )
    return success_response(data=[InventoryAdjustmentResponse.model_validate(a).model_dump() for a in adjustments])