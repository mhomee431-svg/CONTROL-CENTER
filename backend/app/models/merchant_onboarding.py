"""Merchant Onboarding state machine model.

Tracks the onboarding progress for each business through the tiered verification system.
Separate from ShopStatus which tracks operational status.
"""
from datetime import datetime
from sqlalchemy import String, Integer, DateTime, Boolean, Text, ForeignKey, Enum, JSON
from sqlalchemy.orm import Mapped, mapped_column, relationship
import enum

from app.database.session import Base
from app.models.base import TimestampMixin


class OnboardingStatus(str, enum.Enum):
    """Merchant onboarding lifecycle states."""
    DRAFT = "DRAFT"
    PHONE_VERIFIED = "PHONE_VERIFIED"
    IDENTITY_PENDING = "IDENTITY_PENDING"
    IDENTITY_VERIFIED = "IDENTITY_VERIFIED"
    BANK_PENDING = "BANK_PENDING"
    BANK_VERIFIED = "BANK_VERIFIED"
    CATEGORY_DOCUMENTS_PENDING = "CATEGORY_DOCUMENTS_PENDING"
    CATEGORY_DOCUMENTS_VERIFIED = "CATEGORY_DOCUMENTS_VERIFIED"
    PENDING_ADMIN_REVIEW = "PENDING_ADMIN_REVIEW"
    VERIFIED = "VERIFIED"
    REJECTED = "REJECTED"
    SUSPENDED = "SUSPENDED"
    RESUBMISSION_REQUIRED = "RESUBMISSION_REQUIRED"


class MerchantOnboarding(Base, TimestampMixin):
    """Tracks onboarding state for a business.

    Each business (shop) has one onboarding record that tracks progress
    through the tiered verification system.
    """
    __tablename__ = "merchant_onboardings"

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    shop_id: Mapped[int] = mapped_column(
        ForeignKey("shops.id", ondelete="CASCADE"),
        unique=True,
        index=True,
        nullable=False,
    )
    user_id: Mapped[int] = mapped_column(
        ForeignKey("users.id"), index=True, nullable=False
    )
    category_code: Mapped[str] = mapped_column(String(50), nullable=False, index=True)

    # Onboarding state
    status: Mapped[OnboardingStatus] = mapped_column(
        Enum(OnboardingStatus, name="onboarding_status"),
        nullable=False,
        default=OnboardingStatus.DRAFT,
    )

    # Verification step statuses (denormalized for quick queries)
    phone_verified: Mapped[bool] = mapped_column(
        Boolean, nullable=False, default=False, server_default="false"
    )
    phone_verified_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    identity_verified: Mapped[bool] = mapped_column(
        Boolean, nullable=False, default=False, server_default="false"
    )
    identity_verified_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    bank_verified: Mapped[bool] = mapped_column(
        Boolean, nullable=False, default=False, server_default="false"
    )
    bank_verified_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    category_verified: Mapped[bool] = mapped_column(
        Boolean, nullable=False, default=False, server_default="false"
    )
    category_verified_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))

    # Category-specific details (JSON: drug_license_no, fssai_license_no, etc.)
    category_details: Mapped[dict | None] = mapped_column(JSON)

    # Admin review
    admin_reviewed: Mapped[bool] = mapped_column(
        Boolean, nullable=False, default=False, server_default="false"
    )
    admin_reviewed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    admin_reviewed_by: Mapped[int | None] = mapped_column(ForeignKey("users.id"))
    admin_review_notes: Mapped[str | None] = mapped_column(Text)
    rejection_reason: Mapped[str | None] = mapped_column(Text)
    rejection_code: Mapped[str | None] = mapped_column(String(50))

    # Next action hint for frontend
    next_action: Mapped[str | None] = mapped_column(String(100))

    # Idempotency key for duplicate prevention
    idempotency_key: Mapped[str | None] = mapped_column(String(100), unique=True, index=True)

    # Relationships
    shop = relationship("Shop", back_populates="onboarding")
    identity_verifications = relationship(
        "BusinessIdentityVerification",
        back_populates="onboarding",
        cascade="all, delete-orphan",
    )
    bank_verifications = relationship(
        "BankAccountVerification",
        back_populates="onboarding",
        cascade="all, delete-orphan",
    )
    category_verifications = relationship(
        "CategoryDocumentVerification",
        back_populates="onboarding",
        cascade="all, delete-orphan",
    )
    verification_attempts = relationship(
        "VerificationAttempt",
        back_populates="onboarding",
        cascade="all, delete-orphan",
    )


# Valid state transitions for the onboarding state machine
VALID_ONBOARDING_TRANSITIONS: dict[OnboardingStatus, list[OnboardingStatus]] = {
    OnboardingStatus.DRAFT: [
        OnboardingStatus.PHONE_VERIFIED,
        OnboardingStatus.REJECTED,
    ],
    OnboardingStatus.PHONE_VERIFIED: [
        OnboardingStatus.IDENTITY_PENDING,
        OnboardingStatus.REJECTED,
    ],
    OnboardingStatus.IDENTITY_PENDING: [
        OnboardingStatus.IDENTITY_VERIFIED,
        OnboardingStatus.REJECTED,
        OnboardingStatus.RESUBMISSION_REQUIRED,
    ],
    OnboardingStatus.IDENTITY_VERIFIED: [
        OnboardingStatus.BANK_PENDING,
        OnboardingStatus.REJECTED,
    ],
    OnboardingStatus.BANK_PENDING: [
        OnboardingStatus.BANK_VERIFIED,
        OnboardingStatus.REJECTED,
        OnboardingStatus.RESUBMISSION_REQUIRED,
    ],
    OnboardingStatus.BANK_VERIFIED: [
        OnboardingStatus.CATEGORY_DOCUMENTS_PENDING,
        OnboardingStatus.REJECTED,
    ],
    OnboardingStatus.CATEGORY_DOCUMENTS_PENDING: [
        OnboardingStatus.CATEGORY_DOCUMENTS_VERIFIED,
        OnboardingStatus.PENDING_ADMIN_REVIEW,
        OnboardingStatus.REJECTED,
        OnboardingStatus.RESUBMISSION_REQUIRED,
    ],
    OnboardingStatus.CATEGORY_DOCUMENTS_VERIFIED: [
        OnboardingStatus.PENDING_ADMIN_REVIEW,
        OnboardingStatus.VERIFIED,
        OnboardingStatus.REJECTED,
    ],
    OnboardingStatus.PENDING_ADMIN_REVIEW: [
        OnboardingStatus.VERIFIED,
        OnboardingStatus.REJECTED,
        OnboardingStatus.RESUBMISSION_REQUIRED,
    ],
    OnboardingStatus.VERIFIED: [
        OnboardingStatus.SUSPENDED,
    ],
    OnboardingStatus.REJECTED: [
        OnboardingStatus.DRAFT,
        OnboardingStatus.RESUBMISSION_REQUIRED,
    ],
    OnboardingStatus.RESUBMISSION_REQUIRED: [
        OnboardingStatus.DRAFT,
        OnboardingStatus.IDENTITY_PENDING,
        OnboardingStatus.BANK_PENDING,
        OnboardingStatus.CATEGORY_DOCUMENTS_PENDING,
        OnboardingStatus.PENDING_ADMIN_REVIEW,
    ],
    OnboardingStatus.SUSPENDED: [
        OnboardingStatus.VERIFIED,
        OnboardingStatus.REJECTED,
    ],
}
