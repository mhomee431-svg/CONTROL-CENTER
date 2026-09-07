"""OTP model for the Fast2SMS single-use phone verification flow.

OTPs are created on ``POST /api/v1/auth/send-otp``, delivered via the
Fast2SMS ``otp`` route (or printed to the console in ``OTP_MODE=mock``),
and single-use: ``verify-otp`` flips ``is_verified`` to True immediately
after a successful match so the same code can never be reused. Codes live
for 5 minutes (``expires_at``).

Security: the stored ``otp_code`` is a salted HMAC-SHA256 digest of the
raw code (see :mod:`app.services.fast2sms_otp_service`) — never a raw OTP.
"""
from datetime import datetime

from sqlalchemy import Boolean, DateTime, String
from sqlalchemy.orm import Mapped, mapped_column

from app.database.session import Base
from app.models.base import TimestampMixin

# Codes are valid for 5 minutes (mirrors OTP_EXPIRE_MINUTES; kept explicit so
# the schema stays self-describing even if app config changes later).
OTP_EXPIRY_MINUTES = 5


class Otp(Base, TimestampMixin):
    """A single-use, expiring OTP record keyed by phone number."""

    __tablename__ = "otps"

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    phone_number: Mapped[str] = mapped_column(
        String(20), index=True, nullable=False, unique=False
    )
    # Salted HMAC-SHA256 digest of the raw code (raw OTP is never persisted).
    otp_code: Mapped[str] = mapped_column(String(128), nullable=False)
    expires_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, index=True
    )
    is_verified: Mapped[bool] = mapped_column(
        Boolean, nullable=False, default=False, server_default="false"
    )