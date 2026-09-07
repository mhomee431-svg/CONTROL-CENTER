"""Verification Attempt and Provider Log models.

Audit trail for every verification attempt and provider interaction.
Immutable records for compliance.
"""
from datetime import datetime
from sqlalchemy import String, Integer, DateTime, Boolean, Text, ForeignKey, Enum, JSON
from sqlalchemy.orm import Mapped, mapped_column, relationship
import enum

from app.database.session import Base
from app.models.base import TimestampMixin


class VerificationAttemptType(str, enum.Enum):
    """Type of verification attempt."""
    PHONE_OTP = "PHONE_OTP"
    GSTIN_VERIFY = "GSTIN_VERIFY"
    UDYAM_VERIFY = "UDYAM_VERIFY"
    BANK_PENNY_DROP = "BANK_PENNY_DROP"
    DRUG_LICENSE_VERIFY = "DRUG_LICENSE_VERIFY"
    FSSAI_LICENSE_VERIFY = "FSSAI_LICENSE_VERIFY"
    DRIVING_LICENSE_VERIFY = "DRIVING_LICENSE_VERIFY"
    VEHICLE_RC_VERIFY = "VEHICLE_RC_VERIFY"


class VerificationAttemptStatus(str, enum.Enum):
    """Status of a verification attempt."""
    INITIATED = "INITIATED"
    IN_PROGRESS = "IN_PROGRESS"
    SUCCESS = "SUCCESS"
    FAILED = "FAILED"
    TIMEOUT = "TIMEOUT"
    ERROR = "ERROR"


class VerificationAttempt(Base, TimestampMixin):
    """Immutable audit record for each verification attempt."""
    __tablename__ = "verification_attempts"

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    onboarding_id: Mapped[int] = mapped_column(
        ForeignKey("merchant_onboardings.id", ondelete="CASCADE"),
        index=True, nullable=False,
    )
    attempt_type: Mapped[VerificationAttemptType] = mapped_column(
        Enum(VerificationAttemptType, name="verification_attempt_type"), nullable=False,
    )
    status: Mapped[VerificationAttemptStatus] = mapped_column(
        Enum(VerificationAttemptStatus, name="verification_attempt_status"),
        nullable=False, default=VerificationAttemptStatus.INITIATED,
    )
    request_id: Mapped[str | None] = mapped_column(String(100), index=True)
    idempotency_key: Mapped[str | None] = mapped_column(String(100), index=True)
    started_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    completed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    duration_ms: Mapped[int | None] = mapped_column(Integer)
    error_message: Mapped[str | None] = mapped_column(Text)
    error_code: Mapped[str | None] = mapped_column(String(50))
    provider_code: Mapped[str | None] = mapped_column(String(50))
    provider_reference_id: Mapped[str | None] = mapped_column(String(200))
    attempt_number: Mapped[int] = mapped_column(Integer, default=1, server_default="1")
    is_latest_attempt: Mapped[bool] = mapped_column(
        Boolean, nullable=False, default=True, server_default="true"
    )
    extra_data: Mapped[dict | None] = mapped_column(JSON)
    onboarding = relationship("MerchantOnboarding", back_populates="verification_attempts")


class VerificationProviderLog(Base, TimestampMixin):
    """Provider interaction log."""
    __tablename__ = "verification_provider_logs"

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    attempt_id: Mapped[int | None] = mapped_column(
        ForeignKey("verification_attempts.id", ondelete="SET NULL"), index=True,
    )
    onboarding_id: Mapped[int | None] = mapped_column(
        ForeignKey("merchant_onboardings.id", ondelete="SET NULL"), index=True,
    )
    provider_code: Mapped[str] = mapped_column(String(50), nullable=False, index=True)
    provider_environment: Mapped[str] = mapped_column(String(20), nullable=False, default="sandbox")
    request_method: Mapped[str | None] = mapped_column(String(10))
    request_url: Mapped[str | None] = mapped_column(String(500))
    request_headers: Mapped[dict | None] = mapped_column(JSON)
    request_body_reference: Mapped[str | None] = mapped_column(String(200))
    response_status_code: Mapped[int | None] = mapped_column(Integer)
    response_body_reference: Mapped[str | None] = mapped_column(String(200))
    response_time_ms: Mapped[int | None] = mapped_column(Integer)
    is_error: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False, server_default="false")
    error_type: Mapped[str | None] = mapped_column(String(50))
    error_message: Mapped[str | None] = mapped_column(Text)
    provider_reference_id: Mapped[str | None] = mapped_column(String(200), index=True)
    extra_data: Mapped[dict | None] = mapped_column(JSON)
