"""Customer support tickets — the shopper-facing half of the complaints queue.

The customer app's *Report an issue* / *Contact us* screens previously had
NOWHERE to send a report: the only intake route was
``/shopkeeper/support/tickets``, so a Send button would have silently discarded
what the customer typed. These tests cover the new ``/support/issues`` surface
against a REAL database, covering:

  * the customer taxonomy, and the rejection of the shopkeeper's codes
  * ticket creation (subject derivation, reference, real triage status)
  * reporter scoping — one shopper can never read another shopper's tickets
  * the HTTP surface (auth required, 201/422 shape)
  * that a shopper naming a shop is recorded as CONTEXT, never authorized
    against it (the shopkeeper route's 403 must not leak into this one)

Reuses the fixtures in ``test_shopkeeper_support`` so both audiences are proven
to share one storage and one taxonomy, with no duplicated test scaffolding.
"""

import os
import sys
from pathlib import Path

BACKEND_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BACKEND_DIR))

os.environ.setdefault("ENVIRONMENT", "test")
os.environ.setdefault("HYPERLOCAL_ENV", "test")

import pytest  # noqa: E402

from app.core.config import settings  # noqa: E402
from app.core.exceptions import NotFoundError, ValidationError  # noqa: E402
from app.models.admin import AuditLog, Complaint  # noqa: E402
from app.services import support_service  # noqa: E402

# The DB/client fixtures and the user/shop factories are shared verbatim with
# the shopkeeper suite: the whole point is that both audiences are the same
# system, so they must not be allowed to drift into two implementations.
from tests.test_shopkeeper_support import (  # noqa: E402,F401
    client,
    db,
    headers_for,
    make_shop,
    make_user,
    own,
)

ISSUES_PATH = f"{settings.API_PREFIX}/support/issues"


# ── Taxonomy ──────────────────────────────────────────────────────────────
class TestCustomerTaxonomy:
    """A shopper's ticket must land in a queue the support team can filter."""

    # The exact codes the Flutter `SupportIssueCategory` enum sends. Pinned so
    # a rename on either side fails a test instead of silently storing free text.
    CUSTOMER_CODES = {
        "CUST_WRONG_PRICE",
        "CUST_AVAILABILITY",
        "CUST_WRONG_PRODUCT",
        "CUST_SHOP_ISSUE",
        "CUST_APP_BUG",
        "CUST_ACCOUNT",
        "CUST_PRIVACY",
        "CUST_OTHER",
    }

    def test_customer_codes_match_the_client_contract(self):
        assert set(support_service.CUSTOMER_CATEGORIES) == self.CUSTOMER_CODES

    @pytest.mark.parametrize("code", sorted(self.CUSTOMER_CODES))
    def test_every_customer_code_is_accepted(self, code):
        assert (
            support_service.normalize_category(
                code, allowed=support_service.CUSTOMER_CATEGORIES
            )
            == code
        )

    def test_codes_are_case_insensitive_and_trimmed(self):
        assert (
            support_service.normalize_category(
                "  cust_wrong_price ",
                allowed=support_service.CUSTOMER_CATEGORIES,
            )
            == "CUST_WRONG_PRICE"
        )

    def test_a_shopkeeper_code_is_rejected_for_a_customer(self):
        # The regression this guards: the union default would accept `APP_POS`
        # from a shopper and file a customer's bug report into the merchant
        # triage queue.
        with pytest.raises(ValidationError) as err:
            support_service.normalize_category(
                "APP_POS", allowed=support_service.CUSTOMER_CATEGORIES
            )
        assert err.value.status_code == 422
        assert "CUST_OTHER" in err.value.data["allowed_categories"]
        assert "APP_POS" not in err.value.data["allowed_categories"]

    def test_a_customer_code_is_rejected_for_a_shopkeeper(self):
        with pytest.raises(ValidationError):
            support_service.normalize_category(
                "CUST_WRONG_PRICE", allowed=support_service.CATEGORIES
            )

    def test_the_default_scope_accepts_both_audiences(self):
        # Existing callers that pass no scope keep working unchanged.
        assert support_service.normalize_category("APP_OTHER") == "APP_OTHER"
        assert support_service.normalize_category("CUST_OTHER") == "CUST_OTHER"

    def test_the_two_audiences_share_no_codes(self):
        # A code meaning two different things to two teams is worse than a
        # missing code, because nobody can filter on it.
        assert not set(support_service.CATEGORIES) & set(
            support_service.CUSTOMER_CATEGORIES
        )

    def test_every_code_has_a_human_label(self):
        for code in support_service.ALL_CATEGORIES:
            assert support_service.ALL_CATEGORIES[code]
