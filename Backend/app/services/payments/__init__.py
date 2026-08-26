"""Phase 28 — Provider-agnostic payment platform.

The package exposes a small, stable contract that any payment gateway adapter
can implement. Nothing outside this package may depend on a concrete vendor:
callers resolve providers through the registry (``get_provider``).

    PaymentProvider (abstract)      ← gateway adapters implement this
        ├── MockPaymentProvider     ← built-in deterministic mock
        └── (future gateways)
    registry                        ← register / resolve adapters by code
"""

from app.services.payments.base import (
    PaymentIntent,
    PaymentProvider,
    PaymentProviderError,
    PaymentVerificationError,
    VerificationResult,
    WebhookSignatureError,
    get_provider,
    list_providers,
    register_provider,
    sign_payload,
)

# Importing the module registers the built-in mock provider.
from app.services.payments.mock_provider import (  # noqa: F401,E402
    build_webhook_payload,
    encode_webhook,
    mock_payment_provider,
)

__all__ = [
    "PaymentIntent",
    "PaymentProvider",
    "PaymentProviderError",
    "PaymentVerificationError",
    "VerificationResult",
    "WebhookSignatureError",
    "get_provider",
    "list_providers",
    "mock_payment_provider",
    "build_webhook_payload",
    "encode_webhook",
    "register_provider",
    "sign_payload",
]
