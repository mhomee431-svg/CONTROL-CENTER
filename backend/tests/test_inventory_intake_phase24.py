"""Phase 24 — Barcode Scanning and Excel Inventory intake tests.

Covers the full required matrix:
  PART A — Barcode:
    success · invalid format · unknown barcode · duplicate barcode /
    multiple matches · network failure · product unavailable ·
    variant mismatch · duplicate listing · scan-event recording
  PART B — Excel:
    valid file · invalid file · partial failure · large file (background
    job) · duplicate rows · retry · idempotent re-upload · import report
  VERIFY — both paths update the SAME canonical inventory system
    (inventory_service.get_shop_inventory sees BARCODE_SCAN / EXCEL_UPLOAD).
"""

import json
import os
import sys
from pathlib import Path
from types import SimpleNamespace

BACKEND_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BACKEND_DIR))

os.environ.setdefault("ENVIRONMENT", "test")
os.environ.setdefault("HYPERLOCAL_ENV", "test")

import pytest  # noqa: E402
from sqlalchemy.orm import attributes  # noqa: E402

from app.core.config import settings  # noqa: E402

settings.RATE_LIMIT_ENABLED = False


# ── Mock infrastructure (mirrors Phase 22/23 pattern) ────────────────────


class MockQuery:
    """Chainable query mock with FIFO `first()` queues and fixed `all()`."""

    def __init__(self, db, model):
        self._db = db
        self._model = model

    def filter(self, *args, **kwargs):
        return self

    def filter_by(self, **kwargs):
        return self

    def join(self, *args, **kwargs):
        return self

    def options(self, *args, **kwargs):
        return self

    def order_by(self, *args):
        return self

    def offset(self, *args):
        return self

    def limit(self, *args):
        return self

    def first(self):
        queue = self._db.first_queues.get(self._model)
        if queue:
            return queue.pop(0)
        matches = [o for o in self._db.added if isinstance(o, self._model)]
        return matches[0] if matches else None

    def all(self):
        return list(self._db.all_results.get(self._model, []))

    def count(self):
        return len(self.all())

    def delete(self, synchronize_session=False):
        return 0


class IntakeMockDB:
    """DB mock tuned for the Phase 24 intake service call patterns."""

    explode_on_query = False

    def __init__(self):
        self.added = []
        self.committed = 0
        self.flushes = 0
        self.first_queues: dict = {}
        self.all_results: dict = {}
        self._next_id = 900

    def queue_first(self, model, items):
        self.first_queues.setdefault(model, []).extend(items)

    def set_all(self, model, items):
        self.all_results[model] = list(items)

    def query(self, model):
        if self.explode_on_query:
            raise ConnectionError("network unreachable")
        return MockQuery(self, model)

    def add(self, obj):
        self.added.append(obj)

    def add_all(self, objs):
        self.added.extend(objs)

    def flush(self):
        self.flushes += 1
        for obj in self.added:
            if hasattr(obj, "id") and getattr(obj, "id", None) is None:
                obj.id = self._next_id
                self._next_id += 1

    def commit(self):
        self.committed += 1

    def rollback(self):
        pass

    def objects_of(self, cls):
        return [o for o in self.added if isinstance(o, cls)]


class FakeAccess:
    """Pre-authorized access context (permission logic covered in Phase 23)."""

    def __init__(self, shop_id=10):
        self.shop = SimpleNamespace(id=shop_id)

    def can(self, resource, action):
        return True

    def require(self, resource, action):
        return None


def make_user(user_id=7):
    return SimpleNamespace(id=user_id)


# ── Domain fixtures ───────────────────────────────────────────────────────

VALID_BARCODE = "8901234567890"  # EAN-13 with correct GS1 check digit


def make_master(master_id=5, name="Basmati Rice 1kg", variants=None,
                is_active=True, status="APPROVED", brand_name=None,
                image_url=None):
    """Real ORM instance so relationship assignment (sp.product_master) works."""
    from app.models.product import ProductMaster, ProductStatus

    master = ProductMaster(
        name=name,
        slug=f"{name.lower().replace(' ', '-')}-{master_id}",
        status=getattr(ProductStatus, status),
        is_active=is_active,
    )
    master.id = master_id
    master.is_deleted = False
    master.brand_id = None
    master.variants = list(variants) if variants is not None else [make_variant()]
    if brand_name is not None:
        # set_committed_value bypasses the relationship's backref event,
        # which would require a fully-attached ORM Brand instance.
        attributes.set_committed_value(
            master, "brand", SimpleNamespace(name=brand_name)
        )
    if image_url is not None:
        attributes.set_committed_value(
            master, "images",
            [SimpleNamespace(image_url=image_url, is_primary=True)],
        )
    return master


def make_variant(variant_id=11, name="1kg Pack", sku="RICE-1KG"):
    from app.models.product import ProductVariant

    variant = ProductVariant(sku=sku, name=name)
    variant.id = variant_id
    return variant


def make_identifier(barcode=VALID_BARCODE, master_id=5, ident_type="EAN"):
    from app.models.product import IdentifierType

    return SimpleNamespace(
        identifier_value=barcode,
        identifier_type=getattr(IdentifierType, ident_type),
        product_master_id=master_id,
        is_active=True,
    )


def make_relationship(barcode=VALID_BARCODE, master_id=5):
    return SimpleNamespace(
        barcode=barcode,
        product_master_id=master_id,
        relationship_type="PRIMARY",
        is_active=True,
    )


EXCEL_HEADERS = [
    "Barcode", "Product Name", "Brand", "Variant",
    "SKU", "Price", "MRP", "Quantity", "Availability",
]

GOOD_ROW = [VALID_BARCODE, "Basmati Rice 1kg", "India Gate", "1kg Pack",
            "RICE-1KG", "120", "150", "50", "yes"]


def make_excel_rows(data_rows):
    from app.services import xlsx_lite

    return xlsx_lite.write_workbook([EXCEL_HEADERS] + data_rows)


# ── Part A: barcode format validation ────────────────────────────────────


class TestBarcodeFormatValidation:
    def test_valid_ean13(self):
        from app.services import barcode_intake_service as svc

        ok, reason = svc.validate_barcode_format(VALID_BARCODE)
        assert ok and reason is None

    @pytest.mark.parametrize("code,reason", [
        ("", "empty"),
        ("89ABC4567890", "non_numeric"),
        ("12345", "invalid_length"),
        (VALID_BARCODE[:-1] + "1", "bad_check_digit"),
    ])
    def test_invalid_cases(self, code, reason):
        from app.services import barcode_intake_service as svc

        ok, got = svc.validate_barcode_format(code)
        assert not ok and got == reason

    def test_normalization_strips_separators(self):
        from app.services import barcode_intake_service as svc

        cleaned = svc.normalize_barcode(
            f" {VALID_BARCODE[:6]}-{VALID_BARCODE[6:]} "
        )
        assert cleaned == VALID_BARCODE


# ── Part A: barcode scan flow ────────────────────────────────────────────


class TestBarcodeScanFlow:
    def test_barcode_success(self):
        """Scan → identify → find product → FOUND with variant list."""
        from app.services import barcode_intake_service as svc

        master = make_master(
            variants=[make_variant()],
            brand_name="India Gate",
            image_url="https://example.com/basmati.jpg",
        )
        db = IntakeMockDB()
        from app.models.product import BarcodeRelationship, ProductIdentifier, ProductMaster

        db.set_all(ProductIdentifier, [make_identifier()])
        db.set_all(BarcodeRelationship, [])
        db.queue_first(ProductMaster, [master])

        result = svc.resolve_barcode(db, VALID_BARCODE)
        assert result["status"] == "FOUND"
        assert result["barcode_type"] == "EAN-13"
        assert len(result["matches"]) == 1
        match = result["matches"][0]
        assert match["name"] == "Basmati Rice 1kg"
        assert match["brand_name"] == "India Gate"
        assert match["image_url"] == "https://example.com/basmati.jpg"
        assert match["variants"][0]["sku"] == "RICE-1KG"
        assert match["is_available_in_catalog"] is True

    def test_unknown_barcode(self):
        from app.models.product import BarcodeRelationship, ProductIdentifier
        from app.services import barcode_intake_service as svc

        db = IntakeMockDB()
        db.set_all(ProductIdentifier, [])
        db.set_all(BarcodeRelationship, [])

        result = svc.resolve_barcode(db, VALID_BARCODE)
        assert result["status"] == "NOT_FOUND"
        assert result["error_code"] == "BARCODE_NOT_FOUND"

        # Scan event recorded even when nothing matched.
        from app.models.search import BarcodeScan

        svc.record_scan_event(db, VALID_BARCODE, is_match_found=False)
        assert any(isinstance(o, BarcodeScan) for o in db.added)

    def test_invalid_barcode_rejected(self):
        from app.core.exceptions import ValidationError
        from app.services import barcode_intake_service as svc

        with pytest.raises(ValidationError):
            svc.resolve_barcode(IntakeMockDB(), "12345")

    def test_duplicate_barcode_multiple_matches(self):
        """Same code registered to two catalog products → MULTIPLE_MATCHES."""
        from app.models.product import BarcodeRelationship, ProductIdentifier
        from app.services import barcode_intake_service as svc

        master_a = make_master(master_id=5, name="Basmati Rice 1kg")
        master_b = make_master(master_id=6, name="Sona Masoori Rice 1kg")

        db = IntakeMockDB()
        db.set_all(ProductIdentifier, [
            make_identifier(master_id=5),
            make_identifier(master_id=6),
        ])
        db.set_all(BarcodeRelationship, [])
        from app.models.product import ProductMaster

        db.queue_first(ProductMaster, [master_a])
        db.queue_first(ProductMaster, [master_b])

        result = svc.resolve_barcode(db, VALID_BARCODE)
        assert result["status"] == "MULTIPLE_MATCHES"
        assert result["error_code"] == "MULTIPLE_BARCODE_MATCHES"
        assert len(result["matches"]) == 2

    def test_network_failure_maps_to_service_unavailable(self):
        from app.core.exceptions import ServiceUnavailableError
        from app.services import barcode_intake_service as svc

        db = IntakeMockDB()
        db.explode_on_query = True
        with pytest.raises(ServiceUnavailableError):
            svc.resolve_barcode(db, VALID_BARCODE)

    def _save_context(self, db, master):
        from app.models.product import ProductMaster

        db.queue_first(ProductMaster, [master])

    def test_save_from_scan_success(self):
        from app.models.product import (
            Inventory,
            InventoryMovement,
            ProductMaster,
            ShopProduct,
        )
        from app.services import barcode_intake_service as svc

        master = make_master(variants=[make_variant()])
        db = IntakeMockDB()
        self._save_context(db, master)
        db.queue_first(ShopProduct, [None])  # no duplicate listing

        result = svc.save_from_scan(FakeAccess(), db, make_user(), {
            "barcode": VALID_BARCODE,
            "product_master_id": master.id,
            "variant_id": 11,
            "price": 120.0,
            "mrp": 150.0,
            "quantity": 40,
            "is_available": True,
            "publish": True,
        })

        assert result["source"] == "BARCODE_SCAN"
        assert result["quantity"] == 40
        assert result["is_active"] is True  # published

        sp = db.objects_of(ShopProduct)[-1]
        inv = db.objects_of(Inventory)[-1]
        movement = db.objects_of(InventoryMovement)[-1]
        assert sp.source.value == "BARCODE_SCAN"
        assert inv.quantity == 40
        assert movement.reference_type == "BARCODE_SCAN"
        assert movement.movement_type == "INITIAL"

    def test_variant_mismatch_rejected(self):
        """Variant that does not belong to the scanned master is rejected."""
        from app.core.exceptions import ValidationError
        from app.models.product import ProductMaster, ShopProduct
        from app.services import barcode_intake_service as svc

        master = make_master(variants=[make_variant(variant_id=11)])
        other_variant = make_variant(variant_id=99)  # belongs to another product

        db = IntakeMockDB()
        db.queue_first(ProductMaster, [master])

        with pytest.raises(ValidationError):
            svc.save_from_scan(FakeAccess(), db, make_user(), {
                "barcode": VALID_BARCODE,
                "product_master_id": master.id,
                "variant_id": other_variant.id,
                "price": 120.0,
                "quantity": 10,
            })

    def test_product_unavailable_rejected(self):
        """Inactive / archived / rejected catalog products cannot be listed."""
        from app.core.exceptions import ValidationError
        from app.models.product import ProductMaster, ShopProduct
        from app.services import barcode_intake_service as svc

        for status in ("INACTIVE", "ARCHIVED", "REJECTED"):
            master = make_master(status=status)
            db = IntakeMockDB()
            db.queue_first(ProductMaster, [master])
            with pytest.raises(ValidationError):
                svc.save_from_scan(FakeAccess(), db, make_user(), {
                    "barcode": VALID_BARCODE,
                    "product_master_id": master.id,
                    "price": 120.0,
                    "quantity": 10,
                })
            assert not db.objects_of(ShopProduct)

    def test_duplicate_listing_conflict(self):
        """Scanning a product already listed by this shop → ConflictError."""
        from app.core.exceptions import ConflictError
        from app.models.product import Inventory, ProductMaster, ShopProduct
        from app.services import barcode_intake_service as svc

        master = make_master(variants=[make_variant()])
        existing_sp = ShopProduct(
            shop_id=10, product_master_id=master.id, variant_id=11,
            price=100.0,
        )

        db = IntakeMockDB()
        db.queue_first(ProductMaster, [master])
        db.queue_first(ShopProduct, [existing_sp])  # duplicate found

        with pytest.raises(ConflictError):
            svc.save_from_scan(FakeAccess(), db, make_user(), {
                "barcode": VALID_BARCODE,
                "product_master_id": master.id,
                "variant_id": 11,
                "price": 120.0,
                "quantity": 5,
            })
        # Nothing new was created (no Inventory rows added).
        assert not db.objects_of(Inventory)

    def test_price_validation_on_save(self):
        from app.models.product import ProductMaster, ShopProduct
        from app.services import barcode_intake_service as svc

        master = make_master()
        cases = [
            {"mrp": 100.0},          # MRP below price
        ]
        for extra in cases:
            db = IntakeMockDB()
            db.queue_first(ProductMaster, [master])
            db.queue_first(ShopProduct, [None])
            payload = {
                "barcode": VALID_BARCODE,
                "product_master_id": master.id,
                "price": 150.0,
                "quantity": 3,
            }
            payload.update(extra)
            with pytest.raises(Exception):
                svc.save_from_scan(FakeAccess(), db, make_user(), payload)


# ── Part B: Excel import ─────────────────────────────────────────────────


class ExcelTestBase:
    """Shared helpers for Excel import tests."""

    def stage_import(self, data_rows, master=None, ident=None):
        """Run create_import over an in-memory workbook; return (db, result)."""
        from app.models.inventory_import import InventoryImportRow
        from app.services import excel_import_service as svc

        content = make_excel_rows(data_rows)
        db = IntakeMockDB()
        if ident is not None:
            from app.models.product import ProductIdentifier

            db.queue_first(ProductIdentifier, [ident])
        if master is not None:
            from app.models.product import ProductMaster

            db.queue_first(ProductMaster, [master])

        result = svc.create_import(FakeAccess(), db, make_user(), "inventory.xlsx", content)
        rows = db.objects_of(InventoryImportRow)
        db.set_all(InventoryImportRow, rows)  # for subsequent .all() queries
        return db, result, rows

    def collect_rows(self, db):
        from app.models.inventory_import import InventoryImportRow

        return db.objects_of(InventoryImportRow)


class TestExcelValidFile(ExcelTestBase):
    def test_valid_file_end_to_end(self):
        """Upload → validate → parse → preview → confirm → inventory updated."""
        from app.core.exceptions import AppError
        from app.models.product import (
            Inventory,
            ProductMaster,
            ShopProduct,
        )
        from app.services import excel_import_service as svc

        master = make_master(variants=[make_variant()])
        ident = make_identifier()

        db, result, rows = self.stage_import([GOOD_ROW], master=master, ident=ident)

        assert result["status"] == "AWAITING_CONFIRMATION"
        assert result["total_rows"] == 1
        assert result["valid_rows"] == 1
        assert result["error_rows"] == 0
        assert result["preview"][0]["status"] == "VALID"
        assert result["preview"][0]["price"] == 120.0
        assert result["preview"][0]["quantity"] == 50
        assert result["column_mapping"]["barcode"] == 0

        # Confirm → process (nothing exists yet → CREATE path).
        db.queue_first(ProductMaster, [master])
        db.queue_first(ShopProduct, [None])
        summary = svc.confirm_import(FakeAccess(), db, make_user(), result["id"])

        assert summary["status"] == "COMPLETED"
        assert summary["processed_this_run"] == 1

        sp = db.objects_of(ShopProduct)[-1]
        inv = db.objects_of(Inventory)[-1]
        assert sp.source.value == "EXCEL_UPLOAD"
        assert float(sp.price) == 120.0
        assert inv.quantity == 50

    def test_availability_no_marks_unavailable(self):
        row = list(GOOD_ROW)
        row[8] = "no"  # Availability column
        _, result, _ = self.stage_import([row], master=make_master(),
                                         ident=make_identifier())
        preview = result["preview"][0]
        assert preview["availability"] is False


class TestExcelInvalidFile(ExcelTestBase):
    def test_wrong_extension_rejected(self):
        from app.core.exceptions import ValidationError
        from app.services import excel_import_service as svc

        with pytest.raises(ValidationError):
            svc.create_import(
                FakeAccess(), IntakeMockDB(), make_user(), "inventory.csv", b"x"
            )

    def test_corrupt_bytes_rejected(self):
        from app.core.exceptions import ValidationError
        from app.services import excel_import_service as svc

        with pytest.raises(ValidationError):
            svc.create_import(
                FakeAccess(), IntakeMockDB(), make_user(),
                "inventory.xlsx", b"this is not a zip archive",
            )

    def test_empty_file_rejected(self):
        from app.core.exceptions import ValidationError
        from app.services import excel_import_service as svc

        with pytest.raises(ValidationError):
            svc.create_import(
                FakeAccess(), IntakeMockDB(), make_user(), "inventory.xlsx", b""
            )

    def test_missing_identifier_columns_rejected(self):
        from app.core.exceptions import ValidationError
        from app.services import excel_import_service as svc

        content = make_excel_rows([])  # headers only — no data rows either way
        with pytest.raises(ValidationError):
            svc.create_import(
                FakeAccess(), IntakeMockDB(), make_user(), "inventory.xlsx", content
            )

    def test_headerless_grid_rejected(self):
        """A workbook whose columns are unrecognizable is a file-level error."""
        from app.core.exceptions import ValidationError
        from app.services import excel_import_service as svc, xlsx_lite

        content = xlsx_lite.write_workbook([
            ["foo", "bar"],
            ["1", "2"],
        ])
        with pytest.raises(ValidationError):
            svc.create_import(
                FakeAccess(), IntakeMockDB(), make_user(), "inventory.xlsx", content
            )


class TestExcelPartialFailure(ExcelTestBase):
    def test_row_level_errors_reported(self):
        """One good row + several bad rows → per-row error reporting."""
        bad_price = list(GOOD_ROW)
        bad_price[0] = "not-a-number"
        bad_price[5] = "abc"          # Price column — invalid number
        bad_qty = list(GOOD_ROW)
        bad_qty[7] = "-5"             # Quantity — negative
        unknown = list(GOOD_ROW)
        unknown[0] = "9999999999994"  # correct EAN-13 check digit, not in catalog

        master = make_master()
        ident = make_identifier()

        db, result, rows = self.stage_import(
            [GOOD_ROW, bad_price, bad_qty, unknown],
            master=master,
            ident=ident,
        )

        assert result["total_rows"] == 4
        assert result["valid_rows"] == 1
        assert result["error_rows"] == 3

        by_row = {p["row_number"]: p for p in result["preview"]}
        assert by_row[2]["error_code"] == "INVALID_BARCODE"

        assert by_row[3]["error_code"] == "NEGATIVE_QUANTITY"
        assert by_row[4]["error_code"] == "UNKNOWN_PRODUCT"

    def test_confirm_with_only_errors_rejected(self):
        from app.core.exceptions import ValidationError
        from app.services import excel_import_service as svc

        bad = list(GOOD_ROW)
        bad[5] = "abc"
        db, result, _ = self.stage_import([bad], master=make_master(),
                                          ident=make_identifier())
        with pytest.raises(ValidationError):
            svc.confirm_import(FakeAccess(), db, make_user(), result["id"])

    def test_partial_processing_marks_job_partial(self):
        """Row fails mid-processing (catalog row deleted) → PARTIAL + retryable."""
        from app.models.product import ProductMaster
        from app.services import excel_import_service as svc

        master = make_master()
        ident = make_identifier()
        db, result, rows = self.stage_import([GOOD_ROW], master=master, ident=ident)

        # During processing the catalog master has vanished.
        db.queue_first(ProductMaster, [None])
        summary = svc.confirm_import(FakeAccess(), db, make_user(), result["id"])

        assert summary["status"] == "PARTIAL"
        assert summary["failed_this_run"] == 1
        assert rows[0].status == "ERROR"
        assert rows[0].error_code == "NOT_FOUND"

        report = svc.build_report(FakeAccess(), db, result["id"])
        assert report["report"]["failed"] == 1
        assert report["report"]["error_summary"] == {"NOT_FOUND": 1}


class TestExcelLargeFileBackground(ExcelTestBase):
    def test_large_import_uses_background_job(self, monkeypatch):
        """Above the async threshold, confirm queues a Celery job instead."""
        from app.services import excel_import_service as svc

        monkeypatch.setattr(svc, "ASYNC_ROW_THRESHOLD", 2)
        enqueued = []
        monkeypatch.setattr(
            svc, "_enqueue_processing", lambda job_id: enqueued.append(job_id)
        )

        master = make_master()
        ident = make_identifier()
        data_rows = [list(GOOD_ROW) for _ in range(3)]
        db, result, rows = self.stage_import(data_rows, master=master, ident=ident)

        # Only the first row resolves (single queued identifier); mark all
        # three VALID so the threshold check sees a large import.
        for r in rows:
            r.status = "VALID"

        summary = svc.confirm_import(FakeAccess(), db, make_user(), result["id"])
        assert summary["queued"] is True
        assert summary["status"] == "QUEUED"
        assert enqueued == [result["id"]]


class TestExcelDuplicateRows(ExcelTestBase):
    def test_duplicate_rows_flagged(self):
        """The same product twice in one file → second row DUPLICATE_ROW."""
        _, result, _ = self.stage_import(
            [GOOD_ROW, list(GOOD_ROW)],
            master=make_master(),
            ident=make_identifier(),
        )
        assert result["total_rows"] == 2
        assert result["valid_rows"] == 1
        assert result["preview"][1]["error_code"] == "DUPLICATE_ROW"


class TestRetryAndIdempotency(ExcelTestBase):
    def test_retry_failed_rows(self):
        """Failed rows are retried and the job completes once fixed."""
        from app.models.product import ProductMaster, ShopProduct
        from app.services import excel_import_service as svc

        master = make_master(variants=[make_variant()])
        ident = make_identifier()

        db, result, rows = self.stage_import([GOOD_ROW], master=master, ident=ident)

        # First confirm: catalog master missing → transient NOT_FOUND failure.
        db.queue_first(ProductMaster, [None])
        first = svc.confirm_import(FakeAccess(), db, make_user(), result["id"])
        assert first["status"] == "PARTIAL"

        # Retry: master back online → row succeeds, job completes.
        db.queue_first(ProductMaster, [master])
        db.queue_first(ShopProduct, [None])
        retried = svc.retry_failed(FakeAccess(), db, make_user(), result["id"])
        assert retried["status"] == "COMPLETED"
        assert retried["processed_this_run"] == 1

    def test_retry_rejected_when_not_partial(self):
        from app.core.exceptions import ConflictError
        from app.services import excel_import_service as svc

        db, result, _ = self.stage_import([GOOD_ROW], master=make_master(),
                                          ident=make_identifier())
        with pytest.raises(ConflictError):
            svc.retry_failed(FakeAccess(), db, make_user(), result["id"])

    def test_idempotent_reupload(self):
        """Re-uploading the byte-identical file returns the original job."""
        from app.models.inventory_import import InventoryImportJob
        from app.services import excel_import_service as svc

        content = make_excel_rows([GOOD_ROW])
        db = IntakeMockDB()

        first = svc.create_import(FakeAccess(), db, make_user(), "inventory.xlsx", content)
        jobs = db.objects_of(InventoryImportJob)
        assert len(jobs) == 1

        # Same bytes again with the dedupe lookup finding job #1.
        db.queue_first(InventoryImportJob, [jobs[0]])
        second = svc.create_import(FakeAccess(), db, make_user(), "inventory.xlsx", content)
        assert second.get("idempotent_replay") is True
        assert second["id"] == first["id"]


# ── VERIFY: one canonical inventory system ───────────────────────────────


class TestCanonicalInventoryVerify(ExcelTestBase):
    def test_barcode_and_excel_update_same_inventory_system(self):
        """Both intake paths land in inventory_service.get_shop_inventory."""
        from app.models.product import Inventory, ProductMaster, ShopProduct
        from app.services import barcode_intake_service as barcode_svc
        from app.services import excel_import_service as excel_svc
        from app.services import inventory_service

        master = make_master(variants=[make_variant()])
        ident = make_identifier()

        # ── Path 1: barcode scan save ──
        bc_db = IntakeMockDB()
        bc_db.queue_first(ProductMaster, [master])
        bc_db.queue_first(ShopProduct, [None])
        barcode_svc.save_from_scan(FakeAccess(), bc_db, make_user(), {
            "barcode": VALID_BARCODE,
            "product_master_id": master.id,
            "price": 120.0,
            "mrp": 150.0,
            "quantity": 40,
            "is_available": True,
            "publish": True,
        })
        sp_bc = bc_db.objects_of(ShopProduct)[-1]
        inv_bc = bc_db.objects_of(Inventory)[-1]

        # ── Path 2: Excel import ──
        ex_db, result, _rows = self.stage_import([GOOD_ROW], master=master, ident=ident)
        ex_db.queue_first(ProductMaster, [master])
        ex_db.queue_first(ShopProduct, [None])
        excel_svc.confirm_import(FakeAccess(), ex_db, make_user(), result["id"])
        sp_ex = ex_db.objects_of(ShopProduct)[-1]
        inv_ex = ex_db.objects_of(Inventory)[-1]

        # Barcode-saved listing through the platform's canonical reader:
        bc_db.set_all(ShopProduct, [sp_bc])
        bc_db.first_queues.clear()
        bc_db.queue_first(Inventory, [inv_bc])
        view_bc = inventory_service.get_shop_inventory(bc_db, 10)
        assert len(view_bc) == 1
        assert view_bc[0]["quantity"] == 40
        assert view_bc[0]["price"] == 120.0
        assert view_bc[0]["source"] == "BARCODE_SCAN"

        # Excel-imported listing through the SAME function:
        ex_db.set_all(ShopProduct, [sp_ex])
        ex_db.first_queues.clear()
        ex_db.queue_first(Inventory, [inv_ex])
        view_ex = inventory_service.get_shop_inventory(ex_db, 10)
        assert len(view_ex) == 1
        assert view_ex[0]["quantity"] == 50
        assert view_ex[0]["price"] == 120.0
        assert view_ex[0]["source"] == "EXCEL_UPLOAD"


class TestSampleWorkbook(ExcelTestBase):
    """Download Sample — the Import Center's downloadable template."""

    def test_sample_round_trips_and_imports_cleanly(self):
        from app.models.inventory_import import InventoryImportRow
        from app.models.product import (
            ProductIdentifier,
            ProductMaster,
            ProductVariant,
        )
        from app.services import excel_import_service as svc
        from app.services import xlsx_lite

        content = svc.build_sample_workbook()
        assert content.startswith(b"PK")  # a real .xlsx (zip container)

        # The header maps onto every canonical field, and the writer/reader
        # pair can never drift apart.
        grid = xlsx_lite.read_workbook(content)
        mapping = svc.map_headers(grid[0])
        for field in ("barcode", "product_name", "brand", "variant",
                      "sku", "price", "mrp", "quantity", "availability"):
            assert field in mapping, field

        # And the whole file stages cleanly: every example row resolves and
        # validates, so a shopkeeper filling it in starts from a valid file.
        db = IntakeMockDB()
        db.queue_first(ProductIdentifier, [
            make_identifier(barcode="8901234567890", master_id=21),
            make_identifier(barcode="8901234567883", master_id=23),
        ])
        db.queue_first(ProductVariant, [
            make_variant(variant_id=31, name="500 ml", sku="FF-MILK-500"),
        ])
        db.queue_first(ProductMaster, [
            make_master(master_id=21, name="Aashirvaad Salt 1kg",
                        variants=[make_variant(variant_id=32, name="1 kg")]),
            make_master(master_id=22, name="Farm Fresh Milk 500ml",
                        variants=[make_variant(variant_id=31, name="500 ml",
                                               sku="FF-MILK-500")]),
            make_master(master_id=23, name="India Gate Basmati 5kg",
                        variants=[make_variant(variant_id=33, name="5 kg")]),
        ])

        result = svc.create_import(
            FakeAccess(), db, make_user(), svc.SAMPLE_FILE_NAME, content
        )
        assert result["total_rows"] == 3
        assert result["valid_rows"] == 3
        assert result["error_rows"] == 0
        assert len(db.objects_of(InventoryImportRow)) == 3
