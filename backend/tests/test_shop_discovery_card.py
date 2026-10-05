"""Shop discovery: the fields the customer's Shop Card needs.

The card shows image, name, rating, distance, open/closed and verification, and
it can only show what the API actually sends. These tests pin the two payloads
behind the discovery rows — the home feed's `nearby_shops` and `/saved-shops` —
so a field silently disappearing breaks a test instead of quietly deleting a
badge from the card.

DB-free: the routes are exercised with a stubbed session.
"""

import asyncio
import json
import os
import sys
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import MagicMock, patch

BACKEND_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BACKEND_DIR))

os.environ.setdefault("ENVIRONMENT", "test")
os.environ.setdefault("HYPERLOCAL_ENV", "test")

from app.core.config import settings  # noqa: E402

settings.RATE_LIMIT_ENABLED = False

HOME_ROUTE = BACKEND_DIR / "app" / "api" / "routes" / "home.py"
SAVED_ROUTE = BACKEND_DIR / "app" / "api" / "routes" / "saved_shops.py"
SAVED_SCHEMA = BACKEND_DIR / "app" / "schemas" / "saved.py"


def _source(path: Path) -> str:
    return path.read_text(encoding="utf-8")


# ── The home feed's nearby shops ────────────────────────────────────────────
def test_nearby_shops_carry_the_open_closed_verdict():
    """The card's badge needs `is_open_now`; without it there is no badge.

    `is_accepting_orders` is sent too, because "open but not taking orders" is a
    real, distinct state the badge renders differently.
    """
    src = _source(HOME_ROUTE)
    assert '"is_open_now"' in src
    assert '"is_accepting_orders"' in src
    assert '"is_verified"' in src
    assert '"distance"' in src
    assert '"rating"' in src


def test_the_open_verdict_uses_the_shared_opening_hours_helper():
    """One clock, one verdict.

    Recomputing opening hours here would let the same shop read "Open" on the
    home row and "Closed" on its own profile.
    """
    src = _source(HOME_ROUTE)
    assert "from app.services.shop_service import is_shop_open" in src


def test_nearby_rows_keep_the_field_names_the_app_parses():
    """The app reads `image_url`, not `imageUrl`.

    This is a real regression class: json_serializable generated camelCase
    lookups for these models, so a payload that renamed a field would throw on
    the device. The names are asserted here as the contract.
    """
    src = _source(HOME_ROUTE)
    for field in ("id", "name", "image_url", "distance", "rating", "is_verified"):
        assert f'"{field}"' in src, f"{field} missing from the nearby-shop payload"


# ── /saved-shops ────────────────────────────────────────────────────────────
def test_saved_shop_schema_exposes_the_card_fields():
    src = _source(SAVED_SCHEMA)
    for field in (
        "distance_km",
        "is_verified",
        "is_open_now",
        "is_accepting_orders",
    ):
        assert field in src, f"{field} missing from SavedShopResponse"


def test_an_unreported_open_state_is_none_not_false():
    """A missing verdict must serialize as null.

    `is_open_now: bool = False` would tell every client "Closed" whenever the
    value was not computed — a fabricated fact rather than an absent one.
    """
    src = _source(SAVED_SCHEMA)
    assert "is_open_now: bool | None = None" in src
    assert "is_accepting_orders: bool | None = None" in src


def test_saved_shops_distance_requires_both_ends():
    """No coordinates must mean "no distance", not "0.0 km away"."""
    src = _source(SAVED_ROUTE)
    assert "latitude is not None and longitude is not None" in src
    assert "distance_km: float | None = None" in src


def test_saved_shops_reuses_the_shared_helpers():
    src = _source(SAVED_ROUTE)
    assert "resolve_shop_coordinates" in src
    assert "haversine_km" in src
    assert "is_shop_open" in src


def _stub_db(shop):
    """A session whose filters resolve to one saved row pointing at [shop]."""
    saved_row = SimpleNamespace(shop_id=5, created_at="2026-01-01T00:00:00")
    db = MagicMock()
    (
        db.query.return_value.filter.return_value.order_by.return_value.all
    ).return_value = [saved_row]
    db.query.return_value.filter.return_value.first.return_value = shop
    return db


def _list_saved(latitude, longitude, shop, open_now=True):
    """Runs the route with the shared helpers stubbed.

    `open_now` is passed explicitly rather than inferred from the shop, so the
    test states the verdict it wants instead of the assertion silently depending
    on the stub.
    """
    from app.api.routes import saved_shops as route

    with patch.object(
        route, "resolve_shop_coordinates", return_value=(85.13, 25.59)
    ), patch.object(route, "is_shop_open", return_value=open_now), patch.object(
        route, "haversine_km", return_value=2.468
    ):
        response = asyncio.run(
            route.list_saved_shops(
                latitude=latitude,
                longitude=longitude,
                current_user=SimpleNamespace(id=1),
                db=_stub_db(shop),
            )
        )
    return json.loads(bytes(response.body))["data"]["items"][0]


def _shop(**overrides):
    shop = SimpleNamespace(
        id=5,
        name="Sharma Kirana",
        address="Sector 18",
        image_url="/media/shop.png",
        rating=4.5,
        is_verified=True,
        is_accepting_orders=True,
        latitude=25.59,
        longitude=85.13,
    )
    for key, value in overrides.items():
        setattr(shop, key, value)
    return shop


def test_listing_saved_shops_returns_the_enriched_rows():
    """End-to-end through the route with a stubbed session."""
    row = _list_saved(25.6, 85.1, _shop())

    assert row["name"] == "Sharma Kirana"
    assert row["rating"] == 4.5
    assert row["is_open_now"] is True
    assert row["is_verified"] is True
    assert row["is_accepting_orders"] is True
    # Rounded to two places, like every other distance in this API.
    assert row["distance_km"] == 2.47


def test_listing_saved_shops_without_coordinates_omits_the_distance():
    """With location off, the list still works — it just has no distances."""
    row = _list_saved(None, None, _shop(rating=0, is_verified=False), open_now=False)

    # Null, not 0.0 — the app renders no distance chip at all for this.
    assert row["distance_km"] is None
    assert row["is_verified"] is False
    # A verdict the backend DID reach is kept, including a negative one: the app
    # needs `false` to render "Closed" rather than no badge.
    assert row["is_open_now"] is False
