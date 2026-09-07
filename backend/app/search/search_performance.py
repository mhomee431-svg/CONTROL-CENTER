"""Search performance optimization.

Provides:
- Query result caching
- Search analytics tracking
- Performance monitoring
- Query suggestions
"""
import hashlib
import logging
from datetime import datetime, timedelta, timezone
from typing import Any, Optional

from sqlalchemy import func
from sqlalchemy.orm import Session

from app.models.search import PopularSearch, SearchEvent
from app.core.cache import cache

logger = logging.getLogger("app.search.performance")


def get_cache_key(prefix: str, **params) -> str:
    """Generate a cache key from search parameters."""
    param_str = "&".join(f"{k}={v}" for k, v in sorted(params.items()) if v is not None)
    param_hash = hashlib.md5(param_str.encode()).hexdigest()[:12]
    return f"search:{prefix}:{param_hash}"


async def get_cached_results(cache_key: str) -> Optional[dict]:
    """Get cached search results."""
    try:
        return await cache.get("search", cache_key)
    except Exception:
        return None


async def set_cached_results(cache_key: str, results: dict, ttl: int = 300) -> bool:
    """Cache search results with TTL."""
    try:
        return await cache.set("search", results, ttl, cache_key)
    except Exception:
        return False


async def clear_search_cache() -> int:
    """Clear all cached search results."""
    try:
        return await cache.invalidate_domain("search")
    except Exception:
        return 0


def track_search_performance(
    db: Session,
    *,
    query: str,
    result_count: int,
    duration_ms: float,
    user_id: Optional[int] = None,
) -> None:
    """Track search performance metrics."""
    try:
        if duration_ms > 500:
            logger.warning("Slow search query: '%s' took %.2fms (%d results)", query, duration_ms, result_count)
        
        event = SearchEvent(
            user_id=user_id,
            query=query,
            event_type="SEARCH",
            result_count=result_count,
            is_successful=True,
        )
        db.add(event)
        
        if query and query.strip():
            popular = db.query(PopularSearch).filter(PopularSearch.query == query.strip()).first()
            if popular:
                popular.search_count += 1
                popular.result_count = result_count
                popular.last_searched_at = datetime.now(timezone.utc)
            else:
                db.add(PopularSearch(query=query.strip(), search_count=1, result_count=result_count, is_active=True))
        
        db.flush()
    except Exception as exc:
        logger.error("Failed to track search performance: %s", exc)


def get_popular_searches(db: Session, *, limit: int = 10, days: int = 7) -> list[dict]:
    """Get popular searches for suggestions."""
    since = datetime.now(timezone.utc) - timedelta(days=days)
    
    results = (
        db.query(PopularSearch)
        .filter(PopularSearch.is_active == True, PopularSearch.last_searched_at >= since)  # noqa: E712
        .order_by(PopularSearch.search_count.desc())
        .limit(limit)
        .all()
    )
    
    return [{"query": r.query, "count": r.search_count, "results": r.result_count} for r in results]


def get_search_suggestions(db: Session, *, query: str, limit: int = 5) -> list[str]:
    """Get search suggestions based on partial query."""
    if not query or len(query) < 2:
        return []
    
    pattern = f"{query.lower()}%"
    
    results = (
        db.query(PopularSearch.query)
        .filter(PopularSearch.is_active == True, func.lower(PopularSearch.query).like(pattern))  # noqa: E712
        .order_by(PopularSearch.search_count.desc())
        .limit(limit)
        .all()
    )
    
    return [r[0] for r in results]


def get_search_analytics(db: Session, *, days: int = 7) -> dict[str, Any]:
    """Get search analytics summary."""
    since = datetime.now(timezone.utc) - timedelta(days=days)
    
    total_searches = (
        db.query(func.count(SearchEvent.id))
        .filter(SearchEvent.event_type == "SEARCH", SearchEvent.event_time >= since)
        .scalar() or 0
    )
    
    successful_searches = (
        db.query(func.count(SearchEvent.id))
        .filter(SearchEvent.event_type == "SEARCH", SearchEvent.event_time >= since, SearchEvent.is_successful == True)  # noqa: E712
        .scalar() or 0
    )
    
    avg_results = (
        db.query(func.avg(SearchEvent.result_count))
        .filter(SearchEvent.event_type == "SEARCH", SearchEvent.event_time >= since)
        .scalar() or 0
    )
    
    zero_result_searches = (
        db.query(func.count(SearchEvent.id))
        .filter(SearchEvent.event_type == "SEARCH", SearchEvent.event_time >= since, SearchEvent.result_count == 0)
        .scalar() or 0
    )
    
    return {
        "period_days": days,
        "total_searches": total_searches,
        "successful_searches": successful_searches,
        "success_rate": round(successful_searches / total_searches, 4) if total_searches else 0,
        "average_results": round(float(avg_results), 2),
        "zero_result_searches": zero_result_searches,
        "zero_result_rate": round(zero_result_searches / total_searches, 4) if total_searches else 0,
    }