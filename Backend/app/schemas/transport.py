"""Transport & Personal Transport Booking schemas — Master Spec §28-§29."""
from __future__ import annotations

from datetime import date, datetime
from typing import Optional
from pydantic import BaseModel, Field, ConfigDict


# ── Transport Provider ─────────────────────────────────────────────────────
class TransportProviderCreate(BaseModel):
    company_name: str = Field(..., min_length=1, max_length=255)
    license_number: Optional[str] = Field(None, max_length=100)
    shop_id: Optional[int] = None
    service_area_id: Optional[int] = None


class TransportProviderResponse(BaseModel):
    id: int
    user_id: int
    shop_id: Optional[int] = None
    company_name: str
    license_number: Optional[str] = None
    verification_status: str
    service_area_id: Optional[int] = None
    rating: float = 0.0
    review_count: int = 0
    is_active: bool
    created_at: datetime
    updated_at: datetime

    model_config = ConfigDict(from_attributes=True)


# ── Vehicle ────────────────────────────────────────────────────────────────
class VehicleCreate(BaseModel):
    vehicle_type: str = Field(..., description="SEDAN, SUV, HATCHBACK, MPV, BIKE, SCOOTER, TEMPO, MINI_BUS, BUS, VAN")
    make: Optional[str] = Field(None, max_length=100)
    model: Optional[str] = Field(None, max_length=100)
    year: Optional[int] = Field(None, ge=1900, le=2100)
    registration_number: str = Field(..., max_length=30)
    capacity_passengers: int = Field(4, ge=1)
    capacity_luggage_kg: Optional[float] = Field(None, ge=0)
    ac_available: bool = True
    fuel_type: Optional[str] = Field(None, max_length=20)
    color: Optional[str] = Field(None, max_length=30)
    interior_photo_url: Optional[str] = Field(None, max_length=500)
    exterior_photo_url: Optional[str] = Field(None, max_length=500)


class VehicleResponse(BaseModel):
    id: int
    provider_id: int
    vehicle_type: str
    make: Optional[str] = None
    model: Optional[str] = None
    year: Optional[int] = None
    registration_number: str
    capacity_passengers: int
    capacity_luggage_kg: Optional[float] = None
    ac_available: bool
    fuel_type: Optional[str] = None
    color: Optional[str] = None
    interior_photo_url: Optional[str] = None
    exterior_photo_url: Optional[str] = None
    is_active: bool
    created_at: datetime
    updated_at: datetime

    model_config = ConfigDict(from_attributes=True)


# ── Transport Service ──────────────────────────────────────────────────────
class TransportServiceCreate(BaseModel):
    service_type: str = Field(..., description="MARRIAGE, FAMILY_TOUR, PERSONAL_TRAVEL, LOCAL_TRAVEL, EVENT_TRAVEL, AIRPORT, WEDDING, OTHER")
    name: str = Field(..., min_length=1, max_length=255)
    description: Optional[str] = None
    base_price: float = Field(0, ge=0)
    price_unit: str = Field("QUOTE", description="PER_DAY, PER_KM, PER_TRIP, PER_HOUR, QUOTE")
    min_duration_days: int = Field(1, ge=1)


class TransportServiceResponse(BaseModel):
    id: int
    provider_id: int
    service_type: str
    name: str
    description: Optional[str] = None
    base_price: float
    price_unit: str
    min_duration_days: int
    is_active: bool
    created_at: datetime
    updated_at: datetime

    model_config = ConfigDict(from_attributes=True)


# ── Vehicle Availability ───────────────────────────────────────────────────
class VehicleAvailabilityCreate(BaseModel):
    vehicle_id: int
    available_from: date
    available_to: date
    status: str = Field("AVAILABLE", description="AVAILABLE, BOOKED, MAINTENANCE")


# ── Transport Quote ────────────────────────────────────────────────────────
class TransportQuoteCreate(BaseModel):
    provider_id: int
    vehicle_id: Optional[int] = None
    trip_purpose: str = Field(..., description="MARRIAGE, FAMILY_TOUR, PERSONAL_TRAVEL, LOCAL_TRAVEL, EVENT_TRAVEL, OTHER")
    pickup_address: str = Field(..., min_length=1)
    destination_address: str = Field(..., min_length=1)
    pickup_lat: Optional[float] = Field(None, ge=-90, le=90)
    pickup_lng: Optional[float] = Field(None, ge=-180, le=180)
    trip_date: date
    trip_days: int = Field(1, ge=1)
    passenger_count: int = Field(1, ge=1)
    notes: Optional[str] = None


class TransportQuoteResponse(BaseModel):
    id: int
    provider_id: int
    vehicle_id: Optional[int] = None
    customer_user_id: int
    requested_by: int
    trip_purpose: str
    pickup_address: str
    destination_address: str
    pickup_lat: Optional[float] = None
    pickup_lng: Optional[float] = None
    trip_date: date
    trip_days: int
    passenger_count: int
    quote_amount: float
    currency: str
    status: str
    notes: Optional[str] = None
    created_at: datetime
    updated_at: datetime

    model_config = ConfigDict(from_attributes=True)


# ── Transport Booking ──────────────────────────────────────────────────────
class TransportBookingResponse(BaseModel):
    id: int
    quote_id: int
    customer_user_id: int
    provider_id: int
    vehicle_id: int
    status: str
    booking_ref: str
    pickup_address: str
    destination: str
    pickup_lat: Optional[float] = None
    pickup_lng: Optional[float] = None
    trip_date: date
    trip_days: int
    passenger_count: int
    agreed_amount: float
    currency: str
    notes: Optional[str] = None
    confirmed_by: Optional[int] = None
    confirmed_at: Optional[date] = None
    cancelled_at: Optional[date] = None
    cancel_reason: Optional[str] = None
    created_at: datetime
    updated_at: datetime

    model_config = ConfigDict(from_attributes=True)


# ── Booking Status Update ──────────────────────────────────────────────────
class BookingStatusUpdate(BaseModel):
    status: str = Field(..., description="PENDING, CONFIRMED, IN_PROGRESS, COMPLETED, CANCELLED")
    note: Optional[str] = None
