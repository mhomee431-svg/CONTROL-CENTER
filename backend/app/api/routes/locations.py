"""Location APIs: geocoding, autocomplete, directions, and shop discovery."""

from typing import Optional

from fastapi import APIRouter, Depends, Query

from app.core.responses import success_response, error_response
from app.database.session import get_db
from app.models.shop import Shop, ShopStatus
from app.schemas.location import (
    AutocompleteResponse,
    AutocompleteSuggestionResponse,
    DirectionsResponse,
    DirectionsStepResponse,
    DistanceMatrixElementResponse,
    DistanceMatrixResponse,
    ManualLocationSearchResponse,
    NearbyLocationResponse,
    NearbyShopLocationResponse,
    ReverseGeocodeResponse,
)
from app.services.geo_service import haversine_km, resolve_shop_coordinates
from app.services.location_service import (
    address_autocomplete,
    get_directions,
    get_distance_matrix,
    get_place_coordinates,
    reverse_geocode,
)
from app.services.pincode_service import lookup as resolve_pincode

router = APIRouter(prefix="/locations", tags=["locations"])


@router.get("/nearby")
async def get_nearby_locations(
    latitude: float = Query(..., ge=-90, le=90, description="User latitude"),
    longitude: float = Query(..., ge=-180, le=180, description="User longitude"),
    radius_km: float = Query(5.0, gt=0, le=100, description="Search radius in km"),
    include_eta: bool = Query(False, description="Include ETA via Distance Matrix API"),
    db=Depends(get_db),
):
    """Return active shops within the given radius of the user's location."""
    shops = db.query(Shop).all()
    nearby = []
    for shop in shops:

        # Visibility contract matches the other nearby endpoints: only live,
        # verified, order-accepting shops may appear in discovery results.

        if (
            getattr(shop, "is_deleted", False)
            or getattr(shop, "status", None) not in (
                ShopStatus.ACTIVE,
                ShopStatus.VERIFIED,
            )
            or not getattr(shop, "is_verified", False)
            or not getattr(shop, "is_accepting_orders", True)
        ):
            continue
        # Coordinates are resolved via the shared PostGIS/EWKB/fallback helper;

        
        shop_longitude, shop_latitude = resolve_shop_coordinates(shop)
        if shop_longitude is None or shop_latitude is None:

            continue
        distance = haversine_km(latitude, longitude, shop_latitude, shop_longitude)
        if distance <= radius_km:

            address = None
            try:
                addr_list = getattr(shop, "addresses", None) or []
                address = addr_list[0].address_line1 if addr_list else getattr(shop, "address", None)
            except Exception:  # noqa: BLE001 - never fail nearby results on a bad address
                address = None
            nearby.append(
                NearbyShopLocationResponse(
                    shop_id=shop.id,
                    shop_name=shop.name,
                    distance_km=round(distance, 2),
                    latitude=shop_latitude,
                    longitude=shop_longitude,
                    address=address,
                )
            )

    nearby.sort(key=lambda s: s.distance_km)

    # Optionally enrich with live ETA from Distance Matrix API
    if include_eta and nearby:
        origins = [(latitude, longitude)]
        destinations = [(s.latitude, s.longitude) for s in nearby]
        matrix = await get_distance_matrix(origins, destinations)
        if matrix and matrix[0]:
            for i, result in enumerate(matrix[0]):
                if i < len(nearby) and result.duration_seconds > 0:
                    nearby[i].eta_text = result.duration_text
                    nearby[i].eta_seconds = result.duration_seconds

    return success_response(
        data=NearbyLocationResponse(
            user_lat=latitude,
            user_lng=longitude,
            radius_km=radius_km,
            shops=nearby,
        ).model_dump()
    )


@router.get("/manual-search")
def search_manual_locations(
    q: str = Query(..., min_length=1, max_length=100),
):
    """Search manual city locations (mock data for Phase 13; replace with Places API later)."""
    mock_cities = [
        {"city": "Patna", "state": "Bihar", "pincode": "800001", "latitude": 25.5941, "longitude": 85.1376},
        {"city": "Gaya", "state": "Bihar", "pincode": "823001", "latitude": 24.7914, "longitude": 85.0002},
        {"city": "Muzaffarpur", "state": "Bihar", "pincode": "842001", "latitude": 26.1209, "longitude": 85.3647},
    ]
    results = [c for c in mock_cities if q.lower() in c["city"].lower()]
    return success_response(data=[ManualLocationSearchResponse(**c).model_dump() for c in results])


@router.get("/pincode/{pincode}")
async def lookup_pincode(pincode: str):
    """Resolve a 6-digit Indian pincode to city + state (live).

    Primary: PostPin API. Fallback: Google Maps Geocoding.
    """
    info = resolve_pincode(pincode)
    if info is None:
        return error_response(
            message="Could not resolve pincode. Enter city & state manually.",
            error_code="PINCODE_NOT_FOUND",
            status_code=404,
        )
    return success_response(
        data={"pincode": info.pincode, "city": info.city, "state": info.state},
        message="OK",
    )


@router.get("/reverse-geocode")
async def reverse_geocode_endpoint(
    latitude: float = Query(..., ge=-90, le=90, description="Latitude"),
    longitude: float = Query(..., ge=-180, le=180, description="Longitude"),
):
    """Convert lat/lng coordinates into a structured address.

    Uses Google Maps Geocoding API. Requires GOOGLE_MAPS_API_KEY.
    """
    result = await reverse_geocode(latitude, longitude)
    if result is None:
        return error_response(
            message="Could not resolve coordinates to an address. Check GOOGLE_MAPS_API_KEY.",
            error_code="REVERSE_GEOCODE_FAILED",
            status_code=404,
        )
    return success_response(
        data=ReverseGeocodeResponse(
            formatted_address=result.formatted_address,
            street_number=result.street_number,
            route=result.route,
            locality=result.locality,
            district=result.district,
            state=result.state,
            pincode=result.pincode,
            country=result.country,
            latitude=result.latitude,
            longitude=result.longitude,
            place_id=result.place_id,
        ).model_dump(),
        message="OK",
    )


@router.get("/autocomplete")
async def autocomplete_endpoint(
    q: str = Query(..., min_length=2, max_length=200, description="Partial address query"),
    latitude: Optional[float] = Query(None, ge=-90, le=90, description="Optional bias latitude"),
    longitude: Optional[float] = Query(None, ge=-180, le=180, description="Optional bias longitude"),
    radius: int = Query(50000, ge=1000, le=200000, description="Bias radius in meters"),
):
    """Return Places API address autocomplete suggestions.

    Optionally biased toward a (lat, lng) position for relevance.
    """
    bias = (latitude, longitude) if latitude is not None and longitude is not None else None
    suggestions = await address_autocomplete(q, location_bias=bias, radius_meters=radius)
    return success_response(
        data=AutocompleteResponse(
            query=q,
            suggestions=[
                AutocompleteSuggestionResponse(
                    place_id=s.place_id,
                    main_text=s.main_text,
                    secondary_text=s.secondary_text,
                    types=s.types,
                )
                for s in suggestions
            ],
        ).model_dump(),
        message="OK",
    )


@router.get("/place-coordinates")
async def place_coordinates_endpoint(
    place_id: str = Query(..., min_length=1, description="Google Places API place_id"),
):
    """Resolve a Places API place_id to coordinates."""
    coords = await get_place_coordinates(place_id)
    if coords is None:
        return error_response(
            message="Could not resolve place_id to coordinates.",
            error_code="PLACE_NOT_FOUND",
            status_code=404,
        )
    return success_response(
        data={"latitude": coords[0], "longitude": coords[1], "place_id": place_id},
        message="OK",
    )


@router.get("/directions")
async def directions_endpoint(
    origin_lat: float = Query(..., ge=-90, le=90, description="Origin latitude"),
    origin_lng: float = Query(..., ge=-180, le=180, description="Origin longitude"),
    dest_lat: float = Query(..., ge=-90, le=90, description="Destination latitude"),
    dest_lng: float = Query(..., ge=-180, le=180, description="Destination longitude"),
    mode: str = Query("driving", description="Travel mode: driving, walking, bicycling, transit"),
):
    """Get route polyline, distance, and ETA between two coordinates.

    Uses Google Maps Directions API with live traffic when available.
    """
    result = await get_directions(origin_lat, origin_lng, dest_lat, dest_lng, mode=mode)
    if result is None:
        return error_response(
            message="Could not compute directions. Check GOOGLE_MAPS_API_KEY or coordinates.",
            error_code="DIRECTIONS_FAILED",
            status_code=404,
        )
    return success_response(
        data=DirectionsResponse(
            distance_meters=result.distance_meters,
            distance_text=result.distance_text,
            duration_seconds=result.duration_seconds,
            duration_text=result.duration_text,
            polyline=result.polyline,
            start_address=result.start_address,
            end_address=result.end_address,
            steps=[
                DirectionsStepResponse(
                    distance=step["distance"],
                    duration=step["duration"],
                    instruction=step["instruction"],
                    mode=step["mode"],
                )
                for step in result.steps
            ],
        ).model_dump(),
        message="OK",
    )


@router.get("/distance-matrix")
async def distance_matrix_endpoint(
    origins: str = Query(..., description="Semicolon-separated lat,lng pairs"),
    destinations: str = Query(..., description="Semicolon-separated lat,lng pairs"),
    mode: str = Query("driving", description="Travel mode"),
):
    """Compute driving distance and duration for multiple origin-destination pairs.

    Useful for delivery route optimization against multiple shops.
    Format: origins=lat1,lng1;lat2,lng2 destinations=lat1,lng1;lat2,lng2
    """
    try:
        origin_pairs = [tuple(float(c) for c in pair.split(",")) for pair in origins.split(";")]
        dest_pairs = [tuple(float(c) for c in pair.split(",")) for pair in destinations.split(";")]
    except (ValueError, AttributeError):
        return error_response(
            message="Invalid coordinate format. Use 'lat,lng;lat,lng' semicolon-separated pairs.",
            error_code="INVALID_COORDINATES",
            status_code=400,
        )
    results = await get_distance_matrix(origin_pairs, dest_pairs, mode=mode)
    if not results:
        return error_response(
            message="Distance matrix computation failed.",
            error_code="DISTANCE_MATRIX_FAILED",
            status_code=502,
        )
    origin_addresses = []
    dest_addresses = []
    rows_data = []
    for row in results:
        row_data = []
        for elem in row:
            if elem.origin_address and elem.origin_address not in origin_addresses:
                origin_addresses.append(elem.origin_address)
            if elem.destination_address and elem.destination_address not in dest_addresses:
                dest_addresses.append(elem.destination_address)
            row_data.append(
                DistanceMatrixElementResponse(
                    origin_address=elem.origin_address,
                    destination_address=elem.destination_address,
                    distance_meters=elem.distance_meters,
                    distance_text=elem.distance_text,
                    duration_seconds=elem.duration_seconds,
                    duration_text=elem.duration_text,
                )
            )
        rows_data.append(row_data)
    return success_response(
        data=DistanceMatrixResponse(
            origins=origin_addresses,
            destinations=dest_addresses,
            rows=rows_data,
        ).model_dump(),
        message="OK",
    )


def _extract_coords_from_location(shop: Shop) -> tuple[float | None, float | None]:
    """
    Extract (longitude, latitude) from a PostGIS Geography POINT field.


    For-machine-compatibility (and to keep existing imports working) this
    wraps [resolve_shop_coordinates], which handles WKT, EWKB hex blobs,
    bytes, and the scalar latitude/longitude template columns.



    """
    return resolve_shop_coordinates(shop)
