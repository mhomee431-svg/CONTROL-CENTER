"""Phase 25 — Provider-agnostic POS synchronization engine.

Lifecycle: registration → credentials/config → devices → scheduling → manual +
background syncs (initial & incremental) → mapping pipeline (POS Product →
Identifier → Master/Variant → ShopProduct → Price + Inventory) with
source-of-truth rules, conflict handling, idempotency, duplicate prevention,
retries, partial-failure semantics and logs.

Inventory ALWAYS flows through ``inventory_service.create_inventory`` /
``update_inventory`` so POS data lands in the same canonical inventory system
as manual / barcode / Excel sources.
"""

from __future__ import annotations

from datetime import datetime, timedelta, timezone
from traceback import format_exc

from sqlalchemy.orm import Session

from app.core.exceptions import ConflictError, NotFoundError, ValidationError
from app.core.logging import get_logger
from app.models.pos import (
    POSDevice,
    POSIntegration,
    POSIntegrationStatus,
    POSProductMapping,
    POSSyncJob,
    POSSyncLog,
    POSSyncStatus,
)
from app.models.product import (
    Inventory,
    InventorySource,
    PriceHistory,
    ProductIdentifier,
    ProductMaster,
    ProductStatus,
    ProductVariant,
    ShopProduct,
    ShopProductStatus,
)
from app.services import inventory_service
from app.services.pos_integration.base import (
    POSCredentials,
    POSProductRecord,
    POSProviderError,
    get_provider,
    normalize_product_record,
)

logger = get_logger("app.services.pos_sync")

# ── Tunables ─────────────────────────────────────────────────────────────────
MAX_AUTO_RETRIES = 5
RETRY_BACKOFF_BASE_MINUTES = 5          # backoff: 5, 10, 20, 40, 80 minutes
DEFAULT_SYNC_INTERVAL_MINUTES = 60
MIN_SYNC_INTERVAL_MINUTES = 5
VALID_INTEGRATION_TYPES = {"API", "FILE_UPLOAD", "WEBHOOK"}
VALID_SYNC_TYPES = {"FULL", "INCREMENTAL"}
PRICE_TOLERANCE = 0.009                 # cent-level comparison tolerance

# ── Source-of-truth rules ────────────────────────────────────────────────────
# For each synchronized field, who wins on conflict?
#   PLATFORM → platform value preserved; POS value recorded as conflict.
#   POS      → platform value overwritten — deliberately and traceably
#              (PriceHistory rows, inventory movements, WARNING logs).
# Per-integration overrides may live in config_json["field_authorities"].
FIELD_AUTHORITIES: dict[str, str] = {
    "name": "PLATFORM",
    "barcode": "PLATFORM",
    "category": "PLATFORM",
    "unit": "PLATFORM",
    "price": "PLATFORM",     # platform pricing wins by default (offers/MRP logic)
    "mrp": "PLATFORM",
    "inventory": "POS",      # stock levels are authoritative at the till
}


def field_authority(integration: POSIntegration, field: str) -> str:
    """Resolve the authoritative side for *field* (integration override-aware)."""
    overrides = (integration.config_json or {}).get("field_authorities", {}) or {}
    return str(overrides.get(field, FIELD_AUTHORITIES.get(field, "PLATFORM"))).upper()


class ItemSyncError(Exception):
    """Per-record failure inside a sync job (drives partial-failure stats)."""

    def __init__(self, message: str, error_code: str = "ITEM_SYNC_FAILED"):
        super().__init__(message)
        self.message = message
        self.error_code = error_code


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


def _slugify(value: str) -> str:
    cleaned = "".join(ch if ch.isalnum() else "-" for ch in value.lower())
    return "-".join(part for part in cleaned.split("-") if part) or "pos-product"


def _guess_identifier_type(value: str):
    """Best-effort GS1-ish classification for barcodes arriving from a POS."""
    from app.models.product import IdentifierType

    digits = value.strip()
    if digits.isdigit():
        if len(digits) == 13:
            return IdentifierType.EAN
        if len(digits) == 12:
            return IdentifierType.UPC
        if len(digits) in (8, 14):
            return IdentifierType.GTIN
    return IdentifierType.CUSTOM


def _require_integration(db: Session, integration_id: int) -> POSIntegration:
    integration = (
        db.query(POSIntegration)
        .filter(POSIntegration.id == integration_id, POSIntegration.is_deleted == False)  # noqa: E712
        .first()
    )
    if integration is None:
        raise NotFoundError("POS integration not found")
    return integration


def _add_log(
    db: Session,
    job: POSSyncJob,
    level: str,
    message: str,
    item_reference: str | None = None,
    error_code: str | None = None,
    stack_trace: str | None = None,
) -> None:
    db.add(
        POSSyncLog(
            sync_job_id=job.id,
            log_level=level,
            message=message,
            item_reference=item_reference,
            error_code=error_code,
            stack_trace=stack_trace,
        )
    )


# ── Registration / credentials / configuration ───────────────────────────────
def register_integration(
    db: Session,
    *,
    shop_id: int,
    provider_code: str,
    integration_type: str = "API",
    api_base_url: str | None = None,
    api_key: str | None = None,
    api_secret: str | None = None,
    config: dict | None = None,
) -> POSIntegration:
    """Register a new POS integration for a shop (one row per provider)."""
    try:
        provider = get_provider(provider_code)
    except LookupError as exc:
        raise ValidationError(str(exc))

    if integration_type not in VALID_INTEGRATION_TYPES:
        raise ValidationError(f"integration_type must be one of {sorted(VALID_INTEGRATION_TYPES)}")

    existing = (
        db.query(POSIntegration)
        .filter(
            POSIntegration.shop_id == shop_id,
            POSIntegration.provider_code == provider.code,
            POSIntegration.is_deleted == False,  # noqa: E712
        )
        .first()
    )
    if existing is not None:
        raise ConflictError(f"Provider '{provider.code}' is already registered for this shop")

    integration = POSIntegration(
        shop_id=shop_id,
        provider_code=provider.code,
        provider_name=provider.display_name or provider.code,
        integration_type=integration_type,
        api_base_url=api_base_url,
        api_key_encrypted=api_key,
        api_secret_encrypted=api_secret,
        status=POSIntegrationStatus.INACTIVE,
        sync_interval_minutes=DEFAULT_SYNC_INTERVAL_MINUTES,
        config_json=dict(config or {}),
    )
    db.add(integration)
    db.flush()
    logger.info("Registered POS integration shop=%s provider=%s id=%s", shop_id, provider.code, integration.id)
    return integration


def update_credentials(
    db: Session,
    integration_id: int,
    *,
    api_key: str | None = None,
    api_secret: str | None = None,
    api_base_url: str | None = None,
) -> POSIntegration:
    """Rotate stored credentials (encrypted-at-rest columns)."""
    integration = _require_integration(db, integration_id)
    if api_key is not None:
        integration.api_key_encrypted = api_key
    if api_secret is not None:
        integration.api_secret_encrypted = api_secret
    if api_base_url is not None:
        integration.api_base_url = api_base_url
    db.flush()
    return integration


def update_sync_config(db: Session, integration_id: int, config: dict) -> POSIntegration:
    """Merge vendor-neutral sync configuration (deep-merged into config_json)."""
    integration = _require_integration(db, integration_id)
    merged = dict(integration.config_json or {})
    for key, value in (config or {}).items():
        if isinstance(value, dict) and isinstance(merged.get(key), dict):
            merged[key].update(value)
        else:
            merged[key] = value
    integration.config_json = merged
    db.flush()
    return integration


def update_schedule(
    db: Session,
    integration_id: int,
    *,
    sync_interval_minutes: int | None = None,
    sync_enabled: bool | None = None,
) -> POSIntegration:
    """Configure background sync cadence / pause-resume."""
    integration = _require_integration(db, integration_id)
    if sync_interval_minutes is not None:
        if sync_interval_minutes < MIN_SYNC_INTERVAL_MINUTES:
            raise ValidationError(f"sync_interval_minutes must be >= {MIN_SYNC_INTERVAL_MINUTES}")
        integration.sync_interval_minutes = sync_interval_minutes
    if sync_enabled is not None:
        integration.sync_enabled = sync_enabled
    db.flush()
    return integration


# ── Connect / disconnect / reconnect ─────────────────────────────────────────
def connect_integration(db: Session, integration_id: int) -> dict:
    """Validate credentials against the provider; mark ACTIVE or ERROR."""
    integration = _require_integration(db, integration_id)
    provider = get_provider(integration.provider_code or integration.provider_name)
    credentials = POSCredentials.from_integration(integration).as_provider_input()
    try:
        info = provider.test_connection(credentials)
    except POSProviderError as exc:
        integration.status = POSIntegrationStatus.ERROR
        db.flush()
        return {"connected": False, "error_code": exc.error_code, "message": exc.message}

    integration.status = POSIntegrationStatus.ACTIVE
    integration.disconnected_at = None
    integration.consecutive_failures = 0
    db.flush()
    return {"connected": True, "provider": info}


def disconnect_integration(db: Session, integration_id: int) -> POSIntegration:
    """Explicitly disconnect (stops scheduled syncs, blocks manual triggers)."""
    integration = _require_integration(db, integration_id)
    integration.status = POSIntegrationStatus.DISCONNECTED
    integration.disconnected_at = _utcnow()
    db.flush()
    return integration


def reconnect_integration(db: Session, integration_id: int) -> dict:
    """Re-establish connection (credentials revalidated before ACTIVE)."""
    return connect_integration(db, integration_id)


# ── Serialization helpers ────────────────────────────────────────────────────
def integration_payload(db: Session, integration: POSIntegration) -> dict:
    """Safe serialization used by list/detail endpoints."""
    mapping_count = (
        db.query(POSProductMapping)
        .filter(POSProductMapping.integration_id == integration.id, POSProductMapping.is_active == True)  # noqa: E712
        .count()
    )
    device_count = db.query(POSDevice).filter(POSDevice.integration_id == integration.id).count()
    return {
        "id": integration.id,
        "shop_id": integration.shop_id,
        "provider_code": integration.provider_code,
        "provider_name": integration.provider_name,
        "integration_type": integration.integration_type,
        "status": integration.status.value if hasattr(integration.status, "value") else str(integration.status),
        "sync_enabled": integration.sync_enabled,
        "sync_interval_minutes": integration.sync_interval_minutes,
        "auto_create_products": integration.auto_create_products,
        "conflict_strategy": integration.conflict_strategy,
        "incremental_cursor": integration.incremental_cursor,
        "last_sync_at": integration.last_sync_at,
        "last_sync_status": integration.last_sync_status,
        "last_successful_sync_at": integration.last_successful_sync_at,
        "consecutive_failures": integration.consecutive_failures,
        "disconnected_at": integration.disconnected_at,
        "config_json": integration.config_json,
        "credentials": POSCredentials.masked_view(integration),
        "mapped_products": mapping_count,
        "devices": device_count,
    }


def job_payload(job: POSSyncJob) -> dict:
    status = job.status.value if hasattr(job.status, "value") else str(job.status)
    return {
        "id": job.id,
        "integration_id": job.integration_id,
        "shop_id": job.shop_id,
        "sync_type": job.sync_type,
        "status": status,
        "trigger": job.trigger,
        "items_processed": job.items_processed,
        "items_succeeded": job.items_succeeded,
        "items_failed": job.items_failed,
        "duplicates_skipped": job.duplicates_skipped,
        "error_summary": job.error_summary,
        "idempotency_key": job.idempotency_key,
        "retry_count": job.retry_count,
        "next_retry_at": job.next_retry_at,
        "started_at": job.started_at,
        "completed_at": job.completed_at,
        "created_by": job.created_by,
    }


def sync_status(db: Session, integration: POSIntegration) -> dict:
    """Aggregated status view for dashboards (`GET .../status`)."""
    latest_job = (
        db.query(POSSyncJob)
        .filter(POSSyncJob.integration_id == integration.id)
        .order_by(POSSyncJob.id.desc())
        .first()
    )
    payload = integration_payload(db, integration)
    payload["latest_job"] = job_payload(latest_job) if latest_job else None
    return payload


def _require_job(db: Session, job_id: int) -> POSSyncJob:
    job = db.query(POSSyncJob).filter(POSSyncJob.id == job_id).first()
    if job is None:
        raise NotFoundError("POS sync job not found")
    return job


# ── Device mapping ───────────────────────────────────────────────────────────
def register_device(
    db: Session,
    *,
    shop_id: int,
    integration_id: int,
    device_identifier: str,
    device_name: str | None = None,
    device_type: str | None = None,
) -> POSDevice:
    """Idempotently map a physical POS terminal to shop + integration."""
    device = (
        db.query(POSDevice)
        .filter(
            POSDevice.shop_id == shop_id,
            POSDevice.device_identifier == device_identifier,
        )
        .first()
    )
    if device is not None:
        # Re-registration refreshes metadata instead of duplicating the row.
        device.integration_id = integration_id
        if device_name:
            device.device_name = device_name
        if device_type:
            device.device_type = device_type
        device.is_active = True
        db.flush()
        return device

    device = POSDevice(
        shop_id=shop_id,
        integration_id=integration_id,
        device_identifier=device_identifier,
        device_name=device_name,
        device_type=device_type,
        last_connected_at=_utcnow(),
    )
    db.add(device)
    db.flush()
    return device


def list_devices(db: Session, shop_id: int) -> list[POSDevice]:
    return (
        db.query(POSDevice)
        .filter(POSDevice.shop_id == shop_id, POSDevice.is_deleted == False)  # noqa: E712
        .all()
    )


# ── Manual trigger / idempotency / scheduling ────────────────────────────────
def trigger_manual_sync(
    db: Session,
    integration_id: int,
    *,
    sync_type: str = "FULL",
    user_id: int | None = None,
    idempotency_key: str | None = None,
    trigger: str = "MANUAL",
) -> tuple[POSSyncJob, bool]:
    """Queue a sync job. Returns ``(job, created)``.

    Idempotency: repeating a call with the same ``idempotency_key`` returns
    the *existing* job (no duplicate work is ever queued).
    """
    integration = _require_integration(db, integration_id)

    if integration.status == POSIntegrationStatus.DISCONNECTED:
        raise ConflictError("POS integration is disconnected — reconnect before syncing")
    if sync_type not in VALID_SYNC_TYPES:
        raise ValidationError(f"sync_type must be one of {sorted(VALID_SYNC_TYPES)}")

    if idempotency_key:
        existing = db.query(POSSyncJob).filter(POSSyncJob.idempotency_key == idempotency_key).first()
        if existing is not None:
            return existing, False

    running = (
        db.query(POSSyncJob)
        .filter(
            POSSyncJob.integration_id == integration.id,
            POSSyncJob.status.in_([POSSyncStatus.PENDING, POSSyncStatus.RUNNING]),
        )
        .first()
    )
    if running is not None:
        raise ConflictError("A sync job is already queued or running for this integration")

    job = POSSyncJob(
        shop_id=integration.shop_id,
        integration_id=integration.id,
        sync_type=sync_type,
        status=POSSyncStatus.PENDING,
        created_by=user_id,
        idempotency_key=idempotency_key,
        trigger=trigger,
        # Inherit the integration's failure streak so automatic backoff
        # escalates across successive jobs until a sync succeeds.
        retry_count=integration.consecutive_failures or 0,
    )
    db.add(job)
    db.flush()
    logger.info("Queued POS sync job id=%s integration=%s type=%s", job.id, integration.id, sync_type)
    return job, True


def find_due_integrations(db: Session, now: datetime | None = None) -> list[POSIntegration]:
    """Scheduler helper — ACTIVE integrations whose cadence has elapsed.

    Skips integrations that already have a PENDING/RUNNING job so repeated
    scheduler ticks never double-dispatch.
    """
    now = now or _utcnow()
    integrations = (
        db.query(POSIntegration)
        .filter(
            POSIntegration.status == POSIntegrationStatus.ACTIVE,
            POSIntegration.sync_enabled == True,   # noqa: E712
            POSIntegration.is_deleted == False,    # noqa: E712
        )
        .all()
    )
    due: list[POSIntegration] = []
    for integration in integrations:
        if integration.last_successful_sync_at is not None:
            last = integration.last_successful_sync_at
            if last.tzinfo is None:  # SQLite returns naive UTC datetimes
                last = last.replace(tzinfo=timezone.utc)
            deadline = last + timedelta(minutes=integration.sync_interval_minutes)
            if now < deadline:
                continue
        open_job = (
            db.query(POSSyncJob)
            .filter(
                POSSyncJob.integration_id == integration.id,
                POSSyncJob.status.in_([POSSyncStatus.PENDING, POSSyncStatus.RUNNING]),
            )
            .first()
        )
        if open_job is not None:
            continue
        due.append(integration)
    return due


# ── Failure handling / retry policy ──────────────────────────────────────────
def _schedule_retry(job: POSSyncJob, now: datetime) -> None:
    """Exponential backoff; after MAX_AUTO_RETRIES only manual retry applies."""
    if job.retry_count >= MAX_AUTO_RETRIES:
        job.next_retry_at = None  # gave up automatically
        return
    job.retry_count += 1
    delay_minutes = RETRY_BACKOFF_BASE_MINUTES * (2 ** (job.retry_count - 1))
    job.next_retry_at = now + timedelta(minutes=delay_minutes)


def _fail_job(db: Session, job: POSSyncJob, integration: POSIntegration, exc: Exception, now: datetime) -> dict:
    """Whole-job failure (provider unreachable / auth rejected / crashed)."""
    error_code = getattr(exc, "error_code", "POS_PROVIDER_ERROR")
    message = getattr(exc, "message", str(exc))
    job.status = POSSyncStatus.FAILED
    job.completed_at = now
    job.error_summary = f"{error_code}: {message}"
    integration.last_sync_status = "FAILED"
    integration.last_sync_at = now
    integration.consecutive_failures = (integration.consecutive_failures or 0) + 1
    _add_log(db, job, "ERROR", f"Sync failed: {message}", error_code=error_code)
    _schedule_retry(job, now)
    db.flush()
    logger.warning(
        "POS sync job %s failed (%s); attempt=%s next_retry_at=%s",
        job.id, error_code, job.retry_count, job.next_retry_at,
    )
    return job_payload(job)


# ── Job execution ────────────────────────────────────────────────────────────
def run_sync_job(db: Session, job_id: int) -> dict:
    """Execute a queued sync job end-to-end (mapping pipeline per record).

    Guarantees:
      * provider outage / auth failure → whole job FAILED (+ backoff plan)
      * bad individual record          → item failure, job continues (partial)
      * unchanged / duplicate records  → counted & skipped, never re-applied
      * incremental runs               → cursor advanced ONLY on clean success
    """
    job = _require_job(db, job_id)

    if job.status in (POSSyncStatus.COMPLETED, POSSyncStatus.COMPLETED_WITH_ERRORS):
        return {**job_payload(job), "note": "already completed"}

    integration = (
        db.query(POSIntegration).filter(POSIntegration.id == job.integration_id).first()
    )
    now = _utcnow()
    if integration is None:
        job.status = POSSyncStatus.FAILED
        job.completed_at = now
        job.error_summary = "INTEGRATION_MISSING: parent integration was deleted"
        db.flush()
        return job_payload(job)

    if integration.status == POSIntegrationStatus.DISCONNECTED:
        job.status = POSSyncStatus.CANCELLED
        job.completed_at = now
        job.error_summary = "CANCELLED_BEFORE_RUN: integration disconnected"
        _add_log(db, job, "WARNING", "Job cancelled — integration is disconnected", error_code="DISCONNECTED")
        db.flush()
        return job_payload(job)

    provider = get_provider(integration.provider_code or integration.provider_name)
    credentials = POSCredentials.from_integration(integration).as_provider_input()

    job.status = POSSyncStatus.RUNNING
    job.started_at = now
    db.flush()

    since = integration.incremental_cursor if job.sync_type == "INCREMENTAL" else None
    batch_size = int((integration.config_json or {}).get("batch_size", 500))
    try:
        result = provider.fetch_products(credentials, since=since, limit=batch_size)
    except POSProviderError as exc:
        return _fail_job(db, job, integration, exc, _utcnow())
    except Exception as exc:  # noqa: BLE001 — adapter crash is still a retryable failure
        return _fail_job(db, job, integration, POSProviderError(str(exc)), _utcnow())

    seen_codes: set[str] = set()
    conflicts: list[dict] = []

    for record in result.items:
        if isinstance(record, dict):
            record = normalize_product_record(record)

        code = record.pos_product_code
        job.items_processed += 1

        # Duplicate prevention (1/2): repeated code within one fetch.
        if code in seen_codes:
            job.duplicates_skipped += 1
            _add_log(db, job, "WARNING", "Duplicate record within batch — skipped",
                     item_reference=code, error_code="DUPLICATE_IN_BATCH")
            continue
        seen_codes.add(code)

        fingerprint = record.content_fingerprint()
        mapping = (
            db.query(POSProductMapping)
            .filter(
                POSProductMapping.integration_id == integration.id,
                POSProductMapping.pos_product_code == code,
            )
            .first()
        )
        # Duplicate prevention (2/2): identical content since last applied sync.
        if mapping is not None and mapping.last_synced_hash == fingerprint and mapping.shop_product_id:
            job.duplicates_skipped += 1
            _add_log(db, job, "INFO", "Record unchanged since last sync — skipped",
                     item_reference=code, error_code="SKIPPED_UNCHANGED")
            continue

        try:
            outcome = _apply_record(db, integration, job, record, fingerprint)
        except ItemSyncError as exc:
            job.items_failed += 1
            _add_log(db, job, "ERROR", exc.message, item_reference=code, error_code=exc.error_code)
            continue
        except Exception as exc:  # noqa: BLE001 — isolate bad records from the run
            job.items_failed += 1
            _add_log(db, job, "ERROR", str(exc), item_reference=code,
                     error_code="ITEM_SYNC_FAILED", stack_trace=format_exc())
            continue

        job.items_succeeded += 1
        for conflict in outcome.get("conflicts", []):
            conflicts.append({"pos_product_code": code, **conflict})
            _add_log(
                db, job, "WARNING",
                f"Conflict on '{conflict['field']}' for '{code}': POS={conflict['pos_value']} "
                f"vs platform={conflict['platform_value']} — platform value preserved",
                item_reference=code,
                error_code=f"CONFLICT_{str(conflict['field']).upper()}_PRESERVED",
            )
        applied = outcome.get("action", "UPDATED")
        stock_note = f" + {outcome['stock_action']}" if outcome.get("stock_action") else ""
        _add_log(db, job, "INFO", f"Applied ({applied}{stock_note})", item_reference=code)

    finished = _utcnow()
    job.completed_at = finished
    integration.last_sync_at = finished

    if job.items_failed == 0:
        job.status = POSSyncStatus.COMPLETED
        integration.last_sync_status = "COMPLETED"
        integration.last_successful_sync_at = finished
        integration.consecutive_failures = 0
        if provider.supports_incremental and result.cursor:
            # Cursor advances only on clean runs — failed items re-fetch next time.
            integration.incremental_cursor = result.cursor
    else:
        # Partial failure: useful work persisted, but flagged for attention.
        job.status = POSSyncStatus.COMPLETED_WITH_ERRORS
        integration.last_sync_status = "PARTIAL"

    db.flush()

    # Phase 27 — tell the shopkeeper how their sync run ended.
    try:
        from app.models.shop import ShopOwner
        from app.services import notification_service

        owner_row = (
            db.query(ShopOwner.user_id).filter(ShopOwner.shop_id == integration.shop_id).first()
        )
        if owner_row is not None:
            notification_service.notify_pos_sync_event(
                db,
                shopkeeper_user_id=owner_row[0],
                integration_id=integration.id,
                job_id=job.id,
                ok=job.status == POSSyncStatus.COMPLETED,
                detail=f"Sync {job.status.value}: {job.items_succeeded} ok / {job.items_failed} failed",
            )
    except Exception:  # noqa: BLE001 — notifications must never break a sync run
        logger.warning("Failed to notify shopkeeper of POS sync job %s outcome", job.id)

    logger.info(
        "POS sync job %s finished status=%s processed=%s ok=%s failed=%s duplicates=%s",
        job.id, job.status.value, job.items_processed,
        job.items_succeeded, job.items_failed, job.duplicates_skipped,
    )
    return {**job_payload(job), "conflicts": conflicts}


# ── Data mapping pipeline ────────────────────────────────────────────────────
#   POS Product → Product Identifier → Master/Variant → ShopProduct
#     → Price (authority rules) → Inventory (canonical system, POS wins)
def _resolve_existing_product(
    db: Session, record: POSProductRecord
) -> tuple[ProductMaster | None, ProductVariant | None]:
    """Match a POS record to an existing platform product via barcode/SKU."""
    if record.barcode:
        identifiers = (
            db.query(ProductIdentifier)
            .filter(
                ProductIdentifier.identifier_value == record.barcode,
                ProductIdentifier.is_active == True,  # noqa: E712
            )
            .all()
        )
        if len(identifiers) > 1:
            raise ItemSyncError(
                f"Barcode '{record.barcode}' matches multiple catalog products",
                "AMBIGUOUS_BARCODE",
            )
        if len(identifiers) == 1:
            master = (
                db.query(ProductMaster)
                .filter(
                    ProductMaster.id == identifiers[0].product_master_id,
                    ProductMaster.is_deleted == False,  # noqa: E712
                )
                .first()
            )
            if master is not None:
                variant = None
                if record.sku:
                    variant = (
                        db.query(ProductVariant)
                        .filter(
                            ProductVariant.sku == record.sku,
                            ProductVariant.product_master_id == master.id,
                        )
                        .first()
                    )
                return master, variant

    if record.sku:
        variant = db.query(ProductVariant).filter(ProductVariant.sku == record.sku).first()
        if variant is not None:
            master = (
                db.query(ProductMaster)
                .filter(
                    ProductMaster.id == variant.product_master_id,
                    ProductMaster.is_deleted == False,  # noqa: E712
                )
                .first()
            )
            if master is not None:
                return master, variant
    return None, None


def _create_product(
    db: Session, integration: POSIntegration, record: POSProductRecord
) -> tuple[ProductMaster, ProductVariant]:
    """Auto-create ProductMaster (+default variant) for an unknown POS item."""
    base_slug = _slugify(record.name)
    slug = f"{base_slug}-{record.pos_product_code.lower()}"
    suffix = 2
    while db.query(ProductMaster).filter(ProductMaster.slug == slug).first() is not None:
        slug = f"{base_slug}-{record.pos_product_code.lower()}-{suffix}"
        suffix += 1

    master = ProductMaster(name=record.name, slug=slug, status=ProductStatus.DRAFT)
    db.add(master)
    db.flush()

    sku = record.sku or f"POS-{integration.id}-{record.pos_product_code}"
    if db.query(ProductVariant).filter(ProductVariant.sku == sku).first() is not None:
        sku = f"{sku}-{integration.shop_id}"
    variant = ProductVariant(product_master_id=master.id, sku=sku, name=record.name)
    db.add(variant)
    db.flush()
    return master, variant


def _apply_record(
    db: Session,
    integration: POSIntegration,
    job: POSSyncJob,
    record: POSProductRecord,
    fingerprint: str,
) -> dict:
    """Apply one POS record through the full mapping chain."""
    config = integration.config_json or {}
    shop_id = integration.shop_id
    conflicts: list[dict] = []

    mapping = (
        db.query(POSProductMapping)
        .filter(
            POSProductMapping.integration_id == integration.id,
            POSProductMapping.pos_product_code == record.pos_product_code,
        )
        .first()
    )

    # 1) Resolve the mapped catalog entity chain (repair broken mappings).
    master: ProductMaster | None = None
    variant: ProductVariant | None = None
    if mapping is not None and mapping.product_master_id:
        master = (
            db.query(ProductMaster)
            .filter(
                ProductMaster.id == mapping.product_master_id,
                ProductMaster.is_deleted == False,  # noqa: E712
            )
            .first()
        )
        if master is None:
            # Mapped product vanished — deactivate stale mapping, re-resolve.
            mapping.is_active = False
            mapping = None
        elif mapping.variant_id:
            variant = db.query(ProductVariant).filter(ProductVariant.id == mapping.variant_id).first()

    if master is None:
        master, variant = _resolve_existing_product(db, record)
    if master is None:
        if not integration.auto_create_products:
            raise ItemSyncError(
                f"No platform product matches '{record.name}' and auto-create is disabled",
                "NO_PRODUCT_MATCH",
            )
        master, variant = _create_product(db, integration, record)

    # 1b) Enrich the platform catalog with the POS barcode so future scans
    #     and syncs can resolve this product by identifier.
    if record.barcode:
        exists = (
            db.query(ProductIdentifier)
            .filter(ProductIdentifier.identifier_value == record.barcode)
            .first()
        )
        if exists is None:
            db.add(
                ProductIdentifier(
                    product_master_id=master.id,
                    identifier_type=_guess_identifier_type(record.barcode),
                    identifier_value=record.barcode,
                )
            )

    # 2) ShopProduct upsert (unique per shop+master+variant).
    sp_query = db.query(ShopProduct).filter(
        ShopProduct.shop_id == shop_id,
        ShopProduct.product_master_id == master.id,
    )
    if variant is None:
        sp_query = sp_query.filter(ShopProduct.variant_id.is_(None))
    else:
        sp_query = sp_query.filter(ShopProduct.variant_id == variant.id)
    sp = sp_query.first()

    if sp is None:
        sp = ShopProduct(
            shop_id=shop_id,
            product_master_id=master.id,
            variant_id=variant.id if variant else None,
            sku=record.sku,
            price=float(record.price) if record.price is not None else 0.0,
            mrp=float(record.mrp) if record.mrp is not None else None,
            source=InventorySource.POS_INTEGRATION,
            status=ShopProductStatus.ACTIVE,
        )
        db.add(sp)
        db.flush()
        action = "CREATED"
    else:
        action = "UPDATED"

    # 3) Price — governed by source-of-truth rules. Platform pricing is never
    #    overwritten blindly; non-authoritative differences are logged as
    #    conflicts and preserved.
    now = _utcnow()
    if record.price is not None and abs(float(sp.price) - float(record.price)) > PRICE_TOLERANCE:
        if action == "CREATED":
            pass  # POS value seeded at creation — nothing pre-existing overwritten
        elif field_authority(integration, "price") == "POS":
            old_price = float(sp.price)
            old_mrp = float(sp.mrp) if sp.mrp is not None else None
            sp.price = float(record.price)
            if record.mrp is not None:
                sp.mrp = float(record.mrp)
            sp.last_price_update = now
            db.add(
                PriceHistory(
                    shop_product_id=sp.id,
                    old_price=old_price,
                    new_price=float(record.price),
                    old_mrp=old_mrp,
                    new_mrp=float(sp.mrp) if sp.mrp is not None else None,
                )
            )
            action = "PRICE_UPDATED"
        else:
            conflicts.append({
                "field": "price",
                "pos_value": float(record.price),
                "platform_value": float(sp.price),
                "resolution": "PRESERVED_PLATFORM",
            })

    # 4) Inventory — ALWAYS through the canonical inventory service so POS
    #    stock lands in the SAME system as manual/barcode/Excel sources.
    #    Inventory is POS-authoritative by the source-of-truth table.
    stock_action = None
    if record.quantity is not None:
        quantity = max(int(record.quantity), 0)  # clamp negatives defensively
        inv = db.query(Inventory).filter(Inventory.shop_product_id == sp.id).first()
        reference = {
            "source": InventorySource.POS_INTEGRATION,
            "reference_type": "pos_sync",
            "reference_id": job.id,
        }
        try:
            if inv is None:
                inventory_service.create_inventory(
                    db,
                    {
                        "shop_product_id": sp.id,
                        "quantity": quantity,
                        "low_stock_threshold": config.get("low_stock_threshold"),
                        **reference,
                    },
                )
                stock_action = "STOCK_CREATED"
            elif int(inv.quantity) != quantity:
                inventory_service.update_inventory(db, inv.id, {"quantity": quantity, **reference})
                stock_action = "STOCK_UPDATED"
        except ValueError as exc:
            raise ItemSyncError(str(exc), "INVENTORY_SYNC_FAILED")

    # 5) Persist the durable mapping + duplicate-prevention fingerprint.
    if mapping is None:
        mapping = POSProductMapping(
            integration_id=integration.id,
            shop_id=shop_id,
            pos_product_code=record.pos_product_code,
        )
        db.add(mapping)
    mapping.pos_sku = record.sku
    mapping.barcode = record.barcode
    mapping.product_master_id = master.id
    mapping.variant_id = variant.id if variant else None
    mapping.shop_product_id = sp.id
    mapping.last_synced_hash = fingerprint
    mapping.last_synced_at = _utcnow()
    mapping.is_active = True
    mapping.last_conflict_json = {"conflicts": conflicts} if conflicts else None
    db.flush()

    return {"action": action, "stock_action": stock_action, "conflicts": conflicts}


# ── Retry / job queries ──────────────────────────────────────────────────────
def retry_failed_job(db: Session, job_id: int, user_id: int | None = None) -> dict:
    """Manually re-run a FAILED job (allowed even after auto-retries exhausted)."""
    job = _require_job(db, job_id)
    if job.status != POSSyncStatus.FAILED:
        raise ConflictError("Only FAILED jobs can be retried")
    integration = _require_integration(db, job.integration_id)
    if integration.status == POSIntegrationStatus.DISCONNECTED:
        raise ConflictError("POS integration is disconnected — reconnect before retrying")

    job.status = POSSyncStatus.PENDING
    job.error_summary = None
    job.next_retry_at = None
    job.trigger = "RETRY"
    if user_id is not None:
        job.created_by = user_id
    db.flush()
    return run_sync_job(db, job.id)


def list_jobs(db: Session, integration_id: int, limit: int = 20) -> list[POSSyncJob]:
    return (
        db.query(POSSyncJob)
        .filter(POSSyncJob.integration_id == integration_id)
        .order_by(POSSyncJob.id.desc())
        .limit(limit)
        .all()
    )


def get_job_logs(db: Session, job_id: int) -> list[dict]:
    logs = (
        db.query(POSSyncLog)
        .filter(POSSyncLog.sync_job_id == job_id)
        .order_by(POSSyncLog.logged_at.asc(), POSSyncLog.id.asc())
        .all()
    )
    return [
        {
            "id": log.id,
            "log_level": log.log_level,
            "message": log.message,
            "item_reference": log.item_reference,
            "error_code": log.error_code,
            "logged_at": log.logged_at,
        }
        for log in logs
    ]


def job_detail(db: Session, job: POSSyncJob) -> dict:
    """Job payload + full logs + every recorded mapping conflict."""
    payload = job_payload(job)
    payload["logs"] = get_job_logs(db, job.id)

    conflict_entries: list[dict] = []
    mappings = (
        db.query(POSProductMapping)
        .filter(
            POSProductMapping.integration_id == job.integration_id,
            POSProductMapping.last_conflict_json.isnot(None),
        )
        .all()
    )
    for mapping in mappings:
        for conflict in ((mapping.last_conflict_json or {}).get("conflicts") or []):
            conflict_entries.append({"pos_product_code": mapping.pos_product_code, **conflict})
    payload["conflicts"] = conflict_entries
    return payload
