"""The app's wiring, pinned at the level a customer actually touches.

Unit tests exercise route FUNCTIONS, which proves the handler logic. This file
proves the app SERVES those handlers: every customer-facing URL contract the
milestone depends on is asserted against the live OpenAPI document, which is
the exact set of strings (prefix + path, `{param}` included) a device requests.

Why OpenAPI paths and not `app.routes`: this FastAPI stores each
`include_router(...)` as an `_IncludedRouter` whose `.path` is None, so a flat
read of `app.routes` sees only the docs scaffolding while 333 real paths hide
in the spec. Asserting on the spec is strictly stronger — it is the URLs.
"""

import os
import sys
from pathlib import Path

BACKEND_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BACKEND_DIR))

os.environ.setdefault("ENVIRONMENT", "test")
os.environ.setdefault("HYPERLOCAL_ENV", "test")

from app.core.config import settings  # noqa: E402

settings.RATE_LIMIT_ENABLED = False


def _served_paths() -> set[str]:
    from app.main import app

    return set(app.openapi().get("paths", {}))


def _under(prefix: str, *routes: str) -> tuple[str, ...]:
    """Builds the full served URLs from the one configured prefix.

    The prefix is read from settings, not repeated here: a prefix change then
    breaks construction (loud) instead of silently asserting the old spelling
    (quiet and wrong).
    """
    return tuple(f"{prefix.rstrip('/')}{route}" for route in routes)


# ── Discovery: the card can only show what these return ───────────────────
def test_discovery_contracts_are_mounted():
    paths = _served_paths()
    prefix = settings.API_PREFIX

    for expected in _under(
        prefix,
        "/shops/nearby",
        "/shops/public/{shop_id}",
        "/home/feed",
        "/saved-shops",
        "/transport/providers/by-shop/{shop_id}",
        "/restaurants/by-shop/{shop_id}",
    ):
        assert expected in paths, f"{expected} is not served by the app"


# ── The quote lifecycle a customer walks: request → list → accept → booking ─
def test_transport_customer_lifecycle_is_walkable():
    """A missing middle link is invisible to unit tests but breaks the customer.

    The specific failure this guards: a customer could once request a quote and
    accept one by id, but nothing listed their own quotes — so the provider's
    price was unreachable and `accept` could never be called from the app. Each
    link below must exist or that dead end returns.
    """
    paths = _served_paths()
    prefix = settings.API_PREFIX

    for expected in _under(
        prefix,
        "/transport/quotes",  # request + the customer's own list
        "/transport/quotes/{quote_id}",  # one quote, incl. the quoted price
        "/transport/quotes/{quote_id}/accept",  # accept -> booking
        "/transport/bookings",  # the customer's own bookings
        "/transport/bookings/{booking_id}",
        "/transport/bookings/{booking_id}/cancel",
    ):
        assert expected in paths, f"{expected} is not served by the app"


# ── The spec itself must build ──────────────────────────────────────────────
def test_the_openapi_document_builds():
    """A malformed schema raises only when the spec is generated.

    This is where a Pydantic model that cannot be serialised is actually caught,
    long before a customer's request would hit it.
    """
    from app.main import app

    schema = app.openapi()
    assert schema["openapi"].startswith("3.")
    paths = schema["paths"]
    assert len(paths) > 100, (
        f"only {len(paths)} paths — the routers are not mounted"
    )


# ── Customer support: a report must be readable back, not just filable ──────
def test_customer_support_intake_and_history_share_one_url():
    """Both verbs on ONE resource, because the report history screen reads it.

    `POST /support/issues` alone was the whole feature for a while: the app could
    FILE a report and never read one back, so "we have your report" was the last
    word the app ever said. The customer app's report-history screen
    (`/support/issues` in the router) reads the GET on this same path, so a GET
    that disappears breaks a shipped screen — and a POST that disappears breaks
    the form that feeds it.

    Asserted on the OpenAPI document because that is the exact URL a device
    requests, and with both verbs checked so one cannot be dropped silently.
    """
    from app.main import app

    url = f"{settings.API_PREFIX.rstrip('/')}/support/issues"
    operations = app.openapi().get("paths", {}).get(url)
    assert operations is not None, f"{url} is not served by the app"
    for verb in ("get", "post"):
        assert verb in operations, f"{url} does not serve {verb.upper()}"

