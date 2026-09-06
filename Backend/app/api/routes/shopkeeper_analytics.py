"""Shopkeeper Analytics & Business Intelligence API routes.

All data is computed dynamically from the analytics event stream, shop views,
product clicks, customer interactions, and inventory freshness — nothing is
hardcoded.
"""

from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session

from app.core.dependencies import get_current_user
from app.core.responses import error_response, success_response
from app.database.session import get_db
from app.models.user import User
from app.services import shopkeeper_analytics, shopkeeper_service

router = APIRouter(prefix="/shopkeeper", tags=["shopkeeper-analytics"])


def _resolve(shop_id: int, current_user: User, db: Session):
    return shopkeeper_service.resolve_shop_access(db, current_user, shop_id)


@router.get("/shops/{shop_id}/analytics/overview")
async def analytics_overview(
    shop_id: int,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """High-level KPI cards: views/clicks/interactions today vs yesterday."""
    access = _resolve(shop_id, current_user, db)
    access.require("dashboard", "read")
    try:
        data = shopkeeper_analytics.overview(db, shop_id)
        return success_response(data=data)
    except Exception as exc:  # noqa: BLE001
        return error_response(message=str(exc), error_code="ANALYTICS_FAILED", status_code=400)


@router.get("/shops/{shop_id}/analytics/views")
async def analytics_views_timeseries(
    shop_id: int,
    days: int = Query(30, ge=1, le=365),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Daily shop-view counts for the trailing window."""
    access = _resolve(shop_id, current_user, db)
    access.require("dashboard", "read")
    try:
        data = shopkeeper_analytics.views_timeseries(db, shop_id, days=days)
        return success_response(data={"timeseries": data, "days": days})
    except Exception as exc:  # noqa: BLE001
        return error_response(message=str(exc), error_code="ANALYTICS_FAILED", status_code=400)


@router.get("/shops/{shop_id}/analytics/clicks")
async def analytics_clicks_timeseries(
    shop_id: int,
    days: int = Query(30, ge=1, le=365),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Daily product-click counts for the trailing window."""
    access = _resolve(shop_id, current_user, db)
    access.require("dashboard", "read")
    try:
        data = shopkeeper_analytics.clicks_timeseries(db, shop_id, days=days)
        return success_response(data={"timeseries": data, "days": days})
    except Exception as exc:  # noqa: BLE001
        return error_response(message=str(exc), error_code="ANALYTICS_FAILED", status_code=400)


@router.get("/shops/{shop_id}/analytics/top-products")
async def analytics_top_products(
    shop_id: int,
    days: int = Query(30, ge=1, le=365),
    limit: int = Query(10, ge=1, le=50),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Most-viewed products — which items drive the most customer interest."""
    access = _resolve(shop_id, current_user, db)
    access.require("dashboard", "read")
    try:
        data = shopkeeper_analytics.top_products(db, shop_id, days=days, limit=limit)
        return success_response(data={"products": data, "days": days})
    except Exception as exc:  # noqa: BLE001
        return error_response(message=str(exc), error_code="ANALYTICS_FAILED", status_code=400)


@router.get("/shops/{shop_id}/analytics/top-searches")
async def analytics_top_searches(
    shop_id: int,
    days: int = Query(30, ge=1, le=365),
    limit: int = Query(15, ge=1, le=50),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """What customers typed before landing on this shop — demand intelligence."""
    access = _resolve(shop_id, current_user, db)
    access.require("dashboard", "read")
    try:
        data = shopkeeper_analytics.top_searches(db, shop_id, days=days, limit=limit)
        return success_response(data={"searches": data, "days": days})
    except Exception as exc:  # noqa: BLE001
        return error_response(message=str(exc), error_code="ANALYTICS_FAILED", status_code=400)


@router.get("/shops/{shop_id}/analytics/interactions")
async def analytics_interactions(
    shop_id: int,
    days: int = Query(30, ge=1, le=365),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Customer interaction breakdown: calls, messages, ratings."""
    access = _resolve(shop_id, current_user, db)
    access.require("dashboard", "read")
    try:
        data = shopkeeper_analytics.interaction_breakdown(db, shop_id, days=days)
        return success_response(data=data)
    except Exception as exc:  # noqa: BLE001
        return error_response(message=str(exc), error_code="ANALYTICS_FAILED", status_code=400)

@router.get("/shops/{shop_id}/analytics/devices")
async def analytics_devices(
    shop_id: int,
    days: int = Query(30, ge=1, le=365),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Which devices customers use to discover this shop."""
    access = _resolve(shop_id, current_user, db)
    access.require("dashboard", "read")
    try:
        data = shopkeeper_analytics.device_breakdown(db, shop_id, days=days)
        return success_response(data={"devices": data, "days": days})
    except Exception as exc:  # noqa: BLE001
        return error_response(message=str(exc), error_code="ANALYTICS_FAILED", status_code=400)


@router.get("/shops/{shop_id}/analytics/hourly")
async def analytics_hourly(
    shop_id: int,
    days: int = Query(7, ge=1, le=90),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Hour-of-day view distribution - peak hours intelligence."""
    access = _resolve(shop_id, current_user, db)
    access.require("dashboard", "read")
    try:
        data = shopkeeper_analytics.hourly_distribution(db, shop_id, days=days)
        return success_response(data={"hourly": data, "days": days})
    except Exception as exc:  # noqa: BLE001
        return error_response(message=str(exc), error_code="ANALYTICS_FAILED", status_code=400)


@router.get("/shops/{shop_id}/analytics/freshness")
async def analytics_freshness(
    shop_id: int,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Inventory freshness score - how recently stock was updated."""
    access = _resolve(shop_id, current_user, db)
    access.require("dashboard", "read")
    try:
        data = shopkeeper_analytics.freshness_score(db, shop_id)
        return success_response(data=data)
    except Exception as exc:  # noqa: BLE001
        return error_response(message=str(exc), error_code="ANALYTICS_FAILED", status_code=400)


@router.get("/shops/{shop_id}/analytics/full")
async def analytics_full_report(
    shop_id: int,
    days: int = Query(30, ge=1, le=365),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Complete analytics report - all metrics in one call for dashboard load."""
    access = _resolve(shop_id, current_user, db)
    access.require("dashboard", "read")
    try:
        data = {
            "overview": shopkeeper_analytics.overview(db, shop_id),
            "views_timeseries": shopkeeper_analytics.views_timeseries(db, shop_id, days),
            "clicks_timeseries": shopkeeper_analytics.clicks_timeseries(db, shop_id, days),
            "top_products": shopkeeper_analytics.top_products(db, shop_id, days),
            "top_searches": shopkeeper_analytics.top_searches(db, shop_id, days),
            "interactions": shopkeeper_analytics.interaction_breakdown(db, shop_id, days),
            "devices": shopkeeper_analytics.device_breakdown(db, shop_id, days),
            "hourly": shopkeeper_analytics.hourly_distribution(db, shop_id, min(days, 30)),
            "freshness": shopkeeper_analytics.freshness_score(db, shop_id),
        }
        return success_response(data=data)
    except Exception as exc:  # noqa: BLE001
        return error_response(message=str(exc), error_code="ANALYTICS_FAILED", status_code=400)
