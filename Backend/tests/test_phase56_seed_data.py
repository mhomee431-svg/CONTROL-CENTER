"""Tests for Phase 56 real database seed data (db_seed/seed_business_domains.py).

Verifies:
- All 11 approved business domains are represented
- Grocery/general food retail is NOT in the catalog (spec rule 13)
- Realistic price ranges (min <= max, positive)
- 10 Indian cities with valid coordinates
- Brand and shop name coverage for every domain
"""
import sys
from pathlib import Path

import pytest

# Make db_seed importable
REPO_ROOT = Path(__file__).resolve().parents[2]
DB_SEED = REPO_ROOT / "db_seed"
if str(DB_SEED) not in sys.path:
    sys.path.insert(0, str(DB_SEED))

from seed_business_domains import (  # noqa: E402
    BRAND_NAMES,
    BUSINESS_DOMAIN_CATALOG,
    SEED_CITIES,
    SHOP_NAMES,
    build_domain_catalog,
    count_products,
)


APPROVED_DOMAINS = {
    "Pharmacy & Healthcare",
    "Beauty & Personal Care",
    "Furniture & Home Care",
    "Household Goods",
    "Sports, Fitness & Outdoor",
    "Books, Media & Stationery",
    "Automotive Parts & Tools",
    "Hardware",
    "Restaurants",
    "Transport",
    "Personal Transport & Travel",
}

# Spec rule 13: grocery RETAIL is out of scope (packaged staples like
# "Basmati Rice 1 kg"). Restaurant dishes (e.g. "Veg Fried Rice") are in scope
# as the Restaurants domain is discovery-only, so the check skips that domain.
FORBIDDEN_TERMS = {
    "atta", "flour", "basmati", "maida", "besan",
    "toor dal", "moong dal", "sonam masoori",
    "iodised salt", "glucose biscuit", "namkeen",
    "maggi", "toned milk", "fresh paneer",
}


class TestDomainCoverage:
    def test_all_11_domains_present(self):
        domains = {name for name, _ in BUSINESS_DOMAIN_CATALOG}
        assert domains == APPROVED_DOMAINS

    def test_exactly_11_domains(self):
        assert len(BUSINESS_DOMAIN_CATALOG) == 11

    def test_no_grocery_items(self):
        """Spec rule 13 — grocery/general food retail must not appear."""
        import re
        catalog_text = str(BUSINESS_DOMAIN_CATALOG).lower()
        for term in FORBIDDEN_TERMS:
            # Word-boundary match so 'rice' doesn't false-positive on 'price'
            pattern = rf"\b{re.escape(term)}\b"
            assert not re.search(pattern, catalog_text), f"Found forbidden grocery term: {term}"

    def test_every_domain_has_products(self):
        for name, items in BUSINESS_DOMAIN_CATALOG:
            assert len(items) >= 5, f"Domain {name} has too few products ({len(items)})"


class TestPriceSanity:
    def test_price_min_positive(self):
        for name, items in BUSINESS_DOMAIN_CATALOG:
            for item, unit, lo, hi, packs in items:
                assert lo > 0, f"{name}/{item}: price_min must be positive"

    def test_price_min_lte_max(self):
        for name, items in BUSINESS_DOMAIN_CATALOG:
            for item, unit, lo, hi, packs in items:
                assert lo <= hi, f"{name}/{item}: price_min ({lo}) > price_max ({hi})"

    def test_unit_not_empty(self):
        for name, items in BUSINESS_DOMAIN_CATALOG:
            for item, unit, *_ in items:
                assert unit and unit.strip(), f"{name}/{item}: empty unit"

    def test_packs_non_empty(self):
        for name, items in BUSINESS_DOMAIN_CATALOG:
            for item, unit, lo, hi, packs in items:
                assert len(packs) >= 1, f"{name}/{item}: no pack sizes"


class TestGeoSeeds:
    def test_10_cities(self):
        assert len(SEED_CITIES) == 10

    def test_coordinates_valid_india(self):
        """India bounds: lat 6–37, lon 68–97."""
        for city, state, lat, lon in SEED_CITIES:
            assert 6.0 < lat < 37.0, f"{city}: latitude {lat} outside India"
            assert 68.0 < lon < 97.0, f"{city}: longitude {lon} outside India"

    def test_city_names_unique(self):
        names = [c[0] for c in SEED_CITIES]
        assert len(names) == len(set(names))


class TestBrandAndShopCoverage:
    def test_brands_for_every_domain(self):
        domains = {name for name, _ in BUSINESS_DOMAIN_CATALOG}
        assert set(BRAND_NAMES.keys()) == domains

    def test_shops_for_every_domain(self):
        domains = {name for name, _ in BUSINESS_DOMAIN_CATALOG}
        assert set(SHOP_NAMES.keys()) == domains

    def test_min_4_shops_per_domain(self):
        for domain, shops in SHOP_NAMES.items():
            assert len(shops) >= 4, f"{domain}: only {len(shops)} shops"

    def test_min_4_brands_per_domain(self):
        for domain, brands in BRAND_NAMES.items():
            assert len(brands) >= 4, f"{domain}: only {len(brands)} brands"


class TestHelpers:
    def test_build_domain_catalog_returns_same(self):
        assert build_domain_catalog() is BUSINESS_DOMAIN_CATALOG

    def test_count_products(self):
        total = count_products()
        assert total > 100, f"Expected >100 products, got {total}"
        # Manually recompute
        manual = sum(len(packs) for _, items in BUSINESS_DOMAIN_CATALOG for _, _, _, _, packs in items)
        assert total == manual