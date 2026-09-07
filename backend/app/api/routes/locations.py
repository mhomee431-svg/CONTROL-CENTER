"""Location APIs: nearby shops within a radius and manual location search."""

from fastapi import APIRouter, Depends, Query

from app.core.responses import success_response, error_response
from app.database.session import get_db
from app.models.shop import Shop, ShopStatus
from app.schemas.location import (
    ManualLocationSearchResponse,
    NearbyLocationResponse,
    NearbyShopLocationResponse,
)
from app.services.geo_service import haversine_km, resolve_shop_coordinates
from app.services.pincode_service import lookup as resolve_pincode

router = APIRouter(prefix="/locations", tags=["locations"])


@router.get("/nearby")
async def get_nearby_locations(
    latitude: float = Query(..., ge=-90, le=90, description="User latitude"),
    longitude: float = Query(..., ge=-180, le=180, description="User longitude"),
    radius_km: float = Query(5.0, gt=0, le=100, description="Search radius in km"),
    db: Session = Depends(get_db),
):
    """Return the live, verified shops within the given radius of the user's location."""
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


def _extract_coords_from_location(shop: Shop) -> tuple[float | None, float | None]:
    """
    Extract (longitude, latitude) from a PostGIS Geography POINT field.


    For-machine-compatibility (and to keep existing imports working) this
    wraps [resolve_shop_coordinates], which handles WKT, EWKB hex blobs,
    bytes, and the scalar latitude/longitude template columns.



    """
    return resolve_shop_coordinates(shop)
