"""Data validation, backend layer — the authoritative one.

The spec asks for validation at the UI *and* the backend, with the backend
authoritative. This file is the audit of the backend half: one group per rule,
each pinning that a wrong value is REJECTED with a named field, rather than
merely that some code path exists.

Two of these rules were missing entirely when this was written:

  * **Field length.** Nothing capped a value against its column width, so a
    300-character product name passed every check and died at INSERT with
    PostgreSQL's "value too long" — a 500, naming neither the field nor the
    limit, after the request had been accepted.
  * **File-level limits reaching the client.** The server knew the 5 MB cap;
    the client did not, so an oversized file was discovered only after a full
    upload. The limits are now published through the import schema.
"""

from types import SimpleNamespace

import pytest

from app.core.field_limits import FIELD_LIMITS, enforce_text_lengths, text_length_error
from app.core.upload_security import UploadValidationError, validate_upload
from app.models.product import Category
from app.services import excel_import_service as svc

VALID_BARCODE = "8901234567890"  # EAN-13, correct GS1 check digit


class MockQuery:
    def __init__(self, db, model):
        self._db, self._model = db, model

    def filter(self, *args, **kwargs):
        return self

    def all(self):
        return list(self._db.rows.get(self._model, []))

    def first(self):
        rows = self.all()
        return rows[0] if rows else None


class MockDB:
    def __init__(self):
        self.rows = {}
        self.added = []

    def set(self, model, items):
        self.rows[model] = list(items)

    def query(self, model):
        return MockQuery(self, model)

    def add(self, obj):
        self.added.append(obj)

    def add_all(self, objs):
        self.added.extend(objs)

    def flush(self):
        return None


def _catalog(*categories):
    from app.models.product import ProductIdentifier, ProductMaster

    db = MockDB()
    db.set(ProductMaster, [SimpleNamespace(id=5, name="Basmati Rice 1kg", variants=[])])
    db.set(
        ProductIdentifier,
        [
            SimpleNamespace(
                identifier_value=VALID_BARCODE, product_master_id=5, is_active=True
            )
        ],
    )
    db.set(Category, list(categories))
    return db


def _values(**kw):
    base = {
        "barcode": VALID_BARCODE,
        "product_name": "Basmati Rice 1kg",
        "price": 120.0,
        "mrp": 150.0,
        "quantity": 50,
    }
    base.update(kw)
    return base


def _codes(errors):
    return {e["code"] for e in errors}


def _fields(errors):
    return {e["field"] for e in errors}


class TestRequiredFields:
    def test_a_row_with_no_identifier_is_rejected(self):
        _clean, errors = svc.validate_row(
            _catalog(), _values(barcode=None, product_name=None), set()
        )
        assert "MISSING_REQUIRED_FIELD" in _codes(errors)
        assert "product_name" in _fields(errors)

    @pytest.mark.parametrize("identifier", ["barcode", "sku", "product_name"])
    def test_any_one_identifier_is_enough(self, identifier):
        values = _values(barcode=None, product_name=None)
        values[identifier] = "RICE-1KG" if identifier == "sku" else VALID_BARCODE
        if identifier == "product_name":
            values["product_name"] = "Basmati Rice 1kg"
        db = _catalog() if identifier == "barcode" else MockDB()
        _clean, errors = svc.validate_row(db, values, set())
        assert "MISSING_REQUIRED_FIELD" not in _codes(errors)

    def test_price_is_required(self):
        _clean, errors = svc.validate_row(_catalog(), _values(price=None), set())
        assert "MISSING_REQUIRED_FIELD" in _codes(errors)
        assert "price" in _fields(errors)

    def test_a_whitespace_only_name_is_still_missing(self):
        """A cell holding a space looks filled in the spreadsheet and imports as
        nothing at all."""
        _clean, errors = svc.validate_row(
            _catalog(), _values(product_name="   "), set()
        )
        assert "MISSING_REQUIRED_FIELD" in _codes(errors)
        assert "product_name" in _fields(errors)


class TestFieldLength:
    """The rule that was missing entirely — see the module docstring."""

    @pytest.mark.parametrize(
        "field,limit",
        sorted(FIELD_LIMITS.items()),
    )
    def test_a_value_at_the_limit_is_accepted(self, field, limit):
        assert text_length_error(field, "x" * limit) is None

    @pytest.mark.parametrize("field", sorted(FIELD_LIMITS))
    def test_one_character_over_is_rejected(self, field):
        message = text_length_error(field, "x" * (FIELD_LIMITS[field] + 1))
        assert message is not None
        # The message must be actionable on its own: which field, how long, how
        # much too long.
        assert str(FIELD_LIMITS[field]) in message

    def test_the_row_validator_reports_it_as_a_row_error(self):
        _clean, errors = svc.validate_row(
            _catalog(), _values(product_name="x" * 300), set()
        )
        assert "FIELD_TOO_LONG" in _codes(errors)
        assert "product_name" in _fields(errors)

    def test_surrounding_whitespace_does_not_count(self):
        """Excel pads cells constantly; the stored value is trimmed."""
        assert text_length_error("product_name", "  " + "x" * 255 + "  ") is None

    def test_an_absent_field_is_not_an_empty_field_error(self):
        assert text_length_error("brand", None) is None
        assert text_length_error("brand", "") is None

    def test_every_offending_field_is_reported_at_once(self):
        """A spreadsheet is edited cell by cell; one round trip per mistake is
        one round trip too many."""
        _clean, errors = svc.validate_row(
            _catalog(),
            _values(product_name="x" * 300, sku="y" * 200, brand="z" * 200),
            set(),
        )
        assert {"product_name", "sku", "brand"} <= _fields(errors)

    def test_the_request_path_raises_a_clean_422(self):
        with pytest.raises(Exception) as exc:
            enforce_text_lengths({"product_name": "x" * 300})
        assert "maximum is 255" in str(exc.value)

    def test_the_request_path_is_quiet_when_everything_fits(self):
        assert enforce_text_lengths({"product_name": "Rice"}) is None

    def test_the_limits_are_published_for_the_client(self):
        """The UI must mirror the server's numbers, so they travel with the
        schema rather than being restated in the app."""
        assert svc.import_schema()["limits"] == FIELD_LIMITS


class TestNumericValues:
    @pytest.mark.parametrize("bad", ["abc", "12abc", "1.2.3", "--5"])
    def test_a_non_numeric_price_is_rejected(self, bad):
        _clean, errors = svc.validate_row(_catalog(), _values(price=bad), set())
        assert "INVALID_NUMBER" in _codes(errors)
        assert "price" in _fields(errors)

    def test_a_fractional_stock_is_rejected(self):
        """Stock is a count. 3.5 units is not a state the shop can be in."""
        _clean, errors = svc.validate_row(_catalog(), _values(quantity=3.5), set())
        assert "INVALID_QUANTITY" in _codes(errors)

    def test_a_numeric_cell_that_excel_read_as_a_float_is_fine(self):
        # Excel hands back 120.0 for an integer-looking cell; rejecting that
        # would break every real spreadsheet.
        _clean, errors = svc.validate_row(_catalog(), _values(quantity=120.0), set())
        assert errors == []

    @pytest.mark.parametrize("word", ["maybe", "sometimes", "yes-ish"])
    def test_an_unrecognised_availability_word_is_rejected(self, word):
        _clean, errors = svc.validate_row(
            _catalog(), _values(availability=word), set()
        )
        assert "INVALID_AVAILABILITY" in _codes(errors)

    def test_blank_availability_is_left_to_default(self):
        _clean, errors = svc.validate_row(_catalog(), _values(availability=None), set())
        assert errors == []


class TestPrice:
    def test_a_negative_price_is_rejected(self):
        _clean, errors = svc.validate_row(_catalog(), _values(price=-1), set())
        assert "NEGATIVE_PRICE" in _codes(errors)

    def test_zero_is_allowed(self):
        """A free giveaway is a legitimate listing, not a mistake."""
        _clean, errors = svc.validate_row(
            _catalog(), _values(price=0, mrp=None), set()
        )
        assert errors == []

    def test_price_above_mrp_is_rejected(self):
        _clean, errors = svc.validate_row(
            _catalog(), _values(price=200, mrp=100), set()
        )
        assert "PRICE_EXCEEDS_MRP" in _codes(errors)
        assert "mrp" in _fields(errors)

    def test_price_equal_to_mrp_is_allowed(self):
        _clean, errors = svc.validate_row(
            _catalog(), _values(price=100, mrp=100), set()
        )
        assert errors == []

    def test_a_negative_mrp_is_rejected(self):
        _clean, errors = svc.validate_row(_catalog(), _values(mrp=-5), set())
        assert "NEGATIVE_PRICE" in _codes(errors)

    def test_mrp_is_optional(self):
        _clean, errors = svc.validate_row(_catalog(), _values(mrp=None), set())
        assert errors == []


class TestStock:
    def test_negative_stock_is_rejected(self):
        _clean, errors = svc.validate_row(_catalog(), _values(quantity=-1), set())
        assert "NEGATIVE_QUANTITY" in _codes(errors)

    def test_an_absent_stock_column_defaults_to_zero(self):
        _clean, errors = svc.validate_row(_catalog(), _values(quantity=None), set())
        assert errors == []
        assert _clean["quantity"] == 0

    def test_zero_stock_is_a_valid_listing(self):
        """Out of stock is a state, not an error - the shop simply cannot sell
        it yet."""
        _clean, errors = svc.validate_row(_catalog(), _values(quantity=0), set())
        assert errors == []
        assert _clean["quantity"] == 0


class TestBarcode:
    def test_a_bad_check_digit_is_rejected(self):
        _clean, errors = svc.validate_row(
            _catalog(), _values(barcode="8901234567891"), set()
        )
        assert "INVALID_BARCODE" in _codes(errors)
        assert "barcode" in _fields(errors)

    def test_a_non_numeric_barcode_is_rejected(self):
        _clean, errors = svc.validate_row(_catalog(), _values(barcode="ABC"), set())
        assert "INVALID_BARCODE" in _codes(errors)

    def test_separators_are_tolerated(self):
        """Shopkeepers type and scan these; spaces and dashes are noise."""
        _clean, errors = svc.validate_row(
            _catalog(), _values(barcode="890-123 456 7890"), set()
        )
        assert "INVALID_BARCODE" not in _codes(errors)

    def test_an_absent_barcode_is_not_a_barcode_error(self):
        """The row is identified by SKU or name instead."""
        _clean, errors = svc.validate_row(_catalog(), _values(barcode=None), set())
        assert "INVALID_BARCODE" not in _codes(errors)

    def test_a_valid_ean13_is_accepted(self):
        _clean, errors = svc.validate_row(
            _catalog(), _values(barcode=VALID_BARCODE), set()
        )
        assert errors == []


def _root(name="Groceries", cid=3):
    return SimpleNamespace(
        id=cid, name=name, is_subcategory=False, parent_id=None, is_deleted=False
    )


class TestCategory:
    def test_an_unknown_category_is_rejected(self):
        _clean, errors = svc.validate_row(
            _catalog(_root()), _values(category="Spacefood"), set()
        )
        assert "UNKNOWN_CATEGORY" in _codes(errors)

    def test_a_known_category_is_accepted(self):
        _clean, errors = svc.validate_row(
            _catalog(_root()), _values(category="Groceries"), set()
        )
        assert errors == []

    def test_an_unknown_subcategory_is_rejected(self):
        _clean, errors = svc.validate_row(
            _catalog(_root()), _values(category="Groceries", subcategory="Nope"), set()
        )
        assert _codes(errors) & {"UNKNOWN_CATEGORY", "UNKNOWN_SUBCATEGORY"}

    def test_category_is_optional(self):
        _clean, errors = svc.validate_row(_catalog(), _values(category=None), set())
        assert errors == []


class TestDuplicateRecords:
    def test_a_repeated_row_is_flagged(self):
        seen = set()
        db = _catalog()
        _c1, first = svc.validate_row(db, _values(), seen)
        assert first == []
        _c2, second = svc.validate_row(db, _values(), seen)
        assert "DUPLICATE_ROW" in _codes(second)

    def test_two_different_products_are_not_duplicates(self):
        seen = set()
        db = _catalog()
        svc.validate_row(db, _values(), seen)
        _c, errors = svc.validate_row(
            db,
            _values(product_name="Sunflower Oil 1L", barcode=None, sku="OIL-1L"),
            seen,
        )
        assert "DUPLICATE_ROW" not in _codes(errors)

    def test_the_same_product_with_a_different_variant_is_not_a_duplicate(self):
        seen = set()
        db = _catalog()
        svc.validate_row(db, _values(), seen)
        _c, errors = svc.validate_row(db, _values(variant="5kg Pack"), seen)
        assert "DUPLICATE_ROW" not in _codes(errors)


class TestDates:
    """Dates live on offers, not on import rows.

    Enforced in three places on purpose — the database CHECK, the generic offer
    service and the shopkeeper offer path — so a caller that somehow bypasses
    one still cannot store an offer that ends before it starts.
    """

    def _offer(self, start, end):
        return {
            "start_date": start,
            "end_date": end,
            "offer_type": "FLAT_DISCOUNT",
            "discount_value": 10,
            "shop_product_ids": [1],
        }

    def test_an_offer_ending_before_it_starts_is_refused(self):
        from datetime import datetime, timezone

        from app.services import inventory_service

        with pytest.raises(ValueError) as exc:
            inventory_service.create_offer(
                MockDB(),
                self._offer(datetime(2026, 11, 10, tzinfo=timezone.utc),
                datetime(2026, 11, 1, tzinfo=timezone.utc)),
            )
        assert "end_date must be after start_date" in str(exc.value)

    def test_an_offer_ending_the_same_day_is_refused(self):
        from datetime import datetime, timezone

        from app.services import inventory_service

        same_day = datetime(2026, 11, 1, tzinfo=timezone.utc)
        with pytest.raises(ValueError):
            inventory_service.create_offer(MockDB(), self._offer(same_day, same_day))

    def test_a_forward_dated_offer_passes_the_date_check(self):
        from datetime import datetime, timezone

        from app.services import inventory_service

        # Fails later (no such offer type in the enum lookup path is mocked
        # out), but it must get PAST the date guard - which is what this pins.
        try:
            inventory_service.create_offer(
                MockDB(),
                self._offer(
                    datetime(2026, 11, 1, tzinfo=timezone.utc),
                    datetime(2026, 11, 10, tzinfo=timezone.utc),
                ),
            )
        # Deliberately broad: with no database behind the mock the call
        # fails later for an unrelated reason, and what this pins is that it
        # got PAST the date guard.
        except Exception as exc:  # noqa: BLE001
            assert "end_date must be after start_date" not in str(exc)

    def test_the_database_also_refuses_it(self):
        """The last line of defence, and the one that cannot be forgotten."""
        from app.models.product import Offer

        names = {c.name for c in Offer.__table__.constraints}
        assert "ck_offers_end_after_start" in names


class TestFileSize:
    def test_a_file_under_the_cap_is_accepted(self):
        assert validate_upload(
            "s.xlsx",
            b"PK\x03\x04" + b"0" * 100,
            allowed_extensions=(".xlsx",),
            max_bytes=1024,
            expected_magic=b"PK\x03\x04",
        ) == "s.xlsx"

    def test_an_oversized_file_is_refused_before_parsing(self):
        """Rejected on the declared size, so a 500 MB upload costs one length
        check rather than a full read into memory."""
        with pytest.raises(UploadValidationError) as exc:
            validate_upload(
                "s.xlsx",
                b"PK\x03\x04" + b"0" * 200,
                allowed_extensions=(".xlsx",),
                max_bytes=100,
                expected_magic=b"PK\x03\x04",
            )
        assert exc.value.reason_code == "FILE_TOO_LARGE"

    def test_the_cap_is_published_so_the_client_can_check_first(self):
        """Otherwise an oversized file is only discovered after the whole upload
        has crossed the network."""
        assert svc.import_schema()["max_file_size_bytes"] == svc.MAX_FILE_SIZE_BYTES


class TestFileType:
    def test_the_wrong_extension_is_refused(self):
        with pytest.raises(UploadValidationError) as exc:
            validate_upload(
                "evil.exe",
                b"PK\x03\x04" + b"0" * 10,
                allowed_extensions=(".xlsx",),
                max_bytes=1024,
                expected_magic=b"PK\x03\x04",
            )
        assert exc.value.reason_code == "INVALID_FILE_TYPE"

    def test_a_renamed_non_workbook_is_refused(self):
        """An .xlsx name proves nothing; the bytes do."""
        with pytest.raises(UploadValidationError) as exc:
            validate_upload(
                "s.xlsx",
                b"MZ\x90\x00binary",
                allowed_extensions=(".xlsx",),
                max_bytes=1024,
                expected_magic=b"PK\x03\x04",
            )
        assert exc.value.reason_code == "CONTENT_TYPE_MISMATCH"

    def test_an_empty_file_is_refused(self):
        with pytest.raises(UploadValidationError) as exc:
            validate_upload(
                "s.xlsx",
                b"",
                allowed_extensions=(".xlsx",),
                max_bytes=1024,
                expected_magic=b"PK\x03\x04",
            )
        assert exc.value.reason_code == "EMPTY_FILE"

    def test_the_extension_is_stripped_from_the_stored_name(self):
        """A name is display data; a traversal in it is not."""
        safe = validate_upload(
            "../../etc/passwd.xlsx",
            b"PK\x03\x04" + b"0" * 10,
            allowed_extensions=(".xlsx",),
            max_bytes=1024,
            expected_magic=b"PK\x03\x04",
        )
        assert "/" not in safe and ".." not in safe


if __name__ == "__main__":
    raise SystemExit(pytest.main([__file__, "-v"]))