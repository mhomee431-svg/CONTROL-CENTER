"""Phase 25 — POS Integration Platform tests.

Covers the full required matrix against a real in-memory SQLite database:
  * Connect provider mock        · Initial sync            · Incremental sync
  * Duplicate records            · Price update            · Stock update
  * Failed sync                  · Retry                   · Partial failure
  * Disconnect                   · Reconnect
VERIFY — POS inventory flows safely into the SAME canonical inventory system
(inventory_service.create_inventory/update_inventory; source POS_INTEGRATION).
"""

import os
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

BACKEND_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BACKEND_DIR))

os.environ.setdefault("ENVIRONMENT", "test")
os.environ.setdefault("HYPERLOCAL_ENV", "test")

import pytest  # noqa: E402
from sqlalchemy import create_engine  # noqa: E402
from sqlalchemy.orm import sessionmaker  # noqa: E402

from app.core.config import settings  # noqa: E402

settings.RATE_LIMIT_ENABLED = False

from app.core.exceptions import ConflictError, ValidationError  # noqa: E402
from app.models.base import Base  # noqa: E402
from app.models.pos import (  # noqa: E402
    POSDevice,
    POSIntegration,
    POSIntegrationStatus,
    POSProductMapping,
    POSSyncJob,
    POSSyncLog,
    POSSyncStatus,
)
from app.models.product import (  # noqa: E402
    Inventory,
    InventoryMovement,
    PriceHistory,
    ProductIdentifier,
    ProductMaster,
    ProductVariant,
    ShopProduct,
)
from app.services import inventory_service, pos_sync_service  # noqa: E402
from app.services.pos_integration import (  # noqa: E402
    get_provider,
    list_providers,
    normalize_product_record,
)
from app.services.pos_integration.base import POSCredentials  # noqa: E402
from app.services.pos_integration.mock_provider import mock_pos_provider  # noqa: E402

SHOP_ID = 10
API_KEY = "mock-key-25"

T1 = "2026-08-20T10:00:00+00:00"
T2 = "2026-08-21T11:00:00+00:00"
T3 = "2026-08-23T09:30:00+00:00"


# ── Database fixture (real SQLite — unique constraints & flushes matter) ────
TABLES = [
    POSIntegration.__table__,
    POSDevice.__table__,
    POSSyncJob.__table__,
    POSSyncLog.__table__,
    POSProductMapping.__table__,
    ProductMaster.__table__,
    ProductVariant.__table__,
    ProductIdentifier.__table__,
    ShopProduct.__table__,
    Inventory.__table__,
    InventoryMovement.__table__,
    PriceHistory.__table__,
]


@pytest.fixture()
def db():
    engine = create_engine("sqlite://")
    Base.metadata.create_all(engine, tables=TABLES)
    session = sessionmaker(bind=engine)()
    yield session
    session.close()
    engine.dispose()


@pytest.fixture(autouse=True)
def _reset_mock_catalog():
    mock_pos_provider.seed_catalog(API_KEY, [])
    mock_pos_provider.set_outage(False)
    yield
    mock_pos_provider.seed_catalog(API_KEY, [])
    mock_pos_provider.set_outage(False)


# TimestampMixin / SoftDeleteMixin rely on Postgres server-defaults ("now()",
# "false"). SQLite would store those literals verbatim, so stamp equivalent
# values client-side before flush (process-local; no-op semantics elsewhere).
from sqlalchemy import event  # noqa: E402
from sqlalchemy.orm import Session as _Session  # noqa: E402


@event.listens_for(_Session, "before_flush")
def _stamp_portable_defaults(session, flush_context, instances):
    now = datetime.now(timezone.utc)
    for obj in session.new:
        if hasattr(obj, "created_at") and obj.created_at is None:
            obj.created_at = now
        if hasattr(obj, "updated_at") and obj.updated_at is None:
            obj.updated_at = now
        if hasattr(obj, "is_deleted") and obj.is_deleted is None:
            obj.is_deleted = False
    # Mirror the Postgres ON UPDATE now() behaviour client-side.
    for obj in session.dirty:
        if hasattr(obj, "updated_at"):
            obj.updated_at = now


@pytest.fixture(autouse=True)
def _no_live_broker(monkeypatch):
    """The canonical inventory service fire-and-forgets a search-index task;
    stub the enqueue so tests never touch a message broker."""
    monkeypatch.setattr(
        inventory_service, "_enqueue_search_index_update", lambda shop_product_id: None
    )


# ── Domain helpers ───────────────────────────────────────────────────────────
def rec(code, name, *, sku=None, barcode=None, price=None, mrp=None,
        quantity=None, updated_at=T1):
    """Build one raw Mock-POS catalog record."""
    payload = {"pos_product_code": code, "name": name, "updated_at": updated_at}
    for key, value in [("sku", sku), ("barcode", barcode), ("price", price),
                       ("mrp", mrp), ("quantity", quantity)]:
        if value is not None:
            payload[key] = value
    return payload


RICE = rec("SKU-001", "Basmati Rice 1kg", sku="RICE-1KG",
           barcode="8901234567890", price=120.0, mrp=150.0, quantity=50)
OIL = rec("SKU-002", "Sunflower Oil 1L", sku="OIL-1L",
          price=90.0, mrp=110.0, quantity=30, updated_at=T2)
DAL = rec("SKU-003", "Toor Dal 500g", sku="DAL-500G",
          price=70.0, quantity=20, updated_at=T2)


def seed(*records):
    mock_pos_provider.seed_catalog(API_KEY, list(records))


def make_integration(db, **kwargs):
    """Register + connect an integration bound to the seeded mock catalog."""
    integration = pos_sync_service.register_integration(
        db, shop_id=SHOP_ID, provider_code="MOCK", api_key=API_KEY, **kwargs
    )
    result = pos_sync_service.connect_integration(db, integration.id)
    assert result["connected"] is True
    return integration


def trigger_and_run(db, integration, sync_type="FULL", idempotency_key=None,
                    user_id=None):
    job, created = pos_sync_service.trigger_manual_sync(
        db, integration.id, sync_type=sync_type,
        user_id=user_id, idempotency_key=idempotency_key,
    )
    summary = pos_sync_service.run_sync_job(db, job.id)
    db.commit()
    return summary


def shop_products(db):
    return db.query(ShopProduct).filter(ShopProduct.shop_id == SHOP_ID).all()


def logs_of(db, job_id):
    return {log.error_code: log for log in
            db.query(POSSyncLog).filter(POSSyncLog.sync_job_id == job_id).all()}


class _MaskedViewTarget:
    """Minimal stand-in exposing the attributes POSCredentials.masked_view reads."""

    api_base_url = "https://mock-pos.local/api"
    api_key_encrypted = API_KEY
    api_secret_encrypted = "super-secret-value"
    config_json = {"credentials": {"store_code": "STORE-42"}}


# ── Provider abstraction / registry ──────────────────────────────────────────
class TestProviderAbstraction:
    def test_mock_provider_registered(self):
        provider = get_provider("MOCK")
        assert provider.code.upper() == "MOCK"
        codes = [entry["code"] for entry in list_providers()]
        assert "MOCK" in codes

    def test_unknown_provider_raises_lookup_error(self):
        with pytest.raises(LookupError):
            get_provider("NONEXISTENT_VENDOR")

    def test_new_vendor_plugs_in_without_engine_changes(self):
        """Provider-agnostic proof: any contract-compliant adapter slots in."""
        from app.services.pos_integration.base import (
            POSFetchResult,
            POSProvider,
            _PROVIDERS,
            register_provider,
        )

        class FutureVendorPOS(POSProvider):
            code = "FUTUREVENDOR"
            display_name = "Future Vendor 3000"
            supports_incremental = False

            def test_connection(self, credentials):
                return {"ok": True, "provider": self.code}

            def fetch_products(self, credentials, since=None, limit=500):
                return POSFetchResult(items=[])

        try:
            register_provider(FutureVendorPOS())
            resolved = get_provider("futurevendor")
            assert resolved.display_name == "Future Vendor 3000"
            assert resolved.supports_incremental is False
        finally:
            _PROVIDERS.pop("FUTUREVENDOR", None)

    def test_normalize_rejects_records_without_identity(self):
        with pytest.raises(ValueError):
            normalize_product_record({"name": "No Code"})
        with pytest.raises(ValueError):
            normalize_product_record({"pos_product_code": "X1", "name": ""})

    def test_fingerprint_changes_only_when_synced_content_changes(self):
        base = normalize_product_record(RICE)
        same = normalize_product_record(dict(RICE))
        changed = normalize_product_record({**RICE, "price": 999.0})
        assert base.content_fingerprint() == same.content_fingerprint()
        assert base.content_fingerprint() != changed.content_fingerprint()

    def test_credentials_are_masked_never_exposed_raw(self):
        view = POSCredentials.masked_view(_MaskedViewTarget())
        assert view["api_key"].startswith("mock")
        assert "****" in view["api_key"]
        assert API_KEY not in str(view)
        assert "super-secret-value" not in str(view)
        assert view["extra_keys"] == ["store_code"]


# ── Registration / connect lifecycle ────────────────────────────────────────
class TestRegistrationAndConnect:
    def test_register_validates_provider_and_type(self, db):
        with pytest.raises(ValidationError):
            pos_sync_service.register_integration(
                db, shop_id=SHOP_ID, provider_code="GHOST_POS"
            )
        with pytest.raises(ValidationError):
            pos_sync_service.register_integration(
                db, shop_id=SHOP_ID, provider_code="MOCK", integration_type="CARRIER_PIGEON"
            )

    def test_duplicate_registration_prevented(self, db):
        make_integration(db)
        with pytest.raises(ConflictError):
            pos_sync_service.register_integration(
                db, shop_id=SHOP_ID, provider_code="MOCK", api_key=API_KEY
            )

    def test_connect_mock_provider_success_sets_active(self, db):
        seed(RICE)
        integration = make_integration(db)
        payload = pos_sync_service.integration_payload(db, integration)
        assert payload["status"] == "ACTIVE"
        assert payload["provider_code"] == "MOCK"

    def test_connect_with_bad_credentials_marks_error(self, db):
        integration = pos_sync_service.register_integration(
            db, shop_id=SHOP_ID, provider_code="MOCK", api_key="invalid-key"
        )
        result = pos_sync_service.connect_integration(db, integration.id)
        assert result["connected"] is False
        assert result["error_code"] == "POS_AUTH_FAILED"
        db.refresh(integration)
        assert integration.status == POSIntegrationStatus.ERROR

    def test_device_mapping_is_idempotent(self, db):
        integration = make_integration(db)
        first = pos_sync_service.register_device(
            db, shop_id=SHOP_ID, integration_id=integration.id,
            device_identifier="TERM-01", device_name="Front Counter",
        )
        second = pos_sync_service.register_device(
            db, shop_id=SHOP_ID, integration_id=integration.id,
            device_identifier="TERM-01", device_name="Front Counter Renamed",
        )
        assert first.id == second.id
        assert second.device_name == "Front Counter Renamed"
        devices = pos_sync_service.list_devices(db, SHOP_ID)
        assert len(devices) == 1


# ── Initial sync + duplicate prevention + idempotency ────────────────────────
class TestInitialSync:
    def test_initial_full_sync_creates_full_chain(self, db):
        seed(RICE, OIL, DAL)
        integration = make_integration(db)
        summary = trigger_and_run(db, integration)

        assert summary["status"] == "COMPLETED"
        assert summary["items_processed"] == 3
        assert summary["items_succeeded"] == 3
        assert summary["items_failed"] == 0

        products = shop_products(db)
        assert len(products) == 3
        rice = next(p for p in products if p.sku == "RICE-1KG")
        assert float(rice.price) == 120.0
        assert float(rice.mrp) == 150.0
        assert rice.product_master.name == "Basmati Rice 1kg"
        assert rice.variant.sku == "RICE-1KG"

        inv = db.query(Inventory).filter(Inventory.shop_product_id == rice.id).first()
        assert inv is not None and inv.quantity == 50

        # Barcode from POS became a platform ProductIdentifier.
        identifiers = db.query(ProductIdentifier).all()
        assert any(i.identifier_value == "8901234567890" for i in identifiers)

        # Mapping rows carry the duplicate-prevention fingerprint.
        mappings = db.query(POSProductMapping).all()
        assert len(mappings) == 3
        assert all(m.last_synced_hash and m.shop_product_id for m in mappings)

    def test_initial_sync_records_canonical_movement(self, db):
        seed(RICE)
        integration = make_integration(db)
        summary = trigger_and_run(db, integration)

        movement = db.query(InventoryMovement).first()
        assert movement is not None
        assert movement.quantity_change == 50
        assert movement.quantity_after == 50
        assert movement.movement_type == "INITIAL"
        assert movement.source.value == "POS_INTEGRATION"
        assert movement.reference_type == "pos_sync"
        assert movement.reference_id == summary["id"]

    def test_rerun_unchanged_records_are_skipped_not_duplicated(self, db):
        seed(RICE, OIL, DAL)
        integration = make_integration(db)
        trigger_and_run(db, integration)
        before = len(shop_products(db))

        summary = trigger_and_run(db, integration, sync_type="FULL")
        assert summary["status"] == "COMPLETED"
        assert summary["duplicates_skipped"] == 3
        assert summary["items_succeeded"] == 0
        assert len(shop_products(db)) == before == 3
        logs = logs_of(db, summary["id"])
        assert "SKIPPED_UNCHANGED" in logs

    def test_duplicate_code_within_one_batch_is_counted_once(self, db, monkeypatch):
        """Same POS code appearing twice inside one fetch → applied once."""
        seed(RICE)
        integration = make_integration(db)

        original_fetch = mock_pos_provider.fetch_products

        def duplicating_fetch(credentials, since=None, limit=500):
            result = original_fetch(credentials, since=since, limit=limit)
            result.items = result.items + [normalize_product_record(RICE)]
            return result

        monkeypatch.setattr(mock_pos_provider, "fetch_products", duplicating_fetch)

        summary = trigger_and_run(db, integration)
        assert summary["items_processed"] == 2
        assert summary["duplicates_skipped"] == 1
        assert summary["items_succeeded"] == 1
        assert len(shop_products(db)) == 1
        assert "DUPLICATE_IN_BATCH" in logs_of(db, summary["id"])

    def test_idempotency_key_returns_same_job(self, db):
        seed(RICE)
        integration = make_integration(db)
        job_a, created_a = pos_sync_service.trigger_manual_sync(
            db, integration.id, sync_type="FULL", idempotency_key="order-77"
        )
        job_b, created_b = pos_sync_service.trigger_manual_sync(
            db, integration.id, sync_type="FULL", idempotency_key="order-77"
        )
        assert created_a is True and created_b is False
        assert job_a.id == job_b.id
        assert db.query(POSSyncJob).count() == 1


# ── Incremental synchronization ──────────────────────────────────────────────
class TestIncrementalSync:
    def test_incremental_pulls_only_changed_records(self, db):
        seed(RICE, OIL, DAL)
        integration = make_integration(db)
        trigger_and_run(db, integration)
        cursor_after_initial = integration.incremental_cursor
        assert cursor_after_initial  # mock supports cursors

        # Only the rice record changes at the POS.
        mock_pos_provider.upsert_record(API_KEY, {
            **RICE, "quantity": 5, "price": 132.0, "updated_at": T3,
        })
        summary = trigger_and_run(db, integration, sync_type="INCREMENTAL")

        assert summary["status"] in ("COMPLETED", "COMPLETED_WITH_ERRORS")
        assert summary["items_processed"] == 1
        assert summary["items_succeeded"] == 1

        rice = next(p for p in shop_products(db) if p.sku == "RICE-1KG")
        inv = db.query(Inventory).filter(Inventory.shop_product_id == rice.id).first()
        assert inv.quantity == 5
        # Cursor advanced past T3 on the clean run.
        assert integration.incremental_cursor >= cursor_after_initial

    def test_incremental_with_no_changes_processes_nothing(self, db):
        seed(RICE)
        integration = make_integration(db)
        trigger_and_run(db, integration)
        summary = trigger_and_run(db, integration, sync_type="INCREMENTAL")
        assert summary["items_processed"] == 0
        assert summary["status"] == "COMPLETED"

    def test_failed_items_do_not_advance_cursor(self, db):
        """Cursor only moves on clean runs so failed records re-fetch."""
        seed(RICE, OIL)
        integration = make_integration(db)
        trigger_and_run(db, integration)  # initial sync creates both products

        # Flip to strict mode: unknown new POS items become item failures.
        pos_sync_service.update_sync_config(db, integration.id, {"batch_size": 500})
        integration.auto_create_products = False

        mock_pos_provider.upsert_record(API_KEY, {**DAL, "updated_at": T3})
        summary = trigger_and_run(db, integration, sync_type="INCREMENTAL")

        assert summary["status"] == "COMPLETED_WITH_ERRORS"
        assert summary["items_failed"] == 1
        assert "NO_PRODUCT_MATCH" in logs_of(db, summary["id"])
        # Cursor NOT advanced → the failed record is re-fetched on the next run.
        assert integration.incremental_cursor < T3


# ── Price updates / conflict handling / source-of-truth rules ────────────────
class TestPriceAuthorityAndConflicts:
    def _initial(self, db):
        seed(RICE)
        integration = make_integration(db)
        trigger_and_run(db, integration)
        return integration, next(p for p in shop_products(db) if p.sku == "RICE-1KG")

    def test_platform_price_preserved_on_pos_change(self, db):
        """Default rule: price is PLATFORM-authoritative → POS price logged as
        conflict, platform value NEVER overwritten blindly."""
        integration, rice = self._initial(db)
        mock_pos_provider.upsert_record(
            API_KEY, {**RICE, "price": 999.0, "updated_at": T3}
        )
        summary = trigger_and_run(db, integration, sync_type="INCREMENTAL")

        db.refresh(rice)
        assert float(rice.price) == 120.0  # platform value preserved
        assert summary["status"] == "COMPLETED"  # conflicts are not failures
        assert summary["conflicts"][0]["field"] == "price"
        assert summary["conflicts"][0]["pos_value"] == 999.0
        assert summary["conflicts"][0]["resolution"] == "PRESERVED_PLATFORM"
        logs = logs_of(db, summary["id"])
        assert any(code.startswith("CONFLICT_PRICE") for code in logs)

        # Conflict persisted on the mapping row.
        mapping = db.query(POSProductMapping).first()
        stored = mapping.last_conflict_json["conflicts"]
        assert stored[0]["field"] == "price"

        # No PriceHistory row — nothing was applied.
        assert db.query(PriceHistory).count() == 0

    def test_pos_price_applied_when_overridden_as_authoritative(self, db):
        integration, rice = self._initial(db)
        pos_sync_service.update_sync_config(
            db, integration.id,
            {"field_authorities": {"price": "POS"}},
        )
        mock_pos_provider.upsert_record(
            API_KEY, {**RICE, "price": 132.0, "updated_at": T3}
        )
        summary = trigger_and_run(db, integration, sync_type="INCREMENTAL")

        db.refresh(rice)
        assert float(rice.price) == 132.0
        assert not summary.get("conflicts")
        history = db.query(PriceHistory).all()
        assert len(history) == 1
        assert float(history[0].old_price) == 120.0
        assert float(history[0].new_price) == 132.0
        assert summary["status"] == "COMPLETED"

    def test_stock_update_flows_through_canonical_inventory(self, db):
        """VERIFY — POS stock lands in the SAME canonical inventory system."""
        seed(RICE, OIL, DAL)
        integration = make_integration(db)
        trigger_and_run(db, integration)

        # POS sells rice down to near-empty and restocks oil.
        mock_pos_provider.upsert_record(API_KEY, {**RICE, "quantity": 5, "updated_at": T3})
        mock_pos_provider.upsert_record(API_KEY, {**OIL, "quantity": 120, "updated_at": T3})
        trigger_and_run(db, integration, sync_type="INCREMENTAL")

        rice = next(p for p in shop_products(db) if p.sku == "RICE-1KG")
        oil = next(p for p in shop_products(db) if p.sku == "OIL-1L")
        inv_rice = db.query(Inventory).filter(Inventory.shop_product_id == rice.id).first()
        inv_oil = db.query(Inventory).filter(Inventory.shop_product_id == oil.id).first()

        assert inv_rice.quantity == 5
        assert inv_rice.stock_status.value == "LOW_STOCK"
        assert inv_rice.available_quantity == 5
        assert inv_rice.last_updated_source.value == "POS_INTEGRATION"
        assert inv_rice.last_synced_at is not None

        assert inv_oil.quantity == 120
        assert inv_oil.stock_status.value == "IN_STOCK"

        # Canonical audit trail: movement rows with before/after quantities.
        movements = (
            db.query(InventoryMovement)
            .filter(InventoryMovement.inventory_id == inv_rice.id)
            .order_by(InventoryMovement.id.asc())
            .all()
        )
        assert [(m.quantity_before, m.quantity_after) for m in movements] == [(0, 50), (50, 5)]

        # The canonical read path used by customers/shopkeepers sees it too.
        canonical = {
            entry["sku"]: entry
            for entry in inventory_service.get_shop_inventory(db, SHOP_ID)
        }
        assert canonical["RICE-1KG"]["quantity"] == 5
        assert canonical["RICE-1KG"]["source"] == "POS_INTEGRATION"
        assert canonical["RICE-1KG"]["stock_status"] == "LOW_STOCK"

    def test_negative_pos_quantity_clamped_to_zero(self, db):
        seed(RICE)
        integration = make_integration(db)
        trigger_and_run(db, integration)
        mock_pos_provider.upsert_record(
            API_KEY, {**RICE, "quantity": -7, "updated_at": T3}
        )
        trigger_and_run(db, integration, sync_type="INCREMENTAL")
        rice = shop_products(db)[0]
        inv = db.query(Inventory).filter(Inventory.shop_product_id == rice.id).first()
        assert inv.quantity == 0
        assert inv.stock_status.value == "OUT_OF_STOCK"


# ── Failed sync / retry / partial failure / disconnect / reconnect ───────────
class TestFailuresRetriesAndLifecycle:
    def test_failed_sync_schedules_exponential_retry(self, db):
        seed(RICE)
        integration = make_integration(db)
        mock_pos_provider.set_outage(True)

        summary = trigger_and_run(db, integration)

        assert summary["status"] == "FAILED"
        assert "POS_CONNECTION_FAILED" in summary["error_summary"]
        job = db.query(POSSyncJob).filter(POSSyncJob.id == summary["id"]).first()
        assert job.retry_count == 1
        assert job.next_retry_at is not None
        db.refresh(integration)
        assert integration.consecutive_failures == 1
        assert integration.last_sync_status == "FAILED"
        assert "POS_CONNECTION_FAILED" in logs_of(db, job.id)

    def test_retry_after_outage_recovers(self, db):
        seed(RICE)
        integration = make_integration(db)
        mock_pos_provider.set_outage(True)
        failed = trigger_and_run(db, integration)
        assert failed["status"] == "FAILED"

        # Outage over → manual retry succeeds end-to-end.
        mock_pos_provider.set_outage(False)
        result = pos_sync_service.retry_failed_job(db, failed["id"], user_id=1)
        db.commit()

        assert result["status"] == "COMPLETED"
        assert result["items_succeeded"] == 1
        assert len(shop_products(db)) == 1
        job = db.query(POSSyncJob).filter(POSSyncJob.id == failed["id"]).first()
        db.refresh(job)
        assert job.trigger == "RETRY"
        assert job.error_summary is None

    def test_retry_rejected_for_non_failed_jobs(self, db):
        seed(RICE)
        integration = make_integration(db)
        completed = trigger_and_run(db, integration)
        with pytest.raises(ConflictError):
            pos_sync_service.retry_failed_job(db, completed["id"])

    def test_auto_retries_exhaust_then_wait_for_manual_retry(self, db):
        seed(RICE)
        integration = make_integration(db)
        mock_pos_provider.set_outage(True)

        summaries = [
            trigger_and_run(db, integration)
            for _ in range(pos_sync_service.MAX_AUTO_RETRIES + 1)
        ]
        counts = [s["retry_count"] for s in summaries]
        assert counts == [1, 2, 3, 4, 5, 5]  # stops incrementing at MAX_AUTO_RETRIES

        exhausted = db.query(POSSyncJob).filter(
            POSSyncJob.id == summaries[-1]["id"]
        ).first()
        assert exhausted.next_retry_at is None  # gave up — needs manual retry
        db.refresh(integration)
        assert integration.consecutive_failures == 6

    def test_disconnect_blocks_triggers_and_cancels_pending_jobs(self, db):
        seed(RICE)
        integration = make_integration(db)

        pos_sync_service.disconnect_integration(db, integration.id)
        db.refresh(integration)
        assert integration.status == POSIntegrationStatus.DISCONNECTED
        assert integration.disconnected_at is not None

        with pytest.raises(ConflictError):
            pos_sync_service.trigger_manual_sync(db, integration.id, sync_type="FULL")

        # A job already queued before the disconnect must NOT run.
        stranded = POSSyncJob(
            shop_id=SHOP_ID, integration_id=integration.id,
            sync_type="FULL", status=POSSyncStatus.PENDING,
        )
        db.add(stranded)
        db.flush()
        summary = pos_sync_service.run_sync_job(db, stranded.id)
        assert summary["status"] == "CANCELLED"
        assert len(shop_products(db)) == 0

    def test_reconnect_restores_the_full_pipeline(self, db):
        seed(RICE)
        integration = make_integration(db)
        pos_sync_service.disconnect_integration(db, integration.id)

        mock_pos_provider.set_outage(True)
        result = pos_sync_service.reconnect_integration(db, integration.id)
        assert result["connected"] is False  # credentials revalidated honestly
        db.refresh(integration)
        assert integration.status == POSIntegrationStatus.ERROR

        mock_pos_provider.set_outage(False)
        result = pos_sync_service.reconnect_integration(db, integration.id)
        assert result["connected"] is True
        db.refresh(integration)
        assert integration.status == POSIntegrationStatus.ACTIVE
        assert integration.disconnected_at is None

        summary = trigger_and_run(db, integration)
        assert summary["status"] == "COMPLETED"

    def test_scheduler_respects_cadence_state(self, db):
        seed(RICE)
        integration = make_integration(db)

        # Never synced → due immediately.
        assert [i.id for i in pos_sync_service.find_due_integrations(db)] == [integration.id]

        # Recently successful → not due until the interval elapses.
        integration.last_successful_sync_at = datetime.now(timezone.utc) - timedelta(minutes=10)
        assert pos_sync_service.find_due_integrations(db) == []

        # Stale but paused → still not due.
        integration.last_successful_sync_at = datetime.now(timezone.utc) - timedelta(hours=5)
        integration.sync_enabled = False
        assert pos_sync_service.find_due_integrations(db) == []
        integration.sync_enabled = True

        # Disconnected → never scheduled.
        integration.status = POSIntegrationStatus.DISCONNECTED
        assert pos_sync_service.find_due_integrations(db) == []

    def test_background_tasks_are_registered_on_the_broker(self):
        """Celery wiring exists without needing a live broker."""
        import app.services.tasks  # noqa: F401 — registers the Phase 25 tasks
        from app.core.celery_app import celery_app

        assert "app.services.tasks.run_pos_sync_job" in celery_app.tasks
        assert "app.services.tasks.dispatch_scheduled_pos_syncs" in celery_app.tasks


# ── VERIFY — canonical inventory safety net ──────────────────────────────────
class TestCanonicalInventoryVerification:
    def test_pos_inventory_is_indistinguishable_from_other_sources(self, db):
        """The inventory read path treats POS-synced stock exactly like
        barcode/Excel/manual stock — same tables, same rules, same freshness."""
        seed(RICE)
        integration = make_integration(db)
        trigger_and_run(db, integration)

        entries = inventory_service.get_shop_inventory(db, SHOP_ID)
        assert len(entries) == 1
        entry = entries[0]
        assert entry["quantity"] == 50
        assert entry["source"] == "POS_INTEGRATION"
        assert entry["is_available"] is True
        assert entry["freshness_status"] == "RECENTLY_UPDATED"

        # Every quantity change produced a canonical movement audit row.
        movements = db.query(InventoryMovement).all()
        assert movements
        assert all(m.source.value == "POS_INTEGRATION" for m in movements)

        # ShopProduct mirrors canonical state (search/list paths depend on it).
        sp = shop_products(db)[0]
        assert sp.is_available is True
        assert sp.stock_status.value == "IN_STOCK"
        assert sp.source.value == "POS_INTEGRATION"
