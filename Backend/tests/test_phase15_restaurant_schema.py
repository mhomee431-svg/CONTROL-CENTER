"""Phase 15 - Restaurant Discovery schema verification (DB-free unit checks.

These tests require no live database. They statically validate the authored
Restaurant domain land (Master Spec §27, Rule 4). The migration chain
linear-head check lives in tests/test_phase4_rds.py; this module covers the
restaurant tables themselves plus the RDS verifier coverage.
"""

import py_compile

from pathlib import Path

BACKEND_DIR = Path(__file__).resolve().parents[1]
MIGRATION = BACKEND_DIR / "alembic" / "versions" / "0015_restaurant_discovery.py"
MODELS = BACKEND_DIR / "app" / "models" / "restaurant.py"
MODELS_INIT = BACKEND_DIR / "app" / "models" / "__init__.py"
VERIFIER = BACKEND_DIR / "scripts" / "verify_rds.py"


def _source(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def test_migration_0015_registered_linear():
    src = _source(MIGRATION)
    assert 'revision: str = "0015"' in src
    assert 'down_revision: Union[str, None] = "0014"' in src


def test_migration_creates_restaurant_tables():
    src = _source(MIGRATION)
    assert "restaurants" in src
    assert "restaurant_menu_categories" in src
    assert "restaurant_menu_items" in src


def test_restaurant_guardrail_columns():
    src = _source(MIGRATION)
    assert "uq_restaurants_shop_id" in src
    assert "shops.id" in src
    assert "ck_restaurant_menu_items_price_non_negative" in src
    assert "ck_restaurants_rating_range" in src
    assert "ck_restaurants_review_count_non_negative" in src


def test_restaurant_timestamps_and_soft_delete():
    src = _source(MIGRATION)
    assert "_timestamps()" in src
    assert "_soft_delete()" in src
    assert "created_at" in src
    assert "updated_at" in src
    assert "is_deleted" in src
    assert "deleted_at" in src
    assert src.count("*_soft_delete()") == 2


def test_restaurant_models_declared_and_exported():
    model_src = _source(MODELS)
    init_src = _source(MODELS_INIT)
    for cls in ("Restaurant", "RestaurantMenuCategory", "RestaurantMenuItem"):
        assert ("class " + cls + "(") in model_src
    for name in ("Restaurant", "RestaurantMenuCategory", "RestaurantMenuItem"):
        assert name in init_src


def test_verifier_covers_restaurant_tables():
    src = _source(VERIFIER)
    for table in ("restaurants", "restaurant_menu_categories", "restaurant_menu_items"):
        assert '"' + table + '"' in src


def test_migration_and_models_compile():
    for path in (MIGRATION, MODELS, MODELS_INIT):
        path_text = str(path)
        py_compile.compile(path_text, doraise=True)
