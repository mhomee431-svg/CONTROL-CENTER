"""Column Mapping: propose, refuse to guess, and correct before import.

The spec's two hard requirements, tested together because they are the same
requirement seen from two sides:

  * "Do not silently map ambiguous fields" — a contested column must come back
    UNMAPPED with a reason, not resolved by first-match-wins.
  * "Allow correction before import" — the shopkeeper's corrected mapping must
    actually change which rows are valid.

The second only makes sense if the first is real. A silent tie-break would make
the mapping look settled, and the correction step would have nothing to correct.
"""

import json
from types import SimpleNamespace

import pytest

from app.models.inventory_import import ImportJobStatus
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


class FakeAccess:
    shop = SimpleNamespace(id=10)

    def require(self, resource, action):
        return None


def _catalog():
    """A DB where VALID_BARCODE resolves to a real master."""
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
    db.set(Category, [])
    return db


def _job(header, cells, status=ImportJobStatus.AWAITING_CONFIRMATION):

    job = SimpleNamespace(
        id=1,
        shop_id=10,
        filename="stock.xlsx",
        status=status,
        total_rows=len(cells),
        valid_rows=0,
        error_rows=0,
        processed_rows=0,
        failed_rows=0,
        error_message=None,
        created_at=None,
        started_at=None,
        completed_at=None,
        header_row=json.dumps(header),
        column_mapping=None,
    )
    rows = [
        SimpleNamespace(
            job_id=1,
            row_number=i + 1,
            status="VALID",
            raw_data=json.dumps(row),
            normalized_data="{}",
            error_code=None,
            error_field=None,
            error_message=None,
            product_master_id=None,
            variant_id=None,
        )
        for i, row in enumerate(cells)
    ]
    return job, rows


def _db_with(job, rows):
    from app.models.inventory_import import (
        InventoryImportJob,
        InventoryImportRow,
    )

    db = _catalog()
    db.set(InventoryImportJob, [job])
    db.set(InventoryImportRow, rows)
    return db


# A sheet whose 3rd and 4th columns BOTH look like a price — the exact shape
# that used to resolve silently to whichever came first.
CONTESTED_HEADER = ["Barcode", "Item Name", "Price", "Selling Price"]
CONTESTED_CELLS = [[VALID_BARCODE, "Basmati Rice 1kg", "120", "99"]]


class TestAmbiguousColumnsAreNotSilentlyMapped:
    def test_two_columns_claiming_one_field_map_neither(self):
        proposals = svc.propose_columns(CONTESTED_HEADER)

        contested = {p["header"]: p for p in proposals}
        assert contested["Price"]["status"] == "ambiguous"
        assert contested["Selling Price"]["status"] == "ambiguous"
        assert contested["Price"]["suggested_field"] is None
        assert contested["Selling Price"]["suggested_field"] is None

    def test_the_ambiguity_is_explained_not_just_withheld(self):
        """Withheld without a reason looks like a bug; the shopkeeper has to be
        told WHY so they know they have to choose."""
        for p in svc.propose_columns(CONTESTED_HEADER):
            if p["header"] in ("Price", "Selling Price"):
                assert p["reason"] == "MULTIPLE_COLUMNS_CLAIM_THIS_FIELD"
                assert p["candidates"] == ["price"]

    def test_the_uncontested_columns_are_still_mapped(self):
        """Refusing to guess about two columns must not cost the other two."""
        assert svc.map_headers(CONTESTED_HEADER) == {
            "barcode": 0,
            "product_name": 1,
        }

    def test_a_header_matching_several_fields_is_ambiguous(self):
        svc.FIELD_ALIASES["_probe_a"] = {"twice claimed"}
        svc.FIELD_ALIASES["_probe_b"] = {"twice claimed"}
        try:
            proposal = svc.propose_columns(["Twice Claimed"])[0]
            assert proposal["status"] == "ambiguous"
            assert proposal["suggested_field"] is None
            assert proposal["reason"] == "HEADER_MATCHES_SEVERAL_FIELDS"
        finally:
            svc.FIELD_ALIASES.pop("_probe_a", None)
            svc.FIELD_ALIASES.pop("_probe_b", None)

    def test_an_unknown_column_is_unmatched_not_ambiguous(self):
        """Different problem, different wording: nobody claimed this header."""
        proposal = svc.propose_columns(["Colour"])[0]
        assert proposal["status"] == "unmatched"
        assert proposal["candidates"] == []
        assert proposal["reason"] is None

    def test_a_blank_spacer_column_is_not_a_column(self):
        proposals = svc.propose_columns(["Barcode", "", "Price"])
        assert [p["column_index"] for p in proposals] == [0, 2]

    def test_the_original_header_text_is_shown_back_to_the_shopkeeper(self):
        """They are looking at their own sheet, so the app must speak their
        spelling — not a normalised version they do not recognise."""
        proposals = svc.propose_columns(["Item_Name", "Stock Qty"])
        assert [p["header"] for p in proposals] == ["Item_Name", "Stock Qty"]


class TestValidateMapping:
    def test_a_good_mapping_has_no_problems(self):
        assert svc.validate_mapping({"barcode": 0, "price": 2}, CONTESTED_HEADER) == []

    def test_an_unknown_field_is_rejected(self):
        problems = svc.validate_mapping({"colour": 1}, CONTESTED_HEADER)
        assert any("not a field HyperLocal can import" in p for p in problems)

    def test_a_column_past_the_end_of_the_sheet_is_rejected(self):
        problems = svc.validate_mapping({"barcode": 0, "price": 9}, CONTESTED_HEADER)
        assert any("only has 4 columns" in p for p in problems)

    def test_two_fields_on_one_column_is_rejected(self):
        """The cell would have to hold both values; validate_row would quietly
        let one win, which is the bug this whole step exists to stop."""
        problems = svc.validate_mapping(
            {"barcode": 0, "price": 2, "mrp": 2}, CONTESTED_HEADER
        )
        assert any("both point at column 3" in p for p in problems)

    def test_no_identifier_is_rejected(self):
        problems = svc.validate_mapping({"price": 2}, CONTESTED_HEADER)
        assert any("Map at least one of" in p for p in problems)

    def test_every_problem_is_reported_at_once(self):
        """One resubmit per mistake is one resubmit too many."""
        problems = svc.validate_mapping({"colour": 9}, CONTESTED_HEADER)
        assert len(problems) >= 2


class TestCorrectionBeforeImport:
    def test_a_contested_price_leaves_the_row_invalid_until_chosen(self):
        job, rows = _job(CONTESTED_HEADER, CONTESTED_CELLS)
        db = _db_with(job, rows)
        result = svc.remap_import(
            FakeAccess(), db, 1, {"barcode": 0, "product_name": 1}
        )
        assert result["error_rows"] == 1
        # It is the PRICE that is missing, and the row says so by field — not
        # just "something is wrong with this row".
        assert result["rows"][0]["error_field"] == "price"

    def test_choosing_the_first_price_column_makes_the_row_valid(self):
        job, rows = _job(CONTESTED_HEADER, CONTESTED_CELLS)
        db = _db_with(job, rows)
        result = svc.remap_import(
            FakeAccess(), db, 1, {"barcode": 0, "product_name": 1, "price": 2}
        )
        assert result["valid_rows"] == 1
        assert result["rows"][0]["price"] == 120.0

    def test_choosing_the_other_price_column_imports_that_value(self):
        """The correction is not cosmetic — a different column means different
        numbers in the shop's inventory."""
        job, rows = _job(CONTESTED_HEADER, CONTESTED_CELLS)
        db = _db_with(job, rows)
        result = svc.remap_import(
            FakeAccess(), db, 1, {"barcode": 0, "product_name": 1, "price": 3}
        )
        assert result["valid_rows"] == 1
        assert result["rows"][0]["price"] == 99.0

    def test_removing_a_field_revalidates_the_row(self):
        """A row VALID under one mapping can be an ERROR under another: this is
        why the rows are re-validated instead of patched."""
        from app.models.inventory_import import InventoryImportRow

        job, rows = _job(CONTESTED_HEADER, CONTESTED_CELLS)
        db = _db_with(job, rows)
        svc.remap_import(
            FakeAccess(), db, 1, {"barcode": 0, "product_name": 1, "price": 2}
        )
        assert db.rows[InventoryImportRow][0].status == "VALID"

        again = svc.remap_import(
            FakeAccess(), db, 1, {"barcode": 0, "product_name": 1}
        )
        assert again["valid_rows"] == 0
        assert again["error_rows"] == 1

    def test_the_correction_survives_a_reload(self):
        """Otherwise the shopkeeper is asked the same question every time they
        open the preview, and their answer is thrown away."""
        job, rows = _job(CONTESTED_HEADER, CONTESTED_CELLS)
        db = _db_with(job, rows)
        svc.remap_import(
            FakeAccess(), db, 1, {"barcode": 0, "product_name": 1, "price": 3}
        )

        reloaded = svc.get_import_preview(FakeAccess(), db, 1)
        assert reloaded["column_mapping"]["price"] == 3
        assert reloaded["rows"][0]["price"] == 99.0

    def test_a_null_field_is_skipped_rather_than_rejected(self):
        """"Don't import this column" is a valid answer, not a broken payload."""
        job, rows = _job(CONTESTED_HEADER, CONTESTED_CELLS)
        db = _db_with(job, rows)
        result = svc.remap_import(
            FakeAccess(),
            db,
            1,
            {"barcode": 0, "product_name": 1, "price": 2, "mrp": None},
        )
        assert "mrp" not in result["column_mapping"]

    def test_the_result_carries_the_proposal_so_the_screen_can_re_render(self):
        job, rows = _job(CONTESTED_HEADER, CONTESTED_CELLS)
        db = _db_with(job, rows)
        result = svc.remap_import(
            FakeAccess(), db, 1, {"barcode": 0, "product_name": 1, "price": 2}
        )
        assert {p["header"] for p in result["column_proposal"]} == set(CONTESTED_HEADER)
        assert result["header_row"] == CONTESTED_HEADER

    def test_a_replayed_upload_still_shows_the_mapping(self):
        """Re-uploading the same file replays the original job — and it must
        still carry the header and the applied mapping.

        Returning only the job counters would leave the Column Mapping screen
        empty for exactly the shopkeeper who has just re-picked a file, which
        reads as "the mapping was lost" rather than "this file was already
        imported".
        """
        from app.models.inventory_import import (
            InventoryImportJob,
            InventoryImportRow,
        )

        job = SimpleNamespace(
            id=5,
            shop_id=10,
            filename="stock.xlsx",
            status=ImportJobStatus.AWAITING_CONFIRMATION,
            total_rows=1,
            valid_rows=1,
            error_rows=0,
            processed_rows=0,
            failed_rows=0,
            error_message=None,
            created_at=None,
            started_at=None,
            completed_at=None,
            header_row=json.dumps(CONTESTED_HEADER),
            column_mapping=json.dumps({"barcode": 0, "product_name": 1}),
        )
        db = _catalog()
        db.set(InventoryImportJob, [job])
        db.set(InventoryImportRow, [])
        # Any content works: the replay branch is reached before parsing.
        from app.services import xlsx_lite

        content = xlsx_lite.write_workbook(
            [CONTESTED_HEADER] + CONTESTED_CELLS
        )
        result = svc.create_import(
            FakeAccess(), db, SimpleNamespace(id=7), "stock.xlsx", content
        )

        assert result["idempotent_replay"] is True
        assert result["column_mapping"] == {"barcode": 0, "product_name": 1}
        assert result["header_row"] == CONTESTED_HEADER
        assert {p["header"] for p in result["column_proposal"]} == set(CONTESTED_HEADER)

    def test_an_applied_import_can_no_longer_be_remapped(self):
        job, rows = _job(
            CONTESTED_HEADER, CONTESTED_CELLS, status=ImportJobStatus.COMPLETED
        )
        db = _db_with(job, rows)
        with pytest.raises(Exception) as exc:
            svc.remap_import(
                FakeAccess(), db, 1, {"barcode": 0, "product_name": 1, "price": 2}
            )
        assert "already been applied" in str(exc.value)

    def test_a_job_staged_before_mapping_existed_says_so(self):
        """Its rows are field-keyed, so there is nothing to re-index — quietly
        returning blanks would import an empty shop."""
        job, rows = _job(CONTESTED_HEADER, CONTESTED_CELLS)
        job.header_row = None
        db = _db_with(job, rows)
        with pytest.raises(Exception) as exc:
            svc.remap_import(
                FakeAccess(), db, 1, {"barcode": 0, "product_name": 1, "price": 2}
            )
        assert "Upload the file again" in str(exc.value)

    def test_a_stale_product_resolution_is_replaced(self):
        """The row's product ids must follow the NEW mapping.

        A correction can point a row at a different product entirely (the old
        barcode column may have been the SKU column, say). Carrying the old ids
        forward would apply the new prices to the wrong product — the most
        damaging thing this whole step could get wrong.
        """
        job, rows = _job(CONTESTED_HEADER, CONTESTED_CELLS)
        rows[0].product_master_id = 99  # resolved under the previous mapping
        rows[0].variant_id = 7
        db = _db_with(job, rows)

        svc.remap_import(
            FakeAccess(), db, 1, {"barcode": 0, "product_name": 1, "price": 2}
        )

        assert rows[0].product_master_id == 5
        assert rows[0].variant_id is None

    def test_a_bad_mapping_is_refused_before_any_row_is_touched(self):
        job, rows = _job(CONTESTED_HEADER, CONTESTED_CELLS)
        db = _db_with(job, rows)
        with pytest.raises(Exception) as exc:
            svc.remap_import(FakeAccess(), db, 1, {"barcode": 99})
        assert "only has 4 columns" in str(exc.value)
        assert rows[0].status == "VALID"  # untouched
        assert job.column_mapping is None


if __name__ == "__main__":
    raise SystemExit(pytest.main([__file__, "-v"]))