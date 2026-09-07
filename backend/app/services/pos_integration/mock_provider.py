"""Phase 25 — Built-in deterministic Mock POS provider (tests / dev / demo).

Implements the full :class:`POSProvider` contract entirely in memory:

* ``test_connection``      — auth + outage simulation
* ``fetch_products``       — paged catalog with **cursor-based incremental**
* seeded / mutable catalog — tests drive initial syncs, price updates and
  stock updates by calling :meth:`seed_catalog` / :meth:`upsert_record`
* failure injection        — :meth:`set_outage` simulates a dead POS system;
  ``api_key="invalid-key"`` simulates rejected credentials

A module-level singleton (``mock_pos_provider``) is registered under code
``MOCK`` so the whole Phase 25 matrix is exercisable without any vendor.
"""

from __future__ import annotations

from datetime import datetime, timezone
from typing import Optional

from app.services.pos_integration.base import (
    POSAuthError,
    POSConnectionError,
    POSFetchResult,
    POSProvider,
    normalize_product_record,
    register_provider,
)

INVALID_API_KEY = "invalid-key"


def _as_datetime(value) -> Optional[datetime]:
    if value is None:
        return None
    if isinstance(value, datetime):
        return value if value.tzinfo else value.replace(tzinfo=timezone.utc)
    return datetime.fromisoformat(str(value))


class MockPOSProvider(POSProvider):
    code = "MOCK"
    display_name = "Mock POS (built-in)"
    supports_incremental = True

    def __init__(self) -> None:
        # api_key → {pos_product_code → raw record dict}
        self._catalogs: dict[str, dict] = {}
        self._outage = False

    # ── Test helpers ──────────────────────────────────────────────────────
    def seed_catalog(self, api_key: str, records: list[dict]) -> None:
        """Replace the catalog bound to ``api_key`` with ``records``."""
        self._catalogs[api_key] = {r["pos_product_code"]: dict(r) for r in records}

    def upsert_record(self, api_key: str, record: dict) -> None:
        """Insert/update one record — drives incremental-sync scenarios."""
        self._catalogs.setdefault(api_key, {})[record["pos_product_code"]] = dict(record)

    def remove_record(self, api_key: str, pos_product_code: str) -> None:
        self._catalogs.get(api_key, {}).pop(pos_product_code, None)

    def set_outage(self, enabled: bool = True) -> None:
        """Simulate the POS being unreachable (network failure)."""
        self._outage = enabled

    def catalog_size(self, api_key: str) -> int:
        return len(self._catalogs.get(api_key, {}))

    # ── Internals ─────────────────────────────────────────────────────────
    def _store(self, credentials: dict) -> dict:
        if self._outage or credentials.get("simulate_outage"):
            raise POSConnectionError("Mock POS is unreachable (simulated outage)")
        api_key = credentials.get("api_key")
        if not api_key:
            raise POSAuthError("Missing api_key for Mock POS")
        if api_key == INVALID_API_KEY or credentials.get("reject_auth"):
            raise POSAuthError(f"Mock POS rejected credentials '{api_key}'")
        return self._catalogs.setdefault(api_key, {})

    # ── POSProvider contract ──────────────────────────────────────────────
    def test_connection(self, credentials: dict) -> dict:
        store = self._store(credentials)
        return {
            "ok": True,
            "provider": self.code,
            "display_name": self.display_name,
            "product_count": len(store),
        }

    def fetch_products(
        self,
        credentials: dict,
        since: Optional[str] = None,
        limit: int = 500,
    ) -> POSFetchResult:
        store = self._store(credentials)
        rows = list(store.values())

        since_dt = _as_datetime(since) if since else None
        if since_dt is not None:
            rows = [r for r in rows if (_as_datetime(r.get("updated_at")) or datetime.min.replace(tzinfo=timezone.utc)) > since_dt]

        rows.sort(key=lambda r: _as_datetime(r.get("updated_at")) or datetime.min.replace(tzinfo=timezone.utc))
        page = rows[: max(int(limit), 1)]
        items = [normalize_product_record(r) for r in page]

        cursor: Optional[str] = None
        if page:
            latest = max(_as_datetime(r.get("updated_at")) for r in page)
            cursor = latest.isoformat()
        elif since_dt is not None:
            cursor = since_dt.isoformat()

        return POSFetchResult(items=items, cursor=cursor, has_more=len(rows) > len(page))


# Module-level singleton registered on import (see package __init__).
mock_pos_provider = MockPOSProvider()
register_provider(mock_pos_provider)
