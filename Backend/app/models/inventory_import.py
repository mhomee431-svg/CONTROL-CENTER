"""Phase 24 — Inventory import jobs (Excel intake) models."""

from datetime import datetime
from sqlalchemy import (
    String, Integer, DateTime, Text, ForeignKey, Index, Enum,
)
from sqlalchemy.orm import Mapped, mapped_column

import enum

from app.database.session import Base
from app.models.base import TimestampMixin


class ImportJobStatus(str, enum.Enum):
    """Lifecycle of an Excel inventory-import job."""

    VALIDATING = "VALIDATING"                    # parse/validation in flight
    AWAITING_CONFIRMATION = "AWAITING_CONFIRMATION"  # preview ready, shopkeeper must confirm
    QUEUED = "QUEUED"                            # handed to background worker (large import)
    PROCESSING = "PROCESSING"                    # worker applying rows
    COMPLETED = "COMPLETED"                      # every valid row applied
    PARTIAL = "PARTIAL"                          # some rows failed — retry possible
    FAILED = "FAILED"                            # file-level failure (unreadable/invalid)


class InventoryImportJob(Base, TimestampMixin):
    """One uploaded Excel file for one shop's inventory import."""

    __tablename__ = "inventory_import_jobs"
    __table_args__ = (
        # Idempotency: re-uploading the exact same file for the same shop maps
        # to the same key, letting the service return the original job instead
        # of double-applying the import.
        Index("ix_inventory_import_jobs_shop_key", "shop_id", "idempotency_key"),
    )

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    shop_id: Mapped[int] = mapped_column(ForeignKey("shops.id"), index=True, nullable=False)
    uploaded_by: Mapped[int | None] = mapped_column(ForeignKey("users.id"))

    filename: Mapped[str | None] = mapped_column(String(255))
    file_size_bytes: Mapped[int | None] = mapped_column(Integer)
    idempotency_key: Mapped[str | None] = mapped_column(String(64), index=True)

    status: Mapped[ImportJobStatus] = mapped_column(
        Enum(ImportJobStatus, name="inventory_import_job_status"),
        nullable=False,
        default=ImportJobStatus.VALIDATING,
        index=True,
    )

    total_rows: Mapped[int] = mapped_column(Integer, default=0)
    valid_rows: Mapped[int] = mapped_column(Integer, default=0)
    error_rows: Mapped[int] = mapped_column(Integer, default=0)
    processed_rows: Mapped[int] = mapped_column(Integer, default=0)
    failed_rows: Mapped[int] = mapped_column(Integer, default=0)

    error_message: Mapped[str | None] = mapped_column(Text)
    started_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    completed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


class InventoryImportRow(Base, TimestampMixin):
    """One spreadsheet row of an import job with its validation outcome.

    Row-level errors are persisted so the shopkeeper gets actionable,
    field-specific feedback and can fix/retry individual rows.
    """

    __tablename__ = "inventory_import_rows"

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    job_id: Mapped[int] = mapped_column(
        ForeignKey("inventory_import_jobs.id"), index=True, nullable=False
    )
    row_number: Mapped[int] = mapped_column(Integer, nullable=False)  # 1-based data row

    # PENDING → VALID → PROCESSED | ERROR | SKIPPED
    status: Mapped[str] = mapped_column(String(20), nullable=False, default="PENDING", index=True)

    raw_data: Mapped[str | None] = mapped_column(Text)         # JSON: original cells
    normalized_data: Mapped[str | None] = mapped_column(Text)  # JSON: cleaned values

    error_code: Mapped[str | None] = mapped_column(String(60))
    error_message: Mapped[str | None] = mapped_column(Text)
    error_field: Mapped[str | None] = mapped_column(String(60))

    product_master_id: Mapped[int | None] = mapped_column(Integer)
    variant_id: Mapped[int | None] = mapped_column(Integer)
    shop_product_id: Mapped[int | None] = mapped_column(Integer)
