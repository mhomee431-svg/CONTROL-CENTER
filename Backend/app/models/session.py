"""Session and refresh-token models for device/session tracking and revocation."""
from datetime import datetime
from sqlalchemy import String, DateTime, Boolean, ForeignKey, Integer, Text, Index
from sqlalchemy.orm import Mapped, mapped_column, relationship
import uuid

from app.database.session import Base
from app.models.base import TimestampMixin


class AuthSession(Base, TimestampMixin):
    """Persistent login session associated with a user and device."""
    __tablename__ = "auth_sessions"
    __table_args__ = (
        Index("ix_auth_sessions_user_active", "user_id", "is_active"),
        Index("ix_auth_sessions_refresh_token", "refresh_token_hash"),
    )

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    session_id: Mapped[str] = mapped_column(
        String(36), unique=True, nullable=False, default=lambda: str(uuid.uuid4())
    )
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id"), index=True, nullable=False)

    # Device identity
    device_id: Mapped[str | None] = mapped_column(String(255), index=True)
    device_name: Mapped[str | None] = mapped_column(String(255))
    device_type: Mapped[str | None] = mapped_column(String(50))  # android, ios, web
    platform: Mapped[str | None] = mapped_column(String(50))  # os version
    app_version: Mapped[str | None] = mapped_column(String(20))
    ip_address: Mapped[str | None] = mapped_column(String(45))
    user_agent: Mapped[str | None] = mapped_column(String(500))

    # Refresh token (hashed — raw token never stored)
    refresh_token_hash: Mapped[str | None] = mapped_column(String(128))
    refresh_token_expires_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    refresh_token_revoked_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    refresh_token_used_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    refresh_rotation_count: Mapped[int] = mapped_column(Integer, default=0)

    # JWT identifiers for revocation
    access_jti: Mapped[str | None] = mapped_column(String(36), index=True)
    refresh_jti: Mapped[str | None] = mapped_column(String(36), index=True)

    # Session lifecycle
    is_active: Mapped[bool] = mapped_column(Boolean, default=True, index=True)
    is_revoked: Mapped[bool] = mapped_column(Boolean, default=False)
    last_activity_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), index=True)
    expires_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    revoked_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    revoked_reason: Mapped[str | None] = mapped_column(String(100))  # logout, expiry, admin, security
    revoked_by: Mapped[str | None] = mapped_column(String(50))  # user, admin, system

    # Reuse detection (refresh token replay)
    previous_refresh_token_hash: Mapped[str | None] = mapped_column(String(128))
    reuse_detected: Mapped[bool] = mapped_column(Boolean, default=False)

    user = relationship("User", back_populates="auth_sessions")


class TokenBlacklist(Base, TimestampMixin):
    """Revoked JWT tokens (access/refresh) for stateless-token revocation."""
    __tablename__ = "token_blacklist"

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    jti: Mapped[str] = mapped_column(String(36), unique=True, nullable=False, index=True)
    token_type: Mapped[str] = mapped_column(String(20), nullable=False)  # access, refresh
    user_id: Mapped[int | None] = mapped_column(ForeignKey("users.id"), index=True)
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    revoked_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    reason: Mapped[str | None] = mapped_column(String(100))