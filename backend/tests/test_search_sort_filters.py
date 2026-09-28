"""Tests for extended search sort (offers) and filters (offers_only, open_now, category/brand names)."""

import pytest
from app.search.ranking import SearchSort, default_sort_key
from app.search.engine import SearchParams, _resolve_sort


def test_resolve_offers_sort():
    assert _resolve_sort("offers") == SearchSort.OFFERS


def test_offers_sort_key_prioritizes_items_with_offers():
    items = [
        {"id": "sp_1", "product_name": "Item A", "offer_text": None, "price": 100, "mrp": 100, "relevance_score": 10.0},
        {"id": "sp_2", "product_name": "Item B", "offer_text": "10% OFF", "price": 90, "mrp": 100, "relevance_score": 5.0},
        {"id": "sp_3", "product_name": "Item C", "offer_text": None, "price": 80, "mrp": 100, "relevance_score": 8.0},  # has discount (mrp > price)
    ]
    key_func = default_sort_key(SearchSort.OFFERS)
    sorted_items = sorted(items, key=key_func)

    # Both Item B (offer_text) and Item C (discount) have offers -> rank ahead of Item A
    assert sorted_items[0]["id"] in ("sp_2", "sp_3")
    assert sorted_items[1]["id"] in ("sp_2", "sp_3")
    assert sorted_items[2]["id"] == "sp_1"


def test_search_params_accepts_all_filter_fields():
    params = SearchParams(
        q="soap",
        category_name="Personal Care",
        brand_name="Dettol",
        min_price=10.0,
        max_price=200.0,
        min_rating=4.0,
        in_stock_only=True,
        offers_only=True,
        open_now=True,
        sort="offers",
    )
    assert params.category_name == "Personal Care"
    assert params.brand_name == "Dettol"
    assert params.min_price == 10.0
    assert params.max_price == 200.0
    assert params.min_rating == 4.0
    assert params.in_stock_only is True
    assert params.offers_only is True
    assert params.open_now is True
    assert params.sort == "offers"


def test_dynamic_offers_and_open_filters():
    # Simulate post-enrichment filtering logic
    results = [
        {"id": "sp_1", "offer_text": "Buy 1 Get 1", "is_open_now": True},
        {"id": "sp_2", "offer_text": None, "is_open_now": True},
        {"id": "sp_3", "offer_text": "5% off", "is_open_now": False},
        {"id": "sp_4", "offer_text": None, "is_open_now": None},
    ]

    # Filter: offers_only
    offers_filtered = [r for r in results if bool(r.get("offer_text"))]
    assert len(offers_filtered) == 2
    assert {r["id"] for r in offers_filtered} == {"sp_1", "sp_3"}

    # Filter: open_now
    open_filtered = [r for r in results if r.get("is_open_now") is True]
    assert len(open_filtered) == 2
    assert {r["id"] for r in open_filtered} == {"sp_1", "sp_2"}

    # Both: offers_only and open_now
    both_filtered = [
        r for r in results
        if bool(r.get("offer_text")) and r.get("is_open_now") is True
    ]
    assert len(both_filtered) == 1
    assert both_filtered[0]["id"] == "sp_1"
