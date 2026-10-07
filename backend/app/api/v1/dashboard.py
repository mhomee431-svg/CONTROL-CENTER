"""Dashboard metrics and analytics summary.

Every number here is counted from the operational tables, so the dashboard
cannot report a total the list pages would disagree with.
"""

from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.core.inventory_policy import STALE_AFTER_HOURS
from app.core.responses import ok
from app.core.security import get_current_admin
from app.models import (
    AdminUser,
    Complaint,
    Category,
    Product,
    SearchQuery,
    Shop,
    ShopInventory,
    Subscription,
    User,
)

router = APIRouter(prefix="/admin", tags=["dashboard"])


def _count(db: Session, model, *conditions) -> int:
    stmt = select(func.count()).select_from(model)
    for c in conditions:
        stmt = stmt.where(c)
    return db.scalar(stmt) or 0


@router.get("/dashboard/metrics")
def dashboard_metrics(db: Session = Depends(get_db), _: AdminUser = Depends(get_current_admin)):
    cutoff = datetime.now(timezone.utc) - timedelta(hours=STALE_AFTER_HOURS)

    total_searches = _count(db, SearchQuery)
    zero_result_searches = _count(db, SearchQuery, SearchQuery.result_count == 0)
    success_rate = (
        round(((total_searches - zero_result_searches) / total_searches) * 100, 2)
        if total_searches
        else 100.0
    )

    # `popular_categories` drives the dashboard breakdown chart.
    popular = db.execute(
        select(Shop.category, func.count(Shop.id))
        .where(Shop.category.isnot(None))
        .group_by(Shop.category)
        .order_by(func.count(Shop.id).desc())
        .limit(8)
    ).all()

    revenue = db.scalar(select(func.coalesce(func.sum(Subscription.amount), 0))) or 0

    return ok(
        {
            "total_customers": _count(db, User),
            "total_shops": _count(db, Shop),
            "active_shops": _count(db, Shop, Shop.status == "ACTIVE"),
            "pending_verification": _count(db, Shop, Shop.verification_status == "PENDING"),
            "total_products": _count(db, Product),
            "total_inventory_records": _count(db, ShopInventory),
            "total_searches": total_searches,
            "search_success_rate": success_rate,
            "popular_categories": [
                {"id": idx + 1, "name": name, "count": count}
                for idx, (name, count) in enumerate(popular)
            ],
            "active_subscriptions": _count(db, Subscription, Subscription.status == "ACTIVE"),
            "total_subscription_revenue": float(revenue),
            "pending_approvals": _count(db, Product, Product.status == "PENDING"),
            "open_complaints": _count(db, Complaint, Complaint.status == "OPEN"),
            "stale_inventory_count": _count(db, ShopInventory, ShopInventory.last_updated < cutoff),
            "products_missing_prices": _count(db, ShopInventory, ShopInventory.price.is_(None)),
            "sync_failures": _count(db, ShopInventory, ShopInventory.sync_status == "FAILED"),
        }
    )


@router.get("/analytics/summary")
def analytics_summary(db: Session = Depends(get_db), _: AdminUser = Depends(get_current_admin)):
    """Category and city distribution, used by the analytics sections."""
    by_category = db.execute(
        select(Shop.category, func.count(Shop.id))
        .group_by(Shop.category)
        .order_by(func.count(Shop.id).desc())
    ).all()
    by_city = db.execute(
        select(Shop.city, func.count(Shop.id))
        .group_by(Shop.city)
        .order_by(func.count(Shop.id).desc())
        .limit(10)
    ).all()
    return ok(
        {
            "shops_by_category": [
                {"category": c or "Uncategorised", "count": n} for c, n in by_category
            ],
            "shops_by_city": [{"city": c or "Unknown", "count": n} for c, n in by_city],
            "total_categories": _count(db, Category),
            "total_products": _count(db, Product),
            "total_shops": _count(db, Shop),
        }
    )
