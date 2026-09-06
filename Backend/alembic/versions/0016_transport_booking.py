"""Transport & Personal Transport Booking — Master Spec §28-§29 (Rules 5-6).

Revision ID: 0016
Revises: 0015
Create Date: 2026-09-05

Delivers the transport service domain from DATABASE SCHEMA DESIGN.txt (Domain 15):
- transport_providers, vehicles, vehicle_documents, transport_services,
  vehicle_availability, transport_quotes, transport_bookings,
  booking_status_history, trip_details

RULE GUARDRAILS: transport_quotes/transport_bookings are never joined to
shop_products/inventory; booking references users, transport_providers and
vehicles only. No cart/checkout/delivery semantics are introduced.
"""

from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = "0016"
down_revision: Union[str, None] = "0015"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def _timestamps() -> list[sa.Column]:
    return [
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.text("now()")),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.text("now()")),
    ]


def _soft_delete() -> list[sa.Column]:
    return [
        sa.Column("is_deleted", sa.Boolean(), nullable=False, server_default=sa.text("false")),
        sa.Column("deleted_at", sa.DateTime(timezone=True), nullable=True),
    ]


def upgrade() -> None:
    # --- transport_providers: provider profile ---------------------------
    op.create_table(
        "transport_providers",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("user_id", sa.Integer(), sa.ForeignKey("users.id"), nullable=False),
        sa.Column("shop_id", sa.Integer(), sa.ForeignKey("shops.id"), nullable=True),
        sa.Column("company_name", sa.String(255), nullable=False),
        sa.Column("license_number", sa.String(100), nullable=True),
        sa.Column("verification_status", sa.String(30), nullable=False, server_default="PENDING"),
        sa.Column("service_area_id", sa.Integer(), sa.ForeignKey("service_areas.id"), nullable=True),
        sa.Column("rating", sa.Float(), nullable=False, server_default="0"),
        sa.Column("review_count", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("is_active", sa.Boolean(), nullable=False, server_default="true"),
        *_soft_delete(),
        *_timestamps(),
        sa.CheckConstraint("rating >= 0 AND rating <= 5", name="ck_transport_providers_rating_range"),
        sa.CheckConstraint("review_count >= 0", name="ck_transport_providers_review_count_non_negative"),
        sa.CheckConstraint(
            "verification_status IN ('PENDING', 'VERIFIED', 'REJECTED', 'SUSPENDED')",
            name="ck_transport_providers_verification_status",
        ),
    )
    op.create_index("ix_transport_providers_user_id", "transport_providers", ["user_id"])
    op.create_index("ix_transport_providers_shop_id", "transport_providers", ["shop_id"])
    op.create_index("ix_transport_providers_service_area_id", "transport_providers", ["service_area_id"])

    # --- vehicles: physical vehicles ------------------------------------
    op.create_table(
        "vehicles",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("provider_id", sa.Integer(), sa.ForeignKey("transport_providers.id"), nullable=False),
        sa.Column("vehicle_type", sa.String(30), nullable=False),
        sa.Column("make", sa.String(100), nullable=True),
        sa.Column("model", sa.String(100), nullable=True),
        sa.Column("year", sa.Integer(), nullable=True),
        sa.Column("registration_number", sa.String(30), nullable=False),
        sa.Column("capacity_passengers", sa.Integer(), nullable=False, server_default="4"),
        sa.Column("capacity_luggage_kg", sa.Numeric(8, 2), nullable=True),
        sa.Column("ac_available", sa.Boolean(), nullable=False, server_default="true"),
        sa.Column("fuel_type", sa.String(20), nullable=True),
        sa.Column("color", sa.String(30), nullable=True),
        sa.Column("interior_photo_url", sa.String(500), nullable=True),
        sa.Column("exterior_photo_url", sa.String(500), nullable=True),
        sa.Column("is_active", sa.Boolean(), nullable=False, server_default="true"),
        *_soft_delete(),
        *_timestamps(),
        sa.UniqueConstraint("registration_number", name="uq_vehicles_registration_number"),
        sa.CheckConstraint("capacity_passengers >= 1", name="ck_vehicles_capacity_passengers_min"),
        sa.CheckConstraint(
            "vehicle_type IN ('SEDAN', 'SUV', 'HATCHBACK', 'MPV', 'BIKE', "
            "'SCOOTER', 'TEMPO', 'MINI_BUS', 'BUS', 'VAN')",
            name="ck_vehicles_vehicle_type",
        ),
    )
    op.create_index("ix_vehicles_provider_id", "vehicles", ["provider_id"])
    op.create_index(
        "ix_vehicles_provider_type_active", "vehicles", ["provider_id", "vehicle_type", "is_active"]
    )
    # --- vehicle_documents: insurance/registration/permit ---------------
    op.create_table(
        "vehicle_documents",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("vehicle_id", sa.Integer(), sa.ForeignKey("vehicles.id"), nullable=False),
        sa.Column("document_type", sa.String(50), nullable=False),
        sa.Column("document_url", sa.String(500), nullable=False),
        sa.Column("document_number", sa.String(100), nullable=True),
        sa.Column("valid_until", sa.Date(), nullable=True),
        sa.Column("is_verified", sa.Boolean(), nullable=False, server_default="false"),
        sa.Column("verified_at", sa.Date(), nullable=True),
        sa.Column("verified_by", sa.Integer(), sa.ForeignKey("users.id"), nullable=True),
        *_soft_delete(),
        *_timestamps(),
    )
    op.create_index("ix_vehicle_documents_vehicle_id", "vehicle_documents", ["vehicle_id"])

    # --- transport_services: what a provider offers ---------------------
    op.create_table(
        "transport_services",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("provider_id", sa.Integer(), sa.ForeignKey("transport_providers.id"), nullable=False),
        sa.Column("service_type", sa.String(30), nullable=False),
        sa.Column("name", sa.String(255), nullable=False),
        sa.Column("description", sa.Text(), nullable=True),
        sa.Column("base_price", sa.Numeric(12, 2), nullable=False, server_default="0"),
        sa.Column("price_unit", sa.String(20), nullable=False, server_default="QUOTE"),
        sa.Column("min_duration_days", sa.Integer(), nullable=False, server_default="1"),
        sa.Column("is_active", sa.Boolean(), nullable=False, server_default="true"),
        *_soft_delete(),
        *_timestamps(),
        sa.CheckConstraint("base_price >= 0", name="ck_transport_services_base_price_non_negative"),
        sa.CheckConstraint(
            "service_type IN ('MARRIAGE', 'FAMILY_TOUR', 'PERSONAL_TRAVEL', "
            "'LOCAL_TRAVEL', 'EVENT_TRAVEL', 'AIRPORT', 'WEDDING', 'OTHER')",
            name="ck_transport_services_service_type",
        ),
        sa.CheckConstraint(
            "price_unit IN ('PER_DAY', 'PER_KM', 'PER_TRIP', 'PER_HOUR', 'QUOTE')",
            name="ck_transport_services_price_unit",
        ),
    )
    op.create_index("ix_transport_services_provider_id", "transport_services", ["provider_id"])

    # --- vehicle_availability: calendar-style availability --------------
    op.create_table(
        "vehicle_availability",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("vehicle_id", sa.Integer(), sa.ForeignKey("vehicles.id"), nullable=False),
        sa.Column("available_from", sa.Date(), nullable=False),
        sa.Column("available_to", sa.Date(), nullable=False),
        sa.Column("status", sa.String(20), nullable=False, server_default="AVAILABLE"),
        sa.Column("created_by", sa.Integer(), sa.ForeignKey("users.id"), nullable=True),
        *_timestamps(),
        sa.CheckConstraint(
            "status IN ('AVAILABLE', 'BOOKED', 'MAINTENANCE')",
            name="ck_vehicle_availability_status",
        ),
    )
    op.create_index("ix_vehicle_availability_vehicle_id", "vehicle_availability", ["vehicle_id"])
    op.create_index(
        "ix_vehicle_availability_vehicle_status_from",
        "vehicle_availability",
        ["vehicle_id", "status", "available_from"],
    )
    # --- transport_quotes: provider-side quote for a requested trip ------
    op.create_table(
        "transport_quotes",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("provider_id", sa.Integer(), sa.ForeignKey("transport_providers.id"), nullable=False),
        sa.Column("vehicle_id", sa.Integer(), sa.ForeignKey("vehicles.id"), nullable=True),
        sa.Column("customer_user_id", sa.Integer(), sa.ForeignKey("users.id"), nullable=False),
        sa.Column("requested_by", sa.Integer(), sa.ForeignKey("users.id"), nullable=False),
        sa.Column("trip_purpose", sa.String(30), nullable=False),
        sa.Column("pickup_address", sa.Text(), nullable=False),
        sa.Column("destination_address", sa.Text(), nullable=False),
        sa.Column("pickup_lat", sa.Float(), nullable=True),
        sa.Column("pickup_lng", sa.Float(), nullable=True),
        sa.Column("trip_date", sa.Date(), nullable=False),
        sa.Column("trip_days", sa.Integer(), nullable=False, server_default="1"),
        sa.Column("passenger_count", sa.Integer(), nullable=False, server_default="1"),
        sa.Column("quote_amount", sa.Numeric(12, 2), nullable=False, server_default="0"),
        sa.Column("currency", sa.String(10), nullable=False, server_default="INR"),
        sa.Column("status", sa.String(30), nullable=False, server_default="REQUESTED"),
        sa.Column("notes", sa.Text(), nullable=True),
        *_timestamps(),
        sa.CheckConstraint("quote_amount >= 0", name="ck_transport_quotes_amount_non_negative"),
        sa.CheckConstraint("passenger_count >= 1", name="ck_transport_quotes_passenger_min"),
        sa.CheckConstraint(
            "status IN ('REQUESTED', 'QUOTED', 'ACCEPTED', 'REJECTED', 'EXPIRED')",
            name="ck_transport_quotes_status",
        ),
        sa.CheckConstraint(
            "trip_purpose IN ('MARRIAGE', 'FAMILY_TOUR', 'PERSONAL_TRAVEL', "
            "'LOCAL_TRAVEL', 'EVENT_TRAVEL', 'OTHER')",
            name="ck_transport_quotes_trip_purpose",
        ),
    )
    op.create_index("ix_transport_quotes_provider_id", "transport_quotes", ["provider_id"])
    op.create_index("ix_transport_quotes_vehicle_id", "transport_quotes", ["vehicle_id"])
    op.create_index("ix_transport_quotes_customer_user_id", "transport_quotes", ["customer_user_id"])
    op.create_index(
        "ix_transport_quotes_customer_created", "transport_quotes", ["customer_user_id", "created_at"]
    )
    # --- transport_bookings: confirmed booking (separate from product orders) ---
    op.create_table(
        "transport_bookings",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("quote_id", sa.Integer(), sa.ForeignKey("transport_quotes.id"), nullable=False),
        sa.Column("customer_user_id", sa.Integer(), sa.ForeignKey("users.id"), nullable=False),
        sa.Column("provider_id", sa.Integer(), sa.ForeignKey("transport_providers.id"), nullable=False),
        sa.Column("vehicle_id", sa.Integer(), sa.ForeignKey("vehicles.id"), nullable=False),
        sa.Column("status", sa.String(30), nullable=False, server_default="PENDING"),
        sa.Column("booking_ref", sa.String(40), nullable=False),
        sa.Column("pickup_address", sa.Text(), nullable=False),
        sa.Column("destination", sa.Text(), nullable=False),
        sa.Column("pickup_lat", sa.Float(), nullable=True),
        sa.Column("pickup_lng", sa.Float(), nullable=True),
        sa.Column("trip_date", sa.Date(), nullable=False),
        sa.Column("trip_days", sa.Integer(), nullable=False, server_default="1"),
        sa.Column("passenger_count", sa.Integer(), nullable=False, server_default="1"),
        sa.Column("agreed_amount", sa.Numeric(12, 2), nullable=False),
        sa.Column("currency", sa.String(10), nullable=False, server_default="INR"),
        sa.Column("notes", sa.Text(), nullable=True),
        sa.Column("confirmed_by", sa.Integer(), sa.ForeignKey("users.id"), nullable=True),
        sa.Column("confirmed_at", sa.Date(), nullable=True),
        sa.Column("cancelled_at", sa.Date(), nullable=True),
        sa.Column("cancel_reason", sa.Text(), nullable=True),
        *_timestamps(),
        sa.UniqueConstraint("quote_id", name="uq_transport_bookings_quote_id"),
        sa.UniqueConstraint("booking_ref", name="uq_transport_bookings_booking_ref"),
        sa.CheckConstraint("agreed_amount >= 0", name="ck_transport_bookings_amount_non_negative"),
        sa.CheckConstraint("passenger_count >= 1", name="ck_transport_bookings_passenger_min"),
        sa.CheckConstraint(
            "status IN ('PENDING', 'CONFIRMED', 'IN_PROGRESS', 'COMPLETED', 'CANCELLED')",
            name="ck_transport_bookings_status",
        ),
    )
    op.create_index("ix_transport_bookings_quote_id", "transport_bookings", ["quote_id"])
    op.create_index("ix_transport_bookings_customer_user_id", "transport_bookings", ["customer_user_id"])
    op.create_index("ix_transport_bookings_provider_id", "transport_bookings", ["provider_id"])
    op.create_index("ix_transport_bookings_vehicle_id", "transport_bookings", ["vehicle_id"])
    op.create_index(
        "ix_transport_bookings_customer_status", "transport_bookings", ["customer_user_id", "status"]
    )
    op.create_index(
        "ix_transport_bookings_provider_status", "transport_bookings", ["provider_id", "status"]
    )
    # --- booking_status_history: audit of every booking transition ------
    op.create_table(
        "booking_status_history",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("booking_id", sa.Integer(), sa.ForeignKey("transport_bookings.id"), nullable=False),
        sa.Column("from_status", sa.String(30), nullable=True),
        sa.Column("to_status", sa.String(30), nullable=False),
        sa.Column("changed_by", sa.Integer(), sa.ForeignKey("users.id"), nullable=True),
        sa.Column("note", sa.Text(), nullable=True),
        sa.Column("changed_at", sa.Date(), nullable=False),
        *_timestamps(),
    )
    op.create_index("ix_booking_status_history_booking_id", "booking_status_history", ["booking_id"])

    # --- trip_details: operational trip snapshot after confirmation -----
    op.create_table(
        "trip_details",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("booking_id", sa.Integer(), sa.ForeignKey("transport_bookings.id"), nullable=False),
        sa.Column("driver_name", sa.String(120), nullable=True),
        sa.Column("driver_phone", sa.String(20), nullable=True),
        sa.Column("vehicle_actual_id", sa.Integer(), sa.ForeignKey("vehicles.id"), nullable=True),
        sa.Column("start_odometer", sa.Integer(), nullable=True),
        sa.Column("end_odometer", sa.Integer(), nullable=True),
        sa.Column("started_at", sa.Date(), nullable=True),
        sa.Column("ended_at", sa.Date(), nullable=True),
        sa.Column("actual_distance_km", sa.Numeric(8, 2), nullable=True),
        sa.Column("final_amount", sa.Numeric(12, 2), nullable=True),
        sa.Column("payment_status", sa.String(20), nullable=False, server_default="PENDING"),
        *_timestamps(),
        sa.UniqueConstraint("booking_id", name="uq_trip_details_booking_id"),
        sa.CheckConstraint(
            "payment_status IN ('PENDING', 'PAID', 'PARTIAL')",
            name="ck_trip_details_payment_status",
        ),
    )
    op.create_index("ix_trip_details_booking_id", "trip_details", ["booking_id"])
    op.create_index("ix_trip_details_vehicle_actual_id", "trip_details", ["vehicle_actual_id"])


def downgrade() -> None:
    op.drop_table("trip_details")
    op.drop_table("booking_status_history")
    op.drop_table("transport_bookings")
    op.drop_table("transport_quotes")
    op.drop_table("vehicle_availability")
    op.drop_table("transport_services")
    op.drop_table("vehicle_documents")
    op.drop_table("vehicles")
    op.drop_table("transport_providers")
