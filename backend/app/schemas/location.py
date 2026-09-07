from typing import List
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