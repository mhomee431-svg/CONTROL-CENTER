"""Transport & Personal Transport Booking API routes — Master Spec §28-§29 (Rules 5-6).

Transport is a SERVICE domain. Vehicles are NOT shop_products and bookings are
NOT product orders. This module provides:
- Customer: search providers, request quotes, accept quotes, view bookings
- Provider: manage vehicles/services, respond to quotes, manage bookings
"""

from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session

from app.core.dependencies import get_current_user
from app.core.responses import error_response, success_response
from app.database.session import get_db
from app.models.transport import (
    TransportProvider,
    Vehicle,
    VehicleDocument,
    TransportService,
    VehicleAvailability,
    TransportQuote,
    TransportBooking,
    BookingStatusHistory,
    TripDetail,
)
from app.schemas.transport import (
    TransportProviderCreate,
    TransportProviderResponse,
    VehicleCreate,
    VehicleResponse,
    TransportServiceCreate,
    TransportServiceResponse,
    VehicleAvailabilityCreate,
    TransportQuoteCreate,
    TransportQuoteResponse,
    TransportBookingResponse,
    BookingStatusUpdate,
)
from app.services import transport_service

router = APIRouter(prefix="/transport", tags=["transport"])


# ── Customer-facing endpoints ──────────────────────────────────────────────
@router.get("/providers")
async def search_providers(
    latitude: float = Query(..., ge=-90, le=90),
    longitude: float = Query(..., ge=-180, le=180),
    radius_km: float = Query(10.0, gt=0, le=100),
    service_type: str | None = None,
    db: Session = Depends(get_db),
):
    """Search for nearby transport providers with available vehicles."""
    try:
        results = transport_service.search_providers(
            db, latitude=latitude, longitude=longitude, radius_km=radius_km, service_type=service_type
        )
        return success_response(data=results)
    except Exception as exc:  # noqa: BLE001
        return error_response(message=str(exc), error_code="PROVIDER_SEARCH_FAILED", status_code=400)


@router.get("/providers/by-shop/{shop_id}")
async def get_provider_detail_by_shop(
    shop_id: int,
    db: Session = Depends(get_db),
):
    """Transport provider profile for a SHOP (customer shop profile).

    Declared BEFORE ``/providers/{provider_id}`` so ``by-shop`` is never parsed
    as an id. 404 means the shop has no provider record: the customer app then
    shows no service section at all, and in particular no request/booking entry
    point, because there would be nothing to request from.
    """
    provider = transport_service.get_provider_detail_by_shop(db, shop_id)
    if provider is None:
        return error_response(message="Provider not found", error_code="PROVIDER_NOT_FOUND", status_code=404)
    return success_response(data=provider)


@router.get("/providers/{provider_id}")
async def get_provider_detail(
    provider_id: int,
    db: Session = Depends(get_db),
):
    """Get provider detail with vehicles and services."""
    provider = transport_service.get_provider_detail(db, provider_id)
    if provider is None:
        return error_response(message="Provider not found", error_code="PROVIDER_NOT_FOUND", status_code=404)
    return success_response(data=provider)


@router.get("/vehicles/{vehicle_id}")
async def get_vehicle_detail(
    vehicle_id: int,
    db: Session = Depends(get_db),
):
    """Get vehicle detail with availability."""
    vehicle = transport_service.get_vehicle_detail(db, vehicle_id)
    if vehicle is None:
        return error_response(message="Vehicle not found", error_code="VEHICLE_NOT_FOUND", status_code=404)
    return success_response(data=vehicle)

# -- Quote endpoints --------------------------------------------------------
@router.get("/quotes")
async def get_my_quotes(
    status: str | None = None,
    db: Session = Depends(get_db),
    current_user=Depends(get_current_user),
):
    """The current customer's own quote requests, newest first.

    This is the missing link that makes the customer flow completable: a request
    can be sent and the provider can answer it with a price, but the customer
    needs to LIST their quotes to see that price and then accept it. Without it
    `POST /quotes/{id}/accept` is unreachable from the app.
    """
    try:
        quotes = transport_service.get_user_quotes(
            db, user_id=current_user.id, status=status
        )
        return success_response(data=quotes)
    except Exception as exc:  # noqa: BLE001
        return error_response(message=str(exc), error_code="QUOTE_LIST_FAILED", status_code=500)


@router.get("/quotes/{quote_id}")
async def get_quote_detail(
    quote_id: int,
    db: Session = Depends(get_db),
    current_user=Depends(get_current_user),
):
    """One of the current customer's own quotes, including the provider's price."""
    try:
        quote = transport_service.get_quote_detail(
            db, user_id=current_user.id, quote_id=quote_id
        )
    except PermissionError as exc:
        return error_response(message=str(exc), error_code="FORBIDDEN", status_code=403)
    if quote is None:
        return error_response(message="Quote not found", error_code="QUOTE_NOT_FOUND", status_code=404)
    return success_response(data=quote)


@router.post("/quotes")
async def request_quote(
    data: TransportQuoteCreate,
    db: Session = Depends(get_db),
    current_user=Depends(get_current_user),
):
    """Customer requests a quote from a transport provider."""
    try:
        quote = transport_service.request_quote(db, user_id=current_user.id, data=data)
        return success_response(data=quote, message="Quote requested successfully")
    except ValueError as exc:
        return error_response(message=str(exc), error_code="QUOTE_REQUEST_FAILED", status_code=400)
    except Exception as exc:  # noqa: BLE001
        return error_response(message=str(exc), error_code="QUOTE_REQUEST_FAILED", status_code=500)


@router.post("/quotes/{quote_id}/accept")
async def accept_quote(
    quote_id: int,
    db: Session = Depends(get_db),
    current_user=Depends(get_current_user),
):
    """Customer accepts a quote, creating a booking."""
    try:
        booking = transport_service.accept_quote(db, user_id=current_user.id, quote_id=quote_id)
        if booking is None:
            return error_response(message="Quote not found", error_code="QUOTE_NOT_FOUND", status_code=404)
        return success_response(data=booking, message="Quote accepted, booking created")
    except PermissionError as exc:
        return error_response(message=str(exc), error_code="FORBIDDEN", status_code=403)
    except ValueError as exc:
        return error_response(message=str(exc), error_code="QUOTE_ACCEPT_FAILED", status_code=400)
    except Exception as exc:  # noqa: BLE001
        return error_response(message=str(exc), error_code="QUOTE_ACCEPT_FAILED", status_code=500)


# -- Booking endpoints ------------------------------------------------------
@router.get("/bookings")
async def get_my_bookings(
    status: str | None = None,
    db: Session = Depends(get_db),
    current_user=Depends(get_current_user),
):
    """Get current user transport bookings."""
    bookings = transport_service.get_user_bookings(db, user_id=current_user.id, status=status)
    return success_response(data=bookings)


@router.get("/bookings/{booking_id}")
async def get_booking_detail(
    booking_id: int,
    db: Session = Depends(get_db),
    current_user=Depends(get_current_user),
):
    """Get booking detail with status history."""
    booking = transport_service.get_booking_detail(db, user_id=current_user.id, booking_id=booking_id)
    if booking is None:
        return error_response(message="Booking not found", error_code="BOOKING_NOT_FOUND", status_code=404)
    return success_response(data=booking)


@router.post("/bookings/{booking_id}/cancel")
async def cancel_booking(
    booking_id: int,
    reason: str | None = None,
    db: Session = Depends(get_db),
    current_user=Depends(get_current_user),
):
    """Cancel a booking (customer or provider)."""
    try:
        booking = transport_service.cancel_booking(
            db, user_id=current_user.id, booking_id=booking_id, reason=reason
        )
        if booking is None:
            return error_response(message="Booking not found", error_code="BOOKING_NOT_FOUND", status_code=404)
        return success_response(data=booking, message="Booking cancelled")
    except PermissionError as exc:
        return error_response(message=str(exc), error_code="FORBIDDEN", status_code=403)
    except ValueError as exc:
        return error_response(message=str(exc), error_code="BOOKING_CANCEL_FAILED", status_code=400)
    except Exception as exc:  # noqa: BLE001
        return error_response(message=str(exc), error_code="BOOKING_CANCEL_FAILED", status_code=500)

# -- Provider management endpoints ------------------------------------------
@router.post("/provider/register")
async def register_provider(
    data: TransportProviderCreate,
    db: Session = Depends(get_db),
    current_user=Depends(get_current_user),
):
    """Register as a transport provider."""
    try:
        provider = transport_service.register_provider(db, user_id=current_user.id, data=data)
        return success_response(data=provider, message="Transport provider registered")
    except ValueError as exc:
        return error_response(message=str(exc), error_code="PROVIDER_REGISTER_FAILED", status_code=400)
    except Exception as exc:  # noqa: BLE001
        return error_response(message=str(exc), error_code="PROVIDER_REGISTER_FAILED", status_code=500)


@router.post("/provider/vehicles")
async def add_vehicle(
    data: VehicleCreate,
    db: Session = Depends(get_db),
    current_user=Depends(get_current_user),
):
    """Add a vehicle to provider fleet (provider only)."""
    try:
        vehicle = transport_service.add_vehicle(db, user_id=current_user.id, data=data)
        return success_response(data=vehicle, message="Vehicle added")
    except PermissionError as exc:
        return error_response(message=str(exc), error_code="FORBIDDEN", status_code=403)
    except ValueError as exc:
        return error_response(message=str(exc), error_code="VEHICLE_ADD_FAILED", status_code=400)
    except Exception as exc:  # noqa: BLE001
        return error_response(message=str(exc), error_code="VEHICLE_ADD_FAILED", status_code=500)


@router.post("/provider/services")
async def add_service(
    data: TransportServiceCreate,
    db: Session = Depends(get_db),
    current_user=Depends(get_current_user),
):
    """Add a transport service (provider only)."""
    try:
        service = transport_service.add_service(db, user_id=current_user.id, data=data)
        return success_response(data=service, message="Service added")
    except PermissionError as exc:
        return error_response(message=str(exc), error_code="FORBIDDEN", status_code=403)
    except ValueError as exc:
        return error_response(message=str(exc), error_code="SERVICE_ADD_FAILED", status_code=400)
    except Exception as exc:  # noqa: BLE001
        return error_response(message=str(exc), error_code="SERVICE_ADD_FAILED", status_code=500)


@router.post("/provider/quotes/{quote_id}/respond")
async def respond_to_quote(
    quote_id: int,
    quote_amount: float = Query(..., ge=0),
    notes: str | None = None,
    db: Session = Depends(get_db),
    current_user=Depends(get_current_user),
):
    """Provider responds to a quote request with a price."""
    try:
        quote = transport_service.respond_to_quote(
            db, user_id=current_user.id, quote_id=quote_id, quote_amount=quote_amount, notes=notes
        )
        if quote is None:
            return error_response(message="Quote not found", error_code="QUOTE_NOT_FOUND", status_code=404)
        return success_response(data=quote, message="Quote sent")
    except PermissionError as exc:
        return error_response(message=str(exc), error_code="FORBIDDEN", status_code=403)
    except Exception as exc:  # noqa: BLE001
        return error_response(message=str(exc), error_code="QUOTE_RESPOND_FAILED", status_code=500)


@router.post("/provider/bookings/{booking_id}/status")
async def update_booking_status(
    booking_id: int,
    data: BookingStatusUpdate,
    db: Session = Depends(get_db),
    current_user=Depends(get_current_user),
):
    """Provider updates booking status (confirm, start, complete)."""
    try:
        booking = transport_service.update_booking_status(
            db, user_id=current_user.id, booking_id=booking_id, data=data
        )
        if booking is None:
            return error_response(message="Booking not found", error_code="BOOKING_NOT_FOUND", status_code=404)
        return success_response(data=booking, message="Booking status updated")
    except PermissionError as exc:
        return error_response(message=str(exc), error_code="FORBIDDEN", status_code=403)
    except ValueError as exc:
        return error_response(message=str(exc), error_code="STATUS_UPDATE_FAILED", status_code=400)
    except Exception as exc:  # noqa: BLE001
        return error_response(message=str(exc), error_code="STATUS_UPDATE_FAILED", status_code=500)
