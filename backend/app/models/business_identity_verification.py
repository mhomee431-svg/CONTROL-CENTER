"""Business Identity Verification model.

Stores GSTIN/UDYAM verification records for merchant onboarding.
Sensitive data is never stored in raw form.
"""
from datetime import datetime
from sqlalchemy import String, Integer, DateTime, Boolean, Text, ForeignKey, Enum, JSON
from sqlalchemy.orm import Mapped, mapped_column, relationship
import enum

from app.database.session import Base
from app.models.base import TimestampMixin


class IdentityVerificationType(str, enum.Enum):
    """Type of business identity document."""
    GSTIN = "GSTIN"
    UDYAM = "UDYAM"


class IdentityVerificationStatus(str, enum.Enum):
    """Status of identity verification."""
    PENDING = "PENDING"
    VERIFIED = "VERIFIED"
    FAILED = "FAILED"
    REJECTED = "REJECTED"
    UNABLE_TO_VERIFY = "UNABLE_TO_VERIFY"


class BusinessIdentityVerification(Base, TimestampMixin):
    """GSTIN/UDYAM verification record.

    Stores verification results from identity providers.
    Never stores full sensitive identifiers in logs.
    """
    __tablename__ = "business_identity_verifications"

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    onboarding_id: Mapped[int] = mapped_column(
        ForeignKey("merchant_onboardings.id", ondelete="CASCADE"),
        index=True,
        nullable=False,
    )
    verification_type: Mapped[IdentityVerificationType] = mapped_column(
        Enum(IdentityVerificationType, name="identity_verification_type"),
        nullable=False,
    )

    # Identifier (masked in responses, stored encrypted at rest)
    identifier_hash: Mapped[str | None] = mapped_column(String(128), index=True)
    identifier_last_four: Mapped[str | None] = mapped_column(String(10))

    # Verification result
    status: Mapped[IdentityVerificationStatus] = mapped_column(
        Enum(IdentityVerificationStatus, name="identity_verification_status"),
        nullable=False,
        default=IdentityVerificationStatus.PENDING,
    )
    provider: Mapped[str | None] = mapped_column(String(50))
    provider_reference_id: Mapped[str | None] = mapped_column(String(200), index=True)
    verified_name: Mapped[str | None] = mapped_column(String(255))
    verified_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    failure_reason: Mapped[str | None] = mapped_column(Text)
    failure_code: Mapped[str | None] = mapped_column(String(50))

    # Metadata (non-sensitive provider response metadata)
    provider_metadata: Mapped[dict | None] = mapped_column(JSON)

    # Attempt tracking
    attempt_number: Mapped[int] = mapped_column(Integer, default=1, server_default="1")
    is_latest_attempt: Mapped[bool] = mapped_column(
        Boolean, nullable=False, default=True, server_default="true"
    )

    # Relationships
    onboarding = relationship("MerchantOnboarding", back_populates="identity_verifications")


class BankAccountVerification(Base, TimestampMixin):
    """Bank account penny-drop verification record.

    Stores bank verification results. Account number is NEVER stored in full.
    Only last 4 digits and a hash are kept for deduplication.
    """
    __tablename__ = "bank_account_verifications"

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    onboarding_id: Mapped[int] = mapped_column(
        ForeignKey("merchant_onboardings.id", ondelete="CASCADE"),
        index=True,
        nullable=False,
    )

    # Bank details (NEVER store full account number)
    account_number_hash: Mapped[str | None] = mapped_column(String(128), index=True)
    account_number_last_four: Mapped[str | None] = mapped_column(String(10))
    ifsc_code: Mapped[str | None] = mapped_column(String(20))
    account_holder_name: Mapped[str | None] = mapped_column(String(255))
    bank_name: Mapped[str | None] = mapped_column(String(255))

    # Verification result
    status: Mapped[str] = mapped_column(String(30), nullable=False, default="PENDING")
    provider: Mapped[str | None] = mapped_column(String(50))
    provider_reference_id: Mapped[str | None] = mapped_column(String(200), index=True)
    verified_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    failure_reason: Mapped[str | None] = mapped_column(Text)
    failure_code: Mapped[str | None] = mapped_column(String(50))

    # Penny-drop specific
    penny_drop_amount: Mapped[float | None] = mapped_column()
    penny_drop_status: Mapped[str | None] = mapped_column(String(30))

    # Metadata
    provider_metadata: Mapped[dict | None] = mapped_column(JSON)

    # Attempt tracking
    attempt_number: Mapped[int] = mapped_column(Integer, default=1, server_default="1")
    is_latest_attempt: Mapped[bool] = mapped_column(
        Boolean, nullable=False, default=True, server_default="true"
    )

    # Relationships
    onboarding = relationship("MerchantOnboarding", back_populates="bank_verifications")


class CategoryDocumentVerification(Base, TimestampMixin):
    """Category-specific document verification record.

    For pharmacy (drug_license_no), restaurant (fssai_license_no),
    transport (driving_license_no, vehicle_rc_no), etc.
    """
    __tablename__ = "category_document_verifications"

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    onboarding_id: Mapped[int] = mapped_column(
        ForeignKey("merchant_onboardings.id", ondelete="CASCADE"),
        index=True,
        nullable=False,
    )

    # Document details
    document_type: Mapped[str] = mapped_column(String(50), nullable=False)
    document_number_hash: Mapped[str | None] = mapped_column(String(128), index=True)
    document_number_last_four: Mapped[str | None] = mapped_column(String(10))
    document_url: Mapped[str | None] = mapped_column(String(500))

    # Verification result
    status: Mapped[str] = mapped_column(String(30), nullable=False, default="PENDING")
    provider: Mapped[str | None] = mapped_column(String(50))
    provider_reference_id: Mapped[str | None] = mapped_column(String(200), index=True)
    verified_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    failure_reason: Mapped[str | None] = mapped_column(Text)
    failure_code: Mapped[str | None] = mapped_column(String(50))

    # Admin review
    requires_admin_review: Mapped[bool] = mapped_column(
        Boolean, nullable=False, default=True, server_default="true"
    )
    admin_reviewed: Mapped[bool] = mapped_column(
        Boolean, nullable=False, default=False, server_default="false"
    )
    admin_reviewed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    admin_reviewed_by: Mapped[int | None] = mapped_column(ForeignKey("users.id"))
    admin_review_notes: Mapped[str | None] = mapped_column(Text)

    # Metadata
    provider_metadata: Mapped[dict | None] = mapped_column(JSON)
    expiry_date: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))

    # Attempt tracking
    attempt_number: Mapped[int] = mapped_column(Integer, default=1, server_default="1")
    is_latest_attempt: Mapped[bool] = mapped_column(
        Boolean, nullable=False, default=True, server_default="true"
    )

    # Relationships
    onboarding = relationship("MerchantOnboarding", back_populates="category_verifications")
