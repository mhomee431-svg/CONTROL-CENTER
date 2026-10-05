"""The PERSONAL_TRANSPORT_TRAVEL category spec, pinned.

This category's instruction is the strictest in the whole set:

    "Future backend-supported capabilities may include: Service packages,
     Booking/request, Availability, Pricing, Travel/service details.
     Only render these when backend capability exists."

"Only when backend capability exists" turns the whole file into a question:
for each of those five, does the schema have somewhere to put it, for a travel
agency specifically? Checking the models answers it, and the answer is no for
all five — every transport model is chained to a `vehicles` row. So the tests
here assert the ABSENCE of those capabilities, which is the only way this spec
can be satisfied today, and pin the six business-data items that DO have real
destinations.
"""

import re
from pathlib import Path

import pytest

from app.models import merchant_category, product_attributes, transport
from app.models.merchant_category import CategoryCapability
from app.models.service_area import ServiceArea
from app.models.shop import Shop
from app.services.capability_field_specs import capability_fields_for

BACKEND_DIR = Path(__file__).resolve().parents[1]
CODE = "PERSONAL_TRANSPORT_TRAVEL"


def _capabilities(code: str = CODE) -> set:
    resolved = merchant_category.capabilities_for_category(code)
    return set(resolved.get("capabilities", ()))


def _field_keys(code: str = CODE) -> set:
    return {f.key for f in capability_fields_for(code)}


def _tables() -> set:
    found = set()
    for path in (BACKEND_DIR / "app" / "models").glob("*.py"):
        for match in re.finditer(
            r'__tablename__\s*=\s*"([^"]+)"', path.read_text(encoding="utf-8")
        ):
            found.add(match.group(1))
    return found


class TestTheFiveFutureCapabilitiesAreNotRendered:
    """"Only render these when backend capability exists." They do not exist."""

    def test_no_booking_capability_is_granted(self):
        assert CategoryCapability.BOOKING.value not in _capabilities()

    def test_no_price_capability_is_granted(self):
        assert CategoryCapability.PRICE.value not in _capabilities()

    def test_no_booking_lead_time_field_is_offered(self):
        # It comes from the shared BOOKING capability block, so removing the
        # grant is what removes the field. Left in place, a travel agency would
        # be asked for a lead time on bookings it can never receive.
        assert "booking_lead_hours" not in _field_keys()

    @pytest.mark.parametrize(
        "table",
        [
            "travel_packages",
            "tour_packages",
            "itineraries",
            "personal_travel_bookings",
            "travel_bookings",
            "package_availability",
        ],
    )
    def test_no_travel_specific_model_exists_yet(self, table):
        """The honest reason the capabilities are withheld.

        This test is expected to FAIL the day someone adds the model — which is
        the point. It is the signal to re-add BOOKING and PRICE in the same
        commit, rather than shipping a screen first and the storage later.
        """
        assert table not in _tables()

    def test_the_transport_booking_table_cannot_carry_a_travel_agency(self):
        """Not merely absent — structurally wrong for this category.

        A booking needs a vehicle row, which is what makes it a taxi trip rather
        than a tour.
        """
        columns = {c.name for c in transport.TransportBooking.__table__.columns}
        assert "vehicle_id" in columns
        assert "provider_id" in columns

    def test_availability_is_per_vehicle_not_per_package(self):
        columns = {
            c.name for c in transport.VehicleAvailability.__table__.columns
        }
        assert "vehicle_id" in columns
        assert "package_id" not in columns

    def test_trip_detail_is_a_driver_log_not_an_itinerary(self):
        columns = {c.name for c in transport.TripDetail.__table__.columns}
        # Driver and odometer columns describe executing a vehicle trip. A tour
        # itinerary would carry places, legs and timings instead.
        assert {"driver_name", "start_odometer", "actual_distance_km"} <= columns
        assert "itinerary" not in columns


class TestBusinessDataIsRenderedAndBacked:
    """The six items the spec lists under "Business data may include"."""

    def test_business_name_is_modelled(self):
        assert "name" in {c.name for c in Shop.__table__.columns}

    def test_contact_is_modelled_and_collected(self):
        columns = {c.name for c in Shop.__table__.columns}
        assert {"phone", "email"} <= columns
        assert "contact_phone" in _field_keys()

    def test_location_is_modelled_and_granted(self):
        columns = {c.name for c in Shop.__table__.columns}
        assert {"latitude", "longitude"} <= columns
        assert CategoryCapability.LOCATION.value in _capabilities()

    def test_service_description_is_collected(self):
        assert {"service_summary", "business_highlights"} <= _field_keys()

    def test_service_area_has_a_real_table_and_is_collected(self):
        assert "service_areas" in _tables()
        assert "service_area" in _field_keys()
        assert {"name", "area_type"} <= {c.name for c in ServiceArea.__table__.columns}

    def test_operating_hours_are_collected_and_backed(self):
        assert {"opening_time", "closing_time", "closed_on"} <= _field_keys()
        tables = _tables()
        assert "shop_hours" in tables and "shop_holidays" in tables

    def test_service_area_is_stored_in_a_real_column(self):
        # The descriptive fields land in `shops.capability_fields`, which exists.
        assert "capability_fields" in {c.name for c in Shop.__table__.columns}