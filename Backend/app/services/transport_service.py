"""Transport & Personal Transport Booking service — Master Spec §28-§29."""

import secrets
import string
from datetime import date, datetime, timezone
from typing import Optional

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.logging import get_logger
from app.models.shop import ShopOwner
from app.models.service_area import ServiceArea
from app.models.transport import (
    TransportProvider,
    Vehicle,
    TransportService,
    VehicleAvailability,
    TransportQuote,
    TransportBooking,
    BookingStatusHistory,
)
from app.schemas.transport import (
    TransportProviderCreate,
    VehicleCreate,
    TransportServiceCreate,
    TransportQuoteCreate,
    BookingStatusUpdate,
)
from app.services.geo_service import haversine_km

logger = get_logger("app.services.transport")


def _resolve_service_area_center(service_area: ServiceArea | None) -> tuple[float | None, float | None]:
    """Return (latitude, longitude) from a service area's center geography column.

    Resolves the PostGIS EWKB/WKB/WKT payload the same way the shop coordinate
    helpers do, falling back to None when the area has no center point.
    """
    if service_area is None or service_area.center is None:
        return None, None
    center = service_area.center
    # GeoAlchemy2 WKBElement — duck-typed to avoid a hard import.
    data_attr = getattr(center, "data", None)
    raw = None
    if data_attr is not None:
        raw = bytes(data_attr)
    elif isinstance(center, (bytes, bytearray)):
        raw = bytes(center)
    else:
        s = str(center).strip()
        if s.upper().startswith("POINT"):
            try:
                inner = s[6:-1].strip() if s.endswith(")") else s[5:].strip().rstrip(")")
                parts = inner.split()
                if len(parts) == 2:
                    return float(parts[1]), float(parts[0])  # lat, lon (POINT is lon lat)
            except (ValueError, TypeError, IndexError):
                return None, None
        elif len(s) > 8:
            try:
                raw = bytes.fromhex(s.replace(" ", ""))
            except (ValueError, TypeError):
                return None, None
    if raw:
        from app.services.geo_service import _parse_wkb_point
        parsed = _parse_wkb_point(raw)
        if parsed:
            return parsed[1], parsed[0]  # (lon, lat) -> (lat, lon)
    return None, None


def _generate_booking_ref() -> str:
    """Generate a unique booking reference (e.g. TRB-A1B2C3D4)."""
    chars = string.ascii_uppercase + string.digits
    return "TRB-" + "".join(secrets.choice(chars) for _ in range(8))


def _get_provider_for_user(db: Session, user_id: int) -> TransportProvider:
    """Get transport provider for a user, raising PermissionError if not found."""
    provider = (
        db.execute(select(TransportProvider).where(TransportProvider.user_id == user_id))
        .scalars()
        .first()
    )
    if not provider:
        raise PermissionError("You are not registered as a transport provider")
    return provider


def search_providers(
    db: Session,
    latitude: float,
    longitude: float,
    radius_km: float = 10.0,
    service_type: Optional[str] = None,
) -> list[dict]:
    """Find transport providers within radius."""
    stmt = select(TransportProvider).where(
        TransportProvider.is_active == True,  # noqa: E712
        TransportProvider.is_deleted == False,  # noqa: E712
        TransportProvider.verification_status == "VERIFIED",
    )
    providers = db.execute(stmt).scalars().all()

    results = []
    for provider in providers:
        # Dynamic distance from the customer to the provider's service-area center.
        service_area = (
            db.get(ServiceArea, provider.service_area_id)
            if provider.service_area_id
            else None
        )
        area_lat, area_lon = _resolve_service_area_center(service_area)
        if area_lat is None or area_lon is None:
            continue
        dist = haversine_km(latitude, longitude, area_lat, area_lon)
        if dist > radius_km:
            continue
        if service_type:
            has_service = any(
                s.service_type == service_type and s.is_active
                for s in provider.services
            )
            if not has_service:
                continue

        available_vehicles = sum(
            1 for v in provider.vehicles if v.is_active and not v.is_deleted
        )
        results.append({
            "id": provider.id,
            "company_name": provider.company_name,
            "rating": float(provider.rating),
            "review_count": provider.review_count,
            "verification_status": provider.verification_status,
            "available_vehicles": available_vehicles,
            "service_types": [s.service_type for s in provider.services if s.is_active],
            "distance_km": round(dist, 2),
        })

    results.sort(key=lambda x: x["distance_km"])
    return results


def get_provider_detail(db: Session, provider_id: int) -> Optional[dict]:
    """Get provider detail with vehicles and services."""
    provider = db.get(TransportProvider, provider_id)
    if not provider or provider.is_deleted:
        return None

    return {
        "id": provider.id,
        "company_name": provider.company_name,
        "license_number": provider.license_number,
        "verification_status": provider.verification_status,
        "rating": float(provider.rating),
        "review_count": provider.review_count,
        "is_active": provider.is_active,
        "vehicles": [
            {
                "id": v.id,
                "vehicle_type": v.vehicle_type,
                "make": v.make,
                "model": v.model,
                "registration_number": v.registration_number,
                "capacity_passengers": v.capacity_passengers,
                "ac_available": v.ac_available,
                "is_active": v.is_active,
            }
            for v in provider.vehicles if not v.is_deleted
        ],
        "services": [
            {
                "id": s.id,
                "service_type": s.service_type,
                "name": s.name,
                "base_price": float(s.base_price),
                "price_unit": s.price_unit,
                "is_active": s.is_active,
            }
            for s in provider.services if not s.is_deleted
        ],
    }

def get_vehicle_detail(db: Session, vehicle_id: int) -> Optional[dict]:
    """Get vehicle detail with availability."""
    vehicle = db.get(Vehicle, vehicle_id)
    if not vehicle or vehicle.is_deleted:
        return None

    today = date.today()
    availability = (
        db.execute(
            select(VehicleAvailability)
            .where(
                VehicleAvailability.vehicle_id == vehicle_id,
                VehicleAvailability.available_to >= today,
            )
            .order_by(VehicleAvailability.available_from)
            .limit(30)
        )
        .scalars()
        .all()
    )

    return {
        "id": vehicle.id,
        "vehicle_type": vehicle.vehicle_type,
        "make": vehicle.make,
        "model": vehicle.model,
        "year": vehicle.year,
        "registration_number": vehicle.registration_number,
        "capacity_passengers": vehicle.capacity_passengers,
        "capacity_luggage_kg": float(vehicle.capacity_luggage_kg) if vehicle.capacity_luggage_kg else None,
        "ac_available": vehicle.ac_available,
        "fuel_type": vehicle.fuel_type,
        "color": vehicle.color,
        "is_active": vehicle.is_active,
        "availability": [
            {
                "from": str(a.available_from),
                "to": str(a.available_to),
                "status": a.status,
            }
            for a in availability
        ],
    }


def register_provider(db: Session, user_id: int, data: TransportProviderCreate) -> TransportProvider:
    """Register as a transport provider."""
    existing = (
        db.execute(select(TransportProvider).where(TransportProvider.user_id == user_id))
        .scalars()
        .first()
    )
    if existing:
        raise ValueError("You are already registered as a transport provider")

    provider = TransportProvider(
        user_id=user_id,
        shop_id=data.shop_id,
        company_name=data.company_name,
        license_number=data.license_number,
        service_area_id=data.service_area_id,
    )
    db.add(provider)
    db.commit()
    db.refresh(provider)
    return provider


def add_vehicle(db: Session, user_id: int, data: VehicleCreate) -> Vehicle:
    """Add a vehicle to provider fleet (provider only)."""
    provider = _get_provider_for_user(db, user_id)

    existing = (
        db.execute(
            select(Vehicle).where(Vehicle.registration_number == data.registration_number)
        )
        .scalars()
        .first()
    )
    if existing:
        raise ValueError("Vehicle with this registration number already exists")

    vehicle = Vehicle(
        provider_id=provider.id,
        vehicle_type=data.vehicle_type,
        make=data.make,
        model=data.model,
        year=data.year,
        registration_number=data.registration_number,
        capacity_passengers=data.capacity_passengers,
        capacity_luggage_kg=data.capacity_luggage_kg,
        ac_available=data.ac_available,
        fuel_type=data.fuel_type,
        color=data.color,
        interior_photo_url=data.interior_photo_url,
        exterior_photo_url=data.exterior_photo_url,
    )
    db.add(vehicle)
    db.commit()
    db.refresh(vehicle)
    return vehicle


def add_service(db: Session, user_id: int, data: TransportServiceCreate) -> TransportService:
    """Add a transport service (provider only)."""
    provider = _get_provider_for_user(db, user_id)

    service = TransportService(
        provider_id=provider.id,
        service_type=data.service_type,
        name=data.name,
        description=data.description,
        base_price=data.base_price,
        price_unit=data.price_unit,
        min_duration_days=data.min_duration_days,
    )
    db.add(service)
    db.commit()
    db.refresh(service)
    return service

def request_quote(db: Session, user_id: int, data: TransportQuoteCreate) -> TransportQuote:
    """Customer requests a quote from a transport provider."""
    provider = db.get(TransportProvider, data.provider_id)
    if not provider or provider.is_deleted:
        raise ValueError("Transport provider not found")

    if data.vehicle_id:
        vehicle = db.get(Vehicle, data.vehicle_id)
        if not vehicle or vehicle.is_deleted:
            raise ValueError("Vehicle not found")

    quote = TransportQuote(
        provider_id=data.provider_id,
        vehicle_id=data.vehicle_id,
        customer_user_id=user_id,
        requested_by=user_id,
        trip_purpose=data.trip_purpose,
        pickup_address=data.pickup_address,
        destination_address=data.destination_address,
        pickup_lat=data.pickup_lat,
        pickup_lng=data.pickup_lng,
        trip_date=data.trip_date,
        trip_days=data.trip_days,
        passenger_count=data.passenger_count,
        notes=data.notes,
    )
    db.add(quote)
    db.commit()
    db.refresh(quote)
    return quote


def respond_to_quote(
    db: Session, user_id: int, quote_id: int, quote_amount: float, notes: Optional[str] = None
) -> Optional[TransportQuote]:
    """Provider responds to a quote request with a price."""
    quote = db.get(TransportQuote, quote_id)
    if not quote:
        return None

    if quote.provider.user_id != user_id:
        raise PermissionError("You are not the provider for this quote")

    if quote.status != "REQUESTED":
        raise ValueError("Quote has already been responded to")

    quote.quote_amount = quote_amount
    quote.status = "QUOTED"
    if notes:
        quote.notes = notes

    db.commit()
    db.refresh(quote)
    return quote


def accept_quote(db: Session, user_id: int, quote_id: int) -> Optional[TransportBooking]:
    """Customer accepts a quote, creating a booking."""
    quote = db.get(TransportQuote, quote_id)
    if not quote:
        return None

    if quote.customer_user_id != user_id:
        raise PermissionError("You are not the customer for this quote")

    if quote.status != "QUOTED":
        raise ValueError("Quote is not in QUOTED status")

    quote.status = "ACCEPTED"

    booking = TransportBooking(
        quote_id=quote.id,
        customer_user_id=quote.customer_user_id,
        provider_id=quote.provider_id,
        vehicle_id=quote.vehicle_id,
        booking_ref=_generate_booking_ref(),
        pickup_address=quote.pickup_address,
        destination=quote.destination_address,
        pickup_lat=quote.pickup_lat,
        pickup_lng=quote.pickup_lng,
        trip_date=quote.trip_date,
        trip_days=quote.trip_days,
        passenger_count=quote.passenger_count,
        agreed_amount=quote.quote_amount,
        currency=quote.currency,
    )
    db.add(booking)

    status_history = BookingStatusHistory(
        booking=booking,
        from_status=None,
        to_status="PENDING",
        changed_by=user_id,
        changed_at=date.today(),
    )
    db.add(status_history)

    db.commit()
    db.refresh(booking)
    return booking

def get_user_bookings(
    db: Session, user_id: int, status: Optional[str] = None
) -> list[TransportBooking]:
    """Get current user transport bookings."""
    stmt = select(TransportBooking).where(
        TransportBooking.customer_user_id == user_id
    )
    if status:
        stmt = stmt.where(TransportBooking.status == status)
    stmt = stmt.order_by(TransportBooking.created_at.desc())
    return list(db.execute(stmt).scalars().all())


def get_booking_detail(
    db: Session, user_id: int, booking_id: int
) -> Optional[dict]:
    """Get booking detail with status history."""
    booking = db.get(TransportBooking, booking_id)
    if not booking:
        return None

    if booking.customer_user_id != user_id and booking.provider.user_id != user_id:
        raise PermissionError("You don\'t have access to this booking")

    return {
        "id": booking.id,
        "booking_ref": booking.booking_ref,
        "status": booking.status,
        "pickup_address": booking.pickup_address,
        "destination": booking.destination,
        "trip_date": str(booking.trip_date),
        "trip_days": booking.trip_days,
        "passenger_count": booking.passenger_count,
        "agreed_amount": float(booking.agreed_amount),
        "currency": booking.currency,
        "confirmed_at": str(booking.confirmed_at) if booking.confirmed_at else None,
        "cancelled_at": str(booking.cancelled_at) if booking.cancelled_at else None,
        "cancel_reason": booking.cancel_reason,
        "status_history": [
            {
                "from_status": h.from_status,
                "to_status": h.to_status,
                "changed_at": str(h.changed_at),
                "note": h.note,
            }
            for h in booking.status_history
        ],
    }


def cancel_booking(
    db: Session, user_id: int, booking_id: int, reason: Optional[str] = None
) -> Optional[TransportBooking]:
    """Cancel a booking (customer or provider)."""
    booking = db.get(TransportBooking, booking_id)
    if not booking:
        return None

    if booking.customer_user_id != user_id and booking.provider.user_id != user_id:
        raise PermissionError("You don\'t have access to this booking")

    if booking.status in ("COMPLETED", "CANCELLED"):
        raise ValueError("Cannot cancel a completed or already cancelled booking")

    old_status = booking.status
    booking.status = "CANCELLED"
    booking.cancelled_at = date.today()
    if reason:
        booking.cancel_reason = reason

    status_history = BookingStatusHistory(
        booking=booking,
        from_status=old_status,
        to_status="CANCELLED",
        changed_by=user_id,
        changed_at=date.today(),
        note=reason,
    )
    db.add(status_history)

    db.commit()
    db.refresh(booking)
    return booking


def update_booking_status(
    db: Session, user_id: int, booking_id: int, data: BookingStatusUpdate
) -> Optional[TransportBooking]:
    """Provider updates booking status (confirm, start, complete)."""
    booking = db.get(TransportBooking, booking_id)
    if not booking:
        return None

    if booking.provider.user_id != user_id:
        raise PermissionError("You are not the provider for this booking")

    old_status = booking.status
    booking.status = data.status

    if data.status == "CONFIRMED":
        booking.confirmed_at = date.today()
        booking.confirmed_by = user_id

    status_history = BookingStatusHistory(
        booking=booking,
        from_status=old_status,
        to_status=data.status,
        changed_by=user_id,
        changed_at=date.today(),
        note=data.note,
    )
    db.add(status_history)

    db.commit()
    db.refresh(booking)
    return booking
