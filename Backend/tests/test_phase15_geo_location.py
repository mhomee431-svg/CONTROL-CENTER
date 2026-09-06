"""Phase 15 — Google Maps / Location: geo service tests.

Covers the pieces the customer map flow depends on:
- haversine distance math (customer ↔ shop)
- PostGIS WKT coordinate extraction with scalar fallback
- nearby shop query (verification + radius filtering)
- home feed distance computation
"""

import os
import sys
from pathlib import Path

BACKEND_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BACKEND_DIR))

os.environ.setdefault("ENVIRONMENT", "test")
os.environ.setdefault("HYPERLOCAL_ENV", "test")

import pytest  # noqa: E402

from app.core.config import settings  # noqa: E402

settings.RATE_LIMIT_ENABLED = False


# ── Data helpers ──────────────────────────────────────────────────────────────
PATNA = (25.5941, 85.1376)      # lat, lng
GAYA = (24.7914, 85.0002)       # lat, lng
DELHI = (28.7041, 77.1025)      # lat, lng


def test_haversine_zero_distance_for_same_point():
    from app.services.geo_service import haversine_km

    d = haversine_km(*PATNA, *PATNA)
    assert d == pytest.approx(0.0, abs=1e-6)


def test_haversine_patna_to_gaya():
    """Patna → Gaya is ~95–105 km by road; great-circle must fall in range."""
    from app.services.geo_service import haversine_km

    d = haversine_km(*PATNA, *GAYA)
    assert 80 < d < 130


def test_haversine_patna_to_delhi():
    """Patna → Delhi great-circle is ~860–880 km."""
    from app.services.geo_service import haversine_km

    d = haversine_km(*PATNA, *DELHI)
    assert 800 < d < 950


# ── PostGIS WKT extraction ────────────────────────────────────────────────────
class _MockShop:
    """Minimal Shop stand-in exposing the fields the route touches."""

    def __init__(self, location=None, latitude=None, longitude=None):
        self.location = location
        self.latitude = latitude
        self.longitude = longitude


def test_extract_coords_from_wkt_point():
    from app.api.routes.locations import _extract_coords_from_location

    shop = _MockShop(location="POINT(85.1376 25.5941)")
    lng, lat = _extract_coords_from_location(shop)
    assert lat == pytest.approx(25.5941)
    assert lng == pytest.approx(85.1376)


def test_extract_coords_falls_back_to_scalar_columns():
    from app.api.routes.locations import _extract_coords_from_location

    shop = _MockShop(location=None, latitude=25.5941, longitude=85.1376)
    lng, lat = _extract_coords_from_location(shop)
    assert lat == pytest.approx(25.5941)
    assert lng == pytest.approx(85.1376)


def test_extract_coords_missing_returns_none():
    from app.api.routes.locations import _extract_coords_from_location

    assert _extract_coords_from_location(_MockShop(location=None)) == (None, None)
    assert _extract_coords_from_location(_MockShop(location="NOT_A_GEOM")) == (None, None)


# ── Nearby shop query ─────────────────────────────────────────────────────────
class _MockQuery:
    def __init__(self, result=None):
        self._result = result
        self._filtered = result

    def filter(self, *args, **kwargs):
        return self

    def filter_by(self, **kwargs):
        return self

    def all(self):
        return self._filtered or []


class _MockDB:
    """Simulates the visibility filter `nearby_shops` applies on the Shop query."""

    def __init__(self, shops):
        self._shops = shops

    def query(self, model):
        from app.models.shop import Shop, ShopStatus

        if model is Shop:
            filtered = [
                s
                for s in self._shops
                if s.status in (ShopStatus.ACTIVE, ShopStatus.VERIFIED)
                and s.is_verified
                and s.is_accepting_orders
                and not s.is_deleted
            ]
            return _MockQuery(filtered)
        return _MockQuery(self._shops)


class _MockShopForService:
    def __init__(self, sid, name, lat, lng, status, is_verified=True, is_accepting=True):
        self.id = sid
        self.name = name
        self.latitude = lat
        self.longitude = lng
        self.status = status
        self.is_verified = is_verified
        self.is_accepting_orders = is_accepting
        self.image_url = None
        self.rating = 4.5
        self.category = None
        self.is_open_24x7 = True
        self.is_deleted = False


def test_nearby_shops_returns_only_shops_within_radius():
    from app.models.shop import ShopStatus
    from app.services.shop_service import nearby_shops

    # 1 km away is inside a 5 km radius, ~155 km away is not.
    close = _MockShopForService(1, "Corner Store", 25.6000, 85.1400, ShopStatus.ACTIVE)
    far = _MockShopForService(2, "Far Mall", 26.5941, 86.1376, ShopStatus.ACTIVE)

    results = nearby_shops(
        _MockDB([close, far]),
        latitude=PATNA[0],
        longitude=PATNA[1],
        radius_km=5.0,
    )

    assert [r["id"] for r in results] == [1]
    assert results[0]["distance_km"] > 0
    assert results[0]["latitude"] == pytest.approx(25.6000)
    assert results[0]["longitude"] == pytest.approx(85.1400)


def test_nearby_shops_excludes_unverified():
    from app.models.shop import ShopStatus
    from app.services.shop_service import nearby_shops

    verified = _MockShopForService(1, "Verified", *PATNA, ShopStatus.ACTIVE, is_verified=True)
    unverified = _MockShopForService(2, "Not Verified", *PATNA, ShopStatus.ACTIVE, is_verified=False)

    results = nearby_shops(_MockDB([verified, unverified]), latitude=PATNA[0], longitude=PATNA[1])

    assert len(results) == 1
    assert results[0]["id"] == 1


# ── Home feed distance ────────────────────────────────────────────────────────
def test_home_feed_shop_distance_uses_haversine():
    from app.api.routes.home import _shop_distance_km
    from app.models.shop import ShopStatus

    shop = _MockShopForService(1, "Shop", GAYA[0], GAYA[1], ShopStatus.ACTIVE)

    d = _shop_distance_km(shop, PATNA[0], PATNA[1])
    assert 80 < d < 130


def test_home_feed_shop_distance_zero_without_coordinates():
    from app.api.routes.home import _shop_distance_km

    shop = _MockShopForService(1, "Shop", None, None, None)

    assert _shop_distance_km(shop, PATNA[0], PATNA[1]) == 0.0
    assert _shop_distance_km(shop, None, None) == 0.0


# ── HTTP API level (FastAPI TestClient) ──────────────────────────────────────
def _make_http_client(db=None):
    """Builds a TestClient with an optional override for the `get_db` dependency."""
    from fastapi.testclient import TestClient

    from app.database.session import get_db
    from app.main import app

    app.dependency_overrides[get_db] = lambda: db
    return TestClient(app)


def test_locations_manual_search_http():
    """GET /locations/manual-search returns matching cities with coordinates."""
    from app.core.config import settings

    client = _make_http_client()
    try:
        resp = client.get(f"{settings.API_PREFIX}/locations/manual-search", params={"q": "patna"})
        assert resp.status_code == 200
        body = resp.json()
        items = body["data"]
        assert isinstance(items, list) and len(items) == 1
        assert items[0]["city"] == "Patna"
        assert items[0]["latitude"] == pytest.approx(25.5941)
        assert items[0]["longitude"] == pytest.approx(85.1376)
    finally:
        from app.main import app

        app.dependency_overrides.clear()


def test_locations_nearby_http_uses_scalar_coordinate_fallback():
    """GET /locations/nearby resolves shop coordinates and ranks by distance.

    The route falls back to the scalar latitude/longitude template columns when
    the PostGIS geometry column is not hydrated (as in unit-test sessions).
    """
    from app.core.config import settings
    from app.models.shop import ShopStatus

    class Store:
        pass

    def _shop(sid, name, lat, lng, address="Addr", is_verified=True):
        s = Store()
        s.id = sid
        s.name = name
        s.latitude = lat
        s.longitude = lng
        s.address = address
        s.location = None  # no PostGIS geometry in unit tests
        # Visibility contract (matches /shops/nearby + /search/v2/nearby-shops).
        s.is_deleted = False
        s.status = ShopStatus.ACTIVE
        s.is_verified = is_verified
        s.is_accepting_orders = True
        return s

    close = _shop(1, "Corner Store", 25.6000, 85.1400)
    far = _shop(2, "Far Mall", 26.5941, 86.1376)
    # Close to the user but unverified — must be excluded from discovery.
    unverified = _shop(3, "Ghost Store", 25.6001, 85.1401, is_verified=False)

    class HttpMockDB:
        def query(self, model):
            class _Q:
                def all(self):
                    return [close, far, unverified]

            return _Q()

    client = _make_http_client(db=HttpMockDB())
    try:
        resp = client.get(
            f"{settings.API_PREFIX}/locations/nearby",
            params={"latitude": PATNA[0], "longitude": PATNA[1], "radius_km": 5.0},
        )
        assert resp.status_code == 200
        body = resp.json()["data"]
        assert body["user_lat"] == pytest.approx(PATNA[0])
        assert body["radius_km"] == 5.0
        shops = body["shops"]
        assert len(shops) == 1
        assert shops[0]["shop_name"] == "Corner Store"
        assert shops[0]["distance_km"] > 0
        assert shops[0]["latitude"] == pytest.approx(25.6000)
        assert shops[0]["longitude"] == pytest.approx(85.1400)
    finally:
        from app.main import app

        app.dependency_overrides.clear()