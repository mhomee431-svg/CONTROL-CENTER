"""Functional tests for the geospatial service layer (no HTTP/DB/Redis needed).

Exercises core engine logic directly with mocked external providers:
- Geo primitives (haversine, bounding box, formatting/validation)
- Cached reverse geocoding (mock Google + mock Redis)
- Route-ETA fallback (no API key -> haversine estimate)
- PostGIS -> haversine fallback discovery

Sync wrappers use asyncio.run() to match the repo test style.
"""
from __future__ import annotations

import asyncio
from unittest.mock import AsyncMock, MagicMock, patch

from app.services.geospatial_service import (
    CACHE_TTL_GEOCODE,
    _decimal_precision_to_meters,
    _haversine_meters,
    _find_nearby_shops_haversine,
    find_nearby_shops_postgis,
    format_coordinates,
    get_bounding_box,
    get_route_eta_cached,
    reverse_geocode_cached,
    validate_coordinates,
)


# ── Geo primitives ───────────────────────────────────────────────────────────

def test_haversine_self_zero():
    assert _haversine_meters(25.0, 85.0, 25.0, 85.0) == 0.0


def test_haversine_known_bihar():
    d = _haversine_meters(25.5941, 85.1376, 24.7914, 85.0002)
    assert 80000 < d < 100000


def test_decimal_precision_meters():
    assert _decimal_precision_to_meters(7) < 0.012
    assert _decimal_precision_to_meters(6) < 0.12
    assert _decimal_precision_to_meters(5) < 1.12


def test_format_coordinates_7dp():
    out = format_coordinates(12.345678901, 98.765432101, precision=7)
    assert out["latitude"] == 12.3456789
    assert out["longitude"] == 98.7654321
    assert out["precision_decimals"] == 7


def test_validate_coordinates():
    assert validate_coordinates(0, 0)
    assert validate_coordinates(90, 180)
    assert not validate_coordinates(91, 0)
    assert not validate_coordinates(0, 181)


def test_bounding_box_symmetry():
    box = get_bounding_box(25.59, 85.13, 5000.0)
    assert box["sw_lat"] < 25.59 < box["ne_lat"]
    assert box["sw_lng"] < 85.13 < box["ne_lng"]


# ── Cached reverse geocoding ─────────────────────────────────────────────────

@patch("app.services.geospatial_service.cache")
@patch("app.services.geospatial_service.reverse_geocode", new_callable=AsyncMock)
def test_reverse_geocode_cached_miss_writes(mock_geo, mock_cache):
    from app.services.location_service import ReverseGeocodeResult

    mock_cache.get_json = AsyncMock(return_value=None)
    mock_cache.set_json = AsyncMock(return_value=True)
    mock_geo.return_value = ReverseGeocodeResult(
        formatted_address="Patna, Bihar, India",
        locality="Patna",
        state="Bihar",
        pincode="800001",
        country="India",
        latitude=25.5941,
        longitude=85.1376,
        place_id="ChIJ",
    )

    out = asyncio.run(reverse_geocode_cached(25.59409417, 85.13759417))
    assert out["formatted_address"] == "Patna, Bihar, India"
    assert out["pincode"] == "800001"
    mock_cache.set_json.assert_awaited_once()
    _call = mock_cache.set_json.await_args
    args, _kwargs = _call
    _domain, _key, _payload = args
    assert "geocode:25.5940942:85.1375942" in _key
    assert _kwargs["ttl"] == CACHE_TTL_GEOCODE


@patch("app.services.geospatial_service.cache")
@patch("app.services.geospatial_service.reverse_geocode", new_callable=AsyncMock)
def test_reverse_geocode_cached_hit_skips_api(mock_geo, mock_cache):
    mock_cache.get_json = AsyncMock(
        return_value={"formatted_address": "Cached", "pincode": "800001"}
    )
    out = asyncio.run(reverse_geocode_cached(25.0, 85.0))
    assert out["formatted_address"] == "Cached"
    mock_geo.assert_not_awaited()


@patch("app.services.geospatial_service.cache")
@patch("app.services.geospatial_service.reverse_geocode", new_callable=AsyncMock)
def test_reverse_geocode_cached_api_failure(mock_geo, mock_cache):
    mock_cache.get_json = AsyncMock(return_value=None)
    mock_cache.set_json = AsyncMock(return_value=True)
    mock_geo.return_value = None
    out = asyncio.run(reverse_geocode_cached(25.0, 85.0))
    assert out is None
    mock_cache.set_json.assert_not_awaited()

# ── Route ETA fallback ───────────────────────────────────────────────────────

@patch("app.services.geospatial_service.cache")
@patch("app.services.geospatial_service.get_directions", new_callable=AsyncMock)
def test_route_eta_haversine_fallback(mock_directions, mock_cache):
    mock_cache.get_json = AsyncMock(return_value=None)
    mock_directions.return_value = None  # API unavailable / no key

    out = asyncio.run(get_route_eta_cached(25.5941, 85.1376, 25.6041, 85.1476))
    assert out["source"] == "haversine_estimate"
    assert out["distance_meters"] > 1000
    assert out["duration_seconds"] > 0
    assert out["steps"] == []


# ── PostGIS -> haversine fallback shop discovery ─────────────────────────────

def build_shop(_id, lat, lng):
    s = MagicMock()
    s.id, s.name, s.slug = _id, f"Shop {_id}", f"shop-{_id}"
    s.rating, s.review_count = 4.0, 10
    s.is_accepting_orders, s.is_verified = True, True
    s.latitude, s.longitude = lat, lng
    s.is_deleted = False
    return s


class FakeShopStatus:
    ACTIVE = "ACTIVE"
    VERIFIED = "VERIFIED"


@patch("app.models.shop.ShopStatus", FakeShopStatus)
def test_postgis_query_falls_back_to_haversine():
    db = MagicMock()
    # First execute (raw PostGIS SQL) fails; second (select fallback) succeeds.
    empty_result = MagicMock()
    empty_result.scalars.return_value.all.return_value = []
    db.execute = AsyncMock(
        side_effect=[Exception("PostGIS down"), empty_result]
    )
    shops = asyncio.run(find_nearby_shops_postgis(db, 25.5941, 85.1376, 5000, 10))
    assert isinstance(shops, list)
    assert db.execute.await_count == 2


@patch("app.models.shop.ShopStatus", FakeShopStatus)
def test_haversine_filter_keeps_only_within_radius():
    db = MagicMock()
    # Fallback uses select() + await session.execute() -> scalars().all()
    result = MagicMock()
    result.scalars.return_value.all.return_value = [
        build_shop(1, 25.5941, 85.1376),   # ~0 m
        build_shop(2, 25.60, 85.14),       # ~1 km
        build_shop(3, 26.0, 85.5),         # ~95 km - outside
    ]
    db.execute = AsyncMock(return_value=result)
    out = asyncio.run(_find_nearby_shops_haversine(db, 25.5941, 85.1376, 5000, 10))
    ids = [s["shop_id"] for s in out]
    assert ids == [1, 2]
    assert out[0]["distance_meters"] < out[1]["distance_meters"]