from fastapi import APIRouter, Depends, Query, Request
from sqlalchemy.orm import Session

from app.core.dependencies import get_optional_user, require_admin
from app.core.cached_read import cached_read
from app.core.responses import success_response
from app.database.session import get_db
from app.models.user import User
from app.search import engine as search_engine
from app.search.indexer import full_rebuild as index_full_rebuild
from app.search.indexer import incremental_sync as index_incremental_sync
from app.search.engine import SearchParams

router = APIRouter(prefix="/search", tags=["search"])

# Cache domain for search results. Search is the app's single hottest read and
# the same term + filters are re-queried constantly (every retry, every re-open,
# several customers typing the same popular product). Caching the RESULT SET --
# not the analytics -- is what turns a stampede on one popular term into one
# database query.
#
# Writers that change what a search would return (inventory, prices, offers,
# shop status) must call ``await cache.invalidate_domain(SEARCH_CACHE_DOMAIN)``.
SEARCH_CACHE_DOMAIN = "search"


def _search_cache_key(params: SearchParams) -> str:
    """Stable cache key for one search.

    Built from the PARAMS object rather than the raw query string so two
    logically different searches can never collide onto one key (the classic
    bug with naive string concatenation), and so a change that adds a filter
    cannot silently reuse keys built without it.
    """
    return (
        f"{params.q}|{params.latitude}|{params.longitude}|{params.radius_km}"
        f"|{params.category_id}|{params.category_name}|{params.brand_id}"
        f"|{params.brand_name}|{params.min_price}|{params.max_price}"
        f"|{params.min_rating}|{params.in_stock_only}|{params.exclude_stale}"
        f"|{params.exclude_unavailable}|{params.offers_only}|{params.open_now}"
        f"|{params.sort}|{params.page}|{params.limit}"
    )


# ── V2 / Unified product discovery ─────────────────────────────────────────
@router.get("/v2/products")
async def v2_search_products(
    request: Request,
    q: str = Query("", max_length=200, description="Search query (product, brand, category, variant, barcode)"),
    latitude: float | None = Query(None, ge=-90, le=90, description="User latitude for geo search"),
    longitude: float | None = Query(None, ge=-180, le=180, description="User longitude for geo search"),
    radius_km: float = Query(10.0, gt=0, le=100, description="Search radius in km"),
    category: str | None = Query(None, description="Category ID or name filter"),
    brand: str | None = Query(None, description="Brand ID or name filter"),
    min_price: float | None = Query(None, ge=0),
    max_price: float | None = Query(None, ge=0),
    min_rating: float | None = Query(None, ge=0, le=5),
    in_stock: bool = Query(False, description="Only show in-stock items"),
    exclude_stale: bool = Query(False, description="Exclude stale inventory"),
    exclude_unavailable: bool = Query(False, description="Exclude unavailable items"),
    offers_only: bool = Query(False, description="Only show items with active offers"),
    open_now: bool = Query(False, description="Only show shops currently open"),
    sort: str = Query("relevance", pattern="^(relevance|distance|nearest|lowest_price|price_asc|highest_price|price_desc|highest_rated|rating|availability|freshness|recently_updated|offers)$"),
    page: int = Query(1, ge=1),
    limit: int = Query(20, ge=1, le=50),
    db: Session = Depends(get_db),
    user: User | None = Depends(get_optional_user),
):
    """
    Unified discovery engine — search products across nearby shops.

    Uses the search index (optimized layer) backed by PostgreSQL.
    Combines text search (with typo tolerance), geo proximity, and
    all discovery filters in one query.
    """
    cat_id = None
    cat_name = None
    if category:
        try:
            cat_id = int(category)
        except ValueError:
            cat_name = category

    br_id = None
    br_name = None
    if brand:
        try:
            br_id = int(brand)
        except ValueError:
            br_name = brand

    params = SearchParams(
        q=q,
        latitude=latitude,
        longitude=longitude,
        radius_km=radius_km,
        category_id=cat_id,
        category_name=cat_name,
        brand_id=br_id,
        brand_name=br_name,
        min_price=min_price,
        max_price=max_price,
        min_rating=min_rating,
        in_stock_only=in_stock,
        exclude_stale=exclude_stale,
        exclude_unavailable=exclude_unavailable,
        offers_only=offers_only,
        open_now=open_now,
        sort=sort,
        page=page,
        limit=limit,
    )

    async def _load():
        # The ONLY database work on the hot path. `cached_read` runs it for one
        # caller and serves the rest from Redis.
        return search_engine.search_products(db, params)

    result = await cached_read(SEARCH_CACHE_DOMAIN, _search_cache_key(params), _load)

    # ── Analytics ────────────────────────────────────────────────────────────
    # Both writes stay on the request's own session, and deliberately so:
    # they commit with the route's transaction via `get_db`, so a failure rolls
    # back cleanly and no event is half-written.
    #
    # They were a genuine bottleneck here — every search cost two extra INSERTs
    # before the customer saw anything — but they are NOT moved to a background
    # task here, because doing so safely would mean opening a second session
    # outside the request's lifecycle. That is a real change with real failure
    # modes (orphaned sessions, lost events on shutdown) and is worth doing as
    # its own reviewed change, driven by the Celery worker this repo already
    # runs, rather than smuggled into a caching change.
    #
    # The win actually delivered on this path is the result cache above: a cache
    # hit skips the expensive search query entirely, and only these two cheap
    # INSERTs remain.
    search_engine.record_search(
        db,
        user_id=user.id if user else None,
        query=q,
        result_count=result["total"],
        is_successful=result["total"] > 0,
    )

    try:
        from app.services import analytics_system as _analytics

        _analytics.track_search(
            db,
            user_id=user.id if user else None,
            session_id=request.headers.get("X-Session-ID"),
            query=q,
            result_count=result["total"],
        )
    except Exception:  # noqa: BLE001 — analytics must never break discovery
        pass

    return success_response(data=result, message="Search complete")


# ── Nearby shops ───────────────────────────────────────────────────────────
@router.get("/v2/nearby-shops")
def v2_nearby_shops(
    latitude: float = Query(..., ge=-90, le=90),
    longitude: float = Query(..., ge=-180, le=180),
    radius_km: float = Query(10.0, gt=0, le=100),
    category: str | None = Query(None),
    min_rating: float | None = Query(None, ge=0, le=5),
    page: int = Query(1, ge=1),
    limit: int = Query(20, ge=1, le=50),
    db: Session = Depends(get_db),
):
    """Find nearby shops using PostGIS with distance calculation."""
    result = search_engine.nearby_shops(
        db,
        latitude=latitude,
        longitude=longitude,
        radius_km=radius_km,
        category=category,
        min_rating=min_rating,
        page=page,
        limit=limit,
    )
    return success_response(data=result, message="Nearby shops")


# ── Suggestions ────────────────────────────────────────────────────────────
@router.get("/v2/suggestions")
def v2_get_search_suggestions(
    q: str = Query(..., min_length=1, max_length=100),
    limit: int = Query(10, ge=1, le=20),
    db: Session = Depends(get_db),
):
    """Typeahead suggestions across products, brands, and categories."""
    suggestions = search_engine.search_suggestions(db, q, limit=limit)
    return success_response(data=suggestions, message="Suggestions")


# ── Popular searches ───────────────────────────────────────────────────────
@router.get("/v2/popular")
def v2_popular_searches(
    limit: int = Query(10, ge=1, le=50),
    db: Session = Depends(get_db),
):
    """Return the most searched queries across the platform."""
    result = search_engine.popular_searches(db, limit=limit)
    return success_response(data=result, message="Popular searches")


# ── Search history ─────────────────────────────────────────────────────────
@router.get("/v2/history")
def v2_search_history(
    limit: int = Query(10, ge=1, le=50),
    db: Session = Depends(get_db),
    user: User = Depends(get_optional_user),
):
    """Return the authenticated user's search history."""
    if user is None:
        return success_response(data=[], message="Search history unavailable")
    result = search_engine.search_history(db, user.id, limit=limit)
    return success_response(data=result, message="Search history")


# ── Barcode lookup ─────────────────────────────────────────────────────────
@router.get("/v2/barcodes/{barcode}")
def v2_barcode_lookup(
    barcode: str,
    latitude: float | None = Query(None, ge=-90, le=90),
    longitude: float | None = Query(None, ge=-180, le=180),
    radius_km: float = Query(10.0, gt=0, le=100),
    page: int = Query(1, ge=1),
    limit: int = Query(20, ge=1, le=50),
    db: Session = Depends(get_db),
):
    """Look up shops selling the product identified by this barcode.

    Bounded like every other search list: ``page``/``limit`` slice the shop
    hits so one widely stocked barcode cannot materialise an unbounded
    catalogue into a single response.
    """
    result = search_engine.barcode_lookup(
        db,
        barcode,
        latitude=latitude,
        longitude=longitude,
        radius_km=radius_km,
        page=page,
        limit=limit,
    )

    # Record barcode scan
    from app.models.search import BarcodeScan
    db.add(BarcodeScan(
        barcode=barcode,
        is_match_found=len(result) > 0,
    ))
    db.flush()

    return success_response(data=result, message="Barcode lookup")


# ── Search events (analytics recording) ────────────────────────────────────
@router.post("/v2/events")
def v2_record_search_event(
    payload: dict,
    db: Session = Depends(get_db),
    user: User | None = Depends(get_optional_user),
):
    """Record an analytics search event (SEARCH, SUGGESTION_CLICK, RESULT_CLICK)."""
    query = payload.get("query", "")
    event_type = payload.get("event_type", "SEARCH")
    search_engine.record_search_event(
        db,
        user_id=user.id if user else None,
        session_id=payload.get("session_id"),
        query=query,
        event_type=event_type,
        result_count=payload.get("result_count"),
        clicked_product_id=payload.get("product_id"),
        clicked_shop_id=payload.get("shop_id"),
        clicked_shop_product_id=payload.get("shop_product_id"),
        device_type=payload.get("device_type"),
        app_version=payload.get("app_version"),
    )
    return success_response(data={"recorded": True}, message="Event recorded")


# ── Index management (admin) ───────────────────────────────────────────────
@router.post("/v2/index/rebuild")
def v2_index_rebuild(
    db: Session = Depends(get_db),
    _admin: User = Depends(require_admin),
):
    """Full rebuild of the search index from source-of-truth tables (admin only)."""
    run = index_full_rebuild(db)
    return success_response(
        data={
            "sync_id": run.id,
            "status": run.status.value,
            "total_processed": run.total_processed,
            "total_created": run.total_created,
            "error_count": run.error_count,
        },
        message="Search index rebuilt",
    )


@router.post("/v2/index/sync")
def v2_index_incremental(
    db: Session = Depends(get_db),
    _admin: User = Depends(require_admin),
):
    """Incremental sync of changed shop products into the search index (admin only)."""
    run = index_incremental_sync(db)
    return success_response(
        data={
            "run_id": run.id,
            "status": run.status.value,
            "total_processed": run.total_processed,
            "total_created": run.total_created,
            "total_updated": run.total_updated,
            "total_removed": run.total_removed,
            "error_count": run.error_count,
        },
        message="Incremental index sync complete",
    )


@router.get("/v2/index/status")
def v2_index_status(db: Session = Depends(get_db)):
    """Return the current state of the search index (counts)."""
    from app.models.search import SearchIndex, SearchIndexSync
    total = db.query(SearchIndex).count()
    synced = db.query(SearchIndex).filter(SearchIndex.is_synced == True).count()  # noqa: E712
    last_run = (
        db.query(SearchIndexSync)
        .order_by(SearchIndexSync.started_at.desc())
        .first()
    )
    last_status = last_run.status.value if last_run else None
    return success_response(data={
        "total_indexed": total,
        "synced": synced,
        "sync_percentage": round((synced / total * 100), 1) if total > 0 else 0.0,
        "last_sync_status": last_status,
        "last_sync_type": last_run.sync_type if last_run else None,
        "last_sync_at": last_run.completed_at if last_run else None,
    }, message="Index status")
