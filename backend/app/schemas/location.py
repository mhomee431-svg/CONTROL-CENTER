from typing import List, Optional
from pydantic import BaseModel


class NearbyLocationRequest(BaseModel):
    latitude: float
    longitude: float
    radius_km: float = 5.0


class NearbyShopLocationResponse(BaseModel):
    shop_id: int
    shop_name: str
    distance_km: float
    latitude: float
    longitude: float
    address: str | None = None
    eta_text: str | None = None
    eta_seconds: int | None = None


class NearbyLocationResponse(BaseModel):
    user_lat: float
    user_lng: float
    radius_km: float
    shops: List[NearbyShopLocationResponse] = []


class ManualLocationSearchResponse(BaseModel):
    city: str
    state: str
    pincode: str
    latitude: float
    longitude: float
    is_manual: bool = True


class ReverseGeocodeResponse(BaseModel):
    """Structured address from lat/lng reverse geocoding."""
    formatted_address: str
    street_number: str | None = None
    route: str | None = None
    locality: str | None = None
    district: str | None = None
    state: str | None = None
    pincode: str | None = None
    country: str | None = None
    latitude: float | None = None
    longitude: float | None = None
    place_id: str | None = None


class AutocompleteSuggestionResponse(BaseModel):
    """A single Places API suggestion."""
    place_id: str
    main_text: str
    secondary_text: str
    types: List[str] = []


class AutocompleteResponse(BaseModel):
    """Address autocomplete results."""
    query: str
    suggestions: List[AutocompleteSuggestionResponse] = []


class DirectionsStepResponse(BaseModel):
    distance: str
    duration: str
    instruction: str
    mode: str


class DirectionsResponse(BaseModel):
    """Route and ETA between two points."""
    distance_meters: int
    distance_text: str
    duration_seconds: int
    duration_text: str
    polyline: str | None = None
    start_address: str
    end_address: str
    steps: List[DirectionsStepResponse] = []


class DistanceMatrixElementResponse(BaseModel):
    origin_address: str
    destination_address: str
    distance_meters: int
    distance_text: str
    duration_seconds: int
    duration_text: str


class DistanceMatrixResponse(BaseModel):
    """Multi-origin/multi-destination distance and duration."""
    origins: List[str] = []
    destinations: List[str] = []
    rows: List[List[DistanceMatrixElementResponse]] = []
