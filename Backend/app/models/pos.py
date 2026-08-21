"""POS Integration, POS Device, POS Sync Job, POS Sync Log models."""
from datetime import datetime
from sqlalchemy import String, Integer, DateTime, Boolean, Text, ForeignKey, Enum, UniqueConstraint, JSON
from sqlalchemy.orm import Mapped, mapped_column, relationship
import enum

from app.database.session import Base
from app.models.base import TimestampMixin, SoftDeleteMixin


class POSIntegrationStatus(str, enum.Enum):
    ACTIVE = "ACTIVE"
    INACTIVE = "INACTIVE"
    SUSPENDED = "SUSPENDED"
    ERROR = "ERROR"


class POSSyncStatus(str, enum.Enum):
    PENDING = "PENDING"
    RUNNING = "RUNNING"
    COMPLETED = "COMPLETED"
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

    shop = relationship("Shop")
    devices = relationship("POSDevice", back_populates="integration", cascade="all, delete-orphan")
    sync_jobs = relationship("POSSyncJob", back_populates="integration", cascade="all, delete-orphan")


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