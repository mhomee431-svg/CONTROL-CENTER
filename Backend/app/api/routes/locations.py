from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session

from app.core.responses import success_response
from app.database.session import get_db
from app.models.shop import Shop
from app.schemas.location import (
    ManualLocationSearchResponse,
    NearbyLocationResponse,
    NearbyShopLocationResponse,
)
from app.services.geo_service import haversine_km

router = APIRouter(prefix="/locations", tags=["locations"])


@router.get("/nearby")
async def get_nearby_locations(
    latitude: float = Query(..., ge=-90, le=90, description="User latitude"),
    longitude: float = Query(..., ge=-180, le=180, description="User longitude"),
    radius_km: float = Query(5.0, gt=0, le=100, description="Search radius in km"),
    db: Session = Depends(get_db),
):
    """Return all shops within the given radius of the user's location."""
    shops = db.query(Shop).all()
    nearby = []
    for shop in shops:
        # NOTE: shop.location is now a PostGIS Geography POINT.
        # Distance is computed via PostGIS ST_Distance in a later phase.
        # For now, resolve coordinates from WKT and use haversine.
        shop_longitude, shop_latitude = _extract_coords_from_location(shop)
        if shop_longitude is None or shop_latitude is None:
            continue
        distance = haversine_km(latitude, longitude, shop_latitude, shop_longitude)
        if distance <= radius_km:
            nearby.append(
                NearbyShopLocationResponse(
                    shop_id=shop.id,
                    shop_name=shop.name,
                    distance_km=round(distance, 2),
                    latitude=shop_latitude,
                    longitude=shop_longitude,
                    address=(shop.addresses[0].address_line1 if shop.addresses else None),
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


def _extract_coords_from_location(shop: Shop) -> tuple[float | None, float | None]:
    """
    Extract (longitude, latitude) from a PostGIS Geography POINT field.

    The WKT format is 'POINT(lon lat)'. Falls back to the scalar template
    `latitude` / `longitude` columns when the geometry column is not hydrated
    (e.g. projection-less sessions). Returns (None, None) if both are absent.
    """
    try:
        raw = str(shop.location)
        # WKT like: 'POINT(85.1376 25.5941)' or '0101000020E610...' (hex EWKB)
        if raw.startswith("POINT"):
            inner = raw[6:-1].strip()  # strip "POINT(" and ")"
            parts = inner.split()
            if len(parts) == 2:
                return float(parts[0]), float(parts[1])
    except (ValueError, TypeError, IndexError):
        pass

    # Fallback: scalar latitude/longitude template columns.
    if getattr(shop, "latitude", None) is not None and getattr(
        shop, "longitude", None
    ) is not None:
        return shop.longitude, shop.latitude
    return None, None