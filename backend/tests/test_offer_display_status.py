"""The Active/Scheduled bullet of the offer spec, pinned where it is derived.

Stored `status` cannot say "ACTIVE but not started yet" or "ACTIVE but the
window closed", so `_offer_display_status` derives those from the date window.
The shopkeeper app's Active / Scheduled / Expired tabs read this field rather
than re-deriving dates on the client — so if the derivation drifts, a live
offer and a future one become indistinguishable with no client to blame.
"""

from datetime import datetime, timedelta, timezone

import pytest

from app.models.product import Offer, OfferStatus, OfferType
from app.services.shopkeeper_service import _offer_display_status

NOW = datetime(2026, 6, 15, 12, 0, tzinfo=timezone.utc)
FUTURE = NOW + timedelta(days=7)
PAST = NOW - timedelta(days=7)


def _offer(status, start, end) -> Offer:
    return Offer(
        shop_id=1,
        title="Sale",
        offer_type=OfferType.PERCENTAGE_DISCOUNT,
        status=status,
        start_date=start,
        end_date=end,
    )


class TestTheWindowIsWhatTheTabsRead:
    def test_an_active_offer_started_and_unfinished_is_active(self):
        assert _offer_display_status(_offer(OfferStatus.ACTIVE, PAST, FUTURE), NOW) == "ACTIVE"

    def test_an_active_offer_not_started_yet_is_scheduled(self):
        """The spec's "Scheduled" — only derivable from the window."""
        assert (
            _offer_display_status(_offer(OfferStatus.ACTIVE, FUTURE, FUTURE + timedelta(days=7)), NOW)
            == "SCHEDULED"
        )

    def test_an_active_offer_whose_window_closed_is_expired(self):
        assert (
            _offer_display_status(_offer(OfferStatus.ACTIVE, PAST, PAST + timedelta(days=1)), NOW)
            == "EXPIRED"
        )

    def test_a_draft_never_reads_as_live_just_because_its_window_opened(self):
        assert (
            _offer_display_status(_offer(OfferStatus.DRAFT, PAST, FUTURE), NOW) == "DRAFT"
        )

    def test_a_disabled_offer_never_reads_as_live(self):
        assert (
            _offer_display_status(_offer(OfferStatus.DISABLED, PAST, FUTURE), NOW)
            == "DISABLED"
        )

    def test_the_end_date_is_inclusive(self):
        """At exactly `end_date` the offer is still live.

        The comparison is strictly-before, so an end date of "today" keeps the
        offer running through today; it stops the moment the clock passes it.
        Asserted because the opposite reading is equally plausible and the two
        are indistinguishable until an offer silently outlives its window.
        """
        offer = _offer(OfferStatus.ACTIVE, PAST, NOW)
        assert _offer_display_status(offer, NOW) == "ACTIVE"

    def test_a_second_past_the_end_date_is_expired(self):
        offer = _offer(OfferStatus.ACTIVE, PAST, NOW)
        assert (
            _offer_display_status(offer, NOW + timedelta(seconds=1)) == "EXPIRED"
        )


if __name__ == "__main__":
    raise SystemExit(pytest.main([__file__, "-v"]))