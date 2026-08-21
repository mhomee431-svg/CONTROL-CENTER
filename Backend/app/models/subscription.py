"""Subscription, SubscriptionPlan, Payment models."""
from datetime import datetime
from sqlalchemy import String, Integer, DateTime, Boolean, ForeignKey, Float, Text, Enum, JSON, Index
from sqlalchemy.orm import Mapped, mapped_column, relationship
import enum

from app.database.session import Base
from app.models.base import TimestampMixin


class SubscriptionStatus(str, enum.Enum):
    ACTIVE = "ACTIVE"
    PAST_DUE = "PAST_DUE"
    CANCELED = "CANCELED"
    TRIALING = "TRIALING"
    INCOMPLETE = "INCOMPLETE"


class BillingCycle(str, enum.Enum):
    WEEKLY = "WEEKLY"
    MONTHLY = "MONTHLY"
    QUARTERLY = "QUARTERLY"
    ANNUAL = "ANNUAL"


class Subscription(Base, TimestampMixin):
    __tablename__ = "subscriptions"

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id"), index=True, nullable=False)
    shop_id: Mapped[int | None] = mapped_column(ForeignKey("shops.id"), index=True)  # null if user-level
    plan_id: Mapped[int] = mapped_column(ForeignKey("subscription_plans.id"), index=True, nullable=False)
    status: Mapped[SubscriptionStatus] = mapped_column(
        Enum(SubscriptionStatus, name="subscription_status"), nullable=False, default=SubscriptionStatus.ACTIVE
    )
    is_auto_renew: Mapped[bool] = mapped_column(Boolean, default=True)
    current_period_start: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    current_period_end: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    cancel_at_period_end: Mapped[bool] = mapped_column(Boolean, default=False)
    trial_ends_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    created_by: Mapped[int | None] = mapped_column(ForeignKey("users.id"))

    user = relationship("User", back_populates="subscription", foreign_keys=[user_id])
    shop = relationship("Shop", back_populates="subscription")
    plan = relationship("SubscriptionPlan", back_populates="subscriptions")
    payments = relationship("Payment", back_populates="subscription", cascade="all, delete-orphan")


class SubscriptionPlan(Base, TimestampMixin):
    __tablename__ = "subscription_plans"

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    name: Mapped[str] = mapped_column(String(100), nullable=False, unique=True, index=True)
    description: Mapped[str | None] = mapped_column(Text)
    price_monthly: Mapped[float] = mapped_column(Float, nullable=False)
    price_annual: Mapped[float] = mapped_column(Float, nullable=False)
    currency: Mapped[str] = mapped_column(String(10), nullable=False, default="INR")
    billing_cycle: Mapped[BillingCycle] = mapped_column(
        Enum(BillingCycle, name="billing_cycle"), nullable=False, default=BillingCycle.MONTHLY
    )
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)
    features_json: Mapped[dict | None] = mapped_column(JSON)  # {"unlimited_scans": 100, "offline_mode": True}
    max_shops: Mapped[int | None] = mapped_column(Integer)
    max_products: Mapped[int | None] = mapped_column(Integer)
    trial_days: Mapped[int] = mapped_column(Integer, default=0)
    sort_order: Mapped[int] = mapped_column(Integer, default=0)

    subscriptions = relationship("Subscription", back_populates="plan")


class Payment(Base, TimestampMixin):
    __tablename__ = "payments"

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    subscription_id: Mapped[int] = mapped_column(ForeignKey("subscriptions.id"), index=True, nullable=False)
    payment_provider: Mapped[str] = mapped_column(String(100), nullable=False)  # RAZORPAY, CASHFREE, STRIPE
    transaction_id: Mapped[str | None] = mapped_column(String(255), unique=True, index=True)
    amount: Mapped[float] = mapped_column(Float, nullable=False)
    currency: Mapped[str] = mapped_column(String(10), nullable=False, default="INR")
    status: Mapped[str] = mapped_column(String(20), nullable=False, default="PENDING")  # PENDING, SUCCESS, FAILED, REFUNDED
    payment_method: Mapped[str] = mapped_column(String(50), nullable=False)  # CARD, UPI, NETBANKING, WALLET
    paid_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    refunded_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    failure_reason: Mapped[str | None] = mapped_column(Text)
    payment_metadata: Mapped[dict | None] = mapped_column(JSON)

    subscription = relationship("Subscription", back_populates="payments")