"""Phase 2/3 - Media object state-machine model.

Each server-minted S3 object key is tracked through a lifecycle state that is
advanced by the Phase 3 S3-event Lambda (`backend/lambda_function.py`). The
Flutter shopkeeper media UI observes these states:

    PENDING -> UPLOADED -> PROCESSING -> READY | FAILED

The database never stores binary media -- only the object key (and metadata
that is cheap to index) plus the lifecycle state. Quarantined corrupt objects
keep their `quarantine_key` so an operator can inspect them.
"""
from __future__ import annotations

from datetime import datetime
from enum import Enum
from typing import Optional

from sqlalchemy import DateTime, Integer, String, Text
from sqlalchemy.orm import Mapped, mapped_column

from app.database.session import Base
from app.models.base import TimestampMixin


class MediaState(str, Enum):
    """Lifecycle states advanced by the S3-event processor.

    * PENDING   - upload URL minted, object not yet observed by the processor.
    * UPLOADED  - S3 HEAD confirms the object exists; validation pending.
    * PROCESSING- bytes are being validated (magic bytes / content-type / size).
    * READY     - validated and attachable (attach_to_product/shop reads this).
    * FAILED    - quarantined (corrupt/impersonation/size mismatch) or missing.
    """

    PENDING = "PENDING"
    UPLOADED = "UPLOADED"
    PROCESSING = "PROCESSING"
    READY = "READY"
    FAILED = "FAILED"


class Media(Base, TimestampMixin):
    """One row per server-minted object key; state is advanced by the Lambda."""

    __tablename__ = "media"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)

    # Server-minted key shape: {prefix}/{scope}/{YYYY}/{MM}/{uuid8}_{name}.{ext}
    key: Mapped[str] = mapped_column(
        String(512), unique=True, nullable=False, index=True
    )

    # Category registry mirrors MEDIA_CATEGORIES in media_service
    # (PRODUCT_IMAGE | SHOP_IMAGE | DOCUMENT). Nullable so a bare HEAD still
    # creates a row before the intent metadata is known.
    category: Mapped[Optional[str]] = mapped_column(
        String(32), nullable=True, index=True
    )

    # "shop:<id>" | "user:<id>" -- used for authorization at attach time.
    scope: Mapped[Optional[str]] = mapped_column(
        String(64), nullable=True, index=True
    )

    shop_id: Mapped[Optional[int]] = mapped_column(
        Integer, nullable=True, index=True
    )
    user_id: Mapped[Optional[int]] = mapped_column(
        Integer, nullable=True, index=True
    )

    # Declared by the signed-upload intent; verified against the stored object.
    declared_size_bytes: Mapped[Optional[int]] = mapped_column(
        Integer, nullable=True
    )

    # Observed from the stored object's HEAD.
    content_type: Mapped[Optional[str]] = mapped_column(String(100), nullable=True)
    size_bytes: Mapped[Optional[int]] = mapped_column(Integer, nullable=True)

    state: Mapped[MediaState] = mapped_column(
        String(16),
        nullable=False,
        default=MediaState.PENDING,
        server_default="PENDING",
        index=True,
    )

    # When the Lambda finalized the row (READY or FAILED).
    processed_at: Mapped[Optional[datetime]] = mapped_column(
        DateTime(timezone=True), nullable=True
    )

    # Failure diagnostics (populated when state == FAILED).
    error_code: Mapped[Optional[str]] = mapped_column(String(64), nullable=True)
    error_message: Mapped[Optional[str]] = mapped_column(Text, nullable=True)

    # Where a corrupt/impersonating object was moved for forensic inspection.
    quarantine_key: Mapped[Optional[str]] = mapped_column(
        String(512), nullable=True
    )

    def __repr__(self) -> str:  # pragma: no cover - diagnostic only
        return (
            f"Media(id={self.id!r}, key={self.key!r}, state={self.state.value})"
        )
