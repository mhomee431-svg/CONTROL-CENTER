"""Phase 28 — Vendor-neutral payment provider contract and registry.

Any gateway adapter (Razorpay, Cashfree, Stripe, ...) implements
:class:`PaymentProvider`. Nothing outside this package may depend on a
concrete vendor — callers resolve adapters exclusively through the registry
(:func:`get_provider`) so gateways can be swapped without touching the
subscription engine.

Security invariants enforced by the contract:

* ``verify_payment`` re-checks the provider's signature server-side — the
  client's claim of success is never trusted alone.
* ``parse_webhook`` authenticates raw webhook bodies via HMAC signature
  before any state change is derived from them.
"""

from __future__ import annotations

import hashlib
import hmac
from abc import ABC, abstractmethod
from dataclasses import dataclass, field
from typing import Any, ClassVar, Optional


# ── Provider exceptions ──────────────────────────────────────────────────────
class PaymentProviderError(Exception):
    """Base error raised by payment gateway adapters."""

    def __init__(self, message: str = "Payment provider error", error_code: str = "PAYMENT_PROVIDER_ERROR"):
        super().__init__(message)
        self.message = message
        self.error_code = error_code


class PaymentVerificationError(PaymentProviderError):
    """Signature / status verification rejected by the provider."""

    def __init__(self, message: str = "Payment verification failed"):
        super().__init__(message, "PAYMENT_VERIFICATION_FAILED")


class WebhookSignatureError(PaymentProviderError):
    """Webhook body failed HMAC authentication (possible forgery/replay)."""

    def __init__(self, message: str = "Invalid webhook signature"):
        super().__init__(message, "WEBHOOK_SIGNATURE_INVALID")


# ── Value objects ────────────────────────────────────────────────────────────
@dataclass
class PaymentIntent:
    """Opaque result of asking a provider to create an order."""

    provider_order_id: str
    amount: float
    currency: str = "INR"
    provider_code: str = ""
    checkout_payload: dict = field(default_factory=dict)


@dataclass
class VerificationResult:
    """Outcome of server-side payment verification."""

    verified: bool
    reason: Optional[str] = None
    provider_payment_id: Optional[str] = None
    raw: dict = field(default_factory=dict)


def sign_payload(secret: str, body: bytes | str) -> str:
    """Standard HMAC-SHA256 hex digest shared by all mock-side helpers."""
    if isinstance(body, str):
        body = body.encode("utf-8")
    return hmac.new(secret.encode("utf-8"), body, hashlib.sha256).hexdigest()


# ── Abstract provider contract ───────────────────────────────────────────────
class PaymentProvider(ABC):
    """Contract every payment gateway adapter must fulfil."""

    code: ClassVar[str] = ""                 # stable registry key, e.g. "RAZORPAY"
    display_name: ClassVar[str] = ""
    supports_refund: ClassVar[bool] = False

    @abstractmethod
    def create_order(
        self,
        order_ref: str,
        amount: float,
        currency: str,
        payment_method: str,
        notes: dict | None = None,
    ) -> PaymentIntent:
        """Create a provider order for *amount*; returns the intent used to
        open checkout. ``order_ref`` is our internal reference (payment id)."""

    @abstractmethod
    def verify_payment(
        self,
        provider_order_id: str,
        provider_payment_id: str,
        signature: str,
    ) -> VerificationResult:
        """Server-side verification of a checkout callback. Implementations
        MUST validate the signature cryptographically before trusting the
        reported status."""

    @abstractmethod
    def parse_webhook(self, body: bytes, signature: Optional[str]) -> dict:
        """Authenticate + decode a webhook delivery.

        Returns a dict with at least::

            {"event_id": str, "event_type": str,
             "data": {"provider_order_id": str,
                      "provider_payment_id": str|None,
                      "status": "SUCCESS"|"FAILED"|...}}

        Raises ``WebhookSignatureError`` when authentication fails.
        """

    @abstractmethod
    def refund(self, provider_payment_id: str, amount: float, reason: str | None = None) -> dict:
        """Request a (full) refund; returns ``{"refund_id": ..., "status": ...}``.
        Only called when ``supports_refund`` is True."""


# ── Registry ─────────────────────────────────────────────────────────────────
_PROVIDERS: dict[str, PaymentProvider] = {}


def register_provider(provider: PaymentProvider) -> PaymentProvider:
    """Register (or replace) an adapter under its stable ``code``."""
    if not getattr(provider, "code", ""):
        raise ValueError("Payment provider must define a non-empty `code`")
    _PROVIDERS[provider.code.upper()] = provider
    return provider


def get_provider(code: str) -> PaymentProvider:
    """Resolve a registered adapter; ``LookupError`` for unknown codes."""
    provider = _PROVIDERS.get((code or "").upper())
    if provider is None:
        raise LookupError(
            f"Unknown payment provider '{code}'. Registered providers: "
            f"{', '.join(sorted(_PROVIDERS)) or 'none'}"
        )
    return provider


def list_providers() -> list[dict]:
    """Registry listing used by the API."""
    return [
        {
            "code": p.code.upper(),
            "display_name": p.display_name,
            "supports_refund": p.supports_refund,
        }
        for p in sorted(_PROVIDERS.values(), key=lambda x: x.code.upper())
    ]
