"""
High-precision geospatial API routes — reverse geocode, nearby shops
(ST_DWithin), route-ETA (Distance Matrix/Directions), autocomplete.

All endpoints use the shared geospatial service with Redis caching.
"""
from __future__ import annotations

import uuid
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException

from app.core.responses import success_response, error_response
from app.database.session import get_async_db
from app.schemas.geospatial import (
    AutocompleteRequest,
    AutocompleteResponse,
    AutocompleteSuggestion,
    NearbyShop,
    NearbyShopsRequest,
    NearbyShopsResponse,
    PlaceResolveRequest,
    PlaceResolveResponse,
    ReverseGeocodeRequest,
    ReverseGeocodeResponse,
    AddressComponent,
    RouteEtaRequest,
    RouteEtaResponse,
    RouteStep,
)
from app.services.geospatial_service import (
    autocomplete_with_session,
    find_nearby_shops_postgis,
    format_coordinates,
    get_delivery_eta_batch,
    get_route_eta_cached,
    resolve_place_with_session,
    reverse_geocode_cached,
    validate_coordinates,
)

router = APIRouter(prefix="/location", tags=["location"])


@router.post("/reverse-geocode")
async def reverse_geocode_endpoint(request: ReverseGeocodeRequest):
    """Convert lat/lng coordinates into a structured address payload.


    Coordinates are rounded to 7 decimal places for cache key stability.
    Results are cached in Redis for 30 days
    (addresses rarely change).
    """
    if not validate_coordinates(request.latitude, request.longitude):
        return error_response(
            message="Invalid coordinates. Latitude -90..90, Longitude -180..180.",
            error_code="INVALID_COORDINATES",
            status_code=400,
        )

    result = await reverse_geocode_cached(request.latitude, request.longitude)
    if result is None:
        return error_response(
            message="Could not resolve coordinates to an address. Check GOOGLE_MAPS_API_KEY.",
            error_code="REVERSE_GEOCODE_FAILED",
            status_code=404,
        )

    return success_response(
        data={
            "latitude": request.latitude,
            "longitude": request.longitude,
            "formatted_address": result["formatted_address"],
            "address": {
                "house_number": result.get("street_number"),
                "street": result.get("route"),
                "landmark": None,
                "area": result.get("locality"),
                "city": result.get("locality"),
                "state": result.get("state"),
                "pincode": result.get("pincode"),
                "country": result.get("country"),
            },
            "place_id": result.get("place_id"),
        },
        message="OK",
    )


@router.post("/route-eta")
async def route_eta_endpoint(request: RouteEtaRequest):
    """Calculate real-time route distance and estimated travel time.

    Uses Google Maps Directions API with live traffic when available.
    Falls back to a haversine straight-line estimate at ~50 km/h average
    speed when Google Maps API is unavailable or errors.
    Results cached in Redis for 2 minutes (traffic-sensitive).
    """
    if not validate_coordinates(request.origin_latitude, request.origin_longitude) or not validate_coordinates(
        request.dest_latitude, request.dest_longitude
    ):
        return error_response(
            message="Invalid coordinates.",
            error_code="INVALID_COORDINATES",
            status_code=400,
        )

    result = await get_route_eta_cached(
        request.origin_latitude,
        request.origin_longitude,
        request.dest_latitude,
        request.dest_longitude,
        mode=request.mode,
    )

    return success_response(
        data=RouteEtaResponse(
            distance_meters=result["distance_meters"],
            distance_text=result["distance_text"],
            duration_seconds=result["duration_seconds"],
            duration_text=result["duration_text"],
            polyline=result.get("polyline"),
            start_address=result.get("start_address", ""),
            end_address=result.get("end_address", ""),
            steps=[RouteStep(**step) for step in result.get("steps", [])],
            source=result.get("source", "google_directions"),
        ).model_dump(),
        message="OK",
    )


@router.post("/route-eta-batch")
async def route_eta_batch_endpoint(request: dict):
    """Batch ETA calculation: one origin to many destinations (delivery

    boy route optimization across multiple shops).

    Body:
        origin: {"latitude": 25.59, "longitude": 85.13}
        destinations: [{"latitude": ..., "longitude": ...}, ...]
        mode: "driving" (optional)
    """
    origin = request.get("origin")
    destinations = request.get("destinations", [])

    if not origin or not isinstance(destinations, list) or not destinations:
        return error_response(
            message="Body must include 'origin' {'latitude','longitude'} and 'destinations' list.",
            error_code="INVALID_REQUEST",
            status_code=400,
        )

    try:
        o_lat = float(origin["latitude"])
        o_lng = float(origin["longitude"])
        dests = [
            (float(d["latitude"]), float(d["longitude"])) for d in destinations
        ]
    except (KeyError, ValueError, TypeError):
        return error_response(
            message="Invalid coordinates in origin/destinations.",
            error_code="INVALID_COORDINATES",
            status_code=400,
        )

    if not validate_coordinates(o_lat, o_lng) or any(
        not validate_coordinates(lat, lng) for lat, lng in dests
    ):
        return error_response(
            message="Invalid coordinates out of range.",
            error_code="INVALID_COORDINATES",
            status_code=400,
        )

    mode = request.get("mode", "driving")
    results = await get_delivery_eta_batch((o_lat, o_lng), dests, mode=mode)

    payload = []
    for i, r in enumerate(results):
        payload.append({
            "index": i,
            "destination": {"latitude": dests[i][0], "longitude": dests[i][1]},
            "distance_meters": r["distance_meters"],
            "distance_text": r["distance_text"],
            "duration_seconds": r["duration_seconds"],
            "duration_text": r["duration_text"],
            "source": r.get("source", "haversine_estimate"),
        })

    return success_response(data={"results": payload}, message="OK")


@router.post("/nearby-shops")
async def nearby_shops_endpoint(request: NearbyShopsRequest, db=Depends(get_async_db)):
    """Query active shops within X km radius using PostGIS ST_DWithin.

    Returns distance in meters, sorted by proximity. Results are cached
    in Redis for 5 minutes.

    Falls back to an in-application haversine scan (still correct, just
    slower than PostGIS when the extension is unavailable).
    """
    if not validate_coordinates(request.latitude, request.longitude):
        return error_response(
            message="Invalid coordinates.",
            error_code="INVALID_COORDINATES",
            status_code=400,
        )

    shops = await find_nearby_shops_postgis(
        db,
        request.latitude,
        request.longitude,
        radius_meters=request.radius_meters,
        limit=request.limit,
    )

    return success_response(
        data=NearbyShopsResponse(
            user_latitude=request.latitude,
            user_longitude=request.longitude,
            radius_meters=request.radius_meters,
            total=len(shops),
            shops=[NearbyShop(**s) for s in shops],
        ).model_dump(),
        message="OK",
    )


@router.post("/autocomplete")
async def autocomplete_endpoint(request: AutocompleteRequest):
    """Google Places Autocomplete suggestions with session token support."""
    session_token = request.session_token or uuid.uuid4().hex

    suggestions = await autocomplete_with_session(
        request.query,
        session_token=session_token,
        latitude=request.latitude,
        longitude=request.longitude,
        radius_meters=request.radius_meters,
    )

    return success_response(
        data=AutocompleteResponse(
            query=request.query,
            session_token=session_token,
            suggestions=[
                AutocompleteSuggestion(
                    place_id=s["place_id"],
                    main_text=s["main_text"],
                    secondary_text=s["secondary_text"],
                    types=s["types"],
                    session_token=session_token,
                )
                for s in suggestions
            ],
        ).model_dump(),
        message="OK",
    )


@router.post("/place/resolve")
async def place_resolve_endpoint(request: PlaceResolveRequest):
    """Resolve a Places API place_id to coordinates (concludes a session)."""
    session_token = request.session_token or uuid.uuid4().hex

    result = await resolve_place_with_session(request.place_id, session_token=session_token)
    if result is None:
        return error_response(
            message="Could not resolve place_id to coordinates.",
            error_code="PLACE_NOT_FOUND",
            status_code=404,
        )

    return success_response(
        data=PlaceResolveResponse(
            latitude=result["latitude"],
            longitude=result["longitude"],
            place_id=result["place_id"],
            session_token=result["session_token"],
        ).model_dump(),
        message="OK",
    )


@router.get("/health")
async def location_health():
    """Health probe for the location engine (no external calls)."""
    return success_response(
        data={
            "service": "geospatial-location-engine",
            "status": "ok",
        },
        message="OK",
    )