"""Search Control Center.

The admin's highest-priority discovery surface. Three read-only routes:

* ``/admin/search/summary``     — volume, funnel, quality and top-search tiles.
* ``/admin/search/zero-results`` — paginated catalog-gap investigation list.
* ``/admin/search/quality``     — per-term quality breakdown for review.

Honesty contract (same as the analytics sections): every figure is computed
from the ``search_queries`` table, joined to the real catalog where a match is
shown. The platform does not record per-search latency, failures, clicks,
saves, directions or engine-side relevance scores — those are reported as
``null`` (an honest "not collected"), never fabricated. In particular:

* **No product recommendation is ever invented.** `potential_category` is a
  server-side token overlap between the query and category names, and
  `candidate_products` are real catalog rows whose names share a token with
  the query — labelled as candidates for gap review, not as matches.
* **No search-engine logic lives here.** This router only observes what the
  customer app recorded; it never re-runs or re-scores a query.
"""

from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends, Query
from sqlalchemy import case, func, or_, select
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.core.pagination import Pagination, pagination
from app.core.responses import ok, paged
from app.core.security import get_current_admin
from app.models import AdminUser, Category, Product, SearchQuery, User

router = APIRouter(prefix="/admin/search", tags=["search-control"])

# Same window bounds as the analytics sections so two consoles can never
# report over subtly different spans.
DEFAULT_WINDOW_DAYS = 30
MAX_WINDOW_DAYS = 365

# Words that carry no catalog meaning; they never drive a category or product
# candidate match (a "10mm bosch drill" gap is about the drill, not the mm).
_STOPWORDS = {
    "a", "an", "the", "for", "near", "me", "my", "and", "or", "of", "in",
    "on", "with", "buy", "cheap", "shop", "store", "please",
}


def _window(days: int | None) -> tuple[int, datetime, datetime]:
    """Inclusive reporting window: today plus the preceding (days - 1) days."""
    window_days = days if days and days > 0 else DEFAULT_WINDOW_DAYS
    window_days = min(window_days, MAX_WINDOW_DAYS)
    now = datetime.now(timezone.utc)
    start = now - timedelta(days=window_days - 1)
    return window_days, start.replace(hour=0, minute=0, second=0, microsecond=0), now


def _tokens(query: str | None) -> list[str]:
    """Meaningful tokens of a query string, lowercased, de-duplicated."""
    if not query:
        return []
    out: list[str] = []
    for raw in query.lower().replace("-", " ").replace("/", " ").split():
        word = raw.strip(".,!?\"'()[]{}:;")
        if len(word) >= 2 and word not in _STOPWORDS and not word.isdigit():
            out.append(word)
    return list(dict.fromkeys(out))


def _iso(value: datetime | None) -> str | None:
    return value.isoformat() if value else None


def _quality_metrics(total: int, successful: int, avg_results: float | None) -> dict:
    """The quality panel: real rates where collected, honest nulls elsewhere."""
    return {
        "success_rate": round((successful / total) * 100, 2) if total else None,
        "zero_result_rate": round(((total - successful) / total) * 100, 2) if total else None,
        "avg_result_count": round(float(avg_results), 2) if avg_results is not None else None,
        # Not collected by the platform today — null, never a fabricated zero.
        "click_rate": None,
        "product_matching_rate": None,
        "shop_matching_rate": None,
        "latency_ms": None,
        "search_failures": None,
    }



def _gap_analysis(db: Session, query: str, category_names: list[str] | None = None) -> dict:
    """Server-side gap evidence for one zero-result query.

    `potential_category` is a token overlap against real category names, and
    `candidate_products` are real catalog rows sharing a token with the query.
    Both are candidates for operator review — explicitly NOT a recommendation
    or a claimed match, because the customer search itself returned nothing.
    """
    query_tokens = _tokens(query)
    potential_category = None
    if category_names is None:
        category_names = [
            n for (n,) in db.execute(select(Category.name).where(Category.is_active.isnot(False))).all()
        ]
    for name in category_names:
        cat_tokens = set(_tokens(name))
        if cat_tokens and cat_tokens & set(query_tokens):
            potential_category = name
            break

    # Real catalog candidates: any product whose name shares a token.
    candidate_names: list[str] = []
    candidate_count = 0
    for token in query_tokens:
        like = f"%{token}%"
        stmt = select(Product.name).where(Product.name.ilike(like))
        total = db.scalar(select(func.count()).select_from(stmt.subquery())) or 0
        if total:
            candidate_count += total
            names = [n for (n,) in db.execute(stmt.limit(3)).all()]
            candidate_names.extend(names)
    return {
        "potential_category": potential_category,
        "candidate_products": candidate_count,
        "candidate_examples": list(dict.fromkeys(candidate_names))[:5],
        # Zero results is the definition of this row: nothing matched.
        "matched_products": [],
    }



@router.get("/summary")
def search_control_summary(
    days: int | None = Query(None, ge=0, le=MAX_WINDOW_DAYS),
    db: Session = Depends(get_db),
    _: AdminUser = Depends(get_current_admin),
):
    """Volume, funnel, quality and top-search tiles for the control center."""
    window_days, start, end = _window(days)

    total = db.scalar(
        select(func.count()).select_from(SearchQuery).where(SearchQuery.searched_at >= start)
    ) or 0
    successful = db.scalar(
        select(func.count())
        .select_from(SearchQuery)
        .where(SearchQuery.searched_at >= start, SearchQuery.result_count > 0)
    ) or 0
    unique_searchers = db.scalar(
        select(func.count(func.distinct(SearchQuery.user_id))).where(
            SearchQuery.searched_at >= start, SearchQuery.user_id.isnot(None)
        )
    ) or 0
    avg_results = db.scalar(
        select(func.avg(SearchQuery.result_count)).where(SearchQuery.searched_at >= start)
    )

    # Day-by-day volume and zero-result volume (the trends overlay).
    # Built explicitly from unpacked rows rather than `dict(rows)`: each SQLAlchemy
    # Row is a two-tuple, but a static checker cannot see that from the result
    # type and rejects it as a mapping source.
    day = func.date(SearchQuery.searched_at)
    by_day = {
        str(day_key): int(count)
        for day_key, count in db.execute(
            select(day, func.count()).where(SearchQuery.searched_at >= start).group_by(day)
        ).all()
    }
    zero_by_day = {
        str(day_key): int(count)
        for day_key, count in db.execute(
            select(day, func.count())
            .where(SearchQuery.searched_at >= start, SearchQuery.result_count == 0)
            .group_by(day)
        ).all()
    }
    by_location = db.execute(
        select(SearchQuery.location, func.count())
        .where(SearchQuery.searched_at >= start, SearchQuery.location.isnot(None))
        .group_by(SearchQuery.location)
        .order_by(func.count().desc())
        .limit(12)
    ).all()

    # Top searches: per-term volume, zero-result count, average results.
    term_rows = db.execute(
        select(
            SearchQuery.query,
            func.count(),
            func.sum(case((SearchQuery.result_count == 0, 1), else_=0)),
            func.avg(SearchQuery.result_count),
        )
        .where(SearchQuery.searched_at >= start, SearchQuery.query.isnot(None))
        .group_by(SearchQuery.query)
        .order_by(func.count().desc())
        .limit(25)
    ).all()
    top_searches = [
        {
            "term": t,
            "count": n,
            "zero_count": z,
            "zero_rate": round((z / n) * 100, 2) if n else None,
            "avg_result_count": round(float(a), 2) if a is not None else None,
        }
        for t, n, z, a in term_rows
    ]

    # Zero-result demand inside the window, with first/last seen for the range.
    zq = db.execute(
        select(
            SearchQuery.query,
            func.count(),
            func.min(SearchQuery.searched_at),
            func.max(SearchQuery.searched_at),
            func.max(SearchQuery.location),
        )
        .where(SearchQuery.searched_at >= start, SearchQuery.result_count == 0)
        .group_by(SearchQuery.query)
        .order_by(func.count().desc())
        .limit(25)
    ).all()

    # Funnel: the first stages are real per-window counts. Product/shop opens
    # are lifetime user rollups (no per-event table exists) and are labelled
    # as such; directions and saves are not collected at all -> null.
    product_opens = db.scalar(select(func.coalesce(func.sum(User.viewed_product_count), 0))) or 0
    shop_opens = db.scalar(select(func.coalesce(func.sum(User.viewed_shop_count), 0))) or 0

    return ok(
        {
            "period_days": window_days,
            "window_start": start.date().isoformat(),
            "window_end": end.date().isoformat(),
            "volume": {
                "total_searches": total,
                "unique_searchers": unique_searchers,
                "searches_by_day": [
                    {"date": str(d), "count": by_day.get(d, 0)} for d in sorted(by_day)
                ],
                "zero_by_day": [
                    {"date": str(d), "count": zero_by_day.get(d, 0)} for d in sorted(by_day)
                ],
                "searches_by_location": [{"location": loc, "count": n} for loc, n in by_location],
            },
            "funnel": {
                "search_started": total,
                "search_submitted": total,
                "results_returned": successful,
                "product_opened": product_opens,
                "shop_opened": shop_opens,
                "directions_clicked": None,
                "saved": None,
                "product_opened_scope": "lifetime",
                "shop_opened_scope": "lifetime",
            },
            "quality": _quality_metrics(total, successful, avg_results),
            "diagnostics": {
                "exact_matching": None,
                "fuzzy_matching": None,
                "relevance_scores": None,
                "note": "Matching diagnostics are not collected by this platform.",
            },
            "top_searches": top_searches,
            "zero_result_queries": [
                {"query": q, "count": n, "first_seen": _iso(fs), "last_seen": _iso(ls), "location": loc}
                for q, n, fs, ls, loc in zq
            ],
        }
    )


@router.get("/zero-results")
def search_zero_results(
    page: Pagination = Depends(pagination),
    days: int | None = Query(None, ge=0, le=MAX_WINDOW_DAYS),
    location: str | None = None,
    db: Session = Depends(get_db),
    _: AdminUser = Depends(get_current_admin),
):
    """The catalog-gap investigation list: every query that returned nothing.

    Grouped by query so one demand signal is one row, with the real first/last
    seen dates (the date range the operator is asked to show) and the most
    common shopper location. Gap evidence (potential category, catalog
    candidates) is computed server-side from real tables — never invented.
    """
    window_days, start, end = _window(days)

    zero = (
        select(
            SearchQuery.query,
            func.count().label("n"),
            func.min(SearchQuery.searched_at).label("first_seen"),
            func.max(SearchQuery.searched_at).label("last_seen"),
            func.max(SearchQuery.location).label("location"),
        )
        .where(SearchQuery.searched_at >= start, SearchQuery.result_count == 0)
        .group_by(SearchQuery.query)
        .subquery()
    )
    stmt = select(zero)
    if location:
        stmt = stmt.where(zero.c.location.ilike(f"%{location}%"))
    if page.search:
        stmt = stmt.where(zero.c.query.ilike(f"%{page.search}%"))

    total = db.scalar(select(func.count()).select_from(stmt.subquery())) or 0
    start_i, end_i = page.window()
    rows = db.execute(
        stmt.order_by(zero.c.n.desc(), zero.c.query).offset(start_i).limit(end_i - start_i)
    ).all()

    # One categories pass for the page, then per-row gap evidence.
    category_names = [
        n for (n,) in db.execute(select(Category.name).where(Category.is_active.isnot(False))).all()
    ]
    items = []
    for i, row in enumerate(rows):
        gap = _gap_analysis(db, row.query, category_names)
        items.append(
            {
                "id": start_i + i + 1,
                "query": row.query,
                "count": row.n,
                "first_seen": _iso(row.first_seen),
                "last_seen": _iso(row.last_seen),
                "location": row.location,
                **gap,
            }
        )
    return ok(
        paged(
            items,
            total,
            period_days=window_days,
            window_start=start.date().isoformat(),
            window_end=end.date().isoformat(),
        )
    )


@router.get("/quality")
def search_quality(
    page: Pagination = Depends(pagination),
    days: int | None = Query(None, ge=0, le=MAX_WINDOW_DAYS),
    db: Session = Depends(get_db),
    _: AdminUser = Depends(get_current_admin),
):
    """Per-term quality breakdown: volume, zero-result rate, average results.

    This is the Search Review surface — every metric here is computed from
    recorded searches. Matching/latency diagnostics are reported in the
    summary as not-collected rather than estimated here.
    """
    window_days, start, end = _window(days)

    term = (
        select(
            SearchQuery.query,
            func.count().label("n"),
            func.sum(case((SearchQuery.result_count == 0, 1), else_=0)).label("z"),
            func.avg(SearchQuery.result_count).label("a"),
            func.min(SearchQuery.searched_at).label("first_seen"),
            func.max(SearchQuery.searched_at).label("last_seen"),
        )
        .where(SearchQuery.searched_at >= start, SearchQuery.query.isnot(None))
        .group_by(SearchQuery.query)
        .subquery()
    )
    stmt = select(term)
    if page.search:
        stmt = stmt.where(term.c.query.ilike(f"%{page.search}%"))

    total = db.scalar(select(func.count()).select_from(stmt.subquery())) or 0
    start_i, end_i = page.window()
    rows = db.execute(
        stmt.order_by(term.c.n.desc(), term.c.query).offset(start_i).limit(end_i - start_i)
    ).all()

    items = [
        {
            "id": start_i + i + 1,
            "term": r.query,
            "searches": r.n,
            "zero_count": r.z,
            "zero_rate": round((r.z / r.n) * 100, 2) if r.n else None,
            "success_rate": round(((r.n - r.z) / r.n) * 100, 2) if r.n else None,
            "avg_result_count": round(float(r.a), 2) if r.a is not None else None,
            "first_seen": _iso(r.first_seen),
            "last_seen": _iso(r.last_seen),
        }
        for i, r in enumerate(rows)
    ]
    return ok(paged(items, total, period_days=window_days,
                    window_start=start.date().isoformat(),
                    window_end=end.date().isoformat()))

