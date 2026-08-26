"""Phase 25 — Provider-agnostic POS integration platform.

The package exposes a small, stable contract that any POS vendor adapter can
implement. Nothing outside this package may depend on a concrete vendor:
callers resolve providers through the registry (``get_provider``).

    POSProvider (abstract)      ← vendor adapters implement this
        ├── MockPOSProvider     ← built-in deterministic mock
        └── (future vendors)
    POSCredentials              ← vendor-neutral credential/config bag
    registry                    ← register / resolve adapters by code
"""

from app.services.pos_integration.base import (
    POSAuthError,
    POSConnectionError,
    POSCredentials,
    POSFetchResult,
    POSProductRecord,
    POSProvider,
    POSProviderError,
    get_provider,
    list_providers,
    normalize_product_record,
    register_provider,
)

# Importing the module registers the built-in mock provider.
from app.services.pos_integration.mock_provider import mock_pos_provider  # noqa: F401,E402

__all__ = [
    "POSAuthError",
    "POSConnectionError",
    "POSCredentials",
    "POSFetchResult",
    "POSProductRecord",
    "POSProvider",
    "POSProviderError",
    "get_provider",
    "list_providers",
    "mock_pos_provider",
    "normalize_product_record",
    "register_provider",
]
