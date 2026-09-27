"""Phase 25 — Vendor-neutral POS provider contract, credentials and registry.

Any POS vendor adapter implements :class:`POSProvider`. Nothing outside this
package may depend on a concrete vendor — callers resolve adapters exclusively
through the registry (:func:`get_provider`) so new vendors (Marg, Busy,
Vyapar, Tally, Square, ...) can be dropped in without touching the engine.
"""

from __future__ import annotations

import hashlib
import json
from abc import ABC, abstractmethod
from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Any, ClassVar, Optional


# ── Provider exceptions ──────────────────────────────────────────────────────
class POSProviderError(Exception):
    """Base error raised by POS vendor adapters (mapped to sync failures)."""

    def __init__(self, message: str = "POS provider error", error_code: str = "POS_PROVIDER_ERROR"):
        super().__init__(message)
        self.message = message
        self.error_code = error_code


class POSAuthError(POSProviderError):
    """Credentials rejected / expired by the POS vendor."""

    def __init__(self, message: str = "POS authentication failed"):
        super().__init__(message, "POS_AUTH_FAILED")


class POSConnectionError(POSProviderError):
    """POS system unreachable (network outage, firewall, downtime)."""

    def __init__(self, message: str = "POS system unreachable"):
        super().__init__(message, "POS_CONNECTION_FAILED")


# ── Credentials / configuration abstraction ─────────────────────────────────
@dataclass
class POSCredentials:
    """Vendor-neutral credential + configuration bag.

    Secrets live encrypted-at-rest on ``POSIntegration`` columns; this object
    is assembled per-call and never persisted itself. ``extras`` carries
    vendor-specific credential fields defined in the integration's
    ``config_json["credentials"]`` block, so vendors needing more than
    key/secret are supported without schema changes.
    """

    api_base_url: Optional[str] = None
    api_key: Optional[str] = None
    api_secret: Optional[str] = None
    extras: dict[str, Any] = field(default_factory=dict)

    @classmethod
    def from_integration(cls, integration: Any) -> "POSCredentials":
        config = getattr(integration, "config_json", None) or {}
        return cls(
            api_base_url=getattr(integration, "api_base_url", None),
            api_key=getattr(integration, "api_key_encrypted", None),
            api_secret=getattr(integration, "api_secret_encrypted", None),
            extras=dict(config.get("credentials", {}) or {}),
        )

    def as_provider_input(self) -> dict[str, Any]:
        """Flatten into the opaque dict handed to provider methods."""
        payload: dict[str, Any] = {
            "api_base_url": self.api_base_url,
            "api_key": self.api_key,
            "api_secret": self.api_secret,
        }
        payload.update(self.extras)
        return payload

    @staticmethod
    def mask(value: Optional[str]) -> Optional[str]:
        if not value:
            return None
        if len(value) <= 6:
            return "****"
        return f"{value[:4]}****{value[-2:]}"

    @classmethod
    def masked_view(cls, integration: Any) -> dict[str, Any]:
        """Safe-to-serialize view of credentials for API responses."""
        creds = cls.from_integration(integration)
        return {
            "api_base_url": creds.api_base_url,
            "api_key": cls.mask(creds.api_key),
            "api_secret": cls.mask(creds.api_secret),
            "extra_keys": sorted(creds.extras.keys()),
        }

# ── Canonical POS product record ─────────────────────────────────────────────
@dataclass
class POSProductRecord:
    """One sellable item as reported by a POS system (normalized form)."""

    pos_product_code: str
    name: str
    sku: Optional[str] = None
    barcode: Optional[str] = None
    category_name: Optional[str] = None
    unit: Optional[str] = None
    price: Optional[float] = None
    mrp: Optional[float] = None
    quantity: Optional[int] = None
    updated_at: Optional[datetime] = None

    def content_fingerprint(self) -> str:
        """Stable hash over the synchronized fields — used for duplicate
        prevention (unchanged records are skipped, never re-applied)."""
        material = {
            "code": self.pos_product_code,
            "name": self.name,
            "sku": self.sku,
            "barcode": self.barcode,
            "category": self.category_name,
            "unit": self.unit,
            "price": None if self.price is None else round(float(self.price), 2),
            "mrp": None if self.mrp is None else round(float(self.mrp), 2),
            "quantity": self.quantity,
        }
        return hashlib.sha256(json.dumps(material, sort_keys=True).encode("utf-8")).hexdigest()


def normalize_product_record(payload: dict[str, Any]) -> POSProductRecord:
    """Coerce a raw vendor dict into a validated :class:`POSProductRecord`.

    Raises ``ValueError`` for records that cannot safely enter the pipeline
    (missing identity fields) — these become *item* failures inside a sync
    job rather than failing the whole job (partial-failure semantics).
    """
    code = str(payload.get("pos_product_code") or payload.get("code") or "").strip()
    if not code:
        raise ValueError("POS record missing pos_product_code")
    name = str(payload.get("name") or "").strip()
    if not name:
        raise ValueError(f"POS record '{code}' missing name")

    updated_at = payload.get("updated_at")
    if isinstance(updated_at, str) and updated_at:
        updated_at = datetime.fromisoformat(updated_at)
    if isinstance(updated_at, datetime) and updated_at.tzinfo is None:
        updated_at = updated_at.replace(tzinfo=timezone.utc)

    def _num(key: str) -> float | None:
        value = payload.get(key)
        return None if value in (None, "") else float(value)

    quantity = payload.get("quantity") if payload.get("quantity") is not None else payload.get("stock")
    return POSProductRecord(
        pos_product_code=code,
        name=name,
        sku=(str(payload["sku"]).strip() if payload.get("sku") else None),
        barcode=(str(payload["barcode"]).strip() if payload.get("barcode") else None),
        category_name=(str(payload["category_name"]).strip() if payload.get("category_name") else None),
        unit=(str(payload["unit"]).strip() if payload.get("unit") else None),
        price=_num("price"),
        mrp=_num("mrp"),
        quantity=None if quantity is None else int(quantity),
        updated_at=updated_at,
    )


@dataclass
class POSFetchResult:
    """Page of records plus an opaque incremental cursor."""

    items: list[POSProductRecord]
    cursor: Optional[str] = None  # None → provider exhausted / unsupported
    has_more: bool = False


# ── Abstract provider contract ───────────────────────────────────────────────
class POSProvider(ABC):
    """Contract every POS vendor adapter must fulfil."""

    code: ClassVar[str] = ""           # stable registry key, e.g. "MARG"
    display_name: ClassVar[str] = ""
    supports_incremental: ClassVar[bool] = True

    @abstractmethod
    def test_connection(self, credentials: dict[str, Any]) -> dict[str, Any]:
        """Validate credentials; return descriptive info or raise
        ``POSAuthError`` / ``POSConnectionError``."""

    @abstractmethod
    def fetch_products(
        self,
        credentials: dict[str, Any],
        since: Optional[str] = None,
        limit: int = 500,
    ) -> POSFetchResult:
        """Return catalog records.

        ``since`` is the previously returned cursor. Implementations that
        cannot support incremental pulls may ignore it and always return
        everything — the engine's hash-based duplicate prevention keeps that
        safe, just less efficient.
        """


# ── Registry ─────────────────────────────────────────────────────────────────
_PROVIDERS: dict[str, POSProvider] = {}


def register_provider(provider: POSProvider) -> POSProvider:
    """Register (or replace) an adapter under its stable ``code``."""
    if not getattr(provider, "code", ""):
        raise ValueError("POS provider must define a non-empty `code`")
    _PROVIDERS[provider.code.upper()] = provider
    return provider


def get_provider(code: str) -> POSProvider:
    """Resolve a registered adapter; ``LookupError`` for unknown codes."""
    provider = _PROVIDERS.get((code or "").upper())
    if provider is None:
        raise LookupError(
            f"Unknown POS provider '{code}'. Registered providers: "
            f"{', '.join(sorted(_PROVIDERS)) or 'none'}"
        )
    return provider


def list_providers() -> list[dict[str, Any]]:
    """Registry listing used by the API (`GET /shopkeeper/pos/providers`)."""
    return [
        {
            "code": p.code.upper(),
            "display_name": p.display_name,
            "supports_incremental": p.supports_incremental,
        }
        for p in sorted(_PROVIDERS.values(), key=lambda x: x.code.upper())
    ]
