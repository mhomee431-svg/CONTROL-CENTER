from app.services.capability_fields_service import (
    has_product_form,
    sanitise_capability_fields,
)


class TestSanitisation:
    def test_an_approved_key_is_stored(self):
        stored, rejected = sanitise_capability_fields(
            "HARDWARE",
            None,
            {"opening_time": "09:00", "closing_time": "21:00",
             "contact_phone": "9876543210"},
        )
        assert stored["opening_time"] == "09:00"
        assert rejected == []

    def test_an_unapproved_key_is_reported_not_silently_dropped(self):
        stored, rejected = sanitise_capability_fields(
            "HARDWARE", None, {"contact_phone": "9876543210", "admin": "root"}
        )
        assert "admin" not in stored
        assert rejected == ["admin"]

    def test_a_field_from_another_category_is_refused(self):
        _, rejected = sanitise_capability_fields(
            "HARDWARE",
            None,
            {"contact_phone": "9876543210", "travel_details": "tours"},
        )
        assert rejected == ["travel_details"]

    def test_a_travel_field_is_accepted_for_travel(self):
        stored, rejected = sanitise_capability_fields(
            "PERSONAL_TRANSPORT_TRAVEL",
            None,
            {"contact_phone": "9876543210", "service_area": "Goa"},
        )
        assert stored["service_area"] == "Goa"
        assert rejected == []

    def test_values_are_trimmed(self):
        stored, _ = sanitise_capability_fields(
            "HARDWARE", None, {"contact_phone": "  9876543210  "}
        )
        assert stored["contact_phone"] == "9876543210"

    def test_blank_values_are_dropped_not_stored_as_empty(self):
        stored, rejected = sanitise_capability_fields(
            "HARDWARE", None, {"contact_phone": "9876543210", "service_summary": "  "}
        )
        assert "service_summary" not in stored
        assert rejected == []

    def test_none_and_empty_submissions_store_nothing(self):
        for payload in (None, {}):
            stored, rejected = sanitise_capability_fields("HARDWARE", None, payload)
            assert stored == {}
            assert rejected == []

    def test_an_empty_key_is_reported_not_stored(self):
        stored, rejected = sanitise_capability_fields(
            "HARDWARE", None, {"": "x", "contact_phone": "9876543210"}
        )
        assert "" not in stored
        assert rejected == [""]

    def test_an_unknown_category_stores_nothing(self):
        stored, rejected = sanitise_capability_fields(
            "NOT_A_CATEGORY", None, {"contact_phone": "1"}
        )
        assert stored == {}
        assert rejected == ["contact_phone"]


class TestHasProductForm:
    def test_a_stock_category_has_a_product_form(self):
        assert has_product_form("HARDWARE", None) is True

    def test_a_service_category_does_not(self):
        for code in ("RESTAURANTS", "TRANSPORT", "PERSONAL_TRANSPORT_TRAVEL"):
            assert has_product_form(code, None) is False, code

    def test_narrowing_to_service_removes_the_product_form(self):
        assert has_product_form("HARDWARE", "Service") is False
        assert has_product_form("HARDWARE", "Retail") is True

    def test_an_unknown_category_has_none(self):
        assert has_product_form("NOT_A_CATEGORY", None) is False


if __name__ == "__main__":
    raise SystemExit(pytest.main([__file__, "-v"]))