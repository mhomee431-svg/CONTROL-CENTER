"""The DATA SOURCE INDICATOR, backend half.

The spec asks the app to say how data was last updated: manual, barcode,
Excel/CSV, POS. The model has carried ``ShopProduct.source`` from the start, and
every writer goes through one convergence point (``product_convergence``), so the
fact is always recorded.

It was simply never SENT. The row carried price, stock, freshness and
``last_inventory_update`` but no ``source``, so the client fell back to its
default label - which reads "manually" - for every listing in the shop. A price
pushed by POS was presented as a hand edit. An indicator that is confidently
wrong is worse than no indicator, because the shopkeeper trusts it.

These tests pin that the serializers the app actually reads carry the
provenance, and that a listing with nothing recorded says so rather than
guessing.
"""

from types import SimpleNamespace

import pytest

from app.models.product import FreshnessStatus, InventorySource
from app.services import shopkeeper_service as svc


def _listing(source=InventorySource.POS_INTEGRATION):
    return SimpleNamespace(
        id=11,
        shop_id=10,
        sku="RICE-1KG",
        product_master_id=5,
        variant_id=None,
        status=SimpleNamespace(value="ACTIVE"),
        price=499,
        mrp=600,
        is_active=True,
        is_available=True,
        is_featured=False,
        low_stock_threshold=5,
        last_inventory_update=None,
        last_price_update=None,
        source=source,
        freshness_status=FreshnessStatus.RECENTLY_UPDATED,
        product_master=None,
    )


class TestTheProductRowCarriesProvenance:
    def test_it_says_who_wrote_the_listing(self):
        row = svc.serialize_product(_listing(), inv=None)
        assert row["source"] == "POS_INTEGRATION"

    @pytest.mark.parametrize(
        "source",
        [
            InventorySource.MANUAL,
            InventorySource.BARCODE_SCAN,
            InventorySource.EXCEL_UPLOAD,
            InventorySource.POS_INTEGRATION,
            InventorySource.SYSTEM,
        ],
    )
    def test_every_written_source_survives_serialisation(self, source):
        """Each writer - barcode, Excel, POS, manual - has to reach the app, or
        the indicator works only for the case someone typed by hand."""
        row = svc.serialize_product(_listing(source=source), inv=None)
        assert row["source"] == source.value

    def test_freshness_and_last_update_still_travel(self):
        row = svc.serialize_product(_listing(), inv=None)
        # The indicator is additive: it must not cost the shopkeeper the
        # staleness signal that was already there.
        assert row["freshness_status"] == FreshnessStatus.RECENTLY_UPDATED.value
        assert "last_inventory_update" in row

    def test_a_listing_with_no_source_reports_none_rather_than_a_guess(self):
        row = svc.serialize_product(_listing(source=None), inv=None)
        assert row["source"] is None


class TestEveryListSerializerCarriesIt:
    def test_the_inventory_list_has_its_own_keys(self):
        """The inventory list is a SEPARATE serialiser from the product row; a
        key added to one and forgotten in the other is how an indicator ends up
        half-working, with the same field disagreeing between two screens."""
        import inspect

        source = inspect.getsource(svc.inventory_overview)
        assert '"source"' in source
        assert '"freshness_status"' in source


if __name__ == "__main__":
    raise SystemExit(pytest.main([__file__, "-v"]))
