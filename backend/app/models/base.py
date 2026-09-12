"""Base model with common fields for all entities."""
from datetime import datetime
from sqlalchemy import DateTime, Boolean, Integer
from sqlalchemy.orm import Mapped, mapped_column

from app.database.session import Base


class TimestampMixin:
    """Mixin providing created_at and updated_at timestamps."""
    # Python-side default so a real datetime object is always supplied on
    # insert/update — required by SQLite's DateTime dialect (server_default
    # 'now()' is a Postgres-only literal there). Works on Postgres too.
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, default=datetime.now, server_default="now()"
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, default=datetime.now, server_default="now()", onupdate=datetime.now
    )


class SoftDeleteMixin:
    """Mixin providing soft-delete fields."""
    is_deleted: Mapped[bool] = mapped_column(
        Boolean, nullable=False, server_default="false"
    )
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)


class AuditMixin:
    """Mixin providing audit fields."""
    created_by: Mapped[int | None] = mapped_column(Integer, nullable=True)
    updated_by: Mapped[int | None] = mapped_column(Integer, nullable=True)