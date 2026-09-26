"""Unit tests for search open/order-acceptance enrichment.

No database required: the enrichment is exercised against a minimal session
stand-in that exposes only ``query()``. This keeps the tests fast and proves
the contract that matters — every result always carries both keys, and a
failed enrichment never breaks the search response.
"""

from types import SimpleNamespace

from app.search.engine import _attach_shop_open_state


class _FakeQuery:
    def __init__(self, shops):
        self._shops = shops

    def filter(self, *args, **kwargs):
        return self

    def all(self):
        return self._shops


class _FakeDB:
    """Minimal Session stand-in: just ``query(model)``."""

    def __init__(self, shops):
        self._shops = shops

    def query(self, model):
        return _FakeQuery(self._shops)


class _BrokenDB:
    """Simulates a database failure during enrichment."""

    def query(self, model):
        raise RuntimeError("connection lost")


def _shop(shop_id, *, open_24x7=True, accepting=True):
    return SimpleNamespace(
        id=shop_id,
        is_open_24x7=open_24x7,
        is_accepting_orders=accepting,
        holidays=[],
        hours=[],
    )


def test_enrichment_reports_open_24x7_shop_as_open():
    results = [{"id": "sp_1", "shop_id": 7}]
    _attach_shop_open_state(_FakeDB([_shop(7, accepting=True)]), results)

    assert results[0]["is_open_now"] is True
    assert results[0]["is_accepting_orders"] is True


def test_enrichment_reports_closed_when_shop_has_no_hours():
    # Not 24x7 and no opening hours configured -> closed, per is_shop_open.
    results = [{"id": "sp_1", "shop_id": 7}]
    _attach_shop_open_state(
        _FakeDB([_shop(7, open_24x7=False, accepting=True)]), results
    )

    assert results[0]["is_open_now"] is False


def test_enrichment_flags_open_shop_that_stopped_accepting_orders():
    results = [{"id": "sp_1", "shop_id": 7}]
    _attach_shop_open_state(_FakeDB([_shop(7, accepting=False)]), results)

    assert results[0]["is_open_now"] is True
    assert results[0]["is_accepting_orders"] is False


def test_enrichment_keeps_unknown_when_shop_not_on_page():
    # The shop was not returned by the page query -> unknown, never guessed.
    results = [{"id": "sp_1", "shop_id": 999}]
    _attach_shop_open_state(_FakeDB([_shop(7)]), results)

    assert results[0]["is_open_now"] is None
    assert results[0]["is_accepting_orders"] is None


def test_enrichment_defaults_keys_for_results_without_shop_id():
    results = [{"id": "sp_1"}]
    _attach_shop_open_state(_FakeDB([_shop(7)]), results)

    assert "is_open_now" in results[0]
    assert "is_accepting_orders" in results[0]
    assert results[0]["is_open_now"] is None
    assert results[0]["is_accepting_orders"] is None


def test_enrichment_survives_database_failure():
    # Enrichment is best-effort: a DB error must leave the keys present-as-
    # unknown and never propagate (which would fail the whole search).
    results = [{"id": "sp_1", "shop_id": 7}]
    _attach_shop_open_state(_BrokenDB(), results)

    assert results[0]["is_open_now"] is None
    assert results[0]["is_accepting_orders"] is None