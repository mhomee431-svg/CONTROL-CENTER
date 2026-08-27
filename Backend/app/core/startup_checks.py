"""Phase 30 — Production startup security gate.

Fail-fast validation of security-critical configuration. In production the
application MUST refuse to boot when a critical control is misconfigured
(a warning is not enough — it scrolls away and nobody reads it).

Checks:
    1. JWT_SECRET_KEY is not a known default and has adequate entropy length
    2. OTP dev mode disabled (no universal ``123456`` backdoor)
    3. DEBUG off (no verbose error leakage)
    4. CORS origins explicitly configured — never ``*`` while allowing
       credentials
    5. Rate limiting enabled (API abuse protection active)

Non-production environments only log warnings so local development stays
frictionless.
"""
from __future__ import annotations

from app.core.config import Settings
from app.core.logging import get_logger

logger = get_logger("app.startup")

INSECURE_JWT_DEFAULTS = {
    "change-me-in-production",
    "changeme",
    "secret",
    "secretkey",
    "jwt_secret",
    "your-secret-key",
    "supersecret",
}
MIN_JWT_SECRET_LENGTH = 32


class ProductionSecurityError(RuntimeError):
    """Raised when production configuration fails a mandatory security check."""


def run_startup_security_checks(settings: Settings) -> list[str]:
    """Validate security-critical settings; raise in production, warn otherwise.

    Returns the list of human-readable findings (empty == all clear).
    Raises :class:`ProductionSecurityError` in production if any CRITICAL
    finding exists.
    """
    findings: list[str] = []

    # 1. JWT secret strength ────────────────────────────────────────────────
    secret = (settings.JWT_SECRET_KEY or "").strip()
    if not secret or secret.lower() in INSECURE_JWT_DEFAULTS:
        findings.append(
            "CRITICAL: JWT_SECRET_KEY is a known insecure default — tokens can be forged"
        )
    elif len(secret) < MIN_JWT_SECRET_LENGTH:
        findings.append(
            f"CRITICAL: JWT_SECRET_KEY shorter than {MIN_JWT_SECRET_LENGTH} chars — "
            "vulnerable to brute force"
        )

    # 2. OTP dev backdoor ───────────────────────────────────────────────────
    if settings.OTP_DEV_MODE:
        findings.append(
            "CRITICAL: OTP_DEV_MODE is enabled — every phone number authenticates "
            f"with the universal code '{settings.OTP_DEV_VALUE}'"
        )

    # 3. Debug mode ─────────────────────────────────────────────────────────
    if settings.DEBUG:
        findings.append("HIGH: DEBUG is enabled — stack traces leak internals")

    # 4. CORS wildcard with credentials ─────────────────────────────────────
    origins = settings.cors_origin_list
    if not origins or "*" in origins:
        findings.append(
            "HIGH: CORS_ORIGINS is empty or '*' — combined with allow_credentials "
            "this lets any site make credentialed cross-origin requests"
        )

    # 5. Rate limiting ──────────────────────────────────────────────────────
    if not settings.RATE_LIMIT_ENABLED:
        findings.append("HIGH: RATE_LIMIT_ENABLED is false — no API abuse protection")

    critical = [f for f in findings if f.startswith("CRITICAL")]
    high = [f for f in findings if f.startswith("HIGH")]

    if settings.is_production:
        if critical or high:
            for finding in findings:
                logger.error("Startup security check FAILED: %s", finding)
            raise ProductionSecurityError(
                "Refusing to start in production with insecure configuration:\n- "
                + "\n- ".join(findings)
            )
    else:
        for finding in findings:
            logger.warning("Security check (%s env): %s", settings.ENVIRONMENT, finding)

    return findings