"""Customer-facing API routes — recently viewed, favourites, product share.

All data is dynamic and computed live from the customer's actual activity.
The product share endpoint also records an analytics event so shopkeepers see
which products their customers share.
"""

from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session

from app.core.dependencies import get_current_user, get_optional_user
from app.core.responses import error_response, success_response
from app.database.session import get_db
from app.models.customer_favorite import FAVORITE_ITEM_TYPES
from app.models.user import User
from app.services import customer_service

router = APIRouter(prefix="/customer", tags=["customer"])


# ── Recently viewed ──────────────────────────────────────────────────────────
@router.get("/recently-viewed")
async def get_recently_viewed(
    limit: int = Query(20, ge=1, le=50),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """The customer's recently-viewed products (most recent first)."""
    try:
        items = customer_service.list_recent_views(db, current_user, limit=limit)
        return success_response(data={"items": items, "count": len(items)})
    except Exception as exc:  # noqa: BLE001
        return error_response(message=str(exc), error_code="RECENT_VIEWS_FAILED", status_code=400)


@router.post("/recently-viewed", status_code=201)
async def record_recently_viewed(
    product_master_id: int = Query(...),
    variant_id: int | None = Query(None),
    shop_product_id: int | None = Query(None),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Record that the customer viewed a product (UPSERT)."""
    try:
        result = customer_service.record_recent_view(
            db, current_user, product_master_id, variant_id, shop_product_id
        )
        return success_response(data=result, message="Recorded", status_code=201)
    except Exception as exc:  # noqa: BLE001
        return error_response(message=str(exc), error_code="RECENT_VIEW_FAILED", status_code=400)


# ── Favourites ───────────────────────────────────────────────────────────────
@router.get("/favorites")
async def get_favorites(
    item_type: str | None = Query(None, max_length=30),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """The customer's favourites (product/shop/brand/category)."""
    try:
        items = customer_service.list_favorites(db, current_user, item_type=item_type)
        return success_response(data={"items": items, "count": len(items)})
    except Exception as exc:  # noqa: BLE001
        return error_response(message=str(exc), error_code="FAVORITES_FAILED", status_code=400)


@router.post("/favorites", status_code=201)
async def toggle_favorite(
    item_type: str = Query(..., max_length=30),
    item_id: int = Query(...),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Toggle a favourite (add or remove) for the current customer."""
    try:
        result = customer_service.toggle_favorite(
            db, current_user, item_type, item_id, None
        )
        message = "Added to favourites" if result["favorited"] else "Removed from favourites"
        return success_response(data=result, message=message, status_code=201)
    except ValueError as exc:
        return error_response(message=str(exc), error_code="INVALID_FAVORITE", status_code=400)
    except Exception as exc:  # noqa: BLE001
        return error_response(message=str(exc), error_code="FAVORITE_FAILED", status_code=400)


@router.get("/favorites/types")
async def favorite_types():
    """Valid favourite item_type values (for form/selector UI)."""
    return success_response(data={"item_types": list(FAVORITE_ITEM_TYPES)})


# ── Product share ────────────────────────────────────────────────────────────
@router.get("/products/{product_master_id}/share")
async def get_product_share_payload(
    product_master_id: int,
    db: Session = Depends(get_db),
    user: User | None = Depends(get_optional_user),
):
    """Shareable snapshot of a product: name, image, price range, shop count.

    The Flutter app renders a share sheet with this payload; text/links are
    composed client-side so the share UI matches the platform share sheet.
    """
    try:
        payload = customer_service.product_share_payload(db, product_master_id)
    except Exception as exc:  # noqa: BLE001
        return error_response(message=str(exc), error_code="SHARE_PAYLOAD_FAILED", status_code=400)
    if payload is None:
        return error_response(message="Product not found", error_code="PRODUCT_NOT_FOUND", status_code=404)
    return success_response(data=payload)


@router.post("/products/{product_master_id}/share", status_code=201)
async def record_product_share(
    product_master_id: int,
    db: Session = Depends(get_db),
    user: User | None = Depends(get_optional_user),
):
    """Record that a product was shared (analytics; never blocks the UI)."""
    try:
        payload = customer_service.product_share_payload(db, product_master_id)
    except Exception as exc:  # noqa: BLE001
        return error_response(message=str(exc), error_code="SHARE_FAILED", status_code=400)
    if payload is None:
        return error_response(message="Product not found", error_code="PRODUCT_NOT_FOUND", status_code=404)
    customer_service.record_share_event(db, user, product_master_id)
    return success_response(data={"shared": True, "product_master_id": product_master_id}, status_code=201)