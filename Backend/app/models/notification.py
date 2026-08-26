"""Notification, NotificationPreference, DeviceToken, NotificationDelivery models."""
from datetime import datetime
from sqlalchemy import String, Boolean, DateTime, ForeignKey, Text, UniqueConstraint, Index
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database.session import Base
from app.models.base import TimestampMixin


class Notification(Base, TimestampMixin):
    __tablename__ = "notifications"
    __table_args__ = (
        Index("ix_notifications_user_read", "user_id", "is_read"),
        Index("ix_notifications_dedupe", "user_id", "dedupe_key"),
    )

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id"), index=True, nullable=False)
    title: Mapped[str] = mapped_column(String(255), nullable=False)
    body: Mapped[str] = mapped_column(Text, nullable=False)
    type: Mapped[str] = mapped_column(String(50), default="system")  # order_update, price_alert, promotional, system
    # Phase 27 — typed architecture
    audience: Mapped[str | None] = mapped_column(String(20))  # customer, shopkeeper, admin
    deep_link: Mapped[str | None] = mapped_column(String(500))  # app route to open on tap
    dedupe_key: Mapped[str | None] = mapped_column(String(255))  # anti-spam identity within cooldown
    delivery_status: Mapped[str] = mapped_column(String(20), default="PENDING")  # PENDING, SENT, PARTIAL, FAILED, SKIPPED
    delivery_attempts: Mapped[int] = mapped_column(default=0)
    last_attempt_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    provider_message_id: Mapped[str | None] = mapped_column(String(255))
    last_error: Mapped[str | None] = mapped_column(Text)
    is_read: Mapped[bool] = mapped_column(Boolean, default=False)
    payload: Mapped[str | None] = mapped_column(Text)  # JSON data
    read_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    sent_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))

    user = relationship("User", back_populates="notifications")
    deliveries = relationship(
        "NotificationDelivery", back_populates="notification", cascade="all, delete-orphan"
    )


class NotificationPreference(Base, TimestampMixin):
    __tablename__ = "notification_preferences"
    __table_args__ = (
        UniqueConstraint("user_id", name="uq_notification_pref_user"),
    )

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id"), index=True, nullable=False)
    push_enabled: Mapped[bool] = mapped_column(Boolean, default=True)
    email_enabled: Mapped[bool] = mapped_column(Boolean, default=True)
    sms_enabled: Mapped[bool] = mapped_column(Boolean, default=False)
    price_alerts: Mapped[bool] = mapped_column(Boolean, default=True)
    availability_alerts: Mapped[bool] = mapped_column(Boolean, default=True)
    promotional: Mapped[bool] = mapped_column(Boolean, default=False)
    deal_alerts: Mapped[bool] = mapped_column(Boolean, default=True)

    user = relationship("User", back_populates="notification_preferences")


class DeviceToken(Base, TimestampMixin):
    __tablename__ = "device_tokens"
    __table_args__ = (
        UniqueConstraint("token", name="uq_device_tokens_token"),
    )

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id"), index=True, nullable=False)
    token: Mapped[str] = mapped_column(String(500), nullable=False, index=True)
    device_type: Mapped[str] = mapped_column(String(20), nullable=False, default="android")  # android, ios, web
    platform: Mapped[str | None] = mapped_column(String(50))  # FCM, APNS
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)
    failure_count: Mapped[int] = mapped_column(default=0)
    last_used_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    expires_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    app_version: Mapped[str | None] = mapped_column(String(20))

    user = relationship("User", back_populates="device_tokens")


class NotificationDelivery(Base, TimestampMixin):
    """Per-device delivery attempt history for a notification.

    One row per (notification, device token). Records every provider attempt
    (including retries) so delivery status can be surfaced wherever the
    provider supports it.
    """

    __tablename__ = "notification_deliveries"
    __table_args__ = (
        UniqueConstraint("notification_id", "device_token_id", name="uq_notif_delivery_notif_token"),
        Index("ix_notif_delivery_status", "status"),
    )

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    notification_id: Mapped[int] = mapped_column(ForeignKey("notifications.id"), index=True, nullable=False)
    device_token_id: Mapped[int] = mapped_column(ForeignKey("device_tokens.id"), index=True, nullable=False)
    status: Mapped[str] = mapped_column(String(20), default="PENDING")  # PENDING, SENT, FAILED, SKIPPED
    attempts: Mapped[int] = mapped_column(default=0)
    provider_message_id: Mapped[str | None] = mapped_column(String(255))
    error: Mapped[str | None] = mapped_column(Text)
    permanent_failure: Mapped[bool] = mapped_column(Boolean, default=False)
    attempted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    delivered_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))

    notification = relationship("Notification", back_populates="deliveries")
    device_token = relationship("DeviceToken")