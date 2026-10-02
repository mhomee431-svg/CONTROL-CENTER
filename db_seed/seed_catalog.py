"""Synthetic seed catalog for the load/QA seeder.

WHY THIS FILE IS SYNTHETIC DATA
-------------------------------
`seed_data.py` is explicitly a DUMMY seeder, not a production importer: every
slug it writes is prefixed ``dummy-``, every row is stamped with ``SEED_TAG``,
and every image URL points at the reserved ``cdn.example.in``. This module is
therefore deliberately synthetic too -- it exists to create a realistic *shape*
of catalogue (categories, brands, products, packs, price bands) so load tests,
search-index tests and the shop-inventory fan-out have something to bite on.

IT IS NOT A PRODUCT CATALOGUE. Nothing here describes a real trade. Do not
treat these names as reference data.

CONTRACT (consumed by ``seed_data.py``)
---------------------------------------
``BRANDS``
    Non-empty sequence of brand names. ``seed_data.py`` indexes ``BRANDS[0]``
    as a fallback, so an empty list would raise ``IndexError``.
``CATALOG``
    Sequence of ``(category_name, items)`` pairs. The category name becomes a
    row in ``categories``; ``items`` is that category's product list.
``flattened_items()``
    Flattens every category's items into one sequence. Each item is a
    6-tuple ``(category, item_name, unit, price_min, price_max, packs)``,
    where ``packs`` is a non-empty sequence of pack labels indexed with
    ``packs[i % len(packs)]``.

DETERMINISM IS A REQUIREMENT, NOT A NICETY
------------------------------------------
The seeder walks this data with ``items[p % len(items)]`` and derives ids and
prices purely from ``p``, so the same database contents come out on every run.
Anything random here would make load-test results incomparable between runs.

``price_min``/``price_max`` are integer rupees and must satisfy
``price_min <= price_max``; the consumer computes
``price_min + ((p * 7) % (price_max - price_min + 1))`` and would divide by
zero otherwise.
"""

from __future__ import annotations

# ── Brands ────────────────────────────────────────────────────────────────
# Spread across the categories below so `seed_data.py`'s
# `brand_names[p % len(brand_names)]` produces plausible pairings rather than
# every product in a category sharing one brand.
BRANDS: list[str] = [
    "Dove",
    "Colgate",
    "Amul",
    "Surf Excel",
    "Britannia",
    "Tata Tea",
    "Saffola",
    "Head & Shoulders",
    "Vaseline",
    "Haldiram's",
    "Maggi",
    "Fortune",
    "Red Label",
    "Indukan",
    "Surf Excel Matic",
]




# ── Catalog ───────────────────────────────────────────────────────────────
# (category, [(item_name, unit, price_min, price_max, [pack labels]), ...])
#
# Category names intentionally match the customer app's approved product
# categories (`ApprovedCategories`), so seeded data renders in the app without
# a category remap.
CATALOG: list[tuple[str, list[tuple[str, str, int, int, list[str]]]]] = [
    (
        "Beauty & Personal Care",
        [
            ("Bath Bar", "soap", 60, 180, ["100g", "150g", "4x100g"]),
            ("Shampoo", "bottle", 180, 420, ["180ml", "340ml", "650ml"]),
            ("Conditioner", "bottle", 200, 480, ["180ml", "340ml"]),
            ("Body Lotion", "tube", 150, 400, ["200ml", "400ml"]),
            ("Face Wash", "tube", 120, 320, ["100ml", "150g"]),
            ("Deodorant", "stick", 140, 350, ["50g", "100g", "150g"]),
        ],
    ),
    (
        "Household Goods",
        [
            ("Dishwash Bar", "bar", 25, 70, ["100g", "4x100g"]),
            ("Detergent Powder", "box", 220, 650, ["1kg", "2kg", "5kg"]),
            ("Floor Cleaner", "bottle", 120, 400, ["500ml", "1L", "2L"]),
            ("Toilet Cleaner", "bottle", 90, 250, ["500ml", "1L"]),
            ("Scrub Pad", "pack", 20, 60, ["3pc", "6pc"]),
            ("Garbage Bag", "pack", 60, 180, ["30pc", "50pc", "100pc"]),
        ],
    ),
    (
        "Pharmacy & Healthcare",
        [
            ("Hand Sanitiser", "bottle", 120, 350, ["200ml", "500ml"]),
            ("Face Mask", "pack", 99, 399, ["4pc", "10pc"]),
            ("Cotton Buds", "pack", 40, 120, ["100pc", "200pc"]),
            ("Bandage Roll", "roll", 35, 110, ["10pc", "20pc"]),
        ],
    ),
    (
        "Grocery & Staples",
        [
            ("Basmati Rice", "bag", 180, 900, ["1kg", "5kg"]),
            ("Wheat Flour", "bag", 60, 400, ["1kg", "5kg", "10kg"]),
            ("Sunflower Oil", "bottle", 150, 700, ["500ml", "1L", "5L"]),
            ("Table Salt", "pack", 20, 60, ["500g", "1kg"]),
            ("Sugar", "bag", 45, 200, ["500g", "1kg", "5kg"]),
            ("Tea Powder", "box", 120, 500, ["100g", "250g", "500g"]),
        ],
    ),
    (
        "Snacks & Confectionery",
        [
            ("Biscuit", "packet", 20, 90, ["100g", "250g"]),
            ("Namkeen", "packet", 25, 120, ["100g", "200g"]),
            ("Chocolate Bar", "bar", 30, 150, ["45g", "90g", "4x45g"]),
            ("Beverage Mix", "jar", 120, 450, ["200g", "400g"]),
        ],
    ),
]


def flattened_items() -> list[tuple[str, str, str, int, int, list[str]]]:
    """Every item from every category, as one flat list.

    Order is deterministic (category order, then item order) because
    ``seed_data.py`` derives both product identity and price from an item's
    index, so a stable order is what keeps seeded data reproducible.
    """
    out: list[tuple[str, str, str, int, int, list[str]]] = []
    for category, items in CATALOG:
        for item_name, unit, price_min, price_max, packs in items:
            out.append((category, item_name, unit, price_min, price_max, packs))
    return out


if __name__ == "__main__":  # pragma: no cover - manual smoke check
    _items = flattened_items()
    print(f"brands={len(BRANDS)} categories={len(CATALOG)} items={len(_items)}")
    assert BRANDS, "BRANDS must be non-empty: seed_data.py indexes BRANDS[0]"
    assert _items, "flattened_items() must be non-empty"
    for _cat, _name, _unit, _lo, _hi, _packs in _items:
        assert _lo <= _hi, f"{_cat}/{_name}: price_min {_lo} > price_max {_hi}"
        assert _packs, f"{_cat}/{_name}: packs must be non-empty"
    print("contract OK; first item:", _items[0][:2])
