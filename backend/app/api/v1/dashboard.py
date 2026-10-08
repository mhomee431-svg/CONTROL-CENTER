"""Dashboard metrics and analytics summary.

Every number here is counted from the operational tables, so the dashboard
cannot report a total the list pages would disagree with.
"""

from datetime import date, datetime, timedelta, timezone

from fastapi import APIRouter, Depends, Query
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
    ImportJob,
    NotificationCampaign,
    Offer,
    PosIntegration,
    PosSyncRun,
    Product,
    SearchQuery,
    Shop,
    ShopInventory,
    Subscription,
    User,
)

router = APIRouter(prefix="/admin", tags=["dashboard"])

# Customer analytics default and bounds. The reporting window is expressed in
# inclusive days, matching the console's 7D / 30D / 90D presets and its custom
# range (which the client converts into a day span).
DEFAULT_ANALYTICS_DAYS = 30
MAX_ANALYTICS_DAYS = 366


def _count(db: Session, model, *conditions) -> int:
    stmt = select(func.count()).select_from(model)
    for c in conditions:
        stmt = stmt.where(c)
    return db.scalar(stmt) or 0


def _resolve_days(days: int | None) -> int:
    """Clamp the reporting window into a sane, backend-owned range.

    A missing or non-positive value falls back to the 30-day default; an
    over-large value is capped so a hand-crafted query cannot ask the database
    to scan an unbounded window.
    """
    if days is None or days <= 0:
        return DEFAULT_ANALYTICS_DAYS
    return min(days, MAX_ANALYTICS_DAYS)


def _day_start(moment: datetime) -> datetime:
    """Truncate an instant to midnight UTC so day buckets line up."""
    return moment.replace(hour=0, minute=0, second=0, microsecond=0)


def _utc(moment: datetime) -> datetime:
    """Normalise a possibly-naive datetime to UTC.

    SQLite returns naive datetimes even for timezone-aware columns, so any
    comparison against a tz-aware cutoff has to coerce first or it raises.
    """
    return moment if moment.tzinfo else moment.replace(tzinfo=timezone.utc)


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


@router.get("/analytics/customers")
def customer_analytics(
    days: int | None = Query(None, ge=0, le=MAX_ANALYTICS_DAYS),
    db: Session = Depends(get_db),
    _: AdminUser = Depends(get_current_admin),
):
    """Customer analytics: acquisition, engagement and retention.

    The reporting window is a single inclusive day span (`days`), which is the
    same vocabulary the console's 7D / 30D / 90D presets and its custom range
    resolve to — so every surface under Customers Analytics reports over exactly
    the window the operator selected, and none of them disagrees with the others.

    Every figure is counted from `users` / `search_queries`, never estimated:
    a metric the backend cannot substantiate is returned as `null` rather than
    as a plausible-looking zero.
    """
    window_days = _resolve_days(days)
    now = datetime.now(timezone.utc)
    # Inclusive window: today plus the preceding (window_days - 1) days.
    start = _day_start(now) - timedelta(days=window_days - 1)
    previous_start = start - timedelta(days=window_days)

    total_customers = _count(db, User)
    new_customers = _count(db, User, User.created_at >= start)
    # The immediately preceding window of equal length, so a period-over-period
    # comparison is like-for-like rather than against a different span.
    previous_new_customers = _count(
        db, User, User.created_at >= previous_start, User.created_at < start
    )

    active_customers = _count(db, User, User.last_active >= start)
    returning_customers = _count(
        db, User, User.last_active >= start, User.created_at < start
    )
    suspended_customers = _count(db, User, User.status == "SUSPENDED")
    restricted_customers = _count(db, User, User.is_restricted.is_(True))

    # Retention: of everyone who registered *before* this window opened, the
    # share that was active inside it. Measured against the whole eligible base
    # so it reads as a rate, not as a raw count.
    eligible_for_retention = _count(db, User, User.created_at < start)
    retention_rate = (
        round((returning_customers / eligible_for_retention) * 100, 2)
        if eligible_for_retention
        else None
    )

    # Search engagement inside the window.
    searches = _count(db, SearchQuery, SearchQuery.searched_at >= start)
    unique_searchers = db.scalar(
        select(func.count(func.distinct(SearchQuery.user_id))).where(
            SearchQuery.searched_at >= start, SearchQuery.user_id.isnot(None)
        )
    ) or 0

    # Product / shop views and directions are counted from the lifetime rollups
    # the platform already maintains on `users`. They are not windowed because
    # the backend exposes them as running totals; reporting them as a period
    # figure would fabricate a window the data cannot support.
    product_views = db.scalar(select(func.coalesce(func.sum(User.viewed_product_count), 0))) or 0
    shop_views = db.scalar(select(func.coalesce(func.sum(User.viewed_shop_count), 0))) or 0
    favorites = (
        db.scalar(select(func.coalesce(func.sum(User.saved_product_count), 0))) or 0
    ) + (db.scalar(select(func.coalesce(func.sum(User.saved_shop_count), 0))) or 0)

    # Day-by-day registrations, so the trend chart and the totals cannot drift.
    reg_rows = db.execute(
        select(User.created_at).where(User.created_at >= start)
    ).all()
    reg_buckets: dict[str, int] = {}
    for (created_at,) in reg_rows:
        if created_at is None:
            continue
        key = _utc(created_at).date().isoformat()
        reg_buckets[key] = reg_buckets.get(key, 0) + 1

    # Day-by-day searches over the same window.
    search_rows = db.execute(
        select(SearchQuery.searched_at).where(SearchQuery.searched_at >= start)
    ).all()
    search_buckets: dict[str, int] = {}
    for (searched_at,) in search_rows:
        if searched_at is None:
            continue
        key = _utc(searched_at).date().isoformat()
        search_buckets[key] = search_buckets.get(key, 0) + 1

    # A dense series: every day in the window is present, zero-filled, so the
    # chart plots a continuous timeline instead of silently skipping quiet days.
    days_series: list[dict] = []
    cursor = start
    end_date = _day_start(now)
    while cursor <= end_date:
        key = cursor.date().isoformat()
        days_series.append(
            {
                "date": key,
                "registrations": reg_buckets.get(key, 0),
                "searches": search_buckets.get(key, 0),
            }
        )
        cursor += timedelta(days=1)

    # Registration growth versus the previous equal-length window.
    growth_rate = (
        round(((new_customers - previous_new_customers) / previous_new_customers) * 100, 2)
        if previous_new_customers
        else None
    )

    # Registrations grouped by city, for the acquisition breakdown.
    city_rows = db.execute(
        select(User.city, func.count(User.id))
        .where(User.created_at >= start)
        .group_by(User.city)
        .order_by(func.count(User.id).desc())
        .limit(10)
    ).all()

    # Status distribution across the whole base, for the composition panel.
    status_rows = db.execute(
        select(User.status, func.count(User.id))
        .group_by(User.status)
        .order_by(func.count(User.id).desc())
    ).all()

    return ok(
        {
            "period_days": window_days,
            "window_start": start.date().isoformat(),
            "window_end": end_date.date().isoformat(),
            "new_customers": new_customers,
            "previous_new_customers": previous_new_customers,
            "registration_growth_rate": growth_rate,
            "active_users": active_customers,
            "returning_users": returning_customers,
            "total_customers": total_customers,
            "suspended_customers": suspended_customers,
            "restricted_customers": restricted_customers,
            "retention_rate": retention_rate,
            "retention_eligible_base": eligible_for_retention,
            "searches": searches,
            "unique_searchers": unique_searchers,
            "product_views": product_views,
            "shop_views": shop_views,
            "directions": None,
            "favorites": favorites,
            "registrations_by_day": days_series,
            "registrations_by_city": [
                {"city": c or "Unknown", "count": n} for c, n in city_rows
            ],
            "customers_by_status": [
                {"status": s or "UNKNOWN", "count": n} for s, n in status_rows
            ],
        }
    )



def _window(days: int | None) -> tuple[int, datetime, datetime, datetime]:
    """Resolve a reporting window into (days, start, previous_start, end).

    A single helper so every analytics surface derives its window the same way
    and two sections can never report over subtly different spans.
    """
    window_days = _resolve_days(days)
    now = datetime.now(timezone.utc)
    start = _day_start(now) - timedelta(days=window_days - 1)
    previous_start = start - timedelta(days=window_days)
    return window_days, start, previous_start, _day_start(now)


def _dense_series(
    start: datetime, end: datetime, buckets: dict[str, int], key: str
) -> list[dict]:
    """Zero-fill a day-bucketed count into a continuous timeline.

    Every day in the window is present so the chart plots a real timeline
    instead of silently skipping quiet days.
    """
    series: list[dict] = []
    cursor = start
    while cursor <= end:
        day = cursor.date().isoformat()
        series.append({"date": day, key: buckets.get(day, 0)})
        cursor += timedelta(days=1)
    return series


def _bucket_dates(rows, value_key: str = "count") -> dict[str, int]:
    """Fold (datetime,) rows into a date -> count map, tolerating nulls."""
    buckets: dict[str, int] = {}
    for (moment,) in rows:
        if moment is None:
            continue
        key = _utc(moment).date().isoformat()
        buckets[key] = buckets.get(key, 0) + 1
    return buckets


@router.get("/analytics/shopkeepers")
def shopkeeper_analytics(
    days: int | None = Query(None, ge=0, le=MAX_ANALYTICS_DAYS),
    db: Session = Depends(get_db),
    _: AdminUser = Depends(get_current_admin),
):
    """Shopkeeper analytics: merchant onboarding, activation and contribution.

    "Shopkeeper" is a platform user who owns at least one shop. Counts are
    derived from `shops.owner_id` so a merchant with several storefronts is
    counted once, and a customer is never mistaken for a merchant.
    """
    window_days, start, previous_start, end = _window(days)

    # Distinct owners, derived from the shops registry.
    owner_ids = [row[0] for row in db.execute(select(Shop.owner_id).distinct()).all() if row[0]]
    total_shopkeepers = len(owner_ids)

    new_shopkeepers = 0
    if owner_ids:
        new_shopkeepers = _count(
            db, User, User.id.in_(owner_ids), User.created_at >= start
        )
    previous_new_shopkeepers = 0
    if owner_ids:
        previous_new_shopkeepers = _count(
            db,
            User,
            User.id.in_(owner_ids),
            User.created_at >= previous_start,
            User.created_at < start,
        )

    active_shopkeepers = 0
    if owner_ids:
        active_shopkeepers = _count(
            db, User, User.id.in_(owner_ids), User.last_active >= start
        )

    active_businesses = _count(db, Shop, Shop.status == "ACTIVE")

    # Product additions: inventory rows first seen inside the window. The
    # inventory row carries the product listing, so its creation is the
    # product-add event for a merchant.
    product_additions = _count(db, ShopInventory, ShopInventory.created_at >= start)
    inventory_updates = _count(
        db,
        ShopInventory,
        ShopInventory.last_updated >= start,
        ShopInventory.created_at < start,
    )

    # Price updates are inventory edits that carried a price. The backend has no
    # separate price-event table, so this is the honest count of priced rows
    # touched in the window rather than an invented "price change" stream.
    price_updates = _count(
        db,
        ShopInventory,
        ShopInventory.last_updated >= start,
        ShopInventory.price.isnot(None),
    )

    imports_completed = _count(db, ImportJob, ImportJob.status == "COMPLETED")
    imports_failed = _count(db, ImportJob, ImportJob.status == "FAILED")

    pos_sync_failures = _count(db, PosSyncRun, PosSyncRun.status == "FAILED")
    pos_sync_success = _count(db, PosSyncRun, PosSyncRun.status == "SUCCESS")

    # Day-by-day new merchants, so the trend and the total cannot drift.
    new_rows = (
        db.execute(select(User.created_at).where(User.id.in_(owner_ids), User.created_at >= start)).all()
        if owner_ids
        else []
    )
    onboard_buckets = _bucket_dates(new_rows)

    # Merchant contribution: how many shops and inventory rows each merchant runs.
    top_merchants = db.execute(
        select(Shop.owner_id, func.count(Shop.id))
        .where(Shop.owner_id.isnot(None))
        .group_by(Shop.owner_id)
        .order_by(func.count(Shop.id).desc())
        .limit(10)
    ).all()
    owner_names = {}
    if top_merchants:
        ids = [oid for oid, _ in top_merchants]
        for (uid, name) in db.execute(
            select(User.id, User.name).where(User.id.in_(ids))
        ).all():
            owner_names[uid] = name

    # Verification funnel across merchants.
    verification_rows = db.execute(
        select(Shop.verification_status, func.count(Shop.id))
        .group_by(Shop.verification_status)
        .order_by(func.count(Shop.id).desc())
    ).all()

    growth_rate = (
        round(((new_shopkeepers - previous_new_shopkeepers) / previous_new_shopkeepers) * 100, 2)
        if previous_new_shopkeepers
        else None
    )

    return ok(
        {
            "period_days": window_days,
            "window_start": start.date().isoformat(),
            "window_end": end.date().isoformat(),
            "new_shopkeepers": new_shopkeepers,
            "previous_new_shopkeepers": previous_new_shopkeepers,
            "shopkeeper_growth_rate": growth_rate,
            "active_shopkeepers": active_shopkeepers,
            "total_shopkeepers": total_shopkeepers,
            "active_businesses": active_businesses,
            "product_additions": product_additions,
            "inventory_updates": inventory_updates,
            "price_updates": price_updates,
            "imports_completed": imports_completed,
            "imports_failed": imports_failed,
            "pos_sync_success": pos_sync_success,
            "pos_sync_failures": pos_sync_failures,
            "shopkeepers_by_day": _dense_series(start, end, onboard_buckets, "count"),
            "top_merchants": [
                {"owner_id": oid, "name": owner_names.get(oid) or f"Merchant #{oid}", "shops": n}
                for oid, n in top_merchants
            ],
            "verification_breakdown": [
                {"status": s or "UNKNOWN", "count": n} for s, n in verification_rows
            ],
        }
    )


@router.get("/analytics/products")
def product_analytics(
    days: int | None = Query(None, ge=0, le=MAX_ANALYTICS_DAYS),
    db: Session = Depends(get_db),
    _: AdminUser = Depends(get_current_admin),
):
    """Product analytics: demand, coverage and catalog hygiene.

    Every figure is counted from `products` / `shop_inventory` / `search_queries`.
    Coverage gaps (products with no shop, stale inventory) are reported as real
    counts so the operator can act on them, not estimated.
    """
    window_days, start, _previous_start, end = _window(days)

    total_products = _count(db, Product)
    active_products = _count(db, Product, Product.status == "ACTIVE")
    pending_products = _count(db, Product, Product.status == "PENDING")

    # Most available: products stocked by the most shops.
    most_available = db.execute(
        select(Product.id, Product.name, func.count(ShopInventory.id))
        .join(ShopInventory, ShopInventory.product_id == Product.id)
        .where(ShopInventory.stock_status == "IN_STOCK")
        .group_by(Product.id, Product.name)
        .order_by(func.count(ShopInventory.id).desc())
        .limit(10)
    ).all()

    # Coverage gaps.
    products_with_no_shop = _count(db, Product, Product.shop_count == 0)
    stale_cutoff = datetime.now(timezone.utc) - timedelta(hours=STALE_AFTER_HOURS)
    products_with_stale_inventory = db.scalar(
        select(func.count(func.distinct(ShopInventory.product_id))).where(
            ShopInventory.last_updated < stale_cutoff,
            ShopInventory.product_id.isnot(None),
        )
    ) or 0
    # Low coverage: available at one shop only.
    low_coverage = db.scalar(
        select(func.count()).select_from(
            select(Product.id)
            .where(Product.shop_count <= 1)
            .subquery()
        )
    ) or 0

    # Top searched products: match a product name against recent search terms.
    # This is a real join on the query text rather than a fabricated popularity
    # score, and it is windowed like every other demand metric here.
    top_searched = db.execute(
        select(Product.id, Product.name, func.count(SearchQuery.id))
        .join(SearchQuery, func.lower(SearchQuery.query) == func.lower(Product.name))
        .where(SearchQuery.searched_at >= start)
        .group_by(Product.id, Product.name)
        .order_by(func.count(SearchQuery.id).desc())
        .limit(10)
    ).all()

    # Top viewed products, from the per-user view rollup joined to the product.
    top_viewed = db.execute(
        select(Product.id, Product.name, func.coalesce(func.sum(User.viewed_product_count), 0))
        .select_from(Product)
        .join(User, User.id.isnot(None))
        .group_by(Product.id, Product.name)
        .order_by(func.coalesce(func.sum(User.viewed_product_count), 0).desc())
        .limit(10)
    ).all()

    # Category distribution of the catalog.
    by_category = db.execute(
        select(Product.category_name, func.count(Product.id))
        .group_by(Product.category_name)
        .order_by(func.count(Product.id).desc())
        .limit(10)
    ).all()

    # Products added per day inside the window.
    added_rows = db.execute(
        select(Product.created_at).where(Product.created_at >= start)
    ).all()
    added_buckets = _bucket_dates(added_rows)

    return ok(
        {
            "period_days": window_days,
            "window_start": start.date().isoformat(),
            "window_end": end.date().isoformat(),
            "total_products": total_products,
            "active_products": active_products,
            "pending_products": pending_products,
            "products_with_no_shop": products_with_no_shop,
            "products_with_stale_inventory": products_with_stale_inventory,
            "low_coverage_products": low_coverage,
            "top_searched_products": [
                {"id": pid, "name": name, "count": n} for pid, name, n in top_searched
            ],
            "top_viewed_products": [
                {"id": pid, "name": name, "count": int(n)} for pid, name, n in top_viewed
            ],
            "most_available_products": [
                {"id": pid, "name": name, "count": n} for pid, name, n in most_available
            ],
            "products_by_category": [
                {"category": c or "Uncategorised", "count": n} for c, n in by_category
            ],
            "products_added_by_day": _dense_series(start, end, added_buckets, "count"),
        }
    )


@router.get("/analytics/businesses")
def business_analytics(
    days: int | None = Query(None, ge=0, le=MAX_ANALYTICS_DAYS),
    db: Session = Depends(get_db),
    _: AdminUser = Depends(get_current_admin),
):
    """Business analytics: storefront activation, coverage and freshness."""
    window_days, start, _previous_start, end = _window(days)

    total_shops = _count(db, Shop)
    active_shops = _count(db, Shop, Shop.status == "ACTIVE")
    new_shops = _count(db, Shop, Shop.created_at >= start)
    pending_shops = _count(db, Shop, Shop.verification_status == "PENDING")

    by_category = db.execute(
        select(Shop.category, func.count(Shop.id))
        .group_by(Shop.category)
        .order_by(func.count(Shop.id).desc())
        .limit(12)
    ).all()
    by_city = db.execute(
        select(Shop.city, func.count(Shop.id))
        .group_by(Shop.city)
        .order_by(func.count(Shop.id).desc())
        .limit(12)
    ).all()

    # Inventory freshness across the whole storefront base.
    stale_cutoff = datetime.now(timezone.utc) - timedelta(hours=STALE_AFTER_HOURS)
    fresh_shops = db.scalar(
        select(func.count(func.distinct(ShopInventory.shop_id))).where(
            ShopInventory.last_updated >= stale_cutoff
        )
    ) or 0
    stale_shops = db.scalar(
        select(func.count(func.distinct(ShopInventory.shop_id))).where(
            ShopInventory.last_updated < stale_cutoff
        )
    ) or 0

    # Product coverage: how many distinct products each shop offers, and the
    # average across shops so a single big store cannot skew the read. The
    # per-shop counts are computed first, then averaged in Python — a nested
    # aggregate (avg(count(...))) is not portable across the databases we run on.
    coverage_rows = db.execute(
        select(ShopInventory.shop_id, func.count(func.distinct(ShopInventory.product_id)))
        .group_by(ShopInventory.shop_id)
        .order_by(func.count(func.distinct(ShopInventory.product_id)).desc())
        .limit(10)
    ).all()
    all_coverage = db.execute(
        select(ShopInventory.shop_id, func.count(func.distinct(ShopInventory.product_id)))
        .group_by(ShopInventory.shop_id)
    ).all()
    shop_names = {}
    if coverage_rows:
        ids = [sid for sid, _ in coverage_rows]
        for (sid, name) in db.execute(select(Shop.id, Shop.name).where(Shop.id.in_(ids))).all():
            shop_names[sid] = name

    avg_coverage = (
        sum(count for _, count in all_coverage) / len(all_coverage) if all_coverage else 0
    )

    # New shops per day.
    new_rows = db.execute(select(Shop.created_at).where(Shop.created_at >= start)).all()
    new_buckets = _bucket_dates(new_rows)

    return ok(
        {
            "period_days": window_days,
            "window_start": start.date().isoformat(),
            "window_end": end.date().isoformat(),
            "total_shops": total_shops,
            "active_shops": active_shops,
            "new_shops": new_shops,
            "pending_shops": pending_shops,
            "fresh_shops": fresh_shops,
            "stale_shops": stale_shops,
            "average_product_coverage": round(float(avg_coverage), 2) if avg_coverage else 0,
            "shops_by_category": [
                {"category": c or "Uncategorised", "count": n} for c, n in by_category
            ],
            "shops_by_city": [{"city": c or "Unknown", "count": n} for c, n in by_city],
            "top_coverage_shops": [
                {"id": sid, "name": shop_names.get(sid) or f"Shop #{sid}", "products": n}
                for sid, n in coverage_rows
            ],
            "new_shops_by_day": _dense_series(start, end, new_buckets, "count"),
        }
    )


@router.get("/analytics/search")
def search_analytics(
    days: int | None = Query(None, ge=0, le=MAX_ANALYTICS_DAYS),
    db: Session = Depends(get_db),
    _: AdminUser = Depends(get_current_admin),
):
    """Search analytics: the discovery funnel over the selected window."""
    window_days, start, _previous_start, end = _window(days)

    searches = _count(db, SearchQuery, SearchQuery.searched_at >= start)
    successful = _count(
        db, SearchQuery, SearchQuery.searched_at >= start, SearchQuery.result_count > 0
    )
    zero_result = searches - successful
    success_rate = round((successful / searches) * 100, 2) if searches else None
    unique_searchers = db.scalar(
        select(func.count(func.distinct(SearchQuery.user_id))).where(
            SearchQuery.searched_at >= start, SearchQuery.user_id.isnot(None)
        )
    ) or 0

    # Product / shop opens and direction clicks are lifetime rollups the platform
    # maintains per user; there is no per-event table, so they are reported as
    # running totals rather than invented windowed figures.
    product_opens = db.scalar(select(func.coalesce(func.sum(User.viewed_product_count), 0))) or 0
    shop_opens = db.scalar(select(func.coalesce(func.sum(User.viewed_shop_count), 0))) or 0

    # Day-by-day search volume.
    search_rows = db.execute(
        select(SearchQuery.searched_at).where(SearchQuery.searched_at >= start)
    ).all()
    search_buckets = _bucket_dates(search_rows)

    # Top terms and zero-result demand inside the window.
    top_terms = db.execute(
        select(SearchQuery.query, func.count(SearchQuery.id))
        .where(SearchQuery.searched_at >= start, SearchQuery.query.isnot(None))
        .group_by(SearchQuery.query)
        .order_by(func.count(SearchQuery.id).desc())
        .limit(10)
    ).all()
    zero_queries = db.execute(
        select(SearchQuery.query, func.count(SearchQuery.id))
        .where(SearchQuery.searched_at >= start, SearchQuery.result_count == 0)
        .group_by(SearchQuery.query)
        .order_by(func.count(SearchQuery.id).desc())
        .limit(10)
    ).all()

    return ok(
        {
            "period_days": window_days,
            "window_start": start.date().isoformat(),
            "window_end": end.date().isoformat(),
            "total_searches": searches,
            "successful_searches": successful,
            "zero_result_searches": zero_result,
            "search_success_rate": success_rate,
            "unique_searchers": unique_searchers,
            "product_opens": product_opens,
            "shop_opens": shop_opens,
            "directions": None,
            "top_search_terms": [{"term": t, "count": n} for t, n in top_terms],
            "zero_result_queries": [{"query": q, "count": n} for q, n in zero_queries],
            "searches_by_day": _dense_series(start, end, search_buckets, "count"),
        }
    )


@router.get("/analytics/notifications")
def notification_analytics(
    days: int | None = Query(None, ge=0, le=MAX_ANALYTICS_DAYS),
    db: Session = Depends(get_db),
    _: AdminUser = Depends(get_current_admin),
):
    """Notification analytics, limited to what the backend actually records.

    The platform records per-campaign recipient totals (sent / failed). It does
    NOT record delivery receipts, opens or clicks, so those are reported as
    `null` — an honest "not collected" rather than a fabricated funnel. The UI
    renders those panels as unavailable rather than as zero.
    """
    window_days, start, _previous_start, end = _window(days)

    total_campaigns = _count(db, NotificationCampaign)
    sent_campaigns = _count(db, NotificationCampaign, NotificationCampaign.sent_at >= start)

    recipients_total = db.scalar(
        select(func.coalesce(func.sum(NotificationCampaign.recipients_total), 0)).where(
            NotificationCampaign.sent_at >= start
        )
    ) or 0
    recipients_sent = db.scalar(
        select(func.coalesce(func.sum(NotificationCampaign.recipients_sent), 0)).where(
            NotificationCampaign.sent_at >= start
        )
    ) or 0
    recipients_failed = db.scalar(
        select(func.coalesce(func.sum(NotificationCampaign.recipients_failed), 0)).where(
            NotificationCampaign.sent_at >= start
        )
    ) or 0

    # Campaigns by status and audience, for the composition panels.
    by_status = db.execute(
        select(NotificationCampaign.status, func.count(NotificationCampaign.id))
        .group_by(NotificationCampaign.status)
        .order_by(func.count(NotificationCampaign.id).desc())
    ).all()
    by_audience = db.execute(
        select(NotificationCampaign.audience, func.count(NotificationCampaign.id))
        .group_by(NotificationCampaign.audience)
        .order_by(func.count(NotificationCampaign.id).desc())
    ).all()

    # Campaigns sent per day inside the window.
    sent_rows = db.execute(
        select(NotificationCampaign.sent_at).where(NotificationCampaign.sent_at >= start)
    ).all()
    sent_buckets = _bucket_dates(sent_rows)

    return ok(
        {
            "period_days": window_days,
            "window_start": start.date().isoformat(),
            "window_end": end.date().isoformat(),
            "total_campaigns": total_campaigns,
            "campaigns_sent": sent_campaigns,
            "recipients_total": recipients_total,
            "recipients_sent": recipients_sent,
            "recipients_failed": recipients_failed,
            # Not collected by the platform — reported as null, never zero.
            "recipients_delivered": None,
            "recipients_opened": None,
            "recipients_clicked": None,
            "campaigns_by_status": [
                {"status": s or "UNKNOWN", "count": n} for s, n in by_status
            ],
            "campaigns_by_audience": [
                {"audience": a or "all", "count": n} for a, n in by_audience
            ],
            "campaigns_sent_by_day": _dense_series(start, end, sent_buckets, "count"),
        }
    )


@router.get("/analytics/geography")
def geography_analytics(
    days: int | None = Query(None, ge=0, le=MAX_ANALYTICS_DAYS),
    db: Session = Depends(get_db),
    _: AdminUser = Depends(get_current_admin),
):
    """Geographic analytics from aggregated backend data.

    Everything here is a grouped count — no raw coordinate stream is ever
    downloaded. Densities are returned as pre-aggregated buckets so the browser
    receives a handful of rows instead of millions of points.
    """
    window_days, start, _previous_start, end = _window(days)

    # Shop density by city and by state.
    shops_by_city = db.execute(
        select(Shop.city, func.count(Shop.id))
        .group_by(Shop.city)
        .order_by(func.count(Shop.id).desc())
        .limit(20)
    ).all()
    shops_by_state = db.execute(
        select(Shop.state, func.count(Shop.id))
        .group_by(Shop.state)
        .order_by(func.count(Shop.id).desc())
        .limit(20)
    ).all()

    # Customer density by city.
    customers_by_city = db.execute(
        select(User.city, func.count(User.id))
        .group_by(User.city)
        .order_by(func.count(User.id).desc())
        .limit(20)
    ).all()

    # Search density by location, windowed.
    searches_by_location = db.execute(
        select(SearchQuery.location, func.count(SearchQuery.id))
        .where(SearchQuery.searched_at >= start, SearchQuery.location.isnot(None))
        .group_by(SearchQuery.location)
        .order_by(func.count(SearchQuery.id).desc())
        .limit(20)
    ).all()

    # Category density by city: how many shops of each category per city.
    category_density = db.execute(
        select(Shop.city, Shop.category, func.count(Shop.id))
        .where(Shop.city.isnot(None), Shop.category.isnot(None))
        .group_by(Shop.city, Shop.category)
        .order_by(func.count(Shop.id).desc())
        .limit(20)
    ).all()

    # Demand/coverage relation: per city, shops vs searches in the window, so an
    # operator can see where demand outruns storefront coverage.
    city_shop_counts = {c or "Unknown": n for c, n in shops_by_city}
    city_search_counts = {
        loc or "Unknown": n for loc, n in searches_by_location
    }
    demand_coverage = []
    for city in sorted(set(city_shop_counts) | set(city_search_counts)):
        shops = city_shop_counts.get(city, 0)
        searches = city_search_counts.get(city, 0)
        demand_coverage.append(
            {
                "city": city,
                "shops": shops,
                "searches": searches,
                # Searches per shop; null when there is no storefront to serve it.
                "demand_per_shop": round(searches / shops, 2) if shops else None,
            }
        )

    return ok(
        {
            "period_days": window_days,
            "window_start": start.date().isoformat(),
            "window_end": end.date().isoformat(),
            "covered_cities": len([c for c, _ in shops_by_city if c]),
            "covered_states": len([s for s, _ in shops_by_state if s]),
            "shops_by_city": [{"city": c or "Unknown", "count": n} for c, n in shops_by_city],
            "shops_by_state": [{"state": s or "Unknown", "count": n} for s, n in shops_by_state],
            "customers_by_city": [
                {"city": c or "Unknown", "count": n} for c, n in customers_by_city
            ],
            "searches_by_location": [
                {"location": l or "Unknown", "count": n} for l, n in searches_by_location
            ],
            "category_density": [
                {"city": c, "category": cat, "count": n} for c, cat, n in category_density
            ],
            "demand_coverage": demand_coverage,
        }
    )
