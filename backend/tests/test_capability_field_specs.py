"""The Dart field mirror must match the backend's field specifications.

`capability_field_specs.py` now OWNS the field set; `capability_fields.dart` only
supplies presentation (icons, hints). Nothing on the Dart side enforces that, so
these tests do: if a key, label, kind or required flag differs between the two,
the form the shopkeeper sees is not the form the backend validates, and the
failure would otherwise appear only as a rejected save in production.
"""

import re
from pathlib import Path

import pytest

from app.models.merchant_category import CategoryCapability, MerchantCategoryCode
from app.services.capability_field_specs import (
    CAPABILITY_FIELDS,
    SERVICE_PROFILE_FIELDS,
    allowed_capability_field_keys,
    capability_fields_for,
    category_profile,
    validate_capability_fields,
)

_REPO = Path(__file__).resolve().parents[2]
_DART_FIELDS = (
    _REPO / "apps/shopkeeper_app/lib/features/shops/domain/capability_fields.dart"
)
_DART_MODELS = _REPO / "apps/shopkeeper_app/lib/features/shops/domain/shop_models.dart"

_ALL_CODES = [c.value for c in MerchantCategoryCode]

_DART_KIND = {
    "text": "TEXT",
    "multiline": "MULTILINE",
    "number": "NUMBER",
    "choice": "CHOICE",
}


def _grab(block: str, pattern: str) -> str | None:
    match = re.search(pattern, block)
    return match.group(1) if match else None


def _dart_specs() -> list[tuple[str, str, str, bool]]:
    """(key, label, kind, required) for every Dart CapabilityFieldSpec."""
    text = _DART_FIELDS.read_text(encoding="utf-8")
    specs: list[tuple[str, str, str, bool]] = []
    for block in text.split("CapabilityFieldSpec(")[1:]:
        # Stop at the end of this spec's argument list.
        block = block.split("\n    ),", 1)[0]
        key = _grab(block, r"key:\s*'([^']+)'")
        label = _grab(block, r"label:\s*'([^']+)'")
        if key is None or label is None:
            continue
        kind = _grab(block, r"kind:\s*CapabilityFieldKind\.(\w+)") or "text"
        specs.append((key, label, _DART_KIND[kind], "required: true" in block))
    return specs


def _backend_specs() -> list[tuple[str, str, str, bool]]:
    specs = [
        (s.key, s.label, s.kind, s.required)
        for group in CAPABILITY_FIELDS.values()
        for s in group
    ]
    for group in SERVICE_PROFILE_FIELDS.values():
        specs.extend((s.key, s.label, s.kind, s.required) for s in group)
    return specs


class TestDartDrift:
    def test_dart_files_exist(self):
        assert _DART_FIELDS.exists(), _DART_FIELDS
        assert _DART_MODELS.exists(), _DART_MODELS

    def test_the_same_fields_exist_on_both_sides(self):
        backend = {s[0] for s in _backend_specs()}
        dart = {s[0] for s in _dart_specs()}
        assert backend == dart, (
            "field keys differ between backend and Dart: "
            f"backend only {sorted(backend - dart)}, Dart only {sorted(dart - backend)}"
        )

    def test_labels_kinds_and_required_flags_match(self):
        backend = {s[0]: s[1:] for s in _backend_specs()}
        for key, label, kind, required in _dart_specs():
            assert key in backend, f"{key} is Dart-only"
            assert backend[key] == (label, kind, required), (
                f"{key}: backend {backend[key]} vs Dart {(label, kind, required)}"
            )

    def test_dart_does_not_re_type_category_codes(self):
        """The code→profile map belongs to shop_models.dart only."""
        text = _DART_FIELDS.read_text(encoding="utf-8")
        for code in _ALL_CODES:
            assert f"'{code}'" not in text, f"{code} is re-typed in the field file"

    def test_dart_profile_map_covers_the_same_categories(self):
        models = _DART_MODELS.read_text(encoding="utf-8")
        start = models.index("kServiceCategoryProfiles")
        block = models[start:start + 400]
        for code in SERVICE_PROFILE_FIELDS:
            assert f"'{code}'" in block, f"{code} missing from the Dart profile map"


class TestCategoryFields:
    def test_travel_gets_its_own_fields(self):
        keys = allowed_capability_field_keys("PERSONAL_TRANSPORT_TRAVEL")
        assert {"service_area", "service_types", "travel_details"} <= keys

    def test_transport_does_not_get_travel_fields(self):
        keys = allowed_capability_field_keys("TRANSPORT")
        assert "route_fares" in keys
        assert "travel_details" not in keys

    def test_a_stock_category_gets_no_service_fields(self):
        # HARDWARE holds no DOCUMENTS and no CATEGORY_SPECIFIC_DATA, so it gets
        # neither the regulatory fields nor any service-profile field.
        keys = allowed_capability_field_keys("HARDWARE")
        assert "service_area" not in keys
        assert "gst_number" not in keys
        assert "business_highlights" not in keys
        assert "contact_phone" in keys

    def test_a_service_category_gets_its_profile_fields(self):
        keys = allowed_capability_field_keys("RESTAURANTS")
        assert "menu_offerings" in keys
        assert "business_highlights" in keys
        assert "service_area" not in keys

    def test_contact_is_present_for_every_known_category(self):
        for code in _ALL_CODES:
            assert "contact_phone" in allowed_capability_field_keys(code), code

    def test_unknown_category_has_no_fields(self):
        assert allowed_capability_field_keys("NOT_A_CATEGORY") == set()

    def test_field_order_is_stable_across_calls(self):
        first = [s.key for s in capability_fields_for("PERSONAL_TRANSPORT_TRAVEL")]
        second = [s.key for s in capability_fields_for("PERSONAL_TRANSPORT_TRAVEL")]
        assert first == second

    def test_keys_are_unique_within_a_category(self):
        for code in _ALL_CODES:
            keys = [s.key for s in capability_fields_for(code)]
            assert len(keys) == len(set(keys)), code

    def test_narrowing_removes_stock_shaped_fields_only(self):
        narrowed = allowed_capability_field_keys("HOUSEHOLD_GOODS", "Service")
        assert "contact_phone" in narrowed
        assert "opening_time" in narrowed

    def test_category_profile_is_case_insensitive(self):
        assert category_profile("restaurants") == "RESTAURANTS"
        assert category_profile("HARDWARE") is None

    def test_every_capability_field_capability_is_real(self):
        for capability in CAPABILITY_FIELDS:
            assert isinstance(capability, CategoryCapability)


class TestValidation:
    # HARDWARE holds OPERATING_HOURS, so its required fields are opening_time,
    # closing_time and contact_phone. `_FULL` is the minimal valid submission,
    # used wherever the point of the test is a DIFFERENT rule.
    _FULL = {
        "opening_time": "09:00",
        "closing_time": "21:00",
        "contact_phone": "9876543210",
    }

    def test_an_unapproved_key_is_rejected_not_coerced(self):
        errors = validate_capability_fields(
            "HARDWARE", None, {**self._FULL, "admin_notes": "x"}
        )
        assert errors
        assert "not a field for this category" in errors[0]

    def test_a_required_field_must_be_present(self):
        errors = validate_capability_fields("HARDWARE", None, {})
        assert any("contact_phone" in e for e in errors)

    def test_a_blank_required_field_is_an_error(self):
        errors = validate_capability_fields(
            "HARDWARE", None, {**self._FULL, "contact_phone": "   "}
        )
        assert any("required" in e for e in errors)

    def test_a_number_field_rejects_text(self):
        assert any(
            s.key == "booking_lead_hours"
            for s in capability_fields_for("BEAUTY_PERSONAL_CARE")
        )
        errors = validate_capability_fields(
            "BEAUTY_PERSONAL_CARE", None, {"booking_lead_hours": "soon"}
        )
        assert any("must be a number" in e for e in errors)

    def test_a_number_field_rejects_negatives(self):
        errors = validate_capability_fields(
            "BEAUTY_PERSONAL_CARE", None, {"booking_lead_hours": "-4"}
        )
        assert any("negative" in e for e in errors)

    def test_a_choice_must_be_one_of_its_options(self):
        errors = validate_capability_fields(
            "HARDWARE", None, {"closed_on": "Someday"}
        )
        assert any("must be one of" in e for e in errors)

    def test_over_length_text_is_rejected(self):
        # RESTAURANTS holds DOCUMENTS, so gst_number is one of its fields.
        errors = validate_capability_fields(
            "RESTAURANTS", None, {"gst_number": "X" * 40}
        )
        assert any("longer than" in e for e in errors)

    def test_a_valid_submission_has_no_errors(self):
        assert validate_capability_fields("HARDWARE", None, self._FULL) == []

    def test_empty_submission_only_reports_required_fields(self):
        errors = validate_capability_fields("HARDWARE", None, {})
        # Optional blanks are not errors; the three required ones are.
        assert len(errors) == 3
        assert all("required" in e for e in errors)

    def test_an_omitted_required_field_is_still_an_error(self):
        """Regression: looping only over submitted keys made `required` a no-op."""
        errors = validate_capability_fields("HARDWARE", None, {"opening_time": "9"})
        assert any("contact_phone" in e for e in errors)

    def test_travel_fields_validate(self):
        assert validate_capability_fields(
            "PERSONAL_TRANSPORT_TRAVEL",
            None,
            {
                **self._FULL,
                "service_area": "Goa, Mumbai",
                "travel_details": "Family trips",
            },
        ) == []

    def test_whitespace_only_optional_field_is_fine(self):
        assert validate_capability_fields(
            "PERSONAL_TRANSPORT_TRAVEL",
            None,
            {**self._FULL, "service_area": "   "},
        ) == []

    def test_a_travel_only_key_is_refused_for_hardware(self):
        errors = validate_capability_fields(
            "HARDWARE", None, {**self._FULL, "travel_details": "x"}
        )
        assert any("travel_details" in e and "not a field" in e for e in errors)


if __name__ == "__main__":
    raise SystemExit(pytest.main([__file__, "-v"]))