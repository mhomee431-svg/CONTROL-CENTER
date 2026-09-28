"""Search engine — orchestrates text + geo discovery against the search index."""

from datetime import datetime, timedelta, timezone
from typing import Optional

from sqlalchemy import func, or_
from sqlalchemy.orm import Session

from app.core.logging import get_logger
from app.models.search import (
    SearchIndex,
    SearchIndexEntityType,
    PopularSearch,
    SearchHistory,
    SearchEvent,
)
from app.search.normalizer import (
    normalize_text,
    tokenize,
    similarity_threshold,
    is_barcode_query,
)
from app.search.ranking import (
    SearchSort,
    compute_relevance_score,
    text_match_score,
    default_sort_key,
)
from app.services.inventory_service import get_offer_text_for_shop_product

logger = get_logger("app.search.engine")


# ── Query params dataclass ─────────────────────────────────────────────────
class SearchParams:
    """Holds all search parameters for a product discovery query."""
    def __init__(
        self,
        *,
        q: str = "",
        latitude: Optional[float] = None,
        longitude: Optional[float] = None,
        radius_km: float = 10.0,
        category_id: Optional[int] = None,
        category_name: Optional[str] = None,
        brand_id: Optional[int] = None,
        brand_name: Optional[str] = None,
        min_price: Optional[float] = None,
        max_price: Optional[float] = None,
        min_rating: Optional[float] = None,
        in_stock_only: bool = False,
        exclude_stale: bool = False,
        exclude_unavailable: bool = False,
        offers_only: bool = False,
        open_now: bool = False,
        sort: str = "relevance",
        page: int = 1,
        limit: int = 20,
    ):
        self.q = q.strip()
        self.latitude = latitude
        self.longitude = longitude
        self.radius_km = radius_km
        self.category_id = category_id
        self.category_name = category_name.strip() if category_name else None
        self.brand_id = brand_id
        self.brand_name = brand_name.strip() if brand_name else None
        self.min_price = min_price
        self.max_price = max_price
        self.min_rating = min_rating
        self.in_stock_only = in_stock_only
        self.exclude_stale = exclude_stale
        self.exclude_unavailable = exclude_unavailable
        self.offers_only = offers_only
        self.open_now = open_now
        self.sort = sort
        self.page = page
        self.limit = limit


# ── Search execution ───────────────────────────────────────────────────────
def search_products(db: Session, params: SearchParams) -> dict:
    """
    Execute a product discovery query against the search index.

    Supports:
    - Exact, partial, brand, category, barcode, variant search
    - Typo tolerance via pg_trgm similarity
    - Nearby via PostGIS ST_DWithin / ST_Distance
    - Filters: category, brand, price, rating, availability, freshness
    - Sort: relevance, distance, price, rating, availability, freshness
    - Pagination
    """
    import time as _time
    from app.core.observability.metrics import record_search_request

    _start = _time.perf_counter()
    outcome = "ok"
    result = _search_products_inner(db, params)

    try:
        elapsed = _time.perf_counter() - _start
        total = result.get("total", 0) if isinstance(result, dict) else 0
        if total == 0:
            outcome = "empty"
        # Classify by params: barcode-only query vs filtered/text search
        kind = "barcode" if (params.q and is_barcode_query(params.q)) else "products"
        if params.latitude is not None and params.longitude is not None:
            kind = "nearby"
        record_search_request(kind, elapsed, outcome)
    except Exception:  # noqa: BLE001 — telemetry must never break search
        pass

    return result


def _search_products_inner(db: Session, params: "SearchParams") -> dict:
    """Original search body (kept separate so telemetry wraps it cleanly)."""
    query = db.query(SearchIndex)

    # ── 1. Text matching (with typo tolerance) ────────────────────────────
    if params.q:
        norm_q = normalize_text(params.q)

        # Barcode exact lookup first
        if is_barcode_query(params.q):
            query = query.filter(SearchIndex.barcode == params.q)
        else:
            # Progressive OR matching: exact → LIKE → trigram similarity
            like_pattern = f"%{norm_q}%"
            trigram_threshold = similarity_threshold(len(norm_q))

            # pg_trgm similarity works against SHORT fields. Comparing a short
            # query to the whole denormalized search_text dilutes the score far
            # below the threshold (a 1-char typo on 'basamti' scored ~0.04), so
            # typo tolerance compares against the product/brand/category names.
            trigram_expr = or_(
                func.similarity(SearchIndex.product_name, norm_q) > trigram_threshold,
                func.similarity(SearchIndex.brand_name, norm_q) > trigram_threshold,
                func.similarity(SearchIndex.category_name, norm_q) > trigram_threshold,
            )
            query = query.filter(
                or_(
                    SearchIndex.product_name == params.q.strip(),
                    SearchIndex.search_text == norm_q,
                    SearchIndex.search_text.like(like_pattern),
                    SearchIndex.search_text.ilike(f"%{params.q}%"),
                    trigram_expr,
                    SearchIndex.barcode.like(f"%{norm_q}%"),
                )
            )

    # ── 2. Nearby filter (PostGIS) ────────────────────────────────────────
    if params.latitude is not None and params.longitude is not None:
        point_wkt = f"POINT({params.longitude} {params.latitude})"
        # ST_DWithin on geography (metres)
        query = query.filter(
            func.ST_DWithin(
                SearchIndex.location,
                func.ST_GeogFromText(point_wkt),
                params.radius_km * 1000,
            )
        )
        # Compute distance for each row
        query = query.add_columns(
            func.ST_Distance(
                SearchIndex.location,
                func.ST_GeogFromText(point_wkt),
            ).label("computed_distance_km")
        )
    else:
        query = query.add_columns(func.NULL().label("computed_distance_km"))

    # ── 3. Category / Brand filters ────────────────────────────────────────
    if params.category_id is not None:
        query = query.filter(SearchIndex.category_id == params.category_id)
    elif params.category_name:
        query = query.filter(SearchIndex.category_name.ilike(f"%{params.category_name}%"))

    if params.brand_id is not None:
        query = query.filter(SearchIndex.brand_id == params.brand_id)
    elif params.brand_name:
        query = query.filter(SearchIndex.brand_name.ilike(f"%{params.brand_name}%"))

    # ── 4. Price filter ─────────────────────────────────────────────────────
    if params.min_price is not None:
        query = query.filter(SearchIndex.price >= params.min_price)
    if params.max_price is not None:
        query = query.filter(SearchIndex.price <= params.max_price)

    # ── 5. Rating / availability / freshness ───────────────────────────────
    if params.min_rating is not None:
        query = query.filter(SearchIndex.shop_rating >= params.min_rating)
    if params.in_stock_only:
        query = query.filter(SearchIndex.is_available == True, SearchIndex.stock_status != "OUT_OF_STOCK")  # noqa: E712
    if params.exclude_unavailable:
        query = query.filter(SearchIndex.is_available == True)  # noqa: E712
    if params.exclude_stale:
        query = query.filter(SearchIndex.freshness_status != "STALE")

    # Only visible, searchable, accepting orders
    query = query.filter(
        SearchIndex.is_product_searchable == True,  # noqa: E712
        SearchIndex.is_shop_visible == True,  # noqa: E712
        SearchIndex.entity_type == SearchIndexEntityType.SHOP_PRODUCT,
    )

    # ── 6. Sort ────────────────────────────────────────────────────────────
    sort_mode = _resolve_sort(params.sort)
    distance_col = (
        query.column_descriptions[-1]["expr"]
        if (params.latitude is not None and hasattr(query, "column_descriptions") and query.column_descriptions)
        else None
    )

    if sort_mode == SearchSort.DISTANCE and distance_col is not None:
        query = query.order_by(distance_col.asc())
    elif sort_mode == SearchSort.PRICE_ASC:
        query = query.order_by(SearchIndex.price.asc())
    elif sort_mode == SearchSort.PRICE_DESC:
        query = query.order_by(SearchIndex.price.desc())
    elif sort_mode == SearchSort.RATING:
        query = query.order_by(SearchIndex.shop_rating.desc())
    elif sort_mode == SearchSort.AVAILABILITY:
        query = query.order_by(SearchIndex.is_available.desc(), SearchIndex.shop_rating.desc())
    elif sort_mode == SearchSort.FRESHNESS:
        query = query.order_by(SearchIndex.freshness_status.asc(), SearchIndex.last_inventory_update.desc())
    else:
        # RELEVANCE — apply in Python after scoring
        pass

    # ── 7. Pagination ──────────────────────────────────────────────────────
    total = query.count()
    rows = query.offset((params.page - 1) * params.limit).limit(params.limit).all()

    # ── 8. Build results (Python-side relevance scoring) ─────────────────
    from sqlalchemy.engine import Row

    results = []
    for row in rows:
        if isinstance(row, tuple):
            # Python tuple rows (unit-test mocks)
            entry, computed_distance = row
        elif isinstance(row, Row):
            # SQLAlchemy 2.0 Row — add_columns always yields (entity, distance)
            entry = row[0]
            computed_distance = row[1]
        else:
            # Plain ORM entity (no add_columns in the query)
            entry = row
            computed_distance = None
        distance = computed_distance / 1000.0 if computed_distance is not None else None

        # Build result dict
        text_score = text_match_score(tokenize(params.q), entry.search_text or "")
        relevance = compute_relevance_score(
            text_match_score=text_score,
            is_available=entry.is_available,
            is_in_stock=(entry.is_available and entry.stock_status != "OUT_OF_STOCK"),
            distance_km=distance,
            shop_rating=entry.shop_rating,
            freshness_status=entry.freshness_status,
            popularity_score=entry.popularity_score or 0.0,
        )

        results.append({
            "id": f"res_{entry.shop_product_id}",
            "product_id": entry.product_id,
            "product_name": entry.product_name,
            "brand_name": entry.brand_name,
            "category_name": entry.category_name,
            "variant_name": entry.variant_name,
            "product_image_url": None,  # resolved lazily if needed
            "shop_id": entry.shop_id,
            "shop_name": entry.shop_name,
            "shop_rating": entry.shop_rating,
            "shop_review_count": entry.shop_review_count,
            "price": float(entry.price) if entry.price is not None else None,
            "mrp": float(entry.mrp) if entry.mrp is not None else None,
            "is_available": entry.is_available,
            "stock_status": entry.stock_status,
            "freshness_status": entry.freshness_status,
            "last_inventory_update": entry.last_inventory_update,
            "distance_km": round(distance, 2) if distance is not None else None,
            "relevance_score": relevance,
            "offer_text": None,
        })

    # Resolve offer text for each result (cheap join)
    _attach_offer_texts(db, results)
    # Attach open/closed + order-acceptance state so the result card can show it.
    _attach_shop_open_state(db, results)

    # Dynamic filters (after enrichment)
    if params.offers_only:
        results = [
            r for r in results
            if bool(r.get("offer_text") or (r.get("mrp") and r.get("price") and r["mrp"] > r["price"]))
        ]
    if params.open_now:
        results = [r for r in results if r.get("is_open_now") is True]

    # If relevance or offers sort, sort in Python
    if sort_mode in (SearchSort.RELEVANCE, SearchSort.OFFERS):
        key = default_sort_key(sort_mode)
        results.sort(key=key)

    if params.offers_only or params.open_now:
        total = min(total, len(results))

    has_more = (params.page * params.limit) < total

    return {
        "results": results,
        "page": params.page,
        "limit": params.limit,
        "has_more": has_more,
        "total": total,
        "sort": params.sort,
    }


def _resolve_sort(sort: str) -> SearchSort:
    """Map API sort string to enum."""
    mapping = {
        "relevance": SearchSort.RELEVANCE,
        "distance": SearchSort.DISTANCE,
        "nearest": SearchSort.DISTANCE,
        "lowest_price": SearchSort.PRICE_ASC,
        "price_asc": SearchSort.PRICE_ASC,
        "highest_price": SearchSort.PRICE_DESC,
        "price_desc": SearchSort.PRICE_DESC,
        "highest_rated": SearchSort.RATING,
        "rating": SearchSort.RATING,
        "availability": SearchSort.AVAILABILITY,
        "freshness": SearchSort.FRESHNESS,
        "recently_updated": SearchSort.FRESHNESS,
        "offers": SearchSort.OFFERS,
    }
    return mapping.get(sort, SearchSort.RELEVANCE)


def _attach_offer_texts(db: Session, results: list[dict]) -> None:
    """Populate offer_text for each result (one extra query per unique shop-product)."""
    for r in results:
        try:
            sp_id = int(r["id"].split("_")[1])
            r["offer_text"] = get_offer_text_for_shop_product(db, sp_id)
        except (ValueError, IndexError):
            pass
        except Exception:  # noqa: BLE001 — offer lookup is enrichment; never fail the result
            r["offer_text"] = None


def _attach_shop_open_state(db: Session, results: list[dict]) -> None:
    """Populate ``is_open_now`` / ``is_accepting_orders`` for each result.

    One batched query for all shops on the page (rather than a join in the main
    search query, which would change its shape and row semantics). Both keys
    default to ``None`` so the client can distinguish "closed" from "unknown".

    Opening hours are evaluated with the canonical
    :func:`app.services.shop_service.is_shop_open` helper, so search results
    never disagree with the shop page about whether a shop is open.
    """
    from app.models.shop import Shop
    from app.services.shop_service import is_shop_open

    # Default to "unknown" before attempting enrichment.
    for r in results:
        r.setdefault("is_open_now", None)
        r.setdefault("is_accepting_orders", None)

    shop_ids = {
        r.get("shop_id")
        for r in results
        if isinstance(r.get("shop_id"), int)
    }
    if not shop_ids:
        return

    try:
        shops = db.query(Shop).filter(Shop.id.in_(shop_ids)).all()
        now = datetime.now(timezone.utc)
        by_id = {s.id: s for s in shops if hasattr(s, "id")}
        for r in results:
            shop = by_id.get(r.get("shop_id"))
            if shop is None:
                continue
            try:
                r["is_open_now"] = bool(is_shop_open(shop, now))
                r["is_accepting_orders"] = bool(getattr(shop, "is_accepting_orders", False))
            except Exception:  # noqa: BLE001
                logger.warning(
                    "shop open-state computation failed for shop=%s",
                    getattr(shop, "id", None),
                    exc_info=True,
                )
    except Exception:  # noqa: BLE001 — enrichment must never fail search
        logger.warning("shop open-state enrichment failed", exc_info=True)
        return


# ── Nearby shops ───────────────────────────────────────────────────────────
def nearby_shops(
    db: Session,
    *,
    latitude: float,
    longitude: float,
    radius_km: float = 10.0,
    category: Optional[str] = None,
    min_rating: Optional[float] = None,
    page: int = 1,
    limit: int = 20,
) -> dict:
    """Find nearby shops using PostGIS ST_DWithin."""
    from app.models.shop import Shop, ShopStatus

    point_wkt = f"POINT({longitude} {latitude})"

    query = db.query(Shop).filter(
        func.ST_DWithin(
            Shop.location,
            func.ST_GeogFromText(point_wkt),
            radius_km * 1000,
        ),
        Shop.is_deleted == False,  # noqa: E712
        Shop.status.in_([ShopStatus.ACTIVE, ShopStatus.VERIFIED]),
        Shop.is_verified == True,  # noqa: E712
        Shop.is_accepting_orders == True,  # noqa: E712
    )
    if category:
        query = query.filter(Shop.category == category)
    if min_rating is not None:
        query = query.filter(Shop.rating >= min_rating)

    # Attach distance
    query = query.add_columns(
        func.ST_Distance(Shop.location, func.ST_GeogFromText(point_wkt)).label("distance_m")
    )
    query = query.order_by(func.ST_Distance(Shop.location, func.ST_GeogFromText(point_wkt)))

    total = query.count()
    rows = query.offset((page - 1) * limit).limit(limit).all()

    shops = []
    for shop, distance_m in rows:
        shops.append({
            "shop_id": shop.id,
            "shop_name": shop.name,
            "category": shop.category.value if shop.category else None,
            "rating": shop.rating,
            "review_count": shop.review_count,
            "is_accepting_orders": shop.is_accepting_orders,
            "distance_km": round(distance_m / 1000.0, 2),
            "latitude": shop.latitude,
            "longitude": shop.longitude,
            "image_url": shop.image_url,
        })

    return {
        "shops": shops,
        "page": page,
        "limit": limit,
        "has_more": (page * limit) < total,
        "total": total,
    }


# ── Suggestions ────────────────────────────────────────────────────────────
def search_suggestions(db: Session, q: str, limit: int = 10) -> list[dict]:
    """Return typeahead suggestions from the index (product names, brands, categories)."""
    q_norm = normalize_text(q)
    if not q_norm:
        return []

    like_pattern = f"%{q_norm}%"
    trigram_threshold = similarity_threshold(len(q_norm))

    query = (
        db.query(SearchIndex)
        .filter(
            SearchIndex.entity_type == SearchIndexEntityType.SHOP_PRODUCT,
            SearchIndex.is_product_searchable == True,  # noqa: E712
            or_(
                SearchIndex.product_name.ilike(f"%{q}%"),
                func.similarity(SearchIndex.search_text, q_norm) > trigram_threshold,
            )
        )
        .order_by(SearchIndex.popularity_score.desc(), func.similarity(SearchIndex.search_text, q_norm).desc())
        .limit(limit)
        .all()
    )

    suggestions = []
    seen = set()
    for entry in query:
        text = entry.product_name
        if text in seen:
            continue
        seen.add(text)
        suggestions.append({
            "text": text,
            "type": "product",
            "is_category": False,
            "is_brand": entry.brand_name is not None and text == entry.brand_name,
        })

    # Add brand suggestions
    brand_results = (
        db.query(SearchIndex.brand_name)
        .filter(SearchIndex.entity_type == SearchIndexEntityType.SHOP_PRODUCT,
                SearchIndex.brand_name != None, SearchIndex.brand_name.ilike(like_pattern))  # noqa: E711
        .distinct()
        .limit(5)
        .all()
    )
    for (brand_name,) in brand_results:
        if brand_name and brand_name not in seen:
            suggestions.append({
                "text": brand_name,
                "type": "brand",
                "is_category": False,
                "is_brand": True,
            })

    # Add category suggestions
    cat_results = (
        db.query(SearchIndex.category_name)
        .filter(SearchIndex.category_name != None, SearchIndex.category_name.ilike(like_pattern))  # noqa: E711
        .distinct()
        .limit(5)
        .all()
    )
    for (cat_name,) in cat_results:
        if cat_name and cat_name not in seen:
            suggestions.append({
                "text": cat_name,
                "type": "category",
                "is_category": True,
                "is_brand": False,
            })

    return suggestions[:limit]


# ── Barcode lookup ─────────────────────────────────────────────────────────
def barcode_lookup(
    db: Session,
    barcode: str,
    *,
    latitude: Optional[float] = None,
    longitude: Optional[float] = None,
    radius_km: float = 10.0,
    page: int = 1,
    limit: int = 20,
) -> list[dict]:
    """Look up the shops selling a product identified by barcode.

    One GS1 code can be stocked by an arbitrary number of shops, so the hits
    are paged like every other search list rather than materialised whole.
    The order is fixed in SQL *before* the slice — distance when coordinates
    exist, otherwise shop_product_id — because a page sorted afterwards in
    Python is only nearest-first within that page, and page 2 would then
    repeat or skip shops depending on what the database happened to return.
    """
    query = (
        db.query(SearchIndex)
        .filter(
            SearchIndex.barcode == barcode.strip(),
            SearchIndex.entity_type == SearchIndexEntityType.SHOP_PRODUCT,
            SearchIndex.is_product_searchable == True,  # noqa: E712
        )
    )
    if latitude is not None and longitude is not None:
        point_wkt = f"POINT({longitude} {latitude})"
        query = query.filter(
            func.ST_DWithin(SearchIndex.location, func.ST_GeogFromText(point_wkt), radius_km * 1000)
        )
        # id tiebreak keeps the slice stable when two shops tie on distance.
        query = query.order_by(
            func.ST_Distance(SearchIndex.location, func.ST_GeogFromText(point_wkt)),
            SearchIndex.shop_product_id,
        )
    else:
        query = query.order_by(SearchIndex.shop_product_id)

    rows = query.offset((page - 1) * limit).limit(limit).all()

    result = []
    for entry in rows:
        distance = None
        if latitude is not None and longitude is not None:
            # small haversine
            from app.services.geo_service import haversine_km
            if entry.latitude is not None and entry.longitude is not None:
                distance = round(haversine_km(latitude, longitude, entry.latitude, entry.longitude), 2)

        result.append({
            "shop_product_id": entry.shop_product_id,
            "product_id": entry.product_id,
            "product_name": entry.product_name,
            "brand_name": entry.brand_name,
            "category_name": entry.category_name,
            "price": float(entry.price) if entry.price is not None else None,
            "mrp": float(entry.mrp) if entry.mrp is not None else None,
            "is_available": entry.is_available,
            "stock_status": entry.stock_status,
            "freshness_status": entry.freshness_status,
            # A scanned product must show the same factual freshness signal as a
            # typed one, so the timestamp travels with the hit. getattr keeps
            # partial/lightweight rows working (the value is simply unknown).
            "last_inventory_update": getattr(entry, "last_inventory_update", None),
            "shop_id": entry.shop_id,
            "shop_name": entry.shop_name,
            "distance_km": distance,
            "shop_rating": entry.shop_rating,
        })

    # No Python re-sort: the page was already ordered by distance in SQL, and
    # re-sorting here would only reorder rows inside one page.
    # Same open/closed enrichment as text search, so a scanned product and a
    # typed one never disagree about shop state.
    _attach_shop_open_state(db, result)
    return result


# ── Popular searches ───────────────────────────────────────────────────────
def popular_searches(db: Session, limit: int = 10) -> list[dict]:
    """Return the most popular search queries."""
    rows = (
        db.query(PopularSearch)
        .filter(PopularSearch.is_active == True)  # noqa: E712
        .order_by(PopularSearch.search_count.desc())
        .limit(limit)
        .all()
    )
    return [
        {
            "query": p.query,
            "search_count": p.search_count,
            "result_count": p.result_count,
            "last_searched_at": p.last_searched_at,
        }
        for p in rows
    ]


# ── Search history ─────────────────────────────────────────────────────────
def search_history(db: Session, user_id: int, limit: int = 10) -> list[dict]:
    """Return recent search history for a user."""
    rows = (
        db.query(SearchHistory)
        .filter(SearchHistory.user_id == user_id)
        .order_by(SearchHistory.searched_at.desc())
        .limit(limit)
        .all()
    )
    return [
        {
            "id": h.id,
            "query": h.query,
            "result_count": h.result_count,
            "is_successful": h.is_successful,
            "searched_at": h.searched_at,
        }
        for h in rows
    ]


def record_search(db: Session, *, user_id: Optional[int], query: str, result_count: int,
                  is_successful: bool, session_id: Optional[str] = None) -> Optional[SearchHistory]:
    """Record a search event + optionally update popular search."""
    if not query or not query.strip():
        return None

    # Update search history
    history = SearchHistory(
        user_id=user_id if user_id is not None else 0,
        query=query,
        result_count=result_count,
        is_successful=is_successful,
    )
    db.add(history)

    # Update popular search counter
    popular = db.query(PopularSearch).filter(PopularSearch.query == query).first()
    if popular:
        popular.search_count += 1
        popular.result_count = result_count
        popular.last_searched_at = datetime.now(timezone.utc)
    else:
        db.add(PopularSearch(
            query=query,
            search_count=1,
            result_count=result_count,
            is_active=True,
        ))
    db.flush()
    return history


def record_search_event(db: Session, *, user_id: Optional[int], session_id: Optional[str] = None,
                        query: str, event_type: str, result_count: Optional[int] = None,
                        clicked_product_id: Optional[int] = None,
                        clicked_shop_id: Optional[int] = None,
                        clicked_shop_product_id: Optional[int] = None,
                        device_type: Optional[str] = None,
                        app_version: Optional[str] = None) -> SearchEvent:
    """Write an analytics search event."""
    event = SearchEvent(
        user_id=user_id,
        session_id=session_id,
        query=query,
        event_type=event_type,
        result_count=result_count,
        clicked_product_id=clicked_product_id,
        clicked_shop_id=clicked_shop_id,
        clicked_shop_product_id=clicked_shop_product_id,
        device_type=device_type,
        app_version=app_version,
    )
    db.add(event)
    db.flush()
    return event


# ── Aggregate popular searches (background task support) ───────────────────
def aggregate_popular_searches(db: Session, since: Optional[datetime] = None) -> int:
    """Rebuild popular_searches from search_events (aggregation foundation)."""
    since = since or datetime.now(timezone.utc) - timedelta(days=30)

    rows = (
        db.query(
            func.count(SearchEvent.id).label("cnt"),
            SearchEvent.query,
        )
        .filter(
            SearchEvent.event_type == "SEARCH",
            SearchEvent.event_time >= since,
        )
        .group_by(SearchEvent.query)
        .order_by(func.count(SearchEvent.id).desc())
        .all()
    )
    updated = 0
    for count, query in rows:
        pop = db.query(PopularSearch).filter(PopularSearch.query == query).first()
        if pop:
            pop.search_count = count
            pop.last_searched_at = since
            updated += 1
        else:
            db.add(PopularSearch(
                query=query,
                search_count=count,
                is_active=True,
            ))
            updated += 1
    db.flush()
    return updated
