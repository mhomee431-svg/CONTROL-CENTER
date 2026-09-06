"""Phase 15b - Restaurant Discovery API surface (DB-free unit checks).

Complements test_phase15_restaurant_schema.py: the migration/models were already
verified there; these tests verify the newly authored API layer (routes, service,
schemas) for the discovery-only restaurant domain (Master Spec §27, Rule 4).
"""

from pathlib import Path

BACKEND_DIR = Path(__file__).resolve().parents[1]
ROUTES = BACKEND_DIR / "app" / "api" / "routes" / "restaurant.py"
SERVICE = BACKEND_DIR / "app" / "services" / "restaurant_service.py"
SCHEMAS = BACKEND_DIR / "app" / "schemas" / "restaurant.py"
MAIN = BACKEND_DIR / "app" / "main.py"


def _source(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def test_restaurant_api_files_exist():
    for path in (ROUTES, SERVICE, SCHEMAS):
        assert path.exists(), f"{path.relative_to(BACKEND_DIR)} is missing"


def test_restaurant_routes_expose_discovery_endpoints():
    src = _source(ROUTES)
    assert 'prefix="/restaurants"' in src
    assert '"/nearby"' in src
    assert '"GET"' not in src or 'def get_nearby_restaurants' in src


def test_restaurant_schemas_importable():
    import app.schemas.restaurant  # noqa: F401


def test_restaurant_service_importable():
    import app.services.restaurant_service  # noqa: F401


def test_restaurant_routes_importable():
    import app.api.routes.restaurant  # noqa: F401


def test_main_registers_restaurant_router():
    src = _source(MAIN)
    assert "restaurant_routes.router" in src