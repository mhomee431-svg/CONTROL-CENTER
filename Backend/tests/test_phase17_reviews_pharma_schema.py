"""Phase 17 - Reviews & Pharmacy Compliance schema verification (DB-free unit checks).

These tests require no live database. They statically validate the authored
Reviews + pharma compliance land (Master Spec §§19-20, 36, 49) as encoded in
the linear migration 0017 and the ORM models.
"""

import py_compile

from pathlib import Path

BACKEND_DIR = Path(__file__).resolve().parents[1]
MIGRATION = BACKEND_DIR / "alembic" / "versions" / "0017_reviews_pharma_compliance.py"
MODELS = BACKEND_DIR / "app" / "models" / "review.py"
PRODUCT_MODELS = BACKEND_DIR / "app" / "models" / "product.py"
MODELS_INIT = BACKEND_DIR / "app" / "models" / "__init__.py"
ROUTES = BACKEND_DIR / "app" / "api" / "routes" / "reviews.py"
SERVICE = BACKEND_DIR / "app" / "services" / "review_service.py"
SCHEMAS = BACKEND_DIR / "app" / "schemas" / "review.py"


def _source(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def test_migration_0017_registered_linear():
    src = _source(MIGRATION)
    assert 'revision: str = "0017"' in src
    assert 'down_revision: Union[str, None] = "0016"' in src


def test_migration_creates_reviews_table():
    src = _source(MIGRATION)
    assert '"reviews"' in src
    assert "ck_reviews_rating_range" in src
    assert "ck_reviews_target_required" in src
    assert "ck_reviews_status" in src
    assert "ix_reviews_shop_status" in src
    assert "ix_reviews_product_status" in src


def test_migration_adds_pharmacy_compliance_columns():
    src = _source(MIGRATION)
    for col in (
        "prescription_required",
        "regulatory_class",
        "requires_license_type",
        "is_restricted",
        "compliance_notes",
    ):
        assert col in src, f"{col} missing from migration 0017"
    assert "ck_product_masters_regulatory_class" in src
    assert "ix_product_masters_prescription_required" in src
    assert "postgresql_where" in src  # partial index


def test_review_models_declared_and_exported():
    model_src = _source(MODELS)
    init_src = _source(MODELS_INIT)
    assert ("class Review(") in model_src
    assert "Review" in init_src


def test_product_model_has_compliance_fields():
    src = _source(PRODUCT_MODELS)
    for col in (
        "prescription_required",
        "regulatory_class",
        "requires_license_type",
        "is_restricted",
        "compliance_notes",
    ):
        assert col in src, f"{col} missing from ProductMaster model"


def test_review_routes_and_service_exist():
    for path in (ROUTES, SERVICE, SCHEMAS):
        assert path.exists(), f"{path.relative_to(BACKEND_DIR)} is missing"


def test_review_schemas_importable():
    import app.schemas.review  # noqa: F401


def test_review_models_importable():
    from app.models.review import Review  # noqa: F401


def test_pharma_surface_importable():
    import app.models.product  # noqa: F401