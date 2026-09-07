"""Shopkeeper Analytics service — dynamic business intelligence for shop owners.

All data is computed live from the analytics event stream, interaction ledger,
shop/product views, and inventory tables. No hardcoded values — every metric
reflects actual customer behaviour against the shopkeeper's shop(s).
"""

from datetime import datetime, timedelta, timezone
from typing import Any

from sqlalchemy import func
from sqlalchemy.orm import Session

from app.core.logging import get_logger
from app.models.analytics import ProductClick, ProductView, ShopView
from app.models.analytics_event import AnalyticsEvent
from app.models.product import ShopProduct

logger = get_logger("app.services.shopkeeper_analytics")


def _now() -> datetime:
    return datetime.now(timezone.utc)


def _start_of_day(days_ago: int = 0) -> datetime:
    return (_now() - timedelta(days=days_ago)).replace(
        hour=0, minute=0, second=0, microsecond=0
    )


def overview(db: Session, shop_id: int) -> dict[str, Any]:
    """High-level KPIs for the shopkeeper dashboard header cards."""
    now = _now()
    today_start = _start_of_day(0)
    yesterday_start = _start_of_day(1)
    week_start = _start_of_day(7)
    month_start = _start_of_day(30)

    views_today = _count_shop_views(db, shop_id, today_start, now)
    views_yesterday = _count_shop_views(db, shop_id, yesterday_start, today_start)
    views_this_week = _count_shop_views(db, shop_id, week_start, now)
    views_last_week = _count_shop_views(db, shop_id, _start_of_day(14), week_start)

    clicks_today = _count_product_clicks(db, shop_id, today_start, now)
    clicks_week = _count_product_clicks(db, shop_id, week_start, now)

    interactions_today = _count_interactions(db, shop_id, today_start, now)
    interactions_week = _count_interactions(db, shop_id, week_start, now)

    return {
        "views": {
            "today": views_today,
            "yesterday": views_yesterday,
            "change_pct": _pct_change(views_yesterday, views_today),
            "this_week": views_this_week,
            "last_week": views_last_week,
            "week_change_pct": _pct_change(views_last_week, views_this_week),
        },
        "clicks": {
            "today": clicks_today,
            "this_week": clicks_week,
        },
        "interactions": {
            "today": interactions_today,
            "this_week": interactions_week,
        },
        "generated_at": now.isoformat(),
    }


def views_timeseries(db: Session, shop_id: int, days: int = 30) -> list[dict[str, Any]]:
    """Daily shop-view counts for the trailing ``days`` window."""
    start = _start_of_day(days)
    rows = (
        db.query(
            func.date(ShopView.viewed_at).label("day"),
            func.count(ShopView.id).label("count"),
        )
        .filter(ShopView.shop_id == shop_id, ShopView.viewed_at >= start)
        .group_by(func.date(ShopView.viewed_at))
        .order_by("day")
        .all()
    )
    return [{"date": str(r.day), "views": int(r.count)} for r in rows]


def clicks_timeseries(db: Session, shop_id: int, days: int = 30) -> list[dict[str, Any]]:
    """Daily product-click counts for the trailing ``days`` window."""
    start = _start_of_day(days)
    rows = (
        db.query(
            func.date(ProductClick.clicked_at).label("day"),
            func.count(ProductClick.id).label("count"),
        )
        .filter(ProductClick.shop_id == shop_id, ProductClick.clicked_at >= start)
        .group_by(func.date(ProductClick.clicked_at))
        .order_by("day")
        .all()
    )
    return [{"date": str(r.day), "clicks": int(r.count)} for r in rows]


def top_products(db: Session, shop_id: int, days: int = 30, limit: int = 10) -> list[dict[str, Any]]:
    """Most-viewed products in the trailing window."""
    start = _start_of_day(days)
    rows = (
        db.query(
            ShopProduct.id,
            ShopProduct.sku,
            func.count(ProductView.id).label("view_count"),
        )
        .join(ProductView, ProductView.product_master_id == ShopProduct.product_master_id)
        .filter(ShopProduct.shop_id == shop_id, ProductView.viewed_at >= start)
        .group_by(ShopProduct.id, ShopProduct.sku)
        .order_by(func.count(ProductView.id).desc())
        .limit(limit)
        .all()
    )
    return [
        {"shop_product_id": r.id, "sku": r.sku, "views": int(r.view_count)}
        for r in rows
    ]


def top_searches(db: Session, shop_id: int, days: int = 30, limit: int = 15) -> list[dict[str, Any]]:
    """What customers typed before landing on this shop."""
    start = _start_of_day(days)
    rows = (
        db.query(
            AnalyticsEvent.query.label("q"),
            func.count(AnalyticsEvent.id).label("count"),
        )
        .filter(
            AnalyticsEvent.shop_id == shop_id,
            AnalyticsEvent.event_name == "result_click",
            AnalyticsEvent.query.isnot(None),
            AnalyticsEvent.occurred_at >= start,
        )
        .group_by(AnalyticsEvent.query)
        .order_by(func.count(AnalyticsEvent.id).desc())
        .limit(limit)
        .all()
    )
    return [{"query": r.q, "count": int(r.count)} for r in rows]

def interaction_breakdown(db: Session, shop_id: int, days: int = 30) -> dict[str, Any]:
    """Breakdown of customer interactions by type."""
    start = _start_of_day(days)
    from app.models.interaction import UserInteraction
    rows = (
        db.query(
            UserInteraction.action_type,
            func.count(UserInteraction.id).label("count"),
        )
        .filter(UserInteraction.shop_id == shop_id, UserInteraction.created_at >= start)
        .group_by(UserInteraction.action_type)
        .all()
    )
    breakdown = {}
    for r in rows:
        key = r.action_type.value if hasattr(r.action_type, "value") else str(r.action_type)
        breakdown[key] = int(r.count)
    return {
        "call_views": breakdown.get("call_view", 0),
        "messages": breakdown.get("message", 0),
        "ratings": breakdown.get("rating", 0),
        "period_days": days,
    }


def device_breakdown(db: Session, shop_id: int, days: int = 30) -> dict[str, Any]:
    """Which devices customers use to discover this shop."""
    start = _start_of_day(days)
    rows = (
        db.query(
            func.coalesce(ShopView.device_type, "unknown").label("device"),
            func.count(ShopView.id).label("count"),
        )
        .filter(ShopView.shop_id == shop_id, ShopView.viewed_at >= start)
        .group_by(func.coalesce(ShopView.device_type, "unknown"))
        .all()
    )
    return {r.device: int(r.count) for r in rows}


def hourly_distribution(db: Session, shop_id: int, days: int = 7) -> list[dict[str, Any]]:
    """Hour-of-day view distribution."""
    start = _start_of_day(days)
    rows = (
        db.query(
            func.extract("hour", ShopView.viewed_at).label("hour"),
            func.count(ShopView.id).label("count"),
        )
        .filter(ShopView.shop_id == shop_id, ShopView.viewed_at >= start)
        .group_by(func.extract("hour", ShopView.viewed_at))
        .order_by("hour")
        .all()
    )
    return [{"hour": int(r.hour), "views": int(r.count)} for r in rows]


def freshness_score(db: Session, shop_id: int) -> dict[str, Any]:
    """Inventory freshness - how recently stock was updated."""
    from app.models.product import Inventory
    total = db.query(func.count(ShopProduct.id)).filter(ShopProduct.shop_id == shop_id).scalar() or 0
    if total == 0:
        return {"score": 0, "total_products": 0, "fresh": 0, "stale": 0}
    fresh_threshold = _now() - timedelta(hours=24)
    fresh = (
        db.query(func.count(ShopProduct.id))
        .join(Inventory, Inventory.shop_product_id == ShopProduct.id)
        .filter(ShopProduct.shop_id == shop_id, Inventory.last_synced_at >= fresh_threshold)
        .scalar()
        or 0
    )
    stale = total - fresh
    score = round((fresh / total) * 100, 1) if total else 0
    return {"score": score, "total_products": total, "fresh": fresh, "stale": stale}


# -- internal helpers --------------------------------------------------------

def _count_shop_views(db: Session, shop_id: int, start: datetime, end: datetime) -> int:
    return (
        db.query(func.count(ShopView.id))
        .filter(ShopView.shop_id == shop_id, ShopView.viewed_at >= start, ShopView.viewed_at < end)
        .scalar()
        or 0
    )


def _count_product_clicks(db: Session, shop_id: int, start: datetime, end: datetime) -> int:
    return (
        db.query(func.count(ProductClick.id))
        .filter(ProductClick.shop_id == shop_id, ProductClick.clicked_at >= start, ProductClick.clicked_at < end)
        .scalar()
        or 0
    )


def _count_interactions(db: Session, shop_id: int, start: datetime, end: datetime) -> int:
    from app.models.interaction import UserInteraction
    return (
        db.query(func.count(UserInteraction.id))
        .filter(UserInteraction.shop_id == shop_id, UserInteraction.created_at >= start, UserInteraction.created_at < end)
        .scalar()
        or 0
    )


def _pct_change(old: int, new: int) -> float:
    if old == 0:
        return 100.0 if new > 0 else 0.0
    return round(((new - old) / old) * 100, 1)
