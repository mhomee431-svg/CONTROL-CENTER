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
        brand_id: Optional[int] = None,
        min_price: Optional[float] = None,
        max_price: Optional[float] = None,
        min_rating: Optional[float] = None,
        in_stock_only: bool = False,
        exclude_stale: bool = False,
        exclude_unavailable: bool = False,
        sort: str = "relevance",
        page: int = 1,
        limit: int = 20,
    ):
        self.q = q.strip()
        self.latitude = latitude
        self.longitude = longitude
        self.radius_km = radius_km
        self.category_id = category_id
        self.brand_id = brand_id
        self.min_price = min_price
        self.max_price = max_price
        self.min_rating = min_rating
        self.in_stock_only = in_stock_only
        self.exclude_stale = exclude_stale
        self.exclude_unavailable = exclude_unavailable
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

            trigram_expr = func.similarity(SearchIndex.search_text, norm_q) > trigram_threshold
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
    if params.brand_id is not None:
        query = query.filter(SearchIndex.brand_id == params.brand_id)

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
    distance_col = query.column_descriptions[-1]["expr"] if params.latitude is not None else None

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
    results = []
    for row in rows:
        entry = row
        if isinstance(row, tuple):
            entry, computed_distance = row
            distance = computed_distance / 1000.0 if computed_distance is not None else None
        else:
            distance = None

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

    # If relevance sort, sort in Python
    if sort_mode == SearchSort.RELEVANCE:
        key = default_sort_key(sort_mode)
        results.sort(key=key)

    # Resolve offer text for each result (cheap join)
    _attach_offer_texts(db, results)

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
    from app.models.shop import Shop

    point_wkt = f"POINT({longitude} {latitude})"

    query = db.query(Shop).filter(
        func.ST_DWithin(
            Shop.location,
            func.ST_GeogFromText(point_wkt),
            radius_km * 1000,
        ),
        Shop.is_deleted == False,  # noqa: E712
        Shop.status == "ACTIVE",
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
) -> list[dict]:
    """Look up all shops selling a product identified by barcode."""
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

    result = []
    for entry in query.all():
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
            "shop_id": entry.shop_id,
            "shop_name": entry.shop_name,
            "distance_km": distance,
            "shop_rating": entry.shop_rating,
        })

    result.sort(key=lambda r: r["distance_km"] if r["distance_km"] is not None else float("inf"))
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
        popular.last_searched_at = datetime.utcnow()
    else:
        db.add(PopularSearch(
            query=query,
            search_count=1,
            result_count=result_count,
            is_active=True,
        ))
    db.flush()
    return history


def record_search_event(db: Session, *, user_id: Optional[int], session_id: Optional[str],
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
    since = since or datetime.utcnow() - timedelta(days=30)

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
