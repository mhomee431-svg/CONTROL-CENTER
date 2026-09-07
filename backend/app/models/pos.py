"""POS Integration, POS Device, POS Sync Job, POS Sync Log models."""
from datetime import datetime
from sqlalchemy import String, Integer, DateTime, Boolean, Text, ForeignKey, Enum, UniqueConstraint, JSON, Index
from sqlalchemy.orm import Mapped, mapped_column, relationship
import enum

from app.database.session import Base
from app.models.base import TimestampMixin, SoftDeleteMixin


class POSIntegrationStatus(str, enum.Enum):
    ACTIVE = "ACTIVE"
    INACTIVE = "INACTIVE"
    SUSPENDED = "SUSPENDED"
    ERROR = "ERROR"
    DISCONNECTED = "DISCONNECTED"  # Phase 25: explicitly disconnected by shopkeeper


class POSSyncStatus(str, enum.Enum):
    PENDING = "PENDING"
    RUNNING = "RUNNING"
    COMPLETED = "COMPLETED"
    COMPLETED_WITH_ERRORS = "COMPLETED_WITH_ERRORS"  # Phase 25: partial failure
    FAILED = "FAILED"
    CANCELLED = "CANCELLED"


class POSIntegration(Base, TimestampMixin, SoftDeleteMixin):
    __tablename__ = "pos_integrations"

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    shop_id: Mapped[int] = mapped_column(ForeignKey("shops.id"), index=True, nullable=False)
    provider_name: Mapped[str] = mapped_column(String(100), nullable=False)  # e.g. "Marg", "Busy", "Vyapar"
    integration_type: Mapped[str] = mapped_column(String(50), nullable=False)  # API, FILE_UPLOAD, WEBHOOK
    api_base_url: Mapped[str | None] = mapped_column(String(500))
    api_key_encrypted: Mapped[str | None] = mapped_column(Text)
    api_secret_encrypted: Mapped[str | None] = mapped_column(Text)
    status: Mapped[POSIntegrationStatus] = mapped_column(
        Enum(POSIntegrationStatus, name="pos_integration_status"), nullable=False, default=POSIntegrationStatus.ACTIVE
    )
    last_sync_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    last_sync_status: Mapped[str | None] = mapped_column(String(20))
    config_json: Mapped[dict | None] = mapped_column(JSON)

    # ── Phase 25 — sync configuration / schedule / incremental state ──
    provider_code: Mapped[str | None] = mapped_column(String(50), index=True)
    sync_enabled: Mapped[bool] = mapped_column(Boolean, default=True)
    sync_interval_minutes: Mapped[int] = mapped_column(Integer, default=60)  # schedule cadence
    auto_create_products: Mapped[bool] = mapped_column(Boolean, default=True)
    conflict_strategy: Mapped[str] = mapped_column(String(30), default="PRESERVE_PLATFORM")
    incremental_cursor: Mapped[str | None] = mapped_column(String(255))     # opaque provider cursor
    last_successful_sync_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    consecutive_failures: Mapped[int] = mapped_column(Integer, default=0)
    disconnected_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))

    shop = relationship("Shop")
    devices = relationship("POSDevice", back_populates="integration", cascade="all, delete-orphan")
    sync_jobs = relationship("POSSyncJob", back_populates="integration", cascade="all, delete-orphan")
    mappings = relationship("POSProductMapping", back_populates="integration", cascade="all, delete-orphan")


class POSDevice(Base, TimestampMixin, SoftDeleteMixin):
    __tablename__ = "pos_devices"
    __table_args__ = (
        UniqueConstraint("shop_id", "device_identifier", name="uq_pos_device_shop_identifier"),
    )

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    shop_id: Mapped[int] = mapped_column(ForeignKey("shops.id"), index=True, nullable=False)
    integration_id: Mapped[int | None] = mapped_column(ForeignKey("pos_integrations.id"), index=True)
    device_identifier: Mapped[str] = mapped_column(String(100), nullable=False, index=True)
    device_name: Mapped[str | None] = mapped_column(String(255))
    device_type: Mapped[str | None] = mapped_column(String(50))  # POS_TERMINAL, SCANNER, TABLET
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)
    last_connected_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    firmware_version: Mapped[str | None] = mapped_column(String(50))

    shop = relationship("Shop", back_populates="pos_devices")
    integration = relationship("POSIntegration", back_populates="devices")


class POSSyncJob(Base, TimestampMixin):
    __tablename__ = "pos_sync_jobs"

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    shop_id: Mapped[int] = mapped_column(ForeignKey("shops.id"), index=True, nullable=False)
    integration_id: Mapped[int | None] = mapped_column(ForeignKey("pos_integrations.id"), index=True)
    sync_type: Mapped[str] = mapped_column(String(50), nullable=False)  # INVENTORY, PRICE, PRODUCT, FULL
    status: Mapped[POSSyncStatus] = mapped_column(
        Enum(POSSyncStatus, name="pos_sync_status"), nullable=False, default=POSSyncStatus.PENDING
    )
    started_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    completed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    items_processed: Mapped[int] = mapped_column(Integer, default=0)
    items_succeeded: Mapped[int] = mapped_column(Integer, default=0)
    items_failed: Mapped[int] = mapped_column(Integer, default=0)
    error_summary: Mapped[str | None] = mapped_column(Text)
    created_by: Mapped[int | None] = mapped_column(ForeignKey("users.id"))

    # ── Phase 25 — idempotency / retry bookkeeping ──
    idempotency_key: Mapped[str | None] = mapped_column(String(64), unique=True, index=True)
    trigger: Mapped[str] = mapped_column(String(20), default="MANUAL")  # MANUAL, SCHEDULED, RETRY
    retry_count: Mapped[int] = mapped_column(Integer, default=0)
    next_retry_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    duplicates_skipped: Mapped[int] = mapped_column(Integer, default=0)

    shop = relationship("Shop", back_populates="pos_sync_jobs")
    integration = relationship("POSIntegration", back_populates="sync_jobs")
    logs = relationship("POSSyncLog", back_populates="sync_job", cascade="all, delete-orphan")


class POSSyncLog(Base, TimestampMixin):
    __tablename__ = "pos_sync_logs"

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    sync_job_id: Mapped[int] = mapped_column(ForeignKey("pos_sync_jobs.id"), index=True, nullable=False)
    log_level: Mapped[str] = mapped_column(String(20), nullable=False, default="INFO")  # INFO, WARNING, ERROR
    message: Mapped[str] = mapped_column(Text, nullable=False)
    item_reference: Mapped[str | None] = mapped_column(String(255))
    error_code: Mapped[str | None] = mapped_column(String(50))
    stack_trace: Mapped[str | None] = mapped_column(Text)
    logged_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, default=datetime.utcnow)

    sync_job = relationship("POSSyncJob", back_populates="logs")


class POSProductMapping(Base, TimestampMixin):
    """Phase 25 — durable mapping of a POS product to platform entities.

    Data mapping chain:
        POS Product (pos_product_code / pos_sku / barcode)
          → ProductIdentifier (barcode match, when present)
          → ProductMaster / ProductVariant (matched or auto-created)
          → ShopProduct (per-shop listing)
          → Price + Inventory (authoritative-source rules apply)

    ``last_synced_hash`` is the fingerprint of the last applied POS record;
    identical fingerprints are skipped (duplicate prevention / no-op safety).
    """

    __tablename__ = "pos_product_mappings"
    __table_args__ = (
        UniqueConstraint("integration_id", "pos_product_code", name="uq_pos_mapping_integration_code"),
        Index("ix_pos_mappings_shop_product", "shop_product_id"),
        Index("ix_pos_mappings_barcode", "barcode"),
    )

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    integration_id: Mapped[int] = mapped_column(ForeignKey("pos_integrations.id"), index=True, nullable=False)
    shop_id: Mapped[int] = mapped_column(ForeignKey("shops.id"), index=True, nullable=False)
    pos_product_code: Mapped[str] = mapped_column(String(100), nullable=False)
    pos_sku: Mapped[str | None] = mapped_column(String(100))
    barcode: Mapped[str | None] = mapped_column(String(100))

    product_master_id: Mapped[int | None] = mapped_column(ForeignKey("product_masters.id"), index=True)
    variant_id: Mapped[int | None] = mapped_column(ForeignKey("product_variants.id"), index=True)
    shop_product_id: Mapped[int | None] = mapped_column(ForeignKey("shop_products.id"), index=True)

    last_synced_hash: Mapped[str | None] = mapped_column(String(64))
    last_synced_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    last_conflict_json: Mapped[dict | None] = mapped_column(JSON)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)

    integration = relationship("POSIntegration", back_populates="mappings")
    product_master = relationship("ProductMaster")
    variant = relationship("ProductVariant")
    shop_product = relationship("ShopProduct")