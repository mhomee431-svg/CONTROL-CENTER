"""DB-backed, single-use OTP service for the Fast2SMS phone auth flow.

The customer auth endpoints (``/api/v1/auth/send-otp`` and
``/api/v1/auth/verify-otp``) persist OTP records in the ``otps`` table and
deliver codes through :mod:`app.services.fast2sms`:

  * ``OTP_MODE=mock`` prints the code to the console — ₹0 testing.
  * ``OTP_MODE=live`` sends a real SMS through the Fast2SMS "otp" route.

Security properties:
  * Codes are generated from :mod:`secrets` (CSPRNG), 6 numeric digits.
  * Only a salted HMAC-SHA256 digest is stored in ``otp_code`` — raw codes
    never hit the database. Format: ``<salt>:<digest>``.
  * Verification uses constant-time comparison.
  * Single-use: the matching record is marked ``is_verified`` in an atomic
    ``UPDATE ... WHERE is_verified = false``, so the same code cannot be
    redeemed twice even under concurrent requests.
  * Codes expire after ``OTP_EXPIRE_MINUTES`` (5 minutes) via ``expires_at``.

The shopkeeper flow keeps using the Redis-backed
:mod:`app.services.otp_service`; the cooldown/limit exception classes are
re-exported from there so both flows share identical error semantics.
"""
import hashlib
import hmac
import secrets
from datetime import datetime, timedelta, timezone

from sqlalchemy import update
from sqlalchemy.orm import Session

from app.core.config import settings
from app.core.logging import get_logger
from app.models.otp import Otp
from app.services.otp_service import OTPCooldownError, OTPLimitExceeded  # noqa: F401 — shared error types

logger = get_logger("app.services.fast2sms_otp")

# Verification result codes — routes map these to precise error messages.
VERIFY_VALID = "valid"
VERIFY_INVALID = "invalid"
VERIFY_EXPIRED = "expired"
VERIFY_ALREADY_USED = "already_used"


def _normalize_phone(phone_number: str) -> str:
    """Normalize to E.164-ish form (strip spaces, ensure a leading '+')."""
    phone = phone_number.strip()
    if not phone.startswith("+"):
        phone = "+" + phone
    return phone


def _generate_code() -> str:
    """Cryptographically-secure numeric OTP (fixed value in OTP_DEV_MODE)."""
    if settings.OTP_DEV_MODE:
        return settings.OTP_DEV_VALUE
    return "".join(str(secrets.randbelow(10)) for _ in range(settings.OTP_LENGTH))


def _hash_code(code: str, salt: str) -> str:
    return hmac.new(salt.encode(), code.encode(), hashlib.sha256).hexdigest()


def _split_stored(stored: str) -> tuple[str, str]:
    """Split a stored ``<salt>:<digest>`` payload back into its parts."""
    salt, _, digest = stored.partition(":")
    return salt, digest


def _latest_record(db: Session, phone: str) -> Otp | None:
    """Newest OTP row for a phone (the only one that can be redeemed)."""
    return (
        db.query(Otp)
        .filter(Otp.phone_number == phone)
        .order_by(Otp.id.desc())
        .first()
    )
def generate_otp(db: Session, phone_number: str) -> dict:
    """Generate a 6-digit OTP, persist it, and trigger Fast2SMS delivery.

    Returns a dict with ``expires_in`` (and ``dev_otp`` in OTP_DEV_MODE,
    mirroring the legacy Redis-backed flow's response envelope).
    """
    from app.services.fast2sms import send_otp_sms

    phone = _normalize_phone(phone_number)
    now = datetime.now(timezone.utc)

    # ── Cooldown + resend-limit enforcement (parity with the Redis flow) ─────
    latest = _latest_record(db, phone)
    if latest is not None and not latest.is_verified and latest.expires_at > now:
        elapsed = (now - latest.created_at).total_seconds()
        if elapsed < settings.OTP_COOLDOWN_SECONDS:
            raise OTPCooldownError(
                "Please wait before requesting another OTP.",
                retry_after_seconds=int(settings.OTP_COOLDOWN_SECONDS - elapsed),
            )
        unverified_count = (
            db.query(Otp)
            .filter(
                Otp.phone_number == phone,
                Otp.is_verified.is_(False),
                Otp.expires_at > now,
            )
            .count()
        )
        if unverified_count >= settings.OTP_MAX_RESENDS:
            raise OTPLimitExceeded(
                "OTP resend limit reached. Try again later.",
                resend_after_seconds=None,
            )

    # ── Issue + persist ───────────────────────────────────────────────────────
    code = _generate_code()
    salt = secrets.token_hex(16)
    record = Otp(
        phone_number=phone,
        otp_code=f"{salt}:{_hash_code(code, salt)}",
        expires_at=now + timedelta(minutes=settings.OTP_EXPIRE_MINUTES),
        is_verified=False,
    )
    db.add(record)
    db.flush()

    # Deliver the code. On failure the exception propagates and the
    # request-scoped DB session rolls back, so a code the user never received
    # is never persisted.
    send_otp_sms(phone, code)

    logger.info(
        "OTP generated for %s (expires in %s minutes)", phone, settings.OTP_EXPIRE_MINUTES
    )

    result: dict = {"expires_in": settings.OTP_EXPIRE_MINUTES * 60}
    if settings.OTP_DEV_MODE:
        result["dev_otp"] = code
    return result


def verify_otp(db: Session, phone_number: str, otp: str) -> str:
    """Validate a code and enforce single-use.

    Returns one of the ``VERIFY_*`` constants:
      ``valid``        → match; the record is now consumed.
      ``invalid``      → no record / code does not match.
      ``expired``      → code older than the 5-minute window.
      ``already_used`` → code was already redeemed.
    """
    phone = _normalize_phone(phone_number)
    now = datetime.now(timezone.utc)
    record = _latest_record(db, phone)

    if record is None:
        return VERIFY_INVALID

    if now > record.expires_at:
        logger.info("OTP expired for %s", phone)
        return VERIFY_EXPIRED

    if record.is_verified:
        return VERIFY_ALREADY_USED

    salt, expected_digest = _split_stored(record.otp_code)
    actual_digest = _hash_code(otp, salt)
    if not hmac.compare_digest(actual_digest, expected_digest):
        logger.warning("Invalid OTP attempt for %s", phone)
        return VERIFY_INVALID

    # ── Single-use guarantee: only rows still unverified flip to True. ────────
    flipped = db.execute(
        update(Otp)
        .where(Otp.id == record.id, Otp.is_verified.is_(False))
        .values(is_verified=True)
    )
    if flipped.rowcount != 1:
        logger.warning("OTP consumed concurrently for %s", phone)
        return VERIFY_ALREADY_USED
    record.is_verified = True
    db.flush()

    logger.info("OTP verified for %s", phone)
    return VERIFY_VALID


def clear_otp(db: Session, phone_number: str) -> None:
    """Immediately consume the active OTP (logout / account-rejected flows)."""
    phone = _normalize_phone(phone_number)
    record = _latest_record(db, phone)
    if record is not None and not record.is_verified:
        record.is_verified = True
        db.flush()