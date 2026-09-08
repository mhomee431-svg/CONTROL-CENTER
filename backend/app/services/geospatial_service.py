"""
High-Precision Geospatial Engine - PostGIS + Redis + Google Maps APIs.

Provides:
- PostGIS-powered radius queries (ST_DWithin) for shop discovery
- Redis-cached reverse geocoding with TTL expiration
- Distance Matrix / Directions API integration for route ETA
- High-precision coordinate handling (7 decimal places)

All coordinates use SRID 4326 (WGS 84) for PostGIS GEOGRAPHY type.
"""
from __future__ import annotations

import math
from typing import Optional, Tuple

from sqlalchemy import text

from app.core.cache import cache
from app.core.logging import get_logger
from app.services.location_service import (
    address_autocomplete,
    get_directions,
    get_distance_matrix,
    get_place_coordinates,
    reverse_geocode,
)

logger = get_logger("app.services.geospatial")

# Cache TTLs (seconds)
CACHE_TTL_GEOCODE = 86400 * 30       # 30 days - addresses rarely change
CACHE_TTL_NEARBY_SHOPS = 300          # 5 min - shop availability changes
CACHE_TTL_ROUTE_ETA = 120             # 2 min - traffic dependent

# Earth radius for haversine fallback
_EARTH_RADIUS_M = 6_371_000


# ── Reverse Geocoding with Redis Cache ────────────────────────────────────────

async def reverse_geocode_cached(
    latitude: float,
    longitude: float,
) -> Optional[dict]:
    """Reverse geocode with Redis cache layer.

    Rounds coordinates to 7 decimal places (~11mm precision) for cache key.
    Falls back to Google Maps Geocoding API on cache miss.
    """
    lat_r = round(float(latitude), 7)
    lng_r = round(float(longitude), 7)
    cache_key = f"geocode:{lat_r}:{lng_r}"

    cached = await cache.get_json("geospatial", cache_key)
    if cached:
        return cached

    result = await reverse_geocode(lat_r, lng_r)
    if result is None:
        return None

    payload = {
        "formatted_address": result.formatted_address,
        "street_number": result.street_number,
        "route": result.route,
        "locality": result.locality,
        "district": result.district,
        "state": result.state,
        "pincode": result.pincode,
        "country": result.country,
        "latitude": result.latitude,
        "longitude": result.longitude,
        "place_id": result.place_id,
    }

    await cache.set_json("geospatial", cache_key, payload, ttl=CACHE_TTL_GEOCODE)
    return payload

# ── PostGIS Radius Query (ST_DWithin) ─────────────────────────────────────────

async def find_nearby_shops_postgis(
    db_session,
    latitude: float,
    longitude: float,
    radius_meters: float = 5000,
    limit: int = 50,
) -> list[dict]:
    """Find active shops within a radius using PostGIS ST_DWithin.

    Uses the GEOGRAPHY(POINT, 4326) column with a spatial index for
    high-performance radius queries. Distance returned in meters.
    """
    cache_key = (
        f"nearby:{round(latitude,5)}:{round(longitude,5)}:"
        f"{radius_meters}:{limit}"
    )

    cached = await cache.get_json("geospatial", cache_key)
    if cached:
        return cached

    query = text("""
        SELECT
            s.id,
            s.name,
            s.slug,
            s.rating,
            s.review_count,
            s.is_accepting_orders,
            s.is_verified,
            s.latitude,
            s.longitude,
            ST_Y(s.location::geometry) AS loc_lat,
            ST_X(s.location::geometry) AS loc_lng,
            ST_Distance(
                s.location,
                ST_SetSRID(ST_MakePoint(:lng, :lat), 4326)::geography
            ) AS distance_meters
        FROM shops s
        WHERE s.is_deleted = FALSE
          AND s.status IN ('ACTIVE', 'VERIFIED')
          AND s.is_verified = TRUE
          AND s.is_accepting_orders = TRUE
          AND s.location IS NOT NULL
          AND ST_DWithin(
                s.location,
                ST_SetSRID(ST_MakePoint(:lng, :lat), 4326)::geography,
                :radius_m
              )
        ORDER BY distance_meters ASC
        LIMIT :limit_val
    """)

    try:
        result = await db_session.execute(
            query,
            {
                "lat": latitude,
                "lng": longitude,
                "radius_m": radius_meters,
                "limit_val": limit,
            },
        )
        rows = result.fetchall()

        shops = []
        for row in rows:
            shops.append({
                "shop_id": row.id,
                "shop_name": row.name,
                "slug": row.slug,
                "rating": float(row.rating) if row.rating else 0.0,
                "review_count": row.review_count or 0,
                "is_accepting_orders": row.is_accepting_orders,
                "is_verified": row.is_verified,
                "latitude": float(row.loc_lat) if row.loc_lat else row.latitude,
                "longitude": float(row.loc_lng) if row.loc_lng else row.longitude,
                "distance_meters": round(float(row.distance_meters), 1),
                "distance_km": round(float(row.distance_meters) / 1000, 2),
            })

        await cache.set_json(
            "geospatial", cache_key, shops, ttl=CACHE_TTL_NEARBY_SHOPS
        )
        return shops
    except Exception as exc:
        logger.warning(
            "PostGIS nearby query failed, falling back to haversine: %s", exc
        )
        return await _find_nearby_shops_haversine(
            db_session, latitude, longitude, radius_meters, limit
        )

async def _find_nearby_shops_haversine(
    db_session,
    latitude: float,
    longitude: float,
    radius_meters: float,
    limit: int,
) -> list[dict]:
    """Fallback: haversine distance calculation without PostGIS.

    Uses SQLAlchemy 2.0 ``select()`` + ``session.execute()`` so it works with
    both ``Session`` (sync) and ``AsyncSession`` (async) — the nearby route
    passes an async session, and calling legacy ``.query()`` on it would
    raise AttributeError.
    """
    from sqlalchemy import select

    from app.models.shop import Shop, ShopStatus

    stmt = select(Shop).where(
        Shop.is_deleted == False,
        Shop.status.in_([ShopStatus.ACTIVE, ShopStatus.VERIFIED]),
        Shop.is_verified == True,
        Shop.is_accepting_orders == True,
        Shop.latitude.isnot(None),
        Shop.longitude.isnot(None),
    )

    result = await db_session.execute(stmt)
    shops = result.scalars().all()
    results = []

    for shop in shops:
        dist_m = _haversine_meters(
            latitude, longitude, float(shop.latitude), float(shop.longitude)
        )
        if dist_m <= radius_meters:
            results.append({
                "shop_id": shop.id,
                "shop_name": shop.name,
                "slug": shop.slug,
                "rating": float(shop.rating) if shop.rating else 0.0,
                "review_count": shop.review_count or 0,
                "is_accepting_orders": shop.is_accepting_orders,
                "is_verified": shop.is_verified,
                "latitude": float(shop.latitude),
                "longitude": float(shop.longitude),
                "distance_meters": round(dist_m, 1),
                "distance_km": round(dist_m / 1000, 2),
            })

    results.sort(key=lambda s: s["distance_meters"])
    return results[:limit]


def _haversine_meters(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """Calculate great-circle distance in meters between two coordinates."""
    phi1 = math.radians(lat1)
    phi2 = math.radians(lat2)
    dphi = math.radians(lat2 - lat1)
    dlambda = math.radians(lon2 - lon1)

    a = (
        math.sin(dphi / 2) ** 2
        + math.cos(phi1) * math.cos(phi2) * math.sin(dlambda / 2) ** 2
    )
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))
    return _EARTH_RADIUS_M * c

# ── Route ETA with Caching ──────────────────────────────────────────────────

async def get_route_eta_cached(
    origin_lat: float,
    origin_lng: float,
    dest_lat: float,
    dest_lng: float,
    mode: str = "driving",
) -> Optional[dict]:
    """Get route ETA with Redis cache."""
    cache_key = (
        f"route:{round(origin_lat,5)}:{round(origin_lng,5)}:"
        f"{round(dest_lat,5)}:{round(dest_lng,5)}:{mode}"
    )

    cached = await cache.get_json("geospatial", cache_key)
    if cached:
        return cached

    result = await get_directions(origin_lat, origin_lng, dest_lat, dest_lng, mode=mode)
    if result is None:
        dist_m = _haversine_meters(origin_lat, origin_lng, dest_lat, dest_lng)
        return {
            "distance_meters": round(dist_m),
            "distance_text": f"{dist_m/1000:.1f} km",
            "duration_seconds": round(dist_m / 13.89),
            "duration_text": f"{round(dist_m / 13.89 / 60)} min",
            "polyline": None,
            "start_address": "",
            "end_address": "",
            "steps": [],
            "source": "haversine_estimate",
        }

    payload = {
        "distance_meters": result.distance_meters,
        "distance_text": result.distance_text,
        "duration_seconds": result.duration_seconds,
        "duration_text": result.duration_text,
        "polyline": result.polyline,
        "start_address": result.start_address,
        "end_address": result.end_address,
        "steps": result.steps,
        "source": "google_directions",
    }

    await cache.set_json("geospatial", cache_key, payload, ttl=CACHE_TTL_ROUTE_ETA)
    return payload

# ── Delivery ETA Batch (Distance Matrix) ─────────────────────────────────

async def get_delivery_eta_batch(
    origin: Tuple[float, float],
    destinations: list[Tuple[float, float]],
    mode: str = "driving",
) -> list[dict]:
    """Get ETA from one origin to multiple destinations (delivery optimization)."""
    results: list[Optional[dict]] = []
    uncached_indices: list[int] = []
    uncached_dests: list[Tuple[float, float]] = []

    for i, (dest_lat, dest_lng) in enumerate(destinations):
        cache_key = (
            f"route:{round(origin[0],5)}:{round(origin[1],5)}:"
            f"{round(dest_lat,5)}:{round(dest_lng,5)}:{mode}"
        )
        cached = await cache.get_json("geospatial", cache_key)
        if cached:
            results.append(cached)
            continue
        results.append(None)
        uncached_indices.append(i)
        uncached_dests.append((dest_lat, dest_lng))

    if uncached_dests:
        matrix = await get_distance_matrix([origin], uncached_dests, mode=mode)
        if matrix and matrix[0]:
            for j, elem in enumerate(matrix[0]):
                idx = uncached_indices[j] if j < len(uncached_indices) else None
                if idx is None:
                    continue
                dest_lat, dest_lng = uncached_dests[j]
                cache_key = (
                    f"route:{round(origin[0],5)}:{round(origin[1],5)}:"
                    f"{round(dest_lat,5)}:{round(dest_lng,5)}:{mode}"
                )
                payload = {
                    "distance_meters": elem.distance_meters,
                    "distance_text": elem.distance_text,
                    "duration_seconds": elem.duration_seconds,
                    "duration_text": elem.duration_text,
                    "source": "google_distance_matrix",
                }
                await cache.set_json(
                    "geospatial", cache_key, payload, ttl=CACHE_TTL_ROUTE_ETA
                )
                results[idx] = payload

    for i, r in enumerate(results):
        if r is None:
            dest_lat, dest_lng = destinations[i]
            dist_m = _haversine_meters(origin[0], origin[1], dest_lat, dest_lng)
            results[i] = {
                "distance_meters": round(dist_m),
                "distance_text": f"{dist_m/1000:.1f} km",
                "duration_seconds": round(dist_m / 13.89),
                "duration_text": f"{round(dist_m / 13.89 / 60)} min",
                "source": "haversine_estimate",
            }

    return results

# ── Autocomplete + Place Resolution with Session Tokens ─────────────────────

async def autocomplete_with_session(
    query: str,
    session_token: str,
    latitude: Optional[float] = None,
    longitude: Optional[float] = None,
    radius_meters: int = 50000,
) -> list[dict]:
    """Places Autocomplete with session token support for billing optimization."""
    bias = (latitude, longitude) if latitude is not None and longitude is not None else None
    suggestions = await address_autocomplete(query, location_bias=bias, radius_meters=radius_meters)

    return [
        {
            "place_id": s.place_id,
            "main_text": s.main_text,
            "secondary_text": s.secondary_text,
            "types": s.types,
            "session_token": session_token,
        }
        for s in suggestions
    ]


async def resolve_place_with_session(place_id: str, session_token: str) -> Optional[dict]:
    """Resolve a place_id to coordinates, concluding an autocomplete session."""
    coords = await get_place_coordinates(place_id)
    if coords is None:
        return None
    return {
        "latitude": coords[0],
        "longitude": coords[1],
        "place_id": place_id,
        "session_token": session_token,
    }


# ── Geospatial Utility Functions ─────────────────────────────────────────────

def format_coordinates(latitude: float, longitude: float, precision: int = 7) -> dict:
    """Format coordinates to specified decimal precision.
    7 decimal places approximates 1.1mm precision (Zomato-grade).
    """
    return {
        "latitude": round(float(latitude), precision),
        "longitude": round(float(longitude), precision),
        "precision_decimals": precision,
        "accuracy_meters": _decimal_precision_to_meters(precision),
    }


def _decimal_precision_to_meters(decimals: int) -> float:
    """Approximate meters precision for given decimal places at equator."""
    return 111_320.0 / (10 ** decimals)


def validate_coordinates(latitude: float, longitude: float) -> bool:
    """Validate coordinate range."""
    return -90 <= latitude <= 90 and -180 <= longitude <= 180


def get_bounding_box(latitude: float, longitude: float, radius_meters: float) -> dict:
    """Calculate a bounding box around a point for quick pre-filtering."""
    lat_delta = radius_meters / 111_320.0
    lng_delta = radius_meters / (111_320.0 * math.cos(math.radians(latitude)))

    return {
        "sw_lat": latitude - lat_delta,
        "sw_lng": longitude - lng_delta,
        "ne_lat": latitude + lat_delta,
        "ne_lng": longitude + lng_delta,
    }