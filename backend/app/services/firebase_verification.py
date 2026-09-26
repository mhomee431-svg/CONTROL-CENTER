"""Firebase Phone Authentication verification service.

Replaces Fast2SMS for OTP delivery — the Flutter client performs the full
phone-OTP flow with the ``firebase_auth`` package (SMS is sent by Google, no
third-party gateway needed) and forwards the resulting Firebase ID token to
the backend. This service verifies that token via Firebase Admin and extracts
the authenticated phone number AND the firebase_uid.

Safe on platforms without firebase_admin (test, local mock): the import is
deferred and the verify function raises a clear error if the SDK is missing.
"""
import hashlib
import json
import logging
import time
from pathlib import Path
from threading import Lock
from typing import Optional, Tuple

from app.core.config import settings

logger = logging.getLogger("app.services.firebase_verification")

_initialized = False

# ── Verified-token cache ──────────────────────────────────────────────────
# Firebase ID tokens are valid for 1 hour. Re-verifying the same token within
# that window wastes ~200-500ms on a blocking network call to Google's
# certificate servers AND freezes the asyncio event loop for every concurrent
# request.  We cache the verified claims keyed by a SHA-256 fingerprint of the
# token and evict entries when their *exp* claim passes.  This is a pure
# in-memory cache (per worker) — it holds only public claims, never secrets.
_verified_token_cache: dict[str, Tuple[dict, float]] = {}
_cache_lock = Lock()
_cache_stats = {"hits": 0, "misses": 0, "evictions": 0}

# Maximum cache size — bounds memory on high-traffic workers.
_MAX_CACHE_SIZE = 2048


def _token_fingerprint(token: str) -> str:
    """Return a stable, collision-resistant cache key for a Firebase JWT."""
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


def get_firebase_cache_stats() -> dict:
    """Return cache hit/miss/eviction counters (for observability endpoints)."""
    with _cache_lock:
        return {
            "hits": _cache_stats["hits"],
            "misses": _cache_stats["misses"],
            "evictions": _cache_stats["evictions"],
            "size": len(_verified_token_cache),
        }


def clear_firebase_token_cache() -> None:
    """Flush the cache — intended for tests and admin maintenance."""
    with _cache_lock:
        _verified_token_cache.clear()
        for k in _cache_stats:
            _cache_stats[k] = 0

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


def verify_firebase_id_token(id_token: str) -> Tuple[str, str]:
    """Verify a Firebase ID token and return (firebase_uid, phone_number).

    The Flutter ``firebase_auth`` package produces this token after a successful
    phone-OTP sign-in. Verifying it here confirms:
      - The token is genuine (signature checked by Firebase Admin)
      - It belongs to a phone-authenticated user
      - The phone number is the one Google actually sent the OTP to
      - The firebase_uid is the stable Firebase identity

    Returns a tuple of (firebase_uid, phone_number).
    Phone number may be empty string if not present in token.

    Raises FirebaseVerificationError on any failure.
    """
    claims = verify_firebase_id_token_claims(id_token)
    return claims["uid"], claims["phone"]


def _cleanup_expired_cache_entries() -> None:
    """Remove expired entries from the token cache (called periodically)."""
    now = time.time()
    with _cache_lock:
        expired = [k for k, (_, exp_ts) in _verified_token_cache.items() if now >= exp_ts]
        for k in expired:
            del _verified_token_cache[k]
            _cache_stats["evictions"] += 1


def verify_firebase_id_token_claims(id_token: str) -> dict:
    """Verify a Firebase ID token and return the full verified claim set.

    Works for BOTH authentication providers the platform plans to support:

      - Google Sign-In  → ``email`` + ``name`` claims, usually no phone
      - Phone OTP (future) → ``phone_number`` claim

    Returns a dict with keys: ``uid``, ``phone``, ``email``, ``name``,
    ``picture``, ``email_verified``, ``provider`` (Firebase sign-in provider
    id), ``google_id`` (the provider subject when Google supplies it), and the
    raw ``claims`` mapping. ``phone`` is always a string (empty when absent)
    and ``email_verified`` is always a boolean.

    Raises FirebaseVerificationError on any failure.
    """
    _ensure_initialized()

    # ── Layer 1: Check cache ──────────────────────────────────────────────
    # The same token is often re-verified within its 1-hour lifetime (retries,
    # concurrent calls during sign-in).  A cache hit skips the blocking network
    # call to Google entirely — typically saving 200-500ms.
    fp = _token_fingerprint(id_token)
    now = time.time()
    with _cache_lock:
        cached = _verified_token_cache.get(fp)
        if cached:
            claims, exp_ts = cached
            if now < exp_ts:
                _cache_stats["hits"] += 1
                logger.debug("Firebase token cache hit (fp=%s…)", fp[:12])
                return claims
            # Entry expired — evict it below
            del _verified_token_cache[fp]
            _cache_stats["evictions"] += 1
        else:
            _cache_stats["misses"] += 1

    # ── Layer 2: Verify via Firebase Admin (blocking network call) ────────
    from firebase_admin import auth

    try:
        decoded = auth.verify_id_token(id_token)
    except Exception as exc:
        # Log EVERYTHING about the failure — audience, expiry, malformed JWT —
        # so the exact rejection reason is visible in server logs.
        reason = str(exc)
        try:
            # Attempt a structural decode (no signature check) for diagnostics.
            header_b64 = id_token.split(".")[0]
            import base64

            pad = "=" * (-len(header_b64) % 4)
            header = base64.urlsafe_b64decode(header_b64 + pad).decode("utf-8", "ignore")
            reason += f" | header={header}"
        except Exception:
            reason += " | token-not-decodable"
        logger.warning(
            "Firebase verify_id_token rejected token: %s", reason
        )
        raise FirebaseVerificationError(
            f"Invalid or expired Firebase token: {type(exc).__name__}: {exc}"
        ) from exc

    # ── Cache the result until the token's exp claim ──────────────────────
    exp_ts = decoded.get("exp", 0)
    if exp_ts > now:
        with _cache_lock:
            # Evict oldest entries if cache is full (simple size cap)
            if len(_verified_token_cache) >= _MAX_CACHE_SIZE:
                # Remove up to 25% of entries (oldest first by insertion order)
                keys_to_remove = list(_verified_token_cache.keys())[:_MAX_CACHE_SIZE // 4]
                for k in keys_to_remove:
                    del _verified_token_cache[k]
                _cache_stats["evictions"] += len(keys_to_remove)
            _verified_token_cache[fp] = (None, exp_ts)  # placeholder, filled below

    firebase_uid = decoded.get("sub")  # 'sub' is the Firebase UID
    if not firebase_uid:
        raise FirebaseVerificationError(
            "Firebase token has no subject (UID) claim",
            error_code="FIREBASE_UID_MISSING",
            status_code=401,
        )

    # firebase["firebase"]["sign_in_provider"] — e.g. "google.com", "phone"
    provider = ""
    google_id = ""
    firebase_section = decoded.get("firebase")
    if isinstance(firebase_section, dict):
        provider = firebase_section.get("sign_in_provider") or ""
        identities = firebase_section.get("identities") or {}
        google_identities = identities.get("google.com") or []
        if google_identities and isinstance(google_identities[0], str):
            google_id = google_identities[0]

    claims = {
        "uid": firebase_uid,
        "phone": decoded.get("phone_number") or "",
        "email": decoded.get("email") or "",
        "name": decoded.get("name") or "",
        "picture": decoded.get("picture") or "",
        "email_verified": decoded.get("email_verified") is True,
        "provider": provider,
        "google_id": google_id,
        "claims": decoded,
    }

    # Store verified claims in cache for subsequent requests with same token
    if exp_ts > now:
        with _cache_lock:
            _verified_token_cache[fp] = (claims, exp_ts)

    logger.info(
        "Firebase token verified for uid %s (provider=%s)", firebase_uid, provider
    )
    return claims


def verify_firebase_id_token_phone(id_token: str) -> str:
    """Legacy helper: Verify a Firebase ID token and return only the phone number.

    .. deprecated:: 0.21
        Use :func:`verify_firebase_id_token` instead which returns both
        firebase_uid and phone_number.
    """
    _, phone = verify_firebase_id_token(id_token)
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