"""Password reset tokens (salted HMAC digest, single-use, expiring)."""

from datetime import datetime

from sqlalchemy import Boolean, DateTime, ForeignKey, Index, String
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database.session import Base
from app.models.base import TimestampMixin


class PasswordReset(Base, TimestampMixin):
    """A single-use password reset token keyed to a user.

    Security: ``token_hash`` stores a salted HMAC-SHA256 digest of the raw
    reset token — never the raw token. ``is_used`` prevents replay; ``expires_at``
    bounds the validity window (mirrors the app's password reset TTL).
    """

    __tablename__ = "password_resets"
    __table_args__ = (
        Index("ix_password_resets_user_active", "user_id", "is_used"),
    )

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    user_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True, nullable=False
    )
    token_hash: Mapped[str] = mapped_column(
        String(128), unique=True, index=True, nullable=False
    )
    expires_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, index=True
    )
    is_used: Mapped[bool] = mapped_column(
        Boolean, nullable=False, default=False, server_default="false"
    )
    used_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    used_ip: Mapped[str | None] = mapped_column(String(45))

    user = relationship("User", back_populates="password_resets")