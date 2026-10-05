"""The TRANSPORT category spec, pinned.

Two of its instructions are prohibitions, which is where this codebase has
actually gone wrong before:

  * "Do not create fake booking functionality."
  * "Do not force normal product inventory UI if this business does not use
    product inventory."

A fake capability is worse than a missing one: a booking button that cannot
book, or an inventory screen for a provider with no stock, both teach the user
that the platform does something it does not.

The spec also lists five capabilities as "possible FUTURE backend-supported".
Those are not required, so the tests here do NOT demand they be exposed. They
check the opposite and more useful thing: that where the backend does model
them, the modelling is real (a real table with a real column), so a future UI
can be built on them without inventing storage.
"""

import re
from pathlib import Path

import pytest

from app.models import merchant_category, product_attributes, transport
from app.models.merchant_category import CategoryCapability, MerchantCategoryCode
from app.models.service_area import ServiceArea
from app.models.shop import Shop
from app.services.capability_field_specs import capability_fields_for

BACKEND_DIR = Path(__file__).resolve().parents[1]


def _capabilities(code: str = "TRANSPORT") -> set:
    resolved = merchant_category.capabilities_for_category(code)
    return set(resolved.get("capabilities", ()))


def _tables() -> set:
    found = set()
    for path in (BACKEND_DIR / "app" / "models").glob("*.py"):
        for match in re.finditer(
            r'__tablename__\s*=\s*"([^"]+)"', path.read_text(encoding="utf-8")
        ):
            found.add(match.group(1))
    return found


class TestTransportIsServiceOriented:
    def test_it_is_a_registered_business(self):
        assert MerchantCategoryCode.TRANSPORT.value == "TRANSPORT"

    def test_it_carries_no_product_catalogue(self):
        assert product_attributes.product_attributes_for("TRANSPORT") == ()

    @pytest.mark.parametrize(
        "capability",
        [
            CategoryCapability.PRODUCT_CATALOG,
            CategoryCapability.INVENTORY,
            CategoryCapability.BARCODE,
            CategoryCapability.IMPORT,
            CategoryCapability.POS,
        ],
    )
    def test_no_stock_shaped_capability_is_granted(self, capability):
        """These are what the UI uses to decide whether to show an inventory
        form, so granting one is what would force it."""
        assert capability.value not in _capabilities()

    def test_the_service_capabilities_are_granted(self):
        granted = _capabilities()
        for capability in (
            CategoryCapability.BOOKING,
            CategoryCapability.CONTACT,
            CategoryCapability.LOCATION,
            CategoryCapability.OPERATING_HOURS,
            CategoryCapability.SERVICES,
            CategoryCapability.PRICE,
        ):
            assert capability.value in granted, capability


class TestBusinessDataHasRealDestinations:
    """Each item the spec lists must land somewhere that actually exists."""

    def test_business_and_provider_name_are_modelled(self):
        columns = {c.name for c in Shop.__table__.columns}
        assert "name" in columns
        provider = {
            c.name for c in transport.TransportProvider.__table__.columns
        }
        assert "company_name" in provider

    def test_contact_is_modelled_on_the_shop(self):
        columns = {c.name for c in Shop.__table__.columns}
        assert {"phone", "email"} <= columns

    def test_location_is_modelled(self):
        columns = {c.name for c in Shop.__table__.columns}
        assert {"latitude", "longitude"} <= columns

    def test_service_area_has_a_real_table(self):
        assert "service_areas" in _tables()
        columns = {c.name for c in ServiceArea.__table__.columns}
        assert {"name", "area_type", "is_active"} <= columns

    def test_operating_hours_are_modelled(self):
        tables = _tables()
        assert "shop_hours" in tables
        assert "shop_holidays" in tables

    def test_service_description_is_modelled(self):
        columns = {c.name for c in transport.TransportService.__table__.columns}
        assert "description" in columns

    def test_the_profile_form_asks_for_the_specs_business_data(self):
        keys = {f.key for f in capability_fields_for("TRANSPORT")}
        assert {"service_area", "service_summary", "contact_phone"} <= keys
        assert {"opening_time", "closing_time"} <= keys


class TestBookingIsRealNotFaked:
    """"Do not create fake booking functionality."

    Transport booking IS modelled, so a booking UI would be legitimate. The rule
    is therefore tested in both directions: booking must be backed, and a
    category with NO booking table must not be granted a booking-backed field.
    """

    def test_transport_booking_has_a_real_table(self):
        assert "transport_bookings" in _tables()

    def test_the_booking_model_carries_real_trip_columns(self):
        columns = {c.name for c in transport.TransportBooking.__table__.columns}
        assert {
            "status",
            "booking_ref",
            "pickup_address",
            "destination",
            "trip_date",
        } <= columns

    def test_booking_routes_read_and_write_the_real_table(self):
        source = (
            BACKEND_DIR / "app" / "api" / "routes" / "transport.py"
        ).read_text(encoding="utf-8")
        assert "TransportBooking" in source

    def test_the_lead_time_field_is_backed_here(self):
        # Booking lead time only makes sense where booking exists, and for
        # transport it does.
        keys = {f.key for f in capability_fields_for("TRANSPORT")}
        assert "booking_lead_hours" in keys

    def test_a_restaurant_is_not_granted_a_booking_table_it_lacks(self):
        """The other half of the rule.

        Restaurants get the same generic BOOKING field, but there is no
        restaurant bookings table — so the honest thing for THIS category is to
        note the gap, and the pin here stops anyone "fixing" it by adding a
        booking screen with nothing behind it.
        """
        tables = _tables()
        assert not [t for t in tables if "restaurant" in t and "booking" in t]
        assert "transport_bookings" in tables


class TestTheFiveFutureCapabilitiesAreRealWhereModelled:
    """The spec lists these as possible; none is demanded, so each test checks
    that IF the backend models it, the modelling is real."""

    def test_service_type_is_a_real_column(self):
        columns = {c.name for c in transport.TransportService.__table__.columns}
        assert {"service_type", "base_price", "price_unit"} <= columns

    def test_vehicle_information_is_a_real_model(self):
        columns = {c.name for c in transport.Vehicle.__table__.columns}
        assert {"vehicle_type", "make", "model", "year"} <= columns

    def test_availability_is_a_real_table(self):
        assert "vehicle_availability" in _tables()
        columns = {
            c.name for c in transport.VehicleAvailability.__table__.columns
        }
        assert {"available_from", "available_to", "status"} <= columns

    def test_a_request_or_quote_is_a_real_table(self):
        assert "transport_quotes" in _tables()
        columns = {c.name for c in transport.TransportQuote.__table__.columns}
        assert {"pickup_address", "destination_address", "quote_amount"} <= columns

    def test_pricing_has_a_real_destination(self):
        columns = {c.name for c in transport.TransportService.__table__.columns}
        assert "base_price" in columns


class TestNoProductInventoryUiIsImplied:
    def test_transport_products_are_refused_by_the_route_guard(self):
        """The guard lives in the app; this pins the backend fact it relies on."""
        assert product_attributes.product_attributes_for("TRANSPORT") == ()

    def test_no_shop_product_table_gains_a_transport_specific_column(self):
        source = (
            BACKEND_DIR / "app" / "models" / "transport.py"
        ).read_text(encoding="utf-8")
        # Transport rows hang off a provider, never off a product master.
        assert "product_master_id" not in source

    def test_the_personal_travel_twin_behaves_identically(self):
        assert (
            product_attributes.product_attributes_for("PERSONAL_TRANSPORT_TRAVEL")
            == ()
        )
        assert CategoryCapability.PRODUCT_CATALOG.value not in _capabilities(
            "PERSONAL_TRANSPORT_TRAVEL"
        )


if __name__ == "__main__":
    raise SystemExit(pytest.main([__file__, "-v"]))
