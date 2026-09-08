"""
Google Maps Location Service — Geocoding, Places, Directions, Distance Matrix.

Integrates with Google Maps APIs for:
- Reverse Geocoding: lat/lng to structured address
- Address Autocomplete: Places API suggestions
- Route & ETA: Directions API + Distance Matrix API
- Radius-based shop discovery (uses geo_service.haversine_km)

All API keys are loaded from environment/config. No secrets are hardcoded.
"""
from __future__ import annotations

import os
from typing import Any, Optional, Tuple

import httpx

from app.core.config import settings
from app.core.logging import get_logger

logger = get_logger("app.services.location")

# Google Maps API endpoints
_GEOCODE_URL = "https://maps.googleapis.com/maps/api/geocode/json"
_PLACES_AUTOCOMPLETE_URL = "https://maps.googleapis.com/maps/api/place/autocomplete/json"
_PLACE_DETAILS_URL = "https://maps.googleapis.com/maps/api/place/details/json"
_DIRECTIONS_URL = "https://maps.googleapis.com/maps/api/directions/json"
_DISTANCE_MATRIX_URL = "https://maps.googleapis.com/maps/api/distancematrix/json"


def _get_api_key() -> Optional[str]:
    """Resolve the Google Maps API key from settings or environment."""
    key = getattr(settings, "GOOGLE_MAPS_API_KEY", None) or os.getenv("GOOGLE_MAPS_API_KEY")
    if not key:
        logger.warning("GOOGLE_MAPS_API_KEY is not configured — Google Maps APIs will be unavailable")
    return key


class ReverseGeocodeResult:
    """Structured address from reverse geocoding."""

    __slots__ = (
        "formatted_address", "street_number", "route", "locality",
        "district", "state", "pincode", "country", "latitude", "longitude",
        "place_id",
    )

    def __init__(self, **kwargs: Any):
        self.formatted_address: str = kwargs.get("formatted_address", "")
        self.street_number: Optional[str] = kwargs.get("street_number")
        self.route: Optional[str] = kwargs.get("route")
        self.locality: Optional[str] = kwargs.get("locality")
        self.district: Optional[str] = kwargs.get("district")
        self.state: Optional[str] = kwargs.get("state")
        self.pincode: Optional[str] = kwargs.get("pincode")
        self.country: Optional[str] = kwargs.get("country")
        self.latitude: Optional[float] = kwargs.get("latitude")
        self.longitude: Optional[float] = kwargs.get("longitude")
        self.place_id: Optional[str] = kwargs.get("place_id")


class AutocompleteSuggestion:
    """A single Places API autocomplete suggestion."""

    __slots__ = ("place_id", "main_text", "secondary_text", "types")

    def __init__(self, **kwargs: Any):
        self.place_id: str = kwargs.get("place_id", "")
        self.main_text: str = kwargs.get("main_text", "")
        self.secondary_text: str = kwargs.get("secondary_text", "")
        self.types: list = kwargs.get("types", [])


class RouteResult:
    """Route and ETA result from Directions API."""

    __slots__ = (
        "distance_meters", "distance_text", "duration_seconds", "duration_text",
        "polyline", "start_address", "end_address", "steps",
    )

    def __init__(self, **kwargs: Any):
        self.distance_meters: int = kwargs.get("distance_meters", 0)
        self.distance_text: str = kwargs.get("distance_text", "")
        self.duration_seconds: int = kwargs.get("duration_seconds", 0)
        self.duration_text: str = kwargs.get("duration_text", "")
        self.polyline: Optional[str] = kwargs.get("polyline")
        self.start_address: str = kwargs.get("start_address", "")
        self.end_address: str = kwargs.get("end_address", "")
        self.steps: list = kwargs.get("steps", [])



# ── Reverse Geocoding ───────────────────────────────────────────────────────

async def reverse_geocode(latitude: float, longitude: float) -> Optional[ReverseGeocodeResult]:
    """Convert lat/lng coordinates into a structured address payload.

    Uses Google Maps Geocoding API. Returns None if the API key is missing
    or the request fails.
    """
    api_key = _get_api_key()
    if not api_key:
        return None

    try:
        resp = httpx.get(
            _GEOCODE_URL,
            params={
                "latlng": f"{latitude},{longitude}",
                "key": api_key,
                "result_type": "street_address|route|locality|administrative_area_level_1|postal_code",
            },
            timeout=8.0,
        )
        if resp.status_code != 200:
            logger.warning("Geocoding API returned status %s", resp.status_code)
            return None

        data = resp.json()
        if data.get("status") != "OK":
            logger.warning("Geocoding API status: %s", data.get("status"))
            return None

        results = data.get("results", [])
        if not results:
            return None

        return _parse_geocode_result(results[0])
    except Exception as exc:
        logger.warning("Reverse geocoding failed: %s", exc)
        return None


def _parse_geocode_result(result: dict) -> ReverseGeocodeResult:
    """Parse a single geocoding result into a ReverseGeocodeResult."""
    components = result.get("address_components", [])
    loc = result.get("geometry", {}).get("location", {})

    parsed: dict = {
        "formatted_address": result.get("formatted_address", ""),
        "place_id": result.get("place_id"),
        "latitude": loc.get("lat"),
        "longitude": loc.get("lng"),
    }

    for comp in components:
        types = comp.get("types", [])
        if "street_number" in types and "street_number" not in parsed:
            parsed["street_number"] = comp.get("long_name")
        elif "route" in types and "route" not in parsed:
            parsed["route"] = comp.get("long_name")
        elif "locality" in types and "locality" not in parsed:
            parsed["locality"] = comp.get("long_name")
        elif "administrative_area_level_2" in types and "district" not in parsed:
            parsed["district"] = comp.get("long_name")
        elif "administrative_area_level_1" in types and "state" not in parsed:
            parsed["state"] = comp.get("long_name")
        elif "postal_code" in types and "pincode" not in parsed:
            parsed["pincode"] = comp.get("long_name")
        elif "country" in types and "country" not in parsed:
            parsed["country"] = comp.get("long_name")



# ── Address Autocomplete ────────────────────────────────────────────────────

async def address_autocomplete(
    query: str,
    location_bias: Optional[Tuple[float, float]] = None,
    radius_meters: int = 50000,
) -> list[AutocompleteSuggestion]:
    """Return Places API address suggestions for a partial query.

    Args:
        query: Partial address text from user input.
        location_bias: Optional (lat, lng) to bias results toward a region.
        radius_meters: Search radius around the bias point (default 50km).
    """
    api_key = _get_api_key()
    if not api_key:
        return []

    params: dict[str, Any] = {
        "input": query,
        "key": api_key,
        "components": "country:in",
        "types": "geocode|establishment",
    }

    if location_bias:
        params["location"] = f"{location_bias[0]},{location_bias[1]}"
        params["radius"] = radius_meters
        params["strictbounds"] = False

    try:
        resp = httpx.get(_PLACES_AUTOCOMPLETE_URL, params=params, timeout=8.0)
        if resp.status_code != 200:
            return []

        data = resp.json()
        if data.get("status") != "OK":
            return []

        predictions = data.get("predictions", [])
        return [
            AutocompleteSuggestion(
                place_id=p.get("place_id", ""),
                main_text=p.get("structured_formatting", {}).get("main_text", ""),
                secondary_text=p.get("structured_formatting", {}).get("secondary_text", ""),
                types=p.get("types", []),
            )
            for p in predictions[:10]
        ]
    except Exception as exc:
        logger.warning("Address autocomplete failed: %s", exc)
        return []


async def get_place_coordinates(place_id: str) -> Optional[Tuple[float, float]]:
    """Resolve a Places API place_id to (latitude, longitude)."""
    api_key = _get_api_key()
    if not api_key:
        return None

    try:
        resp = httpx.get(
            _PLACE_DETAILS_URL,
            params={
                "place_id": place_id,
                "key": api_key,
                "fields": "geometry",
            },
            timeout=8.0,
        )
        if resp.status_code != 200:
            return None

        result = resp.json().get("result", {})
        loc = result.get("geometry", {}).get("location", {})
        if "lat" in loc and "lng" in loc:
            return float(loc["lat"]), float(loc["lng"])
        return None
    except Exception as exc:
        logger.warning("Place details failed: %s", exc)
        return None


# ── Route & ETA (Directions API) ───────────────────────────────────────────

async def get_directions(
    origin_lat: float,
    origin_lng: float,
    dest_lat: float,
    dest_lng: float,
    mode: str = "driving",
) -> Optional[RouteResult]:
    """Get route and ETA between two coordinates using Directions API.

    Args:
        mode: travel mode - driving, walking, bicycling, transit.
    """
    api_key = _get_api_key()
    if not api_key:
        return None

    try:
        resp = httpx.get(
            _DIRECTIONS_URL,
            params={
                "origin": f"{origin_lat},{origin_lng}",
                "destination": f"{dest_lat},{dest_lng}",
                "mode": mode,
                "key": api_key,
                "departure_time": "now",
                "traffic_model": "best_guess",
            },
            timeout=10.0,
        )
        if resp.status_code != 200:
            return None

        data = resp.json()
        if data.get("status") != "OK":
            logger.warning("Directions API status: %s", data.get("status"))
            return None

        routes = data.get("routes", [])
        if not routes:
            return None

        route = routes[0]
        leg = route.get("legs", [{}])[0]

        return RouteResult(
            distance_meters=leg.get("distance", {}).get("value", 0),
            distance_text=leg.get("distance", {}).get("text", ""),
            duration_seconds=leg.get("duration_in_traffic", {}).get("value")
                or leg.get("duration", {}).get("value", 0),
            duration_text=leg.get("duration_in_traffic", {}).get("text")
                or leg.get("duration", {}).get("text", ""),
            polyline=route.get("overview_polyline", {}).get("points"),
            start_address=leg.get("start_address", ""),
            end_address=leg.get("end_address", ""),
            steps=[
                {
                    "distance": step.get("distance", {}).get("text", ""),
                    "duration": step.get("duration", {}).get("text", ""),
                    "instruction": step.get("html_instructions", ""),
                    "mode": step.get("travel_mode", ""),
                }
                for step in leg.get("steps", [])
            ],
        )
    except Exception as exc:
        logger.warning("Directions request failed: %s", exc)
        return None


# ── Distance Matrix ────────────────────────────────────────────────────────

async def get_distance_matrix(
    origins: list[Tuple[float, float]],
    destinations: list[Tuple[float, float]],
    mode: str = "driving",
) -> list[list[DistanceMatrixResult]]:
    """Compute distance and duration for multiple origin-destination pairs.

    Returns a 2D list: results[i][j] corresponds to origins[i] to destinations[j].
    Useful for delivery boy route optimization against multiple shops.
    """
    api_key = _get_api_key()
    if not api_key:
        return []

    if not origins or not destinations:
        return []

    origins_str = "|".join(f"{lat},{lng}" for lat, lng in origins)
    dest_str = "|".join(f"{lat},{lng}" for lat, lng in destinations)

    try:
        resp = httpx.get(
            _DISTANCE_MATRIX_URL,
            params={
                "origins": origins_str,
                "destinations": dest_str,
                "mode": mode,
                "key": api_key,
                "departure_time": "now",
                "traffic_model": "best_guess",
            },
            timeout=15.0,
        )
        if resp.status_code != 200:
            return []

        data = resp.json()
        if data.get("status") != "OK":
            return []

        rows = data.get("rows", [])
        origin_addresses = data.get("origin_addresses", [])
        dest_addresses = data.get("destination_addresses", [])
        results: list[list[DistanceMatrixResult]] = []

        for i, row in enumerate(rows):
            row_results: list[DistanceMatrixResult] = []
            elements = row.get("elements", [])
            for j, elem in enumerate(elements):
                if elem.get("status") != "OK":
                    row_results.append(DistanceMatrixResult())
                    continue
                row_results.append(
                    DistanceMatrixResult(
                        origin_address=origin_addresses[i] if i < len(origin_addresses) else "",
                        destination_address=dest_addresses[j] if j < len(dest_addresses) else "",
                        distance_meters=elem.get("distance", {}).get("value", 0),
                        distance_text=elem.get("distance", {}).get("text", ""),
                        duration_seconds=elem.get("duration_in_traffic", {}).get("value")
                            or elem.get("duration", {}).get("value", 0),
                        duration_text=elem.get("duration_in_traffic", {}).get("text")
                            or elem.get("duration", {}).get("text", ""),
                    )
                )
            results.append(row_results)

        return results
    except Exception as exc:
        logger.warning("Distance matrix request failed: %s", exc)
        return []
