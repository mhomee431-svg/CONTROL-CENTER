"""Relevance ranking — composite score for search results."""

from datetime import datetime
from enum import Enum
from math import log, exp

# ── Sort modes ─────────────────────────────────────────────────────────────
class SearchSort(str, Enum):
    RELEVANCE = "relevance"
    DISTANCE = "distance"
    PRICE_ASC = "price_asc"
    PRICE_DESC = "price_desc"
    RATING = "rating"
    AVAILABILITY = "availability"
    FRESHNESS = "freshness"
    OFFERS = "offers"


# ── Weight config ──────────────────────────────────────────────────────────
# Weights for the relevance composite score. Tunable at runtime.
RELEVANCE_WEIGHTS = {
    "text_match": 45.0,      # how well the product text matches the query
    "availability": 15.0,    # in-stock and available
    "distance": 15.0,        # closer is better
    "rating": 10.0,          # higher-rated shop is better
    "freshness": 10.0,       # recently-updated inventory is better
    "popularity": 5.0,       # popular products get a boost
}

MAX_DISTANCE_FOR_SCORE = 25.0  # km — beyond this, distance score bottoms out


def compute_relevance_score(
    *,
    text_match_score: float = 0.0,      # 0.0–1.0 from text matching
    is_available: bool = False,
    distance_km: float | None = None,
    shop_rating: float = 0.0,
    freshness_status: str | None = None,
    popularity_score: float = 0.0,
    is_in_stock: bool = False,
    weights: dict | None = None,
) -> float:
    """Compute a composite relevance score (0–100 scale)."""
    w = weights or RELEVANCE_WEIGHTS

    score = 0.0

    # Text match (0–weight)
    score += w["text_match"] * max(0.0, min(1.0, text_match_score))

    # Availability (full weight if in-stock, partial if available, 0 if not)
    if is_in_stock:
        score += w["availability"]
    elif is_available:
        score += w["availability"] * 0.4

    # Distance (closer → higher score)
    if distance_km is not None:
        # Score from 1.0 (distance=0) to 0.0 (distance >= capacity)
        dist_norm = max(0.0, 1.0 - distance_km / MAX_DISTANCE_FOR_SCORE)
        score += w["distance"] * dist_norm

    # Rating (4.5+ full, 4.0 → 70%, etc.)
    rating_norm = max(0.0, min(1.0, shop_rating / 5.0))
    score += w["rating"] * rating_norm

    # Freshness (RECENTLY_UPDATED → full, STALE → 20%, None → 40%)
    if freshness_status is None:
        score += w["freshness"] * 0.4
    elif freshness_status == "RECENTLY_UPDATED":
        score += w["freshness"] * 1.0
    elif freshness_status == "STALE":
        # Prevent stale inventory from misleading — penalize heavily
        score += w["freshness"] * 0.2
    else:
        score += w["freshness"] * 0.4

    # Popularity (0–1 normalized)
    pop_norm = max(0.0, min(1.0, popularity_score))
    score += w["popularity"] * pop_norm

    return round(score, 4)


def text_match_score(query_tokens: list[str], search_text: str) -> float:
    """
    Compute a text-match score between query tokens and a search text.

    Returns 0.0–1.0. Token matches count; exact phrase more.
    """
    if not query_tokens:
        return 1.0  # empty query → no discriminator

    norm_text = search_text
    if not norm_text:
        return 0.0

    # Count how many query tokens appear in the normalized text
    found = sum(1 for t in query_tokens if t in norm_text)
    ratio = found / len(query_tokens)

    # Boost for exact full-phrase match
    phrase = " ".join(query_tokens)
    if phrase in norm_text:
        ratio = max(ratio, 0.95)

    return ratio


def default_sort_key(mode: SearchSort | str):
    """Return a key-function factory for sorting search results by mode."""
    if isinstance(mode, str) and not isinstance(mode, SearchSort):
        try:
            mode = SearchSort(mode)
        except ValueError:
            mode = SearchSort.RELEVANCE

    def key(item: dict):
        if mode == SearchSort.DISTANCE:
            d = item.get("distance_km")
            return ("distance", d if d is not None else float("inf"))
        if mode == SearchSort.PRICE_ASC:
            p = item.get("price")
            return ("price", p if p is not None else float("inf"))
        if mode == SearchSort.PRICE_DESC:
            p = item.get("price")
            return ("price", -p if p is not None else float("inf"))
        if mode == SearchSort.RATING:
            r = item.get("shop_rating")
            return ("rating", -(r if r is not None else 0.0))
        if mode == SearchSort.AVAILABILITY:
            return ("avail", not bool(item.get("is_available", False)))
        if mode == SearchSort.FRESHNESS:
            # Ascending sort puts False first — map fresh→False, stale→True
            # so recently-updated inventory ranks before stale.
            return ("fresh", (item.get("freshness_status") or "") == "STALE")
        if mode == SearchSort.OFFERS:
            has_offer = bool(
                item.get("offer_text")
                or (
                    item.get("mrp") is not None
                    and item.get("price") is not None
                    and item["mrp"] > item["price"]
                )
            )
            rel = item.get("relevance_score")
            return ("offer", 0 if has_offer else 1, -(rel if rel is not None else 0.0))
        # RELEVANCE
        rel = item.get("relevance_score")
        return ("rel", -(rel if rel is not None else 0.0))
    return key