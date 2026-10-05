"""Initial shop registration: the minimum data, and the location storage.

Two things are pinned here.

The first is that registration collects the MINIMUM the spec lists. Category and
business type are required because the capability model resolves through the
category — a shop without one answers 404 on every capability route, permanently
and silently.

The second is the location contract. The spec asks for GPS, manual correction and
map confirmation, stored as latitude / longitude / accuracy / captured_at /
source / address in a PostGIS-compatible shape. The schema already carries all
of it, including a real `geography(POINT,4326)`; what this file protects is the
NULLABLE agreement between the model, the migration and the route, because the
route deliberately creates a shop before a pin exists.
"""

import pytest
from geoalchemy2 import Geography
from pydantic import ValidationError

from app.models.base import Base
from app.models.merchant_category import MerchantCategoryCode
from app.models.shop import Shop
from app.schemas.shopkeeper import ShopkeeperProfileCreateRequest

from tests.geo_compat import declared_type

# The spec's "Store:" list, verbatim.
LOCATION_STORAGE = (
    "latitude",
    "longitude",
    "accuracy_meters",
    "location_captured_at",
    "location_source",
    "location",
)


def _shop_columns() -> set:
    return {c.name for c in Shop.__table__.columns}


class TestTheMinimumRequiredData:
    def test_shop_name_is_required(self):
        with pytest.raises(ValidationError):
            ShopkeeperProfileCreateRequest(
                category="HARDWARE", business_type="Retail"
            )

    def test_category_is_required(self):
        with pytest.raises(ValidationError):
            ShopkeeperProfileCreateRequest(
                shop_name="Tandoor", business_type="Retail"
            )

    def test_business_type_is_required(self):
        with pytest.raises(ValidationError):
            ShopkeeperProfileCreateRequest(shop_name="Tandoor", category="HARDWARE")

    def test_a_complete_minimum_is_accepted(self):
        request = ShopkeeperProfileCreateRequest(
            shop_name="Tandoor", category="HARDWARE", business_type="Retail"
        )
        assert request.shop_name == "Tandoor"
        assert request.category == "HARDWARE"
        assert request.business_type == "Retail"

    @pytest.mark.parametrize("code", list(MerchantCategoryCode))
    def test_the_category_check_tracks_the_registry(self, code):
        """The valid set is read from the registry, not re-typed.

        Re-typing eleven codes is how a category ends up registrable but
        unrecognised — which would only surface as a 404 much later.
        """
        assert (
            ShopkeeperProfileCreateRequest(
                shop_name="Tandoor", category=code.value, business_type="Retail"
            ).category
            == code.value
        )

    def test_an_unregistered_category_is_refused(self):
        with pytest.raises(ValidationError):
            ShopkeeperProfileCreateRequest(
                shop_name="Tandoor", category="GENERAL_STORE", business_type="Retail"
            )


class TestTheOptionalProfileFieldsRemainOptional:
    """Registration stays fast: these are collected but not demanded up front."""

    @pytest.mark.parametrize("field", ["name", "email", "phone", "description"])
    def test_the_field_exists_on_the_payload(self, field):
        assert field in ShopkeeperProfileCreateRequest.model_fields

    def test_the_minimum_payload_carries_none_of_them(self):
        request = ShopkeeperProfileCreateRequest(
            shop_name="Tandoor", category="HARDWARE", business_type="Retail"
        )
        assert request.email is None
        assert request.phone is None
        assert request.description is None


class TestLocationStorageMatchesTheSpec:
    def test_every_field_the_spec_lists_is_stored(self):
        columns = _shop_columns()
        for field in LOCATION_STORAGE:
            assert field in columns, field

    def test_the_point_is_a_real_postgis_geography(self):
        """Not two floats pretending to be a point.

        `declared_type` rather than `column.type`: `tests/geo_compat` strips
        Geography to Text on the SHARED metadata so SQLite can `create_all`, so
        by the time this file runs the live column may already be Text. Asking
        the pristine declaration is what actually pins the schema.
        """
        pristine = declared_type("shops", "location")
        assert isinstance(pristine, Geography)
        assert pristine.geometry_type == "POINT"
        assert pristine.srid == 4326

    def test_the_geography_column_is_spatially_indexed(self):
        """A geometry nobody can query by distance is decoration."""
        assert declared_type("shops", "location").spatial_index is True

    def test_the_live_column_is_geography_or_its_sqlite_stand_in(self):
        """Either form is valid depending on what has run in this process."""
        from sqlalchemy import Text

        column = Shop.__table__.columns["location"]
        assert isinstance(column.type, (Geography, Text))

    def test_latitude_and_longitude_are_floats(self):
        for name in ("latitude", "longitude"):
            column = Shop.__table__.columns[name]
            assert "FLOAT" in str(column.type).upper(), name

    def test_accuracy_is_measured_in_metres(self):
        assert "FLOAT" in str(
            Shop.__table__.columns["accuracy_meters"].type
        ).upper()

    def test_the_source_is_recorded_not_guessed(self):
        """`location_source` distinguishes how a pin was obtained, which is what
        lets the capture flow treat a manual correction differently from a GPS
        fix."""
        assert Shop.__table__.columns["location_source"].nullable is False

    def test_a_shop_may_exist_before_it_has_a_pin(self):
        """Registration creates the shop first; the capture flow supplies the pin.

        This is the agreement that was wrong: the model declared NOT NULL while
        the migration and the route both allowed no location. The database
        accepted it, so nothing failed — until the first autogenerate migration
        read the model and emitted an ALTER that would reject every new shop.
        """
        assert Shop.__table__.columns["location"].nullable is True

    def test_accuracy_and_capture_time_may_also_be_absent(self):
        """A manual or map-confirmed fix has no GPS accuracy reading."""
        columns = _shop_columns()
        for name in ("accuracy_meters", "location_captured_at"):
            assert name in columns, name
            assert Shop.__table__.columns[name].nullable is True, name


class TestTheAddressSideIsModelled:
    """Address, city, state, pincode and landmark live on `shop_addresses`,
    separate from the shop's point — one shop can serve several addresses."""

    def test_the_table_exists_with_the_specs_fields(self):
        columns = {c.name for c in Base.metadata.tables["shop_addresses"].columns}
        for field in (
            "address_line1",
            "landmark",
            "city",
            "state",
            "pincode",
            "country",
        ):
            assert field in columns, field

    def test_an_address_also_carries_its_own_point(self):
        columns = {c.name for c in Base.metadata.tables["shop_addresses"].columns}
        assert {"latitude", "longitude", "location"} <= columns

    def test_a_shop_can_have_more_than_one_address(self):
        columns = {c.name for c in Base.metadata.tables["shop_addresses"].columns}
        assert "is_primary" in columns
        assert "shop_id" in columns

    def test_address_point_is_optional_like_the_shop_point(self):
        table = Base.metadata.tables["shop_addresses"]
        assert table.columns["location"].nullable is True


class TestOperatingHoursAreModelled:
    """The spec lists Operating Hours as a core field."""

    def test_hours_and_holidays_have_their_own_tables(self):
        assert "shop_hours" in Base.metadata.tables
        assert "shop_holidays" in Base.metadata.tables


if __name__ == "__main__":
    raise SystemExit(pytest.main([__file__, "-v"]))
