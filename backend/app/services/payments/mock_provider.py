"""Phase 28 — Built-in deterministic Mock payment provider (tests / dev / demo).

Implements the full :class:`PaymentProvider` contract in memory:

* ``create_order``   — deterministic provider order ids
* ``verify_payment`` — HMAC signature check; ``simulate_failure`` notes or
  :meth:`fail_next_payment` inject gateway declines
* ``parse_webhook``  — HMAC-authenticated event decoding, with
  :func:`build_webhook_payload` as the canonical sender-side helper
* ``refund``         — deterministic refund ids (provider supports refunds)

A module-level singleton (``mock_payment_provider``) is registered under code
``MOCK`` so the whole Phase 28 matrix is exercisable without any gateway.
"""

from __future__ import annotations

import hashlib
import json
from typing import Optional

from app.services.payments.base import (
    PaymentIntent,
    PaymentProvider,
    PaymentVerificationError,
    VerificationResult,
    WebhookSignatureError,
    register_provider,
    sign_payload,
)

DEFAULT_MOCK_SECRET = "mock-payment-secret"


def _resolve_mock_secret(explicit: Optional[str]) -> str:
    """Return the explicit secret, else the configured MOCK_PAYMENT_SECRET.

    Production startup checks refuse a known-default value, so operators MUST
    set MOCK_PAYMENT_SECRET (via env / Secrets Manager) before money flows.
    """
    if explicit:
        return explicit
    try:
        from app.core.config import settings

        return getattr(settings, "MOCK_PAYMENT_SECRET", None) or DEFAULT_MOCK_SECRET
    except Exception:  # noqa: BLE001 — settings not yet available at import
        return DEFAULT_MOCK_SECRET


def _deterministic_id(prefix: str, *parts) -> str:
    digest = hashlib.sha1("|".join(str(p) for p in parts).encode("utf-8")).hexdigest()[:14]
    return f"{prefix}_{digest}"


class MockPaymentProvider(PaymentProvider):
    code = "MOCK"
    display_name = "Mock Gateway (built-in)"
    supports_refund = True

    def __init__(self, secret: Optional[str] = None) -> None:
        self._secret = _resolve_mock_secret(secret)
        self._fail_next = 0

    # ── Test helpers ──────────────────────────────────────────────────────
    def set_secret(self, secret: str) -> None:
        self._secret = secret

    def fail_next_payment(self, count: int = 1) -> None:
        """Force the next *count* verifications to report a gateway decline."""
        self._fail_next += count

    @property
    def secret(self) -> str:
        return self._secret

    # ── Signature helpers (shared with checkout + webhook senders) ────────
    def checkout_signature(self, provider_order_id: str, provider_payment_id: str) -> str:
        return sign_payload(self._secret, f"{provider_order_id}|{provider_payment_id}")

    def webhook_signature(self, body: bytes | str) -> str:
        return sign_payload(self._secret, body)

    # ── PaymentProvider contract ──────────────────────────────────────────
    def create_order(
        self,
        order_ref: str,
        amount: float,
        currency: str,
        payment_method: str,
        notes: dict | None = None,
    ) -> PaymentIntent:
        provider_order_id = _deterministic_id("order", order_ref)
        return PaymentIntent(
            provider_order_id=provider_order_id,
            amount=float(amount),
            currency=currency,
            provider_code=self.code,
            checkout_payload={
                "order_id": provider_order_id,
                "amount": float(amount),
                "currency": currency,
                "payment_method": payment_method,
            },
        )

    def verify_payment(
        self,
        provider_order_id: str,
        provider_payment_id: str,
        signature: str,
    ) -> VerificationResult:
        expected = self.checkout_signature(provider_order_id, provider_payment_id)
        if not signature or not hmac_compare(signature, expected):
            raise PaymentVerificationError("Invalid checkout signature")

        if self._fail_next > 0:
            self._fail_next -= 1
            return VerificationResult(
                verified=False,
                reason="GATEWAY_DECLINED",
                provider_payment_id=provider_payment_id,
            )
        return VerificationResult(verified=True, provider_payment_id=provider_payment_id)

    def parse_webhook(self, body: bytes, signature: Optional[str]) -> dict:
        if not signature or not hmac_compare(signature, self.webhook_signature(body)):
            raise WebhookSignatureError("Webhook signature verification failed")
        try:
            payload = json.loads(body.decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError) as exc:
            raise WebhookSignatureError(f"Malformed webhook body: {exc}") from exc

        required = {"event_id", "event_type", "data"}
        if not required.issubset(payload):
            raise WebhookSignatureError("Webhook payload missing required fields")
        return payload

    def refund(self, provider_payment_id: str, amount: float, reason: str | None = None) -> dict:
        return {
            "refund_id": _deterministic_id("rfnd", provider_payment_id),
            "status": "PROCESSED",
            "amount": float(amount),
            "reason": reason,
        }


def hmac_compare(a: str, b: str) -> bool:
    """Constant-time string comparison for signatures."""
    return hmac_cmp_bytes(a.encode("utf-8"), b.encode("utf-8"))


def hmac_cmp_bytes(a: bytes, b: bytes) -> bool:
    import hmac as _hmac

    return _hmac.compare_digest(a, b)


# ── Canonical sender-side webhook builder (tests / gateway simulation) ──────
def build_webhook_payload(
    event_id: str,
    event_type: str,
    provider_order_id: str,
    provider_payment_id: Optional[str] = None,
    status: str = "SUCCESS",
    extra: dict | None = None,
) -> dict:
    data = {
        "provider_order_id": provider_order_id,
        "provider_payment_id": provider_payment_id,
        "status": status,
    }
    if extra:
        data.update(extra)
    return {"event_id": event_id, "event_type": event_type, "data": data}


def encode_webhook(payload: dict) -> bytes:
    """Serialize a webhook payload exactly the way the mock signs it."""
    return json.dumps(payload, separators=(",", ":"), sort_keys=True).encode("utf-8")


# Module-level singleton registered on import (see package __init__).
mock_payment_provider = MockPaymentProvider()
register_provider(mock_payment_provider)
