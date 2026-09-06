"""Phase 16 - Transport & Personal Transport Booking schema verification (DB-free unit checks).

These tests require no live database. They statically validate the authored
Transport domain land (Master Spec §28-§29, Rules 5-6) as encoded in the
linear migration 0016 and the ORM models.
"""

import py_compile

from pathlib import Path

BACKEND_DIR = Path(__file__).resolve().parents[1]
MIGRATION = BACKEND_DIR / "alembic" / "versions" / "0016_transport_booking.py"
MODELS = BACKEND_DIR / "app" / "models" / "transport.py"
MODELS_INIT = BACKEND_DIR / "app" / "models" / "__init__.py"
ROUTES = BACKEND_DIR / "app" / "api" / "routes" / "transport.py"
SERVICE = BACKEND_DIR / "app" / "services" / "transport_service.py"
SCHEMAS = BACKEND_DIR / "app" / "schemas" / "transport.py"
REHEARSAL = BACKEND_DIR / "scripts" / "migration_rehearsal.py"


def _source(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def test_migration_0016_registered_linear():
    src = _source(MIGRATION)
    assert 'revision: str = "0016"' in src
    assert 'down_revision: Union[str, None] = "0015"' in src


def test_migration_creates_all_transport_tables():
    src = _source(MIGRATION)
    for table in (
        "transport_providers",
        "vehicles",
        "vehicle_documents",
        "transport_services",
        "vehicle_availability",
        "transport_quotes",
        "transport_bookings",
        "booking_status_history",
        "trip_details",
    ):
        assert table in src, f"{table} missing from migration 0016"


def test_migration_guardrail_constraints():
    src = _source(MIGRATION)
    # Rule 5/6 guardrails
    assert "ck_transport_providers_verification_status" in src
    assert "ck_transport_services_service_type" in src
    assert "ck_transport_quotes_status" in src
    assert "ck_transport_bookings_status" in src
    assert "uq_transport_bookings_quote_id" in src
    assert "uq_transport_bookings_booking_ref" in src
    assert "uq_vehicles_registration_number" in src
    assert "ck_trip_details_payment_status" in src
    # Bookings reference users / providers / vehicles only — never shop_products.
    assert "shop_products.id" not in src


def test_transport_timestamps_and_soft_delete():
    src = _source(MIGRATION)
    assert "_timestamps()" in src
    assert "_soft_delete()" in src
    assert src.count("*_soft_delete()") == 4  # providers, vehicles, docs, services


def test_transport_models_declared_and_exported():
    model_src = _source(MODELS)
    init_src = _source(MODELS_INIT)
    for cls in (
        "TransportProvider",
        "Vehicle",
        "VehicleDocument",
        "TransportService",
        "VehicleAvailability",
        "TransportQuote",
        "TransportBooking",
        "BookingStatusHistory",
        "TripDetail",
    ):
        assert ("class " + cls + "(") in model_src
    for name in (
        "TransportProvider",
        "Vehicle",
        "VehicleDocument",
        "TransportService",
        "VehicleAvailability",
        "TransportQuote",
        "TransportBooking",
        "BookingStatusHistory",
        "TripDetail",
    ):
        assert name in init_src


def test_transport_routes_and_service_exist():
    for path in (ROUTES, SERVICE, SCHEMAS, REHEARSAL):
        assert path.exists(), f"{path.relative_to(BACKEND_DIR)} is missing"


def test_rehearsal_covers_transport_tables():
    src = _source(REHEARSAL)
    for table in (
        "transport_providers",
        "vehicles",
        "vehicle_availability",
        "transport_quotes",
        "transport_bookings",
        "booking_status_history",
        "trip_details",
    ):
        assert table in src, f"{table} missing from rehearsal expectation"


def test_transport_schemas_importable():
    import app.schemas.transport  # noqa: F401


def test_transport_models_importable():
    from app.models.transport import (  # noqa: F401
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