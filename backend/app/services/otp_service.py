"""Production-grade OTP service with expiry, retry limits, resend limits, and cooldowns."""
import hashlib
import hmac
import secrets
from datetime import datetime, timedelta, timezone

from app.core.config import settings
from app.core.logging import get_logger
from app.services.otp_store import get_otp_store

logger = get_logger("app.services.otp")


def _store():
    """Return the active OTP store (in-memory or Redis via OTP_STORAGE_URI)."""
    return get_otp_store(settings.OTP_STORAGE_URI)


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
    """Generate and store an OTP for the phone number, then DELIVER it.

    Delivery is handled by :func:`app.services.fast2sms.send_otp_sms`, which
    respects ``OTP_MODE``:
      - ``mock`` → prints the code to the server console (₹0 testing).
      - ``live`` → sends a real SMS through Fast2SMS (balance debited).

    Returns a dict with:
      - otp:        the raw OTP (only returned in dev mode)
      - expires_in: seconds until expiry
    """
    from app.services.fast2sms import send_otp_sms  # local import avoids cycles

    phone = _ensure_phone_normalized(phone_number)
    now = datetime.now(timezone.utc)
    store = _store()
    existing = store.get(phone)

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

    record = {
        "otp_hash": otp_hash,
        "salt": salt,
        "expires_at": expires_at,
        "attempts": 0,
        "resend_count": (existing["resend_count"] + 1) if existing else 1,
        "last_resend_at": now,
        "created_at": now,
    }
    # TTL gets a small buffer beyond the logical expiry so verify_otp can
    # still distinguish "expired" from "never issued" in its response path.
    ttl_seconds = settings.OTP_EXPIRE_MINUTES * 60 + 60
    store.set(phone, record, ttl_seconds)

    # Deliver the code. Mock mode prints it to the console; live mode sends a
    # real SMS via Fast2SMS. On live-mode failure the exception propagates and
    # the stored record is dropped so a code the user never received cannot be
    # redeemed later.
    try:
        send_otp_sms(phone, otp)
    except Exception:
        store.pop(phone)
        raise

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
    store = _store()
    record = store.get(phone)
    if record is None:
        return False

    now = datetime.now(timezone.utc)

    # Expiry check
    if now > record["expires_at"]:
        store.pop(phone)
        logger.info("OTP expired for %s", phone)
        return False

    # Max attempts check
    if record["attempts"] >= settings.OTP_MAX_ATTEMPTS:
        store.pop(phone)  # Invalidate OTP after too many attempts
        logger.warning("OTP max attempts exceeded for %s", phone)
        return False

    # Verify using constant-time comparison
    expected_hash = record["otp_hash"]
    salt = record["salt"]
    actual_hash = _hash_otp(otp, salt)
    is_valid = hmac.compare_digest(actual_hash, expected_hash)

    if is_valid:
        store.pop(phone)  # Single-use
        logger.info("OTP verified for %s", phone)
        return True

    record["attempts"] += 1
    # Persist the incremented attempt count (a Redis get() returns a fresh
    # deserialized copy — without this write-back lockout would never trigger).
    ttl_seconds = max(1, int((record["expires_at"] - now).total_seconds())) + 60
    store.set(phone, record, ttl_seconds)
    logger.warning("Invalid OTP attempt for %s (attempt %d)", phone, record["attempts"])
    return False


def resend_otp(phone_number: str) -> dict:
    """Alias for generate_otp — used by endpoints to differentiate paths."""
    return generate_otp(phone_number)


def remaining_attempts(phone_number: str) -> int:
    """Return how many attempts remain for a phone number."""
    phone = _ensure_phone_normalized(phone_number)
    record = _store().get(phone)
    if record is None:
        return 0
    return max(0, settings.OTP_MAX_ATTEMPTS - record["attempts"])


def clear_otp(phone_number: str) -> None:
    """Force-invalidate an OTP (used on logout / account actions).

    Best-effort: storage backend failures must not break logout flows.
    """
    phone = _ensure_phone_normalized(phone_number)
    try:
        _store().pop(phone)
    except Exception as exc:  # noqa: BLE001 — Redis outage must not block logout
        logger.error("clear_otp failed for %s: %s", phone, exc)


def clear_all_otps() -> None:
    """Wipe every OTP record (ops reset / test isolation).

    Best-effort: storage backend failures are logged, never raised.
    """
    try:
        _store().clear_all()
    except Exception as exc:  # noqa: BLE001
        logger.error("clear_all_otps failed: %s", exc)


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
