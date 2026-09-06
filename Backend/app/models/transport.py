"""Transport & Personal Transport Booking models — Master Spec §28-§29 (Rules 5-6).

Transport is a SERVICE domain. Vehicles are NOT shop_products and bookings are
NOT product orders. This module is architecturally separate from the product
inventory system.

RULE 5: Transport != Product Inventory
RULE 6: Personal Transport Booking != Product Order
"""

from sqlalchemy import (
    Boolean,
    CheckConstraint,
    Date,
    Float,
    ForeignKey,
    Integer,
    Numeric,
    String,
    Text,
    UniqueConstraint,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database.session import Base
from app.models.base import SoftDeleteMixin, TimestampMixin


class TransportProvider(Base, TimestampMixin, SoftDeleteMixin):
    """Provider profile — owner of vehicles and transport services."""

    __tablename__ = "transport_providers"
    __table_args__ = (
        CheckConstraint("rating >= 0 AND rating <= 5", name="ck_transport_providers_rating_range"),
        CheckConstraint("review_count >= 0", name="ck_transport_providers_review_count_non_negative"),
        CheckConstraint(
            "verification_status IN ('PENDING', 'VERIFIED', 'REJECTED', 'SUSPENDED')",
            name="ck_transport_providers_verification_status",
        ),
    )

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id"), index=True, nullable=False)
    shop_id: Mapped[int | None] = mapped_column(ForeignKey("shops.id"), index=True)
    company_name: Mapped[str] = mapped_column(String(255), nullable=False)
    license_number: Mapped[str | None] = mapped_column(String(100))
    verification_status: Mapped[str] = mapped_column(
        String(30), nullable=False, server_default="PENDING"
    )
    service_area_id: Mapped[int | None] = mapped_column(ForeignKey("service_areas.id"), index=True)
    rating: Mapped[float] = mapped_column(Float, default=0.0)
    review_count: Mapped[int] = mapped_column(Integer, default=0, server_default="0")
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)

    user = relationship("User")
    vehicles = relationship("Vehicle", back_populates="provider", cascade="all, delete-orphan")
    services = relationship("TransportService", back_populates="provider", cascade="all, delete-orphan")
    quotes = relationship("TransportQuote", back_populates="provider", cascade="all, delete-orphan")
    bookings = relationship("TransportBooking", back_populates="provider", cascade="all, delete-orphan")

class Vehicle(Base, TimestampMixin, SoftDeleteMixin):
    """A physical vehicle owned by a transport provider."""

    __tablename__ = "vehicles"
    __table_args__ = (
        UniqueConstraint("registration_number", name="uq_vehicles_registration_number"),
        CheckConstraint("capacity_passengers >= 1", name="ck_vehicles_capacity_passengers_min"),
        CheckConstraint(
            "vehicle_type IN ('SEDAN', 'SUV', 'HATCHBACK', 'MPV', 'BIKE', "
            "'SCOOTER', 'TEMPO', 'MINI_BUS', 'BUS', 'VAN')",
            name="ck_vehicles_vehicle_type",
        ),
    )

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    provider_id: Mapped[int] = mapped_column(
        ForeignKey("transport_providers.id"), index=True, nullable=False
    )
    vehicle_type: Mapped[str] = mapped_column(String(30), nullable=False)
    make: Mapped[str | None] = mapped_column(String(100))
    model: Mapped[str | None] = mapped_column(String(100))
    year: Mapped[int | None] = mapped_column(Integer)
    registration_number: Mapped[str] = mapped_column(String(30), unique=True, index=True, nullable=False)
    capacity_passengers: Mapped[int] = mapped_column(Integer, nullable=False, default=4)
    capacity_luggage_kg: Mapped[float | None] = mapped_column(Numeric(8, 2))
    ac_available: Mapped[bool] = mapped_column(Boolean, default=True)
    fuel_type: Mapped[str | None] = mapped_column(String(20))
    color: Mapped[str | None] = mapped_column(String(30))
    interior_photo_url: Mapped[str | None] = mapped_column(String(500))
    exterior_photo_url: Mapped[str | None] = mapped_column(String(500))
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)

    provider = relationship("TransportProvider", back_populates="vehicles")
    documents = relationship("VehicleDocument", back_populates="vehicle", cascade="all, delete-orphan")
    availability = relationship("VehicleAvailability", back_populates="vehicle", cascade="all, delete-orphan")
    quotes = relationship("TransportQuote", back_populates="vehicle")
    bookings = relationship("TransportBooking", back_populates="vehicle")


class VehicleDocument(Base, TimestampMixin, SoftDeleteMixin):
    """Insurance / registration / permit documents for a vehicle (private S3 bucket)."""

    __tablename__ = "vehicle_documents"

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    vehicle_id: Mapped[int] = mapped_column(ForeignKey("vehicles.id"), index=True, nullable=False)
    document_type: Mapped[str] = mapped_column(String(50), nullable=False)
    document_url: Mapped[str] = mapped_column(String(500), nullable=False)
    document_number: Mapped[str | None] = mapped_column(String(100))
    valid_until: Mapped[Date | None] = mapped_column(Date)
    is_verified: Mapped[bool] = mapped_column(Boolean, default=False)
    verified_at: Mapped[Date | None] = mapped_column(Date)
    verified_by: Mapped[int | None] = mapped_column(ForeignKey("users.id"))

    vehicle = relationship("Vehicle", back_populates="documents")


class TransportService(Base, TimestampMixin, SoftDeleteMixin):
    """What a provider offers - marriage, tour, local travel, etc."""

    __tablename__ = "transport_services"
    __table_args__ = (
        CheckConstraint("base_price >= 0", name="ck_transport_services_base_price_non_negative"),
        CheckConstraint(
            "service_type IN ('MARRIAGE', 'FAMILY_TOUR', 'PERSONAL_TRAVEL', "
            "'LOCAL_TRAVEL', 'EVENT_TRAVEL', 'AIRPORT', 'WEDDING', 'OTHER')",
            name="ck_transport_services_service_type",
        ),
        CheckConstraint(
            "price_unit IN ('PER_DAY', 'PER_KM', 'PER_TRIP', 'PER_HOUR', 'QUOTE')",
            name="ck_transport_services_price_unit",
        ),
    )

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    provider_id: Mapped[int] = mapped_column(
        ForeignKey("transport_providers.id"), index=True, nullable=False
    )
    service_type: Mapped[str] = mapped_column(String(30), nullable=False)
    name: Mapped[str] = mapped_column(String(255), nullable=False)
    description: Mapped[str | None] = mapped_column(Text)
    base_price: Mapped[float] = mapped_column(Numeric(12, 2), nullable=False, default=0)
    price_unit: Mapped[str] = mapped_column(String(20), nullable=False, default="QUOTE")
    min_duration_days: Mapped[int] = mapped_column(Integer, default=1)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)

    provider = relationship("TransportProvider", back_populates="services")


class VehicleAvailability(Base, TimestampMixin):
    """Calendar-style availability per vehicle."""

    __tablename__ = "vehicle_availability"
    __table_args__ = (
        CheckConstraint(
            "status IN ('AVAILABLE', 'BOOKED', 'MAINTENANCE')",
            name="ck_vehicle_availability_status",
        ),
    )

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    vehicle_id: Mapped[int] = mapped_column(ForeignKey("vehicles.id"), index=True, nullable=False)
    available_from: Mapped[Date] = mapped_column(Date, nullable=False)
    available_to: Mapped[Date] = mapped_column(Date, nullable=False)
    status: Mapped[str] = mapped_column(String(20), nullable=False, default="AVAILABLE")
    created_by: Mapped[int | None] = mapped_column(ForeignKey("users.id"))

    vehicle = relationship("Vehicle", back_populates="availability")

class TransportQuote(Base, TimestampMixin):
    """Provider-side quote for a requested trip."""

    __tablename__ = "transport_quotes"
    __table_args__ = (
        CheckConstraint("quote_amount >= 0", name="ck_transport_quotes_amount_non_negative"),
        CheckConstraint("passenger_count >= 1", name="ck_transport_quotes_passenger_min"),
        CheckConstraint(
            "status IN ('REQUESTED', 'QUOTED', 'ACCEPTED', 'REJECTED', 'EXPIRED')",
            name="ck_transport_quotes_status",
        ),
        CheckConstraint(
            "trip_purpose IN ('MARRIAGE', 'FAMILY_TOUR', 'PERSONAL_TRAVEL', "
            "'LOCAL_TRAVEL', 'EVENT_TRAVEL', 'OTHER')",
            name="ck_transport_quotes_trip_purpose",
        ),
    )

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    provider_id: Mapped[int] = mapped_column(ForeignKey("transport_providers.id"), index=True, nullable=False)
    vehicle_id: Mapped[int | None] = mapped_column(ForeignKey("vehicles.id"), index=True)
    customer_user_id: Mapped[int] = mapped_column(ForeignKey("users.id"), index=True, nullable=False)
    requested_by: Mapped[int] = mapped_column(ForeignKey("users.id"), nullable=False)
    trip_purpose: Mapped[str] = mapped_column(String(30), nullable=False)
    pickup_address: Mapped[str] = mapped_column(Text, nullable=False)
    destination_address: Mapped[str] = mapped_column(Text, nullable=False)
    pickup_lat: Mapped[float | None] = mapped_column(Float)
    pickup_lng: Mapped[float | None] = mapped_column(Float)
    trip_date: Mapped[Date] = mapped_column(Date, nullable=False)
    trip_days: Mapped[int] = mapped_column(Integer, default=1)
    passenger_count: Mapped[int] = mapped_column(Integer, nullable=False, default=1)
    quote_amount: Mapped[float] = mapped_column(Numeric(12, 2), nullable=False, default=0)
    currency: Mapped[str] = mapped_column(String(10), default="INR")
    status: Mapped[str] = mapped_column(String(30), nullable=False, default="REQUESTED")
    notes: Mapped[str | None] = mapped_column(Text)

    provider = relationship("TransportProvider", back_populates="quotes")
    vehicle = relationship("Vehicle", back_populates="quotes")
    booking = relationship("TransportBooking", back_populates="quote", uselist=False)


class TransportBooking(Base, TimestampMixin):
    """Confirmed booking � separate from product orders (Rule 6)."""

    __tablename__ = "transport_bookings"
    __table_args__ = (
        UniqueConstraint("quote_id", name="uq_transport_bookings_quote_id"),
        UniqueConstraint("booking_ref", name="uq_transport_bookings_booking_ref"),
        CheckConstraint("agreed_amount >= 0", name="ck_transport_bookings_amount_non_negative"),
        CheckConstraint("passenger_count >= 1", name="ck_transport_bookings_passenger_min"),
        CheckConstraint(
            "status IN ('PENDING', 'CONFIRMED', 'IN_PROGRESS', 'COMPLETED', 'CANCELLED')",
            name="ck_transport_bookings_status",
        ),
    )

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    quote_id: Mapped[int] = mapped_column(
        ForeignKey("transport_quotes.id"), unique=True, index=True, nullable=False
    )
    customer_user_id: Mapped[int] = mapped_column(ForeignKey("users.id"), index=True, nullable=False)
    provider_id: Mapped[int] = mapped_column(ForeignKey("transport_providers.id"), index=True, nullable=False)
    vehicle_id: Mapped[int] = mapped_column(ForeignKey("vehicles.id"), index=True, nullable=False)
    status: Mapped[str] = mapped_column(String(30), nullable=False, default="PENDING")
    booking_ref: Mapped[str] = mapped_column(String(40), unique=True, index=True, nullable=False)
    pickup_address: Mapped[str] = mapped_column(Text, nullable=False)
    destination: Mapped[str] = mapped_column(Text, nullable=False)
    pickup_lat: Mapped[float | None] = mapped_column(Float)
    pickup_lng: Mapped[float | None] = mapped_column(Float)
    trip_date: Mapped[Date] = mapped_column(Date, nullable=False)
    trip_days: Mapped[int] = mapped_column(Integer, default=1)
    passenger_count: Mapped[int] = mapped_column(Integer, nullable=False, default=1)
    agreed_amount: Mapped[float] = mapped_column(Numeric(12, 2), nullable=False)
    currency: Mapped[str] = mapped_column(String(10), default="INR")
    notes: Mapped[str | None] = mapped_column(Text)
    confirmed_by: Mapped[int | None] = mapped_column(ForeignKey("users.id"))
    confirmed_at: Mapped[Date | None] = mapped_column(Date)
    cancelled_at: Mapped[Date | None] = mapped_column(Date)
    cancel_reason: Mapped[str | None] = mapped_column(Text)

    quote = relationship("TransportQuote", back_populates="booking")
    provider = relationship("TransportProvider", back_populates="bookings")
    vehicle = relationship("Vehicle", back_populates="bookings")
    status_history = relationship("BookingStatusHistory", back_populates="booking", cascade="all, delete-orphan")
    trip = relationship("TripDetail", back_populates="booking", uselist=False)

class BookingStatusHistory(Base, TimestampMixin):
    """Audit of every booking transition."""

    __tablename__ = "booking_status_history"

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    booking_id: Mapped[int] = mapped_column(ForeignKey("transport_bookings.id"), index=True, nullable=False)
    from_status: Mapped[str | None] = mapped_column(String(30))
    to_status: Mapped[str] = mapped_column(String(30), nullable=False)
    changed_by: Mapped[int | None] = mapped_column(ForeignKey("users.id"))
    note: Mapped[str | None] = mapped_column(Text)
    changed_at: Mapped[Date] = mapped_column(Date, nullable=False)

    booking = relationship("TransportBooking", back_populates="status_history")


class TripDetail(Base, TimestampMixin):
    """Operational trip snapshot after confirmation."""

    __tablename__ = "trip_details"
    __table_args__ = (
        UniqueConstraint("booking_id", name="uq_trip_details_booking_id"),
        CheckConstraint(
            "payment_status IN ('PENDING', 'PAID', 'PARTIAL')",
            name="ck_trip_details_payment_status",
        ),
    )

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    booking_id: Mapped[int] = mapped_column(
        ForeignKey("transport_bookings.id"), unique=True, index=True, nullable=False
    )
    driver_name: Mapped[str | None] = mapped_column(String(120))
    driver_phone: Mapped[str | None] = mapped_column(String(20))
    vehicle_actual_id: Mapped[int | None] = mapped_column(ForeignKey("vehicles.id"))
    start_odometer: Mapped[int | None] = mapped_column(Integer)
    end_odometer: Mapped[int | None] = mapped_column(Integer)
    started_at: Mapped[Date | None] = mapped_column(Date)
    ended_at: Mapped[Date | None] = mapped_column(Date)
    actual_distance_km: Mapped[float | None] = mapped_column(Numeric(8, 2))
    final_amount: Mapped[float | None] = mapped_column(Numeric(12, 2))
    payment_status: Mapped[str] = mapped_column(String(20), nullable=False, default="PENDING")

    booking = relationship("TransportBooking", back_populates="trip")
