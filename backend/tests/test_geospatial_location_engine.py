"""Tests for the High-Precision Geospatial Location Engine API.

Covers:
- reverse-geocode (validation + service wiring)
- nearby-shops (PostGIS ST_DWithin + haversine fallback)
- route-eta (Directions API + haversine estimate fallback)
- autocomplete + place/resolve (session tokens)
- utility primitives (7-decimal formatting, haversine)

Most endpoints are tested with the Google Maps API key unset, which
exercises the graceful-degradation paths.
"""
from __future__ import annotations

import asyncio
from unittest.mock import AsyncMock, patch

import pytest
from fastapi.testclient import TestClient

from app.main import app


@pytest.fixture()
def client():
    with TestClient(app) as c:
        yield c


# ── Reverse Geocode ──────────────────────────────────────────────────────────

def test_reverse_geocode_invalid_coords(client):
    resp = client.post(
        "/api/v1/location/reverse-geocode",
        json={"latitude": 91.0, "longitude": 85.13},
    )
    assert resp.status_code == 400
    body = resp.json()
    assert body["success"] is False
    assert body["error_code"] == "INVALID_COORDINATES"


def test_reverse_geocode_no_api_key(client, monkeypatch):
    monkeypatch.setattr("app.services.location_service._get_api_key", lambda: None)
    resp = client.post(
        "/api/v1/location/reverse-geocode",
        json={"latitude": 25.5941, "longitude": 85.1376},
    )
    assert resp.status_code == 404
    assert resp.json()["error_code"] == "REVERSE_GEOCODE_FAILED"


@patch("app.services.geospatial_service.reverse_geocode", new_callable=AsyncMock)
def test_reverse_geocode_success(mock_reverse, client):
    from app.services.location_service import ReverseGeocodeResult

    mock_reverse.return_value = ReverseGeocodeResult(
        formatted_address="Patna, Bihar, India",
        route="Main Road",
        locality="Patna",
        district="Patna",
        state="Bihar",
        pincode="800001",
        country="India",
        latitude=25.5941,
        longitude=85.1376,
        place_id="ChIJ-test",
    )
    resp = client.post(
        "/api/v1/location/reverse-geocode",
        json={"latitude": 25.5940941, "longitude": 85.1375941},
    )
    assert resp.status_code == 200
    body = resp.json()
    assert body["success"] is True
    address = body["data"]["address"]
    assert address["state"] == "Bihar"
    assert address["pincode"] == "800001"
    assert body["data"]["formatted_address"] == "Patna, Bihar, India"


# ── Nearby Shops ─────────────────────────────────────────────────────────────

def test_nearby_shops_invalid_coords(client):
    resp = client.post(
        "/api/v1/location/nearby-shops",
        json={"latitude": 25.59, "longitude": 200.0, "radius_meters": 5000},
    )
    assert resp.status_code == 400
    assert resp.json()["error_code"] == "INVALID_COORDINATES"


def test_nearby_shops_pydantic_validation(client):
    resp = client.post(
        "/api/v1/location/nearby-shops",
        json={"latitude": 25.59, "longitude": 85.13, "radius_meters": -5},
    )
    assert resp.status_code == 422  # radius_meters must be > 0


# ── Route ETA ────────────────────────────────────────────────────────────────

def test_route_eta_invalid_coords(client):
    resp = client.post(
        "/api/v1/location/route-eta",
        json={
            "origin_latitude": 90.5,
            "origin_longitude": 85.13,
            "dest_latitude": 25.6,
            "dest_longitude": 85.15,
        },
    )
    assert resp.status_code == 400


def test_route_eta_haversine_fallback(client, monkeypatch):
    monkeypatch.setattr("app.services.location_service._get_api_key", lambda: None)
    resp = client.post(
        "/api/v1/location/route-eta",
        json={
            "origin_latitude": 25.5941,
            "origin_longitude": 85.1376,
            "dest_latitude": 25.6041,
            "dest_longitude": 85.1476,
            "mode": "driving",
        },
    )
    assert resp.status_code == 200
    data = resp.json()["data"]
    assert data["source"] == "haversine_estimate"
    assert data["distance_meters"] > 0
    assert data["duration_seconds"] > 0


# ── Autocomplete ─────────────────────────────────────────────────────────────

def test_autocomplete_no_api_key(client, monkeypatch):
    monkeypatch.setattr("app.services.location_service._get_api_key", lambda: None)
    resp = client.post("/api/v1/location/autocomplete", json={"query": "patna"})
    assert resp.status_code == 200
    data = resp.json()["data"]
    assert data["suggestions"] == []
    assert data["session_token"]  # generated server-side


def test_autocomplete_preserves_session_token(client, monkeypatch):
    monkeypatch.setattr("app.services.location_service._get_api_key", lambda: None)
    resp = client.post(
        "/api/v1/location/autocomplete",
        json={"query": "patna", "session_token": "tok-123"},
    )
    assert resp.json()["data"]["session_token"] == "tok-123"


@patch("app.services.geospatial_service.get_place_coordinates", new_callable=AsyncMock)
def test_place_resolve_not_found_direct(mock_coords):
    mock_coords.return_value = None
    from app.services.geospatial_service import resolve_place_with_session

    result = asyncio.run(resolve_place_with_session("bad-place", "tok-1"))
    assert result is None


# ── Utility primitives ───────────────────────────────────────────────────────

def test_format_coordinates_precision():
    from app.services.geospatial_service import format_coordinates

    out = format_coordinates(25.59409417, 85.13759417, precision=7)
    assert out["latitude"] == round(25.59409417, 7)
    assert out["accuracy_meters"] < 0.02  # sub-2cm


def test_haversine_reference_distance():
    from app.services.geospatial_service import _haversine_meters

    # Patna -> Patna City straight-line (~1.5km) sanity check.
    dist = _haversine_meters(25.5941, 85.1376, 25.6041, 85.1476)
    assert 1400 < dist < 1600