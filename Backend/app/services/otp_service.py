"""Production-grade OTP service with expiry, retry limits, resend limits, and cooldowns."""
import hashlib
import hmac
import secrets
from datetime import datetime, timedelta, timezone

from app.core.config import settings
from app.core.logging import get_logger

logger = get_logger("app.services.otp")

# ─────────────────────────────────────────────────────────────────────────────
# Storage — In-memory store for development/single-instance.
# Phase 17+ can swap this with Redis for distributed/expiring storage.
# ─────────────────────────────────────────────────────────────────────────────
_otp_store: dict[str, dict] = {}


def _hash_otp(otp: str, salt: str) -> str:
    """Hash the OTP with a random salt (never store raw OTP)."""
    return hmac.new(
        salt.encode(),
        otp.encode(),
        hashlib.sha256,
    ).hexdigest()


def _generate_otp_code() -> str:
    """Generate a cryptographically-secure numeric OTP."""
    if settings.OTP_DEV_MODE:
        return settings.OTP_DEV_VALUE
    length = settings.OTP_LENGTH
    return "".join(str(secrets.randbelow(10)) for _ in range(length))


def _ensure_phone_normalized(phone_number: str) -> str:
    """Normalize phone number to E.164-ish format (strip spaces, ensure +)."""
    phone = phone_number.strip()
    if not phone.startswith("+"):
        phone = "+" + phone
    return phone


def generate_otp(phone_number: str) -> dict:
    """Generate and store an OTP for the phone number.

    Returns a dict with:
      - otp:        the raw OTP (only returned in dev mode)
      - expires_in: seconds until expiry
    """
    phone = _ensure_phone_normalized(phone_number)
    now = datetime.now(timezone.utc)
    existing = _otp_store.get(phone)

    # Enforce resend limits
    if existing:
        if existing["resend_count"] >= settings.OTP_MAX_RESENDS:
            raise OTPLimitExceeded(
                f"OTP resend limit reached. Try again later.",
                resend_after_seconds=None,
            )
        # Enforce resend cooldown
        if existing.get("last_resend_at"):
            elapsed = (now - existing["last_resend_at"]).total_seconds()
            cooldown = settings.OTP_RESEND_COOLDOWN_SECONDS
            if elapsed < cooldown:
                raise OTPCooldownError(
                    f"Please wait before requesting another OTP.",
                    retry_after_seconds=int(cooldown - elapsed),
                )

    # Generate new OTP
    otp = _generate_otp_code()
    salt = secrets.token_hex(16)
    otp_hash = _hash_otp(otp, salt)

    expires_at = now + timedelta(minutes=settings.OTP_EXPIRE_MINUTES)

    _otp_store[phone] = {
        "otp_hash": otp_hash,
        "salt": salt,
        "expires_at": expires_at,
        "attempts": 0,
        "resend_count": (existing["resend_count"] + 1) if existing else 1,
        "last_resend_at": now,
        "created_at": now,
    }

    logger.info("OTP generated for %s (expires in %s minutes)", phone, settings.OTP_EXPIRE_MINUTES)

    result: dict = {
        "expires_in": settings.OTP_EXPIRE_MINUTES * 60,
    }
    if settings.OTP_DEV_MODE:
        result["dev_otp"] = otp

    return result


def verify_otp(phone_number: str, otp: str) -> bool:
    """Verify an OTP for the phone number and invalidate it on success.

    Handles:
      - Expired OTP
      - Max attempts
      - Correct / incorrect OTP
    """
    phone = _ensure_phone_normalized(phone_number)
    record = _otp_store.get(phone)
    if record is None:
        return False

    now = datetime.now(timezone.utc)

    # Expiry check
    if now > record["expires_at"]:
        _otp_store.pop(phone, None)
        logger.info("OTP expired for %s", phone)
        return False

    # Max attempts check
    if record["attempts"] >= settings.OTP_MAX_ATTEMPTS:
        _otp_store.pop(phone, None)  # Invalidate OTP after too many attempts
        logger.warning("OTP max attempts exceeded for %s", phone)
        return False

    # Verify using constant-time comparison
    expected_hash = record["otp_hash"]
    salt = record["salt"]
    actual_hash = _hash_otp(otp, salt)
    is_valid = hmac.compare_digest(actual_hash, expected_hash)

    if is_valid:
        _otp_store.pop(phone, None)  # Single-use
        logger.info("OTP verified for %s", phone)
        return True

    record["attempts"] += 1
    logger.warning("Invalid OTP attempt for %s (attempt %d)", phone, record["attempts"])
    return False


def resend_otp(phone_number: str) -> dict:
    """Alias for generate_otp — used by endpoints to differentiate paths."""
    return generate_otp(phone_number)


def remaining_attempts(phone_number: str) -> int:
    """Return how many attempts remain for a phone number."""
    phone = _ensure_phone_normalized(phone_number)
    record = _otp_store.get(phone)
    if record is None:
        return 0
    return max(0, settings.OTP_MAX_ATTEMPTS - record["attempts"])


def clear_otp(phone_number: str) -> None:
    """Force-invalidate an OTP (used on logout / account actions)."""
    phone = _ensure_phone_normalized(phone_number)
    _otp_store.pop(phone, None)


class OTPError(Exception):
    """Base OTP error."""
    def __init__(self, message: str):
        super().__init__(message)
        self.message = message


class OTPCooldownError(OTPError):
    """Raised when the user must wait before requesting a new OTP."""
    def __init__(self, message: str, retry_after_seconds: int):
        super().__init__(message)
        self.retry_after_seconds = retry_after_seconds


class OTPLimitExceeded(OTPError):
    """Raised when the user has exceeded the resend limit."""
    def __init__(self, message: str, resend_after_seconds: int | None):
        super().__init__(message)
        self.resend_after_seconds = resend_after_seconds
