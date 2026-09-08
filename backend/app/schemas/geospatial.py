"""Request/response schemas for the high-precision geospatial location API."""

from typing import List, Optional

from pydantic import BaseModel, Field


class ReverseGeocodeRequest(BaseModel):
    """Convert lat/lng to structured address."""
    latitude: float = Field(..., ge=-90, le=90, description="Latitude (WGS84)")
    longitude: float = Field(..., ge=-180, le=180, description="Longitude (WGS84)")


class AddressComponent(BaseModel):
    """A structured address component."""
    house_number: Optional[str] = None
    street: Optional[str] = None
    landmark: Optional[str] = None
    area: Optional[str] = None
    city: Optional[str] = None
    state: Optional[str] = None
    pincode: Optional[str] = None
    country: Optional[str] = None


class ReverseGeocodeResponse(BaseModel):
    latitude: float
    longitude: float
    formatted_address: str
    address: AddressComponent
    place_id: Optional[str] = None


class NearbyShopsRequest(BaseModel):
    """Find shops within a radius."""
    latitude: float = Field(..., ge=-90, le=90)
    longitude: float = Field(..., ge=-180, le=180)
    radius_meters: float = Field(5000.0, gt=0, le=25000, description="Search radius in meters")
    limit: int = Field(50, ge=1, le=100)


class NearbyShop(BaseModel):
    shop_id: int
    shop_name: str
    slug: Optional[str] = None
    rating: float = 0.0
    review_count: int = 0
    is_accepting_orders: bool = True
    is_verified: bool = False
    latitude: float
    longitude: float
    distance_meters: float
    distance_km: float


class NearbyShopsResponse(BaseModel):
    user_latitude: float
    user_longitude: float
    radius_meters: float
    total: int
    shops: List[NearbyShop] = []


class RouteEtaRequest(BaseModel):
    """Route and ETA between origin and destination."""
    origin_latitude: float = Field(..., ge=-90, le=90)
    origin_longitude: float = Field(..., ge=-180, le=180)
    dest_latitude: float = Field(..., ge=-90, le=90)
    dest_longitude: float = Field(..., ge=-180, le=180)
    mode: str = Field("driving", pattern="^(driving|walking|bicycling|transit)$")


class RouteStep(BaseModel):
    distance: str
    duration: str
    instruction: str
    mode: str


class RouteEtaResponse(BaseModel):
    distance_meters: int
    distance_text: str
    duration_seconds: int
    duration_text: str
    polyline: Optional[str] = None
    start_address: str = ""
    end_address: str = ""
    steps: List[RouteStep] = []
    source: str = "google_directions"


class AutocompleteRequest(BaseModel):
    query: str = Field(..., min_length=2, max_length=200)
    session_token: Optional[str] = Field(None, max_length=64)
    latitude: Optional[float] = Field(None, ge=-90, le=90)
    longitude: Optional[float] = Field(None, ge=-180, le=180)
    radius_meters: int = Field(50000, ge=1000, le=200000)


class AutocompleteSuggestion(BaseModel):
    place_id: str
    main_text: str
    secondary_text: str
    types: List[str] = []
    session_token: Optional[str] = None


class AutocompleteResponse(BaseModel):
    query: str
    session_token: Optional[str] = None
    suggestions: List[AutocompleteSuggestion] = []


class PlaceResolveRequest(BaseModel):
    place_id: str = Field(..., min_length=1)
    session_token: Optional[str] = Field(None, max_length=64)


class PlaceResolveResponse(BaseModel):
    latitude: float
    longitude: float
    place_id: str
    session_token: Optional[str] = None