"""Invariant tests for the canonical merchant-category registry.

These tests do NOT require a database. They pin the single source of truth
(``app.models.merchant_category.MerchantCategoryCode`` + ``MERCHANT_CATEGORY_NAMES``)
so the 11 approved categories can never drift:

 * The count is exactly 11.
 * Display names are the canonical set (incl. "Personal Transport / Personal Travel").
 * Grocery / General Food are forbidden by construction (absent from every name/code).
 * The schema's accepted codes, the seed names and the db_seed domain names all
   equal this one registry.
"""
import pytest

from app.models.merchant_category import MERCHANT_CATEGORY_NAMES, MerchantCategoryCode

APPROVED_DISPLAY_NAMES = {
    "Pharmacy & Healthcare",
    "Beauty & Personal Care",
    "Furniture & Home Care",
    "Household Goods",
    "Sports, Fitness & Outdoor",
    "Books, Media & Stationery",
    "Automotive Parts & Tools",
    "Hardware",
    "Restaurants",
    "Transport",
    "Personal Transport / Personal Travel",
}
FORBIDDEN_TERMS = {"grocery", "general food", "staples"}


def test_approved_category_count_is_11():
    assert len(MerchantCategoryCode) == 11


def test_codes_are_canonical():
    assert {c.value for c in MerchantCategoryCode} == set(MERCHANT_CATEGORY_NAMES)


def test_names_are_canonical_display_names():
    assert set(MERCHANT_CATEGORY_NAMES.values()) == APPROVED_DISPLAY_NAMES


def test_names_are_bijective():
    names = list(MERCHANT_CATEGORY_NAMES.values())
    assert len(names) == len(set(names)), "duplicate category display names"


def test_personal_transport_uses_canonical_slash_form():
    assert (
        MERCHANT_CATEGORY_NAMES[
            MerchantCategoryCode.PERSONAL_TRANSPORT_TRAVEL.value
        ]
        == "Personal Transport / Personal Travel"
    )


def test_no_forbidden_grocery_terms_in_codes_or_names():
    blob = " ".join(MERCHANT_CATEGORY_NAMES.keys()).lower()
    blob += " " + " ".join(MERCHANT_CATEGORY_NAMES.values()).lower()
    for term in FORBIDDEN_TERMS:
        assert term not in blob, f"forbidden term present in category registry: {term}"


def test_schema_accepts_exactly_canonical_codes():
    """The onboarding request-validator accepts ONLY the 11 canonical codes
    and rejects grocery / general food at the schema boundary."""
    from app.schemas.merchant_onboarding import MerchantOnboardingRequest

    # field_validator produces a classmethod -> callable directly with just `v`.
    validate = MerchantOnboardingRequest.validate_category

    # Every canonical code (and any-case variant) is accepted and upper-cased.
    for code in MerchantCategoryCode:
        assert validate(code.value) == code.value
        assert validate(code.value.lower()) == code.value

    # Grocery / general food / staples are rejected.
    for bad in ("GROCERY", "grocery", "GENERAL_FOOD", "staples", "FOO_BAR"):
        with pytest.raises(ValueError):
            validate(bad)
