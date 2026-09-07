"""Firebase Phone Authentication verification service.

Replaces Fast2SMS for OTP delivery — the Flutter client performs the full
phone-OTP flow with the ``firebase_auth`` package (SMS is sent by Google, no
third-party gateway needed) and forwards the resulting Firebase ID token to
the backend. This service verifies that token via Firebase Admin and extracts
the authenticated phone number.

Safe on platforms without firebase_admin (test, local mock): the import is
deferred and the verify function raises a clear error if the SDK is missing.
"""
import json
import logging
from pathlib import Path
from typing import Optional

from app.core.config import settings

logger = logging.getLogger("app.services.firebase_verification")

_initialized = False

# backend/ directory — used to resolve relative credential paths regardless of
# the current working directory (important on AWS ECS/docker where CWD differs).
BACKEND_DIR = Path(__file__).resolve().parents[2]


def _resolve_absolute_path(path: str) -> str:
    """Resolve a credential path to an absolute path.

    Absolute paths pass through unchanged; relative paths are interpreted as
    relative to the backend/ directory (matching config.py behaviour), so the
    app works regardless of the current working directory.
    """
    p = Path(path).expanduser()
    if p.is_absolute():
        return str(p)
    return str(BACKEND_DIR / p)


def _resolve_credentials_file() -> Optional[str]:
    """Resolve the Firebase service-account credential source.

    Order:
      1. ``FIREBASE_CREDENTIALS_FILE`` — explicit path
      2. ``FCM_CREDENTIALS_FILE`` — reuse the same service account as push
      3. None — credentials not configured
    """
    raw = (
        settings.FIREBASE_CREDENTIALS_FILE
        or settings.FCM_CREDENTIALS_FILE
        or None
    )
    if raw:
        return _resolve_absolute_path(raw)
    return None


def _resolve_credentials_json() -> Optional[str]:
    """Resolve inline service-account JSON."""
    return (
        settings.FIREBASE_CREDENTIALS_JSON
        or settings.FCM_CREDENTIALS_JSON
        or None
    )


def _ensure_initialized() -> None:
    """Idempotent Firebase Admin initialization."""
    global _initialized
    if _initialized:
        return

    import firebase_admin
    from firebase_admin import credentials

    if firebase_admin._apps:
        _initialized = True
        return

    cred_path = _resolve_credentials_file()
    if cred_path:
        if not Path(cred_path).exists():
            raise RuntimeError(
                f"Firebase credentials file not found at resolved path: {cred_path}"
            )
        cred = credentials.Certificate(cred_path)
        firebase_admin.initialize_app(cred)
        _initialized = True
        logger.info("Firebase Admin initialized from credentials file: %s", cred_path)
        return

    cred_json = _resolve_credentials_json()
    if cred_json:
        cred = credentials.Certificate(json.loads(cred_json))
        firebase_admin.initialize_app(cred)
        _initialized = True
        logger.info("Firebase Admin initialized from inline credentials JSON")
        return

    raise RuntimeError(
        "Firebase credentials not configured. Set FIREBASE_CREDENTIALS_FILE "
        "(or reuse FCM_CREDENTIALS_FILE) or FIREBASE_CREDENTIALS_JSON."
    )


def verify_firebase_id_token(id_token: str) -> str:
    """Verify a Firebase ID token and return the authenticated phone number.

    The Flutter ``firebase_auth`` package produces this token after a successful
    phone-OTP sign-in. Verifying it here confirms:
      - The token is genuine (signature checked by Firebase Admin)
      - It belongs to a phone-authenticated user
      - The phone number is the one Google actually sent the OTP to

    Returns the phone number in E.164 format (e.g. ``+919999999999``).

    Raises FirebaseVerificationError on any failure.
    """
    _ensure_initialized()

    from firebase_admin import auth

    try:
        decoded = auth.verify_id_token(id_token)
    except Exception as exc:
        raise FirebaseVerificationError(
            f"Invalid or expired Firebase token: {type(exc).__name__}"
        ) from exc

    phone = decoded.get("phone_number")
    if not phone:
        raise FirebaseVerificationError(
            "Firebase token has no phone_number claim",
            error_code="FIREBASE_PHONE_MISSING",
            status_code=401,
        )

    logger.info("Firebase token verified for phone %s", phone)
    return phone


class FirebaseVerificationError(Exception):
    """Raised when a Firebase ID token cannot be verified."""

    def __init__(
        self,
        message: str,
        error_code: str = "FIREBASE_VERIFICATION_FAILED",
        status_code: int = 401,
    ):
        self.message = message
        self.error_code = error_code
        self.status_code = status_code
        super().__init__(message)