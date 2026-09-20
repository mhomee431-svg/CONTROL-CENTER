"""Manual product-create taxonomy + barcode tests.

The models have always carried `category_id` / `subcategory_id` and a
`product_identifiers` table — the manual-create contract simply never exposed
them. These tests pin the new, still-OPTIONAL surface:

  - `ShopkeeperProductCreate` accepts category/subcategory/barcode, keeps every
    existing field optional, and bounds the barcode like the DB does
  - barcode symbology is inferred from LENGTH and never mis-guessed
  - a subcategory must actually be a child of the chosen category
  - `CategoryResponse` exposes `parent_id` / `is_subcategory` so a client can
    build the category → subcategory cascade from ONE request
"""

import os
import sys
from datetime import datetime, timezone
from pathlib import Path

BACKEND_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BACKEND_DIR))

os.environ.setdefault("ENVIRONMENT", "test")
os.environ.setdefault("HYPERLOCAL_ENV", "test")

import pytest  # noqa: E402

from app.core.exceptions import ConflictError, ValidationError  # noqa: E402
from app.models.product import Category, IdentifierType  # noqa: E402
from app.schemas.category import CategoryResponse  # noqa: E402
from app.schemas.shopkeeper import ShopkeeperProductCreate  # noqa: E402
from app.services import shopkeeper_service as svc  # noqa: E402


# ── Schema contract ──────────────────────────────────────────────────────────


def test_create_schema_accepts_the_new_optional_fields():
    payload = ShopkeeperProductCreate(
        name="Basmati Rice",
        price=120,
        category_id=4,
        subcategory_id=41,
        barcode="8901234567890",
        barcode_type="EAN",
    )
    assert payload.category_id == 4
    assert payload.subcategory_id == 41
    assert payload.barcode == "8901234567890"
    assert payload.barcode_type == "EAN"


def test_create_schema_keeps_every_field_optional_except_name_and_price():
    payload = ShopkeeperProductCreate(name="Tea", price=100)
    assert payload.category_id is None
    assert payload.subcategory_id is None
    assert payload.barcode is None
    assert payload.barcode_type is None


def test_create_schema_still_requires_name_and_price():
    with pytest.raises(Exception):
        ShopkeeperProductCreate(price=100)  # no name
    with pytest.raises(Exception):
        ShopkeeperProductCreate(name="Tea")  # no price


def test_create_schema_rejects_an_impossibly_short_barcode():
    with pytest.raises(Exception):
        ShopkeeperProductCreate(name="Tea", price=100, barcode="12")


def test_create_schema_rejects_non_positive_category_ids():
    with pytest.raises(Exception):
        ShopkeeperProductCreate(name="Tea", price=100, category_id=0)
    with pytest.raises(Exception):
        ShopkeeperProductCreate(name="Tea", price=100, subcategory_id=-2)


# ── Barcode helpers (pure) ───────────────────────────────────────────────────


def test_normalize_barcode_strips_paste_and_scanner_noise():
    assert svc.normalize_barcode(" 890-1234 5678 ") == "89012345678"
    assert svc.normalize_barcode(None) == ""
    assert svc.normalize_barcode("") == ""


def test_detect_identifier_type_maps_known_retail_lengths():
    assert svc.detect_identifier_type("12345678") is IdentifierType.EAN
    assert svc.detect_identifier_type("123456789012") is IdentifierType.UPC
    assert svc.detect_identifier_type("8901234567890") is IdentifierType.EAN
    assert svc.detect_identifier_type("01234567890128") is IdentifierType.GTIN


def test_detect_identifier_type_never_guesses_an_unknown_length():
    # A 7-digit code is NOT an EAN — it must not be labelled as one.
    assert svc.detect_identifier_type("1234567") is IdentifierType.CUSTOM


def test_resolve_identifier_type_honours_an_explicit_valid_type():
    assert svc.resolve_identifier_type("8901234567890", "upc") is IdentifierType.UPC
    # An unknown explicit name falls back to inference rather than crashing.
    assert (
        svc.resolve_identifier_type("8901234567890", "nonsense")
        is IdentifierType.EAN
    )
    assert svc.resolve_identifier_type("8901234567890", None) is IdentifierType.EAN


# ── Taxonomy validation (pure) ───────────────────────────────────────────────


def _category(cid, name="Grocery", parent=None, active=True):
    return Category(
        id=cid,
        name=name,
        slug=name.lower().replace(" ", "-"),
        parent_id=parent.id if parent is not None else None,
        is_active=active,
        is_subcategory=parent is not None,
    )


def test_validate_taxonomy_accepts_a_matching_parent_child_pair():
    parent = _category(4)
    child = _category(41, name="Rice", parent=parent)
    svc.validate_taxonomy(parent, child, 4, 41)  # no exception


def test_validate_taxonomy_rejects_an_unknown_category():
    with pytest.raises(ValidationError):
        svc.validate_taxonomy(None, None, 9999, None)


def test_validate_taxonomy_rejects_an_unknown_subcategory():
    parent = _category(4)
    with pytest.raises(ValidationError):
        svc.validate_taxonomy(parent, None, 4, 4242)


def test_validate_taxonomy_rejects_a_child_from_a_different_parent():
    parent = _category(4)
    other = _category(9, name="Other")
    child = _category(91, name="Rice", parent=other)
    with pytest.raises(ValidationError) as exc:
        svc.validate_taxonomy(parent, child, 4, 91)
    assert "does not belong" in str(exc.value)


def test_validate_taxonomy_rejects_inactive_rows():
    parent = _category(4, active=False)
    with pytest.raises(ValidationError):
        svc.validate_taxonomy(parent, None, 4, None)

    ok_parent = _category(4)
    child = _category(41, name="Rice", parent=ok_parent, active=False)
    with pytest.raises(ValidationError):
        svc.validate_taxonomy(ok_parent, child, 4, 41)


def test_validate_taxonomy_allows_a_subcategory_on_its_own():
    # No category chosen — the subcategory cannot be checked against one.
    parent = _category(4)
    child = _category(41, name="Rice", parent=parent)
    svc.validate_taxonomy(None, child, None, 41)  # no exception


# ── Category response shape ──────────────────────────────────────────────────


def test_category_response_exposes_the_cascade_fields():
    parent = _category(4)
    child = _category(41, name="Rice", parent=parent)
    now = datetime.now(timezone.utc)
    parent.created_at = now
    child.created_at = now

    parent_out = CategoryResponse.model_validate(parent)
    child_out = CategoryResponse.model_validate(child)

    assert child_out.parent_id == parent_out.id
    assert child_out.is_subcategory is True
    assert parent_out.is_subcategory is False
    assert parent_out.parent_id is None
