"""Customer-facing shop profile response contract.

Covers the customer-facing `GET /shops/{shop_id}` payload, specifically the
public contact surface that the customer Shop Profile screen consumes.
"""

import asyncio
import json
import os
import sys
from datetime import datetime, timezone
from pathlib import Path
from unittest.mock import MagicMock, patch

BACKEND_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BACKEND_DIR))

os.environ.setdefault("ENVIRONMENT", "test")
os.environ.setdefault("HYPERLOCAL_ENV", "test")

from app.core.config import settings  # noqa: E402

settings.RATE_LIMIT_ENABLED = False


def _make_shop(alternate_phone):
    """A real, in-memory Shop row with only the columns this route reads.

    A real model (not a stub object) matters: the route serializes through
    `ShopDetailResponse.model_validate(shop)`, which needs the ORM attributes.
    """
    from app.models.shop import Shop, ShopStatus

    shop = Shop()
    shop.id = 7
    shop.name = "Gupta Mobile"
    shop.slug = "gupta-mobile"
    shop.phone = "+919876543210"
    shop.alternate_phone = alternate_phone
    shop.email = "care@example.com"
    shop.description = "Trusted electronics store."
    shop.tagline = None
    shop.image_url = None
    shop.cover_image_url = None
    shop.logo_url = None
    shop.rating = 4.6
    shop.review_count = 342
    shop.is_verified = True
    shop.is_featured = False
    shop.is_open_24x7 = False
    shop.is_accepting_orders = True
    shop.subcategories = None
    shop.latitude = 28.7150
    shop.longitude = 77.1150
    shop.min_order_amount = None
    shop.delivery_radius_km = None
    shop.delivery_fee = None
    shop.free_delivery_above = None
    shop.is_delivery_available = True
    shop.is_pickup_available = True
    shop.established_year = None
    shop.status = ShopStatus.ACTIVE
    shop.created_at = datetime.now(timezone.utc)
    shop.updated_at = datetime.now(timezone.utc)
    return shop


def _profile_payload(shop):
    """Invoke the route coroutine directly and return its `data` payload.

    The route returns a `JSONResponse` (not a dict), so the body is decoded.
    """
    from app.api.routes import shops as shops_routes

    db = MagicMock()
    db.query.return_value.filter.return_value.all.return_value = []
    db.query.return_value.filter.return_value.first.return_value = None

    with (
        patch.object(
            shops_routes.shop_service, "get_shop_detail", return_value=shop
        ),
        patch.object(shops_routes.shop_service, "is_shop_open", return_value=True),
        patch.object(
            shops_routes.shop_service, "parse_subcategories", return_value=[]
        ),
    ):
        response = asyncio.run(
            shops_routes.get_shop(
                shop_id=7,
                latitude=None,
                longitude=None,
                db=db,
            )
        )
    return json.loads(bytes(response.body))["data"]


def test_shop_profile_exposes_secondary_phone():
    """The alternate phone must reach the client as `secondary_phone`."""
    data = _profile_payload(_make_shop("+919876543219"))

    assert data["secondary_phone"] == "+919876543219"
    # The primary number keeps its own field — the two must not collide.
    assert data["phone"] == "+919876543210"


def test_shop_profile_secondary_phone_is_null_when_not_set():
    """A shop with no alternate phone reports null, not a fabricated number.

    The client treats a missing secondary as "no such contact action", so a
    placeholder here would render a dead call/WhatsApp row.
    """
    data = _profile_payload(_make_shop(None))

    assert data["secondary_phone"] is None


def test_shop_profile_secondary_phone_preserves_formatting():
    """The value is passed through verbatim; the client normalizes for `tel:`."""
    data = _profile_payload(_make_shop("+91 98765 43219"))

    assert data["secondary_phone"] == "+91 98765 43219"


def test_shop_model_stores_alternate_phone_column():
    """The column backing `secondary_phone` must exist on the Shop model."""
    from app.models.shop import Shop

    assert "alternate_phone" in Shop.__table__.columns


# ── The authorization boundary on GET /shops/{id} ───────────────────────────
#
# `GET /shops/{id}` is reachable WITHOUT a token — a customer browsing a shop
# must be able to open it. That is only safe because the response carries NO
# private shopkeeper data. These tests exist so nobody re-adds `owners`,
# `managers`, `verifications` or `documents` to that payload: the moment they
# come back, every shop's owner roster is public to anyone who guesses an id.
#
# The legitimate consumer for those fields is `GET /shops/my/shops/{id}`, which
# requires a token AND checks ownership via `has_shop_access`.

_PRIVATE_SHOP_FIELDS = ("owners", "managers", "verifications", "documents")


def test_public_shop_route_never_serializes_private_shopkeeper_data():
    """The no-token shop route must not emit the shopkeeper's private data."""
    data = _profile_payload(_make_shop(None))

    for field in _PRIVATE_SHOP_FIELDS:
        assert field not in data, (
            f"'{field}' is shopkeeper-private and must not be served by the "
            f"unauthenticated /shops/{{id}} route"
        )


def test_public_shop_route_still_serves_the_customer_contact_surface():
    """Removing the private fields must not empty the customer-facing payload.

    Guards against "fix the leak by deleting everything": the shop's name, phone
    and rating are what a customer came for and must still be present.
    """
    data = _profile_payload(_make_shop("+919876543219"))

    assert data["name"] == "Gupta Mobile"
    assert data["phone"] == "+919876543210"
    assert data["secondary_phone"] == "+919876543219"
    assert data["rating"] == 4.6
