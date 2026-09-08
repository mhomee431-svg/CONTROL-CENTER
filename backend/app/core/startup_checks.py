"""Phase 30 — Production startup security gate.

Fail-fast validation of security-critical configuration. In production the
application MUST refuse to boot when a critical control is misconfigured
(a warning is not enough — it scrolls away and nobody reads it).

Checks:
    1. JWT_SECRET_KEY is not a known default and has adequate entropy length
    2. DEBUG off (no verbose error leakage)
    3. CORS origins explicitly configured — never ``*`` while allowing
       credentials
    4. Rate limiting enabled (API abuse protection active)

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

    # 2. Debug mode ─────────────────────────────────────────────────────────
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

    # 6. Distributed OTP storage ────────────────────────────────────────────
    if (settings.OTP_STORAGE_URI or "memory://").lower().startswith("memory"):
        findings.append(
            "CRITICAL: OTP_STORAGE_URI is in-memory — OTPs issued by one worker "
            "cannot be verified by another; auth breaks with 2+ workers/instances. "
            "Use a redis:// URI in production"
        )

    # 7. Distributed rate-limit counters ────────────────────────────────────
    if (settings.RATE_LIMIT_STORAGE_URI or "memory://").lower().startswith("memory"):
        findings.append(
            "HIGH: RATE_LIMIT_STORAGE_URI is in-memory — limits are enforced per "
            "process, so effective limits scale up with worker count. Use a "
            "redis:// URI in production"
        )

    # 8. Push provider credentials ──────────────────────────────────────────
    if (settings.PUSH_PROVIDER or "mock").lower() == "fcm" and not (
        settings.FCM_CREDENTIALS_FILE or settings.FCM_CREDENTIALS_JSON
    ):
        findings.append(
            "CRITICAL: PUSH_PROVIDER=fcm but no FCM credentials are configured — "
            "set FCM_CREDENTIALS_FILE or FCM_CREDENTIALS_JSON"
        )

    # 9. Mock payment provider must NOT be live with a public default secret ──
    # The built-in mock gateway signs checkouts + webhooks with
    # MOCK_PAYMENT_SECRET. The default value is published in source, so an
    # attacker could forge "payment successful" webhooks and activate paid
    # subscriptions for free. In production this only boots when a real
    # non-mock gateway is registered OR the operator set a strong secret.
    known_mock_secrets = {
        "mock-payment-secret",
        "change-me",
        "changeme",
        "secret",
        "",
        "mock",
    }
    try:
        from app.services.payments import list_providers

        registered = list_providers()
    except Exception:  # noqa: BLE001
        registered = []
    has_real_gateway = any(
        str(p.get("code", "")).upper() != "MOCK" for p in registered
    )
    uses_default_mock_secret = (
        (settings.MOCK_PAYMENT_SECRET or "").strip().lower() in known_mock_secrets
    )
    if not has_real_gateway and uses_default_mock_secret:
        findings.append(
            "CRITICAL: only the MockPaymentProvider is registered and its secret is "
            "a known default — anyone can forge payment/webhook signatures. Set a "
            "strong MOCK_PAYMENT_SECRET or register a real payment gateway."
        )

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