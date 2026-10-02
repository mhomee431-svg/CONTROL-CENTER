"""Customer-facing transport trips: quotes, accepting, cancelling.

These pin the half of the flow that connects a REQUEST to a BOOKING. The routes
already allowed a customer to request a quote and accept one by id, but nothing
let them LIST their own quotes — so the provider's price was unreachable and
`accept_quote` could never be called from the app. These tests cover that listing
and the access rules around it, DB-free.
"""

import asyncio
import json
import os
import sys
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import MagicMock, patch

import pytest

BACKEND_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BACKEND_DIR))

os.environ.setdefault("ENVIRONMENT", "test")
os.environ.setdefault("HYPERLOCAL_ENV", "test")

from app.core.config import settings  # noqa: E402

settings.RATE_LIMIT_ENABLED = False


def _quote(**overrides):
    quote = SimpleNamespace(
        id=7,
        provider_id=9001,
        customer_user_id=1,
        status="REQUESTED",
        trip_purpose="AIRPORT",
        pickup_address="Connaught Place",
        destination_address="IGI Airport",
        trip_date="2026-03-07",
        trip_days=1,
        passenger_count=2,
        quote_amount=0,
        currency="INR",
        notes=None,
        created_at="2026-02-01T10:00:00",
        provider=SimpleNamespace(company_name="Raftaar City Movers"),
    )
    for key, value in overrides.items():
        setattr(quote, key, value)
    return quote


def _db_returning(quotes):
    """A session whose `execute(...).scalars().all()` yields [quotes]."""
    db = MagicMock()
    db.execute.return_value.scalars.return_value.all.return_value = quotes
    return db


def _body(response):
    return json.loads(bytes(response.body))["data"]


# ── The listing itself ──────────────────────────────────────────────────────
def test_a_requested_quote_is_listed_without_a_price():
    """A quote nobody has answered must not carry the column's zero default.

    `quote_amount` is 0 on a fresh row, and "₹0" would read as a free trip.
    """
    from app.services import transport_service

    result = transport_service.get_user_quotes(_db_returning([_quote()]), user_id=1)

    assert len(result) == 1
    assert result[0]["provider_name"] == "Raftaar City Movers"
    assert result[0]["pickup_address"] == "Connaught Place"
    assert result[0]["destination_address"] == "IGI Airport"
    # The point of the whole change: no price yet, and no ₹0.
    assert result[0]["quote_amount"] is None


def test_a_quoted_quote_carries_the_providers_price():
    from app.services import transport_service

    result = transport_service.get_user_quotes(
        _db_returning([_quote(status="QUOTED", quote_amount=650.0)]), user_id=1
    )

    assert result[0]["quote_amount"] == 650.0
    assert result[0]["currency"] == "INR"


def test_operator_only_fields_never_reach_the_customer():
    """`requested_by` is the requesting account's business, not the customer's."""
    from app.services import transport_service

    # The KEYS the summary publishes, not the words in its prose: a docstring that
    # explains the omission would otherwise fail this check.
    quote = _quote(requested_by=99)
    summary = transport_service._quote_summary(quote)
    assert "requested_by" not in summary
    assert "requested_by" not in summary.values()


def test_the_list_is_scoped_to_the_requesting_customer_only():
    """A provider must not be able to read trips through the customer route."""
    from app.services import transport_service

    db = _db_returning([_quote()])
    transport_service.get_user_quotes(db, user_id=42)

    statement = str(db.execute.call_args[0][0])
    assert "customer_user_id" in statement
    # A provider-side filter here would leak another customer's trips.
    assert "provider_id ==" not in statement


def test_a_status_filter_is_optional():
    from app.services import transport_service

    db = _db_returning([_quote(status="QUOTED")])
    transport_service.get_user_quotes(db, user_id=1, status="QUOTED")
    assert "status" in str(db.execute.call_args[0][0])


# ── Access rules ────────────────────────────────────────────────────────────
def test_another_customers_quote_is_forbidden():
    from app.services import transport_service

    db = MagicMock()
    # The row belongs to customer 1; the caller is customer 2.
    db.get.return_value = _quote(customer_user_id=1)
    with pytest.raises(PermissionError):
        transport_service.get_quote_detail(db, user_id=2, quote_id=7)


def test_an_unknown_quote_is_absent_not_forbidden():
    from app.services import transport_service

    db = MagicMock()
    db.get.return_value = None
    assert transport_service.get_quote_detail(db, user_id=1, quote_id=999) is None


def test_the_owner_reads_their_own_quote():
    from app.services import transport_service

    db = MagicMock()
    db.get.return_value = _quote(status="QUOTED", quote_amount=650.0)
    result = transport_service.get_quote_detail(db, user_id=1, quote_id=7)

    assert result is not None
    assert result["quote_amount"] == 650.0


# ── The route ───────────────────────────────────────────────────────────────
def test_the_route_lists_the_customers_quotes():
    from app.api.routes import transport as transport_routes

    db = MagicMock()
    with patch.object(
        transport_routes.transport_service,
        "get_user_quotes",
        return_value=[{"id": 7, "status": "QUOTED", "quote_amount": 650.0}],
    ) as listing:
        response = asyncio.run(
            transport_routes.get_my_quotes(
                status=None, db=db, current_user=SimpleNamespace(id=1)
            )
        )

    assert _body(response)[0]["quote_amount"] == 650.0
    # Scoped to the caller, never to a provider id from the request.
    assert listing.call_args.kwargs["user_id"] == 1


def test_the_route_reports_a_missing_quote_as_404():
    from app.api.routes import transport as transport_routes

    with patch.object(
        transport_routes.transport_service, "get_quote_detail", return_value=None
    ):
        response = asyncio.run(
            transport_routes.get_quote_detail(
                quote_id=999, db=MagicMock(), current_user=SimpleNamespace(id=1)
            )
        )

    assert response.status_code == 404
    assert json.loads(bytes(response.body))["error_code"] == "QUOTE_NOT_FOUND"


def test_the_quote_list_route_precedes_the_id_route():
    """`/quotes/{id}` must not swallow `/quotes` (and vice versa)."""
    from app.api.routes import transport as transport_routes

    paths = [r.path for r in transport_routes.router.routes if "quote" in r.path]
    assert "/transport/quotes" in paths
    assert "/transport/quotes/{quote_id}" in paths
    # Ordering is the contract: the collection is declared first, so no later edit
    # can make it unreachable behind the parameterized path.
    assert paths.index("/transport/quotes") < paths.index(
        "/transport/quotes/{quote_id}"
    )

