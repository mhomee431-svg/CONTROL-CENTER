"""Phase 29 — Platform analytics system.

Single source of truth for meaningful platform events:

    CUSTOMER    SEARCH, SEARCH_RESULT_CLICK, PRODUCT_VIEW, SHOP_VIEW,
                DIRECTIONS, SAVE, SHARE
    SHOPKEEPER  PRODUCT_ADDED, INVENTORY_UPDATED, PRICE_CHANGED,
                OFFER_CREATED, BARCODE_SCAN, EXCEL_IMPORT, POS_SYNC,
                SUBSCRIPTION_CREATED, SUBSCRIPTION_RENEWED,
                SUBSCRIPTION_CANCELLED, PAYMENT_SUCCEEDED
    PLATFORM    SEARCH_SUCCESS, SEARCH_FAILURE, INVENTORY_FRESHNESS,
                API_PERFORMANCE, ERROR

Design rules:
    * Events are append-only; every dashboard/report metric is derived from
      them (business metrics trace back to raw events — VERIFY requirement).
    * No personal information is stored: actor_id is a surrogate id, session
      ids are opaque, and free-form props pass through :func:`sanitize_props`.
    * Daily aggregates are rebuildable at any time (idempotent per day).
"""
from __future__ import annotations

from datetime import date as date_cls
from datetime import datetime, time, timedelta, timezone

from sqlalchemy import distinct, func
from sqlalchemy.orm import Session

from app.core.exceptions import NotFoundError, ValidationError
from app.models.analytics_event import AnalyticsDailyAggregate, AnalyticsEvent
from app.models.admin import Report

# ── Event catalog ────────────────────────────────────────────────────────────
ACTOR_CUSTOMER = "CUSTOMER"
ACTOR_SHOPKEEPER = "SHOPKEEPER"
ACTOR_PLATFORM = "PLATFORM"
VALID_ACTORS = (ACTOR_CUSTOMER, ACTOR_SHOPKEEPER, ACTOR_PLATFORM)

CUSTOMER_EVENTS = {
    "SEARCH",
    "SEARCH_RESULT_CLICK",
    "PRODUCT_VIEW",
    "SHOP_VIEW",
    "DIRECTIONS",
    "SAVE",
    "SHARE",
}

SHOPKEEPER_EVENTS = {
    "PRODUCT_ADDED",
    "INVENTORY_UPDATED",
    "PRICE_CHANGED",
    "OFFER_CREATED",
    "BARCODE_SCAN",
    "EXCEL_IMPORT",
    "POS_SYNC",
    # Phase-29 additions so subscription metrics stay event-traceable.
    "SUBSCRIPTION_CREATED",
    "SUBSCRIPTION_RENEWED",
    "SUBSCRIPTION_CANCELLED",
    "PAYMENT_SUCCEEDED",
}

PLATFORM_EVENTS = {
    "SEARCH_SUCCESS",
    "SEARCH_FAILURE",
    "INVENTORY_FRESHNESS",
    "API_PERFORMANCE",
    "ERROR",
}

EVENT_CATALOG: dict[str, set[str]] = {
    ACTOR_CUSTOMER: CUSTOMER_EVENTS,
    ACTOR_SHOPKEEPER: SHOPKEEPER_EVENTS,
    ACTOR_PLATFORM: PLATFORM_EVENTS,
}
ALL_EVENTS = CUSTOMER_EVENTS | SHOPKEEPER_EVENTS | PLATFORM_EVENTS

# ── Privacy scrubbing ────────────────────────────────────────────────────────
#: prop keys that would carry personal information — never persisted.
FORBIDDEN_PROP_KEYS = {
    "email", "e_mail", "phone", "phone_number", "mobile", "name",
    "full_name", "first_name", "last_name", "address", "street", "city",
    "pincode", "zip", "postal_code", "password", "token", "otp",
    "latitude", "longitude", "lat", "lng", "lon", "gps", "location",
    "device_id", "imei", "aadhaar", "pan", "card_number", "upi_id",
}


def sanitize_props(props: dict | None) -> dict | None:
    """Strip personal information from free-form event properties.

    - removes any key in ``FORBIDDEN_PROP_KEYS`` (case-insensitive)
    - truncates long string values, caps the number of retained keys
    """
    if not props:
        return None
    cleaned: dict = {}
    for key, value in list(props.items())[:25]:
        if str(key).strip().lower() in FORBIDDEN_PROP_KEYS:
            continue
        if isinstance(value, str):
            value = value[:255]
        elif isinstance(value, (int, float, bool)) or value is None:
            pass
        else:
            value = str(value)[:255]
        cleaned[str(key)[:50]] = value
    return cleaned or None


# ── Event generation ─────────────────────────────────────────────────────────
def track_event(
    db: Session,
    *,
    event_name: str,
    actor_type: str,
    actor_id: int | None = None,
    session_id: str | None = None,
    shop_id: int | None = None,
    product_master_id: int | None = None,
    category_id: int | None = None,
    query: str | None = None,
    metric_value: float | None = None,
    props: dict | None = None,
    device_type: str | None = None,
    app_version: str | None = None,
    occurred_at: datetime | None = None,
) -> AnalyticsEvent:
    """Record one analytics event. Validates against the phase-29 catalog."""
    if actor_type not in VALID_ACTORS:
        raise ValidationError(f"Unknown actor type: {actor_type}")
    if event_name not in EVENT_CATALOG[actor_type]:
        raise ValidationError(f"Unknown {actor_type} event: {event_name}")
    if query:
        query = query.strip()[:255]
        if not query:
            query = None

    event = AnalyticsEvent(
        event_name=event_name,
        actor_type=actor_type,
        actor_id=actor_id,
        session_id=session_id[:64] if session_id else None,
        shop_id=shop_id,
        product_master_id=product_master_id,
        category_id=category_id,
        query=query,
        metric_value=float(metric_value) if metric_value is not None else None,
        props=sanitize_props(props),
        device_type=device_type[:20] if device_type else None,
        app_version=app_version[:20] if app_version else None,
        occurred_at=occurred_at or datetime.now(timezone.utc),
    )
    db.add(event)
    db.flush()
    return event


def track_search(
    db: Session,
    *,
    user_id: int | None,
    session_id: str | None = None,
    query: str,
    result_count: int,
    device_type: str | None = None,
    app_version: str | None = None,
    occurred_at: datetime | None = None,
) -> AnalyticsEvent:
    """Customer search + the paired platform outcome event.

    One customer ``SEARCH`` always yields exactly one of ``SEARCH_SUCCESS`` /
    ``SEARCH_FAILURE`` (platform), sharing the same session id so conversion
    funnels remain joinable.
    """
    event = track_event(
        db,
        event_name="SEARCH",
        actor_type=ACTOR_CUSTOMER,
        actor_id=user_id,
        session_id=session_id,
        query=query,
        metric_value=float(result_count),
        device_type=device_type,
        app_version=app_version,
        occurred_at=occurred_at,
    )
    successful = result_count > 0
    track_event(
        db,
        event_name="SEARCH_SUCCESS" if successful else "SEARCH_FAILURE",
        actor_type=ACTOR_PLATFORM,
        actor_id=user_id,
        session_id=session_id,
        query=query,
        metric_value=float(result_count),
        occurred_at=event.occurred_at,
    )
    return event


def get_event(db: Session, event_id: int) -> AnalyticsEvent:
    event = db.query(AnalyticsEvent).filter(AnalyticsEvent.id == event_id).first()
    if event is None:
        raise NotFoundError("Analytics event not found")
    return event


def serialize_event(event: AnalyticsEvent) -> dict:
    return {
        "id": event.id,
        "event_name": event.event_name,
        "actor_type": event.actor_type,
        "actor_id": event.actor_id,
        "session_id": event.session_id,
        "shop_id": event.shop_id,
        "product_master_id": event.product_master_id,
        "category_id": event.category_id,
        "query": event.query,
        "metric_value": event.metric_value,
        "props": event.props,
        "device_type": event.device_type,
        "app_version": event.app_version,
        "occurred_at": event.occurred_at.isoformat() if event.occurred_at else None,
    }


# ── Aggregation ──────────────────────────────────────────────────────────────
def _day_bounds(day):
    start = datetime.combine(day, time.min)
    return start, start + timedelta(days=1)


def aggregate_daily(db: Session, day=None) -> dict:
    """(Re)build daily rollups for one UTC day. Idempotent per day.

    Groups raw events by (event_name, actor_type, shop, product, category)
    with counts, distinct sessions/actors and summed metric values.
    """
    if isinstance(day, datetime):
        day = day.date()
    day = day or datetime.now(timezone.utc).date()
    start, end = _day_bounds(day)

    rows = (
        db.query(
            AnalyticsEvent.event_name,
            AnalyticsEvent.actor_type,
            AnalyticsEvent.shop_id,
            AnalyticsEvent.product_master_id,
            AnalyticsEvent.category_id,
            func.count(AnalyticsEvent.id).label("event_count"),
            func.count(distinct(AnalyticsEvent.session_id)).label("distinct_sessions"),
            func.count(distinct(AnalyticsEvent.actor_id)).label("distinct_actors"),
            func.coalesce(func.sum(AnalyticsEvent.metric_value), 0.0).label("metric_sum"),
        )
        .filter(AnalyticsEvent.occurred_at >= start, AnalyticsEvent.occurred_at < end)
        .group_by(
            AnalyticsEvent.event_name,
            AnalyticsEvent.actor_type,
            AnalyticsEvent.shop_id,
            AnalyticsEvent.product_master_id,
            AnalyticsEvent.category_id,
        )
        .all()
    )

    # Idempotent rebuild for the day.
    db.query(AnalyticsDailyAggregate).filter(
        AnalyticsDailyAggregate.aggregate_date == day
    ).delete()

    written = 0
    for r in rows:
        db.add(
            AnalyticsDailyAggregate(
                aggregate_date=day,
                event_name=r.event_name,
                actor_type=r.actor_type,
                shop_id=r.shop_id,
                product_master_id=r.product_master_id,
                category_id=r.category_id,
                event_count=int(r.event_count),
                distinct_sessions=int(r.distinct_sessions or 0),
                distinct_actors=int(r.distinct_actors or 0),
                metric_sum=float(r.metric_sum or 0.0),
            )
        )
        written += 1
    db.flush()
    return {"date": day.isoformat(), "groups": written}


def aggregate_range(db: Session, days: int = 30, end_day=None) -> dict:
    """Aggregate the trailing ``days`` days ending at ``end_day`` (inclusive)."""
    end_day = end_day or datetime.now(timezone.utc).date()
    total = 0
    for offset in range(days):
        result = aggregate_daily(db, end_day - timedelta(days=offset))
        total += result["groups"]
    return {"days": days, "groups_total": total}


def read_aggregates(
    db: Session, *, event_name: str | None = None, limit: int = 200
) -> list[dict]:
    query = (
        db.query(AnalyticsDailyAggregate)
        .order_by(
            AnalyticsDailyAggregate.aggregate_date.desc(),
            AnalyticsDailyAggregate.event_name,
        )
    )
    if event_name:
        query = query.filter(AnalyticsDailyAggregate.event_name == event_name)
    return [
        {
            "aggregate_date": a.aggregate_date.isoformat(),
            "event_name": a.event_name,
            "actor_type": a.actor_type,
            "shop_id": a.shop_id,
            "product_master_id": a.product_master_id,
            "category_id": a.category_id,
            "event_count": a.event_count,
            "distinct_sessions": a.distinct_sessions,
            "distinct_actors": a.distinct_actors,
            "metric_sum": a.metric_sum,
        }
        for a in query.limit(limit).all()
    ]


# ── Dashboard builders (all derived from raw events) ─────────────────────────
def _window_start(days: int) -> datetime:
    return datetime.now(timezone.utc) - timedelta(days=max(int(days), 1))


def search_trends(db: Session, days: int = 30) -> dict:
    since = _window_start(days)

    def _count(name):
        return int(
            db.query(func.count(AnalyticsEvent.id))
            .filter(
                AnalyticsEvent.event_name == name,
                AnalyticsEvent.occurred_at >= since,
            )
            .scalar()
            or 0
        )

    total = _count("SEARCH")
    successes = _count("SEARCH_SUCCESS")
    failures = _count("SEARCH_FAILURE")
    daily = (
        db.query(
            func.date(AnalyticsEvent.occurred_at).label("d"),
            func.count(AnalyticsEvent.id),
        )
        .filter(
            AnalyticsEvent.event_name == "SEARCH",
            AnalyticsEvent.occurred_at >= since,
        )
        .group_by(func.date(AnalyticsEvent.occurred_at))
        .order_by(func.date(AnalyticsEvent.occurred_at))
        .all()
    )
    top_queries = (
        db.query(AnalyticsEvent.query, func.count(AnalyticsEvent.id).label("cnt"))
        .filter(
            AnalyticsEvent.event_name == "SEARCH",
            AnalyticsEvent.occurred_at >= since,
            AnalyticsEvent.query.isnot(None),
        )
        .group_by(AnalyticsEvent.query)
        .order_by(func.count(AnalyticsEvent.id).desc())
        .limit(10)
        .all()
    )
    return {
        "window_days": int(days),
        "total_searches": total,
        "daily": [{"date": str(d), "searches": int(c)} for d, c in daily],
        "top_queries": [{"query": q, "count": int(c)} for q, c in top_queries],
        "success_rate": round(successes / total, 4) if total else None,
        "failures": failures,
    }


def popular_products(db: Session, days: int = 30, limit: int = 10) -> list[dict]:
    since = _window_start(days)
    rows = (
        db.query(
            AnalyticsEvent.product_master_id.label("pid"),
            func.count(AnalyticsEvent.id).label("views"),
            func.count(distinct(AnalyticsEvent.session_id)).label("sessions"),
        )
        .filter(
            AnalyticsEvent.product_master_id.isnot(None),
            AnalyticsEvent.event_name.in_(["PRODUCT_VIEW", "SEARCH_RESULT_CLICK"]),
            AnalyticsEvent.occurred_at >= since,
        )
        .group_by(AnalyticsEvent.product_master_id)
        .order_by(func.count(AnalyticsEvent.id).desc())
        .limit(limit)
        .all()
    )
    return [
        {
            "product_master_id": pid,
            "activity_count": int(views),
            "distinct_sessions": int(sessions),
        }
        for pid, views, sessions in rows
    ]


def popular_categories(db: Session, days: int = 30, limit: int = 10) -> list[dict]:
    since = _window_start(days)
    rows = (
        db.query(
            AnalyticsEvent.category_id.label("cid"),
            func.count(AnalyticsEvent.id).label("cnt"),
        )
        .filter(AnalyticsEvent.category_id.isnot(None), AnalyticsEvent.occurred_at >= since)
        .group_by(AnalyticsEvent.category_id)
        .order_by(func.count(AnalyticsEvent.id).desc())
        .limit(limit)
        .all()
    )
    return [{"category_id": cid, "event_count": int(cnt)} for cid, cnt in rows]


def popular_shops(db: Session, days: int = 30, limit: int = 10) -> list[dict]:
    since = _window_start(days)
    rows = (
        db.query(
            AnalyticsEvent.shop_id.label("sid"),
            func.count(AnalyticsEvent.id).label("cnt"),
            func.count(distinct(AnalyticsEvent.session_id)).label("sessions"),
        )
        .filter(
            AnalyticsEvent.shop_id.isnot(None),
            AnalyticsEvent.event_name.in_(["SHOP_VIEW", "DIRECTIONS", "SEARCH_RESULT_CLICK"]),
            AnalyticsEvent.occurred_at >= since,
        )
        .group_by(AnalyticsEvent.shop_id)
        .order_by(func.count(AnalyticsEvent.id).desc())
        .limit(limit)
        .all()
    )
    return [
        {"shop_id": sid, "activity_count": int(cnt), "distinct_sessions": int(sessions)}
        for sid, cnt, sessions in rows
    ]


def search_to_shop_conversion(db: Session, days: int = 30) -> dict:
    """Share of search sessions that continued into a shop view / directions."""
    since = _window_start(days)

    def _sessions(names):
        rows = (
            db.query(AnalyticsEvent.session_id)
            .filter(
                AnalyticsEvent.event_name.in_(list(names)),
                AnalyticsEvent.session_id.isnot(None),
                AnalyticsEvent.occurred_at >= since,
            )
            .distinct()
            .all()
        )
        return {r[0] for r in rows}

    search_sessions = _sessions(["SEARCH"])
    shop_sessions = _sessions(["SHOP_VIEW", "DIRECTIONS"])
    converted = search_sessions & shop_sessions
    rate = round(len(converted) / len(search_sessions), 4) if search_sessions else None
    return {
        "window_days": int(days),
        "search_sessions": len(search_sessions),
        "converted_to_shop": len(converted),
        "conversion_rate": rate,
    }


def inventory_freshness(db: Session, days: int = 30) -> dict:
    """Average freshness ratio (0..1) reported via INVENTORY_FRESHNESS events."""
    since = _window_start(days)
    daily_rows = (
        db.query(
            func.date(AnalyticsEvent.occurred_at).label("d"),
            func.avg(AnalyticsEvent.metric_value).label("avg_freshness"),
            func.count(AnalyticsEvent.id),
        )
        .filter(
            AnalyticsEvent.event_name == "INVENTORY_FRESHNESS",
            AnalyticsEvent.occurred_at >= since,
        )
        .group_by(func.date(AnalyticsEvent.occurred_at))
        .order_by(func.date(AnalyticsEvent.occurred_at))
        .all()
    )
    by_shop = (
        db.query(
            AnalyticsEvent.shop_id.label("sid"),
            func.avg(AnalyticsEvent.metric_value).label("avg_freshness"),
        )
        .filter(
            AnalyticsEvent.event_name == "INVENTORY_FRESHNESS",
            AnalyticsEvent.shop_id.isnot(None),
            AnalyticsEvent.occurred_at >= since,
        )
        .group_by(AnalyticsEvent.shop_id)
        .all()
    )
    values = [float(r[1]) for r in daily_rows if r[1] is not None]
    overall = round(sum(values) / len(values), 4) if values else None
    return {
        "window_days": int(days),
        "overall_avg_freshness": overall,
        "daily": [
            {"date": str(d), "avg_freshness": round(float(a), 4), "samples": int(c)}
            for d, a, c in daily_rows
        ],
        "by_shop": [
            {"shop_id": sid, "avg_freshness": round(float(a), 4)} for sid, a in by_shop
        ],
    }


def shop_activity(db: Session, days: int = 30, limit: int = 20) -> list[dict]:
    """All tracked activity grouped per shop (views, directions, keeper ops...)."""
    since = _window_start(days)
    rows = (
        db.query(
            AnalyticsEvent.shop_id.label("sid"),
            func.count(AnalyticsEvent.id).label("cnt"),
        )
        .filter(AnalyticsEvent.shop_id.isnot(None), AnalyticsEvent.occurred_at >= since)
        .group_by(AnalyticsEvent.shop_id)
        .order_by(func.count(AnalyticsEvent.id).desc())
        .limit(limit)
        .all()
    )
    return [{"shop_id": sid, "event_count": int(cnt)} for sid, cnt in rows]


def product_activity(db: Session, days: int = 30, limit: int = 20) -> list[dict]:
    since = _window_start(days)
    rows = (
        db.query(
            AnalyticsEvent.product_master_id.label("pid"),
            func.count(AnalyticsEvent.id).label("cnt"),
        )
        .filter(
            AnalyticsEvent.product_master_id.isnot(None),
            AnalyticsEvent.occurred_at >= since,
        )
        .group_by(AnalyticsEvent.product_master_id)
        .order_by(func.count(AnalyticsEvent.id).desc())
        .limit(limit)
        .all()
    )
    return [{"product_master_id": pid, "event_count": int(cnt)} for pid, cnt in rows]


def subscription_metrics(db: Session, days: int = 90) -> dict:
    """Subscription funnel derived from shopkeeper-family lifecycle events."""
    since = _window_start(days)
    names = [
        "SUBSCRIPTION_CREATED",
        "SUBSCRIPTION_RENEWED",
        "SUBSCRIPTION_CANCELLED",
        "PAYMENT_SUCCEEDED",
    ]
    rows = (
        db.query(AnalyticsEvent.event_name, func.count(AnalyticsEvent.id))
        .filter(AnalyticsEvent.event_name.in_(names), AnalyticsEvent.occurred_at >= since)
        .group_by(AnalyticsEvent.event_name)
        .all()
    )
    counts = {name: int(cnt) for name, cnt in rows}
    revenue_row = (
        db.query(func.coalesce(func.sum(AnalyticsEvent.metric_value), 0.0))
        .filter(
            AnalyticsEvent.event_name == "PAYMENT_SUCCEEDED",
            AnalyticsEvent.occurred_at >= since,
        )
        .scalar()
    )
    created = counts.get("SUBSCRIPTION_CREATED", 0)
    cancelled = counts.get("SUBSCRIPTION_CANCELLED", 0)
    churn = round(cancelled / created, 4) if created else None
    return {
        "window_days": int(days),
        "subscriptions_created": created,
        "subscriptions_renewed": counts.get("SUBSCRIPTION_RENEWED", 0),
        "subscriptions_cancelled": cancelled,
        "payments_succeeded": counts.get("PAYMENT_SUCCEEDED", 0),
        "revenue": float(revenue_row or 0.0),
        "churn_rate": churn,
    }


def platform_health(db: Session, hours: int = 24) -> dict:
    """API performance + error + search-outcome health from platform events."""
    since = datetime.now(timezone.utc) - timedelta(hours=max(int(hours), 1))

    durations = [
        float(v[0])
        for v in db.query(AnalyticsEvent.metric_value)
        .filter(
            AnalyticsEvent.event_name == "API_PERFORMANCE",
            AnalyticsEvent.occurred_at >= since,
            AnalyticsEvent.metric_value.isnot(None),
        )
        .all()
    ]
    durations.sort()

    def _count(name):
        return int(
            db.query(func.count(AnalyticsEvent.id))
            .filter(
                AnalyticsEvent.event_name == name,
                AnalyticsEvent.occurred_at >= since,
            )
            .scalar()
            or 0
        )

    error_count = _count("ERROR")
    successes = _count("SEARCH_SUCCESS")
    failures = _count("SEARCH_FAILURE")

    def _percentile(sorted_vals, pct):
        if not sorted_vals:
            return None
        idx = min(len(sorted_vals) - 1, max(0, round(pct * (len(sorted_vals) - 1))))
        return sorted_vals[idx]

    searches = successes + failures
    return {
        "window_hours": int(hours),
        "api_calls": len(durations),
        "latency_ms_avg": round(sum(durations) / len(durations), 2) if durations else None,
        "latency_ms_p50": _percentile(durations, 0.50),
        "latency_ms_p95": _percentile(durations, 0.95),
        "errors": error_count,
        "search_successes": successes,
        "search_failures": failures,
        "search_failure_rate": round(failures / searches, 4) if searches else None,
    }


# ── Reports ──────────────────────────────────────────────────────────────────
REPORT_BUILDERS = {
    "SEARCH_TRENDS": search_trends,
    "POPULAR_PRODUCTS": popular_products,
    "POPULAR_CATEGORIES": popular_categories,
    "POPULAR_SHOPS": popular_shops,
    "CONVERSION": search_to_shop_conversion,
    "INVENTORY_FRESHNESS": inventory_freshness,
    "SHOP_ACTIVITY": shop_activity,
    "PRODUCT_ACTIVITY": product_activity,
    "SUBSCRIPTIONS": subscription_metrics,
    "PLATFORM_HEALTH": platform_health,
}

_REPORT_PARAM_DEFAULTS = {"days": 30, "hours": 24, "limit": 20}


def generate_report(
    db: Session,
    *,
    report_type: str,
    generated_by: int | None = None,
    params: dict | None = None,
) -> Report:
    """Build an analytics report synchronously and persist it with its payload."""
    report_type = (report_type or "").upper()
    builder = REPORT_BUILDERS.get(report_type)
    if builder is None:
        raise NotFoundError(f"Unknown report type: {report_type}")

    params = {**_REPORT_PARAM_DEFAULTS, **(params or {})}
    report = Report(
        report_type=f"ANALYTICS_{report_type}",
        report_name=f"{report_type.replace('_', ' ').title()} Report",
        parameters_json={"report_type": report_type, **params},
        generated_by=generated_by,
        status="GENERATING",
        started_at=datetime.now(timezone.utc),
    )
    db.add(report)
    db.flush()

    try:
        arg_names = builder.__code__.co_varnames[: builder.__code__.co_argcount]
        kwargs = {key: params[key] for key in ("days", "hours", "limit") if key in arg_names}
        payload = builder(db, **kwargs)
        report.result_json = {
            "report_type": report_type,
            "generated_at": datetime.now(timezone.utc).isoformat(),
            "data": payload,
        }
        report.status = "READY"
        report.completed_at = datetime.now(timezone.utc)
    except Exception as exc:  # noqa: BLE001 — persist failure state for observability
        report.status = "FAILED"
        report.error_message = str(exc)[:2000]
    db.flush()
    return report


def serialize_report(report: Report) -> dict:
    return {
        "id": report.id,
        "report_type": report.report_type,
        "report_name": report.report_name,
        "parameters_json": report.parameters_json,
        "result_json": report.result_json,
        "status": report.status,
        "generated_by": report.generated_by,
        "started_at": report.started_at.isoformat() if report.started_at else None,
        "completed_at": report.completed_at.isoformat() if report.completed_at else None,
        "error_message": report.error_message,
    }


def get_report(db: Session, report_id: int) -> Report:
    report = db.query(Report).filter(Report.id == report_id).first()
    if report is None:
        raise NotFoundError("Report not found")
    return report