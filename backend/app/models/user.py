"""User model with lifecycle/status and role relationship."""
from datetime import datetime
from sqlalchemy import String, DateTime, Boolean, ForeignKey, Enum, Text, Index
from sqlalchemy.orm import Mapped, mapped_column, relationship
import enum

from app.database.session import Base
from app.models.base import TimestampMixin, SoftDeleteMixin


class UserStatus(str, enum.Enum):
    ACTIVE = "ACTIVE"
    INACTIVE = "INACTIVE"
    SUSPENDED = "SUSPENDED"
    BANNED = "BANNED"
    PENDING_VERIFICATION = "PENDING_VERIFICATION"


class User(Base, TimestampMixin, SoftDeleteMixin):
    __tablename__ = "users"
    __table_args__ = (
        Index("ix_users_firebase_uid", "firebase_uid", unique=True),
    )

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    # Firebase UID — stable external identity identifier from Firebase Authentication.
    # This is the PRIMARY link between Firebase and the application user.
    # Phone number can change/recycle; firebase_uid is permanent.
    firebase_uid: Mapped[str | None] = mapped_column(String(128), unique=True, index=True, nullable=True)
    # Phone may be NULL for Google-only signups; OTP-registered users always have one.
    phone_number: Mapped[str | None] = mapped_column(String(20), unique=True, index=True, nullable=True)
    google_id: Mapped[str | None] = mapped_column(String(64), unique=True, index=True, nullable=True)
    name: Mapped[str | None] = mapped_column(String(120))
    email: Mapped[str | None] = mapped_column(String(255), index=True)
    avatar_url: Mapped[str | None] = mapped_column(String(500))
    password_hash: Mapped[str | None] = mapped_column(String(255))
    role_id: Mapped[int | None] = mapped_column(ForeignKey("roles.id"), index=True)
    status: Mapped[UserStatus] = mapped_column(
        Enum(UserStatus, name="user_status"), nullable=False, default=UserStatus.ACTIVE
    )
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)
    last_login_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    last_login_ip: Mapped[str | None] = mapped_column(String(45))
    device_tokens = relationship("DeviceToken", back_populates="user", cascade="all, delete-orphan")
    auth_sessions = relationship("AuthSession", back_populates="user", cascade="all, delete-orphan")
    saved_products = relationship("SavedProduct", back_populates="user", cascade="all, delete-orphan")
    saved_shops = relationship("SavedShop", back_populates="user", cascade="all, delete-orphan")
    notifications = relationship("Notification", back_populates="user", cascade="all, delete-orphan")
    search_history = relationship("SearchHistory", back_populates="user", cascade="all, delete-orphan")
    customer_profile = relationship("Customer", back_populates="user", uselist=False)
    role = relationship("Role", back_populates="users")
    addresses = relationship("CustomerAddress", back_populates="user", cascade="all, delete-orphan")
    notification_preferences = relationship("NotificationPreference", back_populates="user", uselist=False)
    subscription = relationship(
        "Subscription",
        back_populates="user",
        uselist=False,
        foreign_keys="Subscription.user_id",
    )
    interactions = relationship(
        "UserInteraction",
        back_populates="user",
        cascade="all, delete-orphan",
    )
    password_resets = relationship(
        "PasswordReset",
        back_populates="user",
        cascade="all, delete-orphan",
    )
