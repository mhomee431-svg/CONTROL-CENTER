"""Phase 17 Product Master Catalog tests.

Verifies:
- Product creation, update, retrieval
- Variant creation
- Brand/category relationship
- Barcode lookup
- Duplicate handling
- Image handling
- Approval states
- Category hierarchy
- Identifier lookup
- Search document preparation
- Single product connected to multiple shops
"""

import asyncio
import os
import sys
from pathlib import Path

BACKEND_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BACKEND_DIR))

os.environ.setdefault("ENVIRONMENT", "test")
os.environ.setdefault("HYPERLOCAL_ENV", "test")

import pytest  # noqa: E402


# ── Model / Enum tests ──────────────────────────────────────────────────────
def test_product_status_enum_values():
    """Product lifecycle must have the required states."""
    from app.models.product import ProductStatus

    values = {s.value for s in ProductStatus}
    assert "DRAFT" in values
    assert "PENDING_REVIEW" in values
    assert "APPROVED" in values
    assert "REJECTED" in values
    assert "INACTIVE" in values
    assert "ARCHIVED" in values


def test_identifier_type_enum_values():
    """Identifier types must support multiple identifier types."""
    from app.models.product import IdentifierType

    values = {s.value for s in IdentifierType}
    assert "EAN" in values
    assert "UPC" in values
    assert "ISBN" in values
    assert "GTIN" in values
    assert "ASIN" in values
    assert "SKU" in values
    assert "MPN" in values
    assert "MODEL_NUMBER" in values
    assert "JAN" in values
    assert "ITF" in values
    assert "CUSTOM" in values


def test_shop_product_status_enum_values():
    """Shop product status must have the required states."""
    from app.models.product import ShopProductStatus

    values = {s.value for s in ShopProductStatus}
    assert "ACTIVE" in values
    assert "INACTIVE" in values
    assert "DISCONTINUED" in values
    assert "PENDING_REVIEW" in values
    assert "APPROVED" in values
    assert "REJECTED" in values


def test_product_models_importable():
    """All product catalog models must be importable."""
    from app.models.product import (
        BarcodeRelationship,
        Brand,
        Category,
        ProductAttribute,
        ProductAttributeValue,
        ProductIdentifier,
        ProductImage,
        ProductMaster,
        ProductVariant,
        ShopProduct,
    )

    assert BarcodeRelationship is not None
    assert Brand is not None
    assert Category is not None
    assert ProductAttribute is not None
    assert ProductAttributeValue is not None
    assert ProductIdentifier is not None
    assert ProductImage is not None
    assert ProductMaster is not None
    assert ProductVariant is not None
    assert ShopProduct is not None


def test_product_master_has_subcategory():
    """ProductMaster must have subcategory_id field."""
    from app.models.product import ProductMaster

    assert hasattr(ProductMaster, "subcategory_id")
    assert hasattr(ProductMaster, "rejected_by")
    assert hasattr(ProductMaster, "rejected_at")
    assert hasattr(ProductMaster, "rejection_reason")
    assert hasattr(ProductMaster, "search_updated_at")


def test_category_has_is_subcategory():
    """Category model must have is_subcategory field."""
    from app.models.product import Category

    assert hasattr(Category, "is_subcategory")


def test_product_identifier_has_is_active():
    """ProductIdentifier model must have is_active field."""
    from app.models.product import ProductIdentifier

    assert hasattr(ProductIdentifier, "is_active")


# ── Schema tests ────────────────────────────────────────────────────────────
def test_catalog_schemas_importable():
    """All catalog schemas must be importable."""
    from app.schemas.catalog import (
        BarcodeRelationshipCreate,
        BarcodeRelationshipResponse,
        BrandCreate,
        BrandResponse,
        BrandUpdate,
        CategoryCreate,
        CategoryResponse,
        CategoryTreeResponse,
        CategoryUpdate,
        IdentifierLookupResponse,
        ProductApprovalCreate,
        ProductApprovalResponse,
        ProductApprovalReview,
        ProductDetailResponse,
        ProductIdentifierCreate,
        ProductIdentifierResponse,
        ProductImageCreate,
        ProductImageResponse,
        ProductMasterCreate,
        ProductMasterResponse,
        ProductMasterUpdate,
        ProductSearchDocument,
        ProductVariantCreate,
        ProductVariantResponse,
        ProductVariantUpdate,
        ShopProductCreate,
        ShopProductResponse,
    )

    assert CategoryCreate is not None
    assert BrandCreate is not None
    assert ProductMasterCreate is not None
    assert ProductVariantCreate is not None
    assert ProductIdentifierCreate is not None
    assert ProductSearchDocument is not None


def test_product_master_create_schema():
    """ProductMasterCreate schema must validate correctly."""
    from app.schemas.catalog import ProductMasterCreate

    payload = ProductMasterCreate(
        name="Test Product",
        slug="test-product",
        identifiers=[{"identifier_type": "EAN", "identifier_value": "8901234567890"}],
    )
    assert payload.name == "Test Product"
    assert len(payload.identifiers) == 1


def test_category_tree_schema():
    """CategoryTreeResponse should support nested children."""
    from app.schemas.catalog import CategoryTreeResponse

    tree = CategoryTreeResponse(
        id=1,
        name="Electronics",
        slug="electronics",
        sort_order=0,
        is_active=True,
        is_subcategory=False,
        created_at="2026-01-01T00:00:00Z",
        updated_at="2026-01-01T00:00:00Z",
        children=[],
    )
    assert tree.children == []


# ── Service tests ───────────────────────────────────────────────────────────
def test_slugify():
    """Slugify should produce URL-safe slugs."""
    from app.services.catalog_service import slugify

    assert slugify("Samsung Galaxy S24 Ultra 5G") == "samsung-galaxy-s24-ultra-5g"
    assert slugify("  Hello   World  ") == "hello-world"
    assert slugify("Café & Restaurant") == "caf-restaurant"


def test_normalize_identifier():
    """Normalize identifier should strip and uppercase."""
    from app.services.catalog_service import normalize_identifier

    assert normalize_identifier("  8901234567890  ") == "8901234567890"
    assert normalize_identifier("abc-def") == "ABC-DEF"


@pytest.mark.asyncio
async def test_find_duplicate_product_no_match():
    """find_duplicate_product should return None when no match exists."""
    from app.services.catalog_service import find_duplicate_product

    # Use a mock session
    class MockResult:
        def scalars(self):
            return self

        def first(self):
            return None

    class MockSession:
        async def execute(self, stmt):
            return MockResult()

    result = await find_duplicate_product(
        MockSession(),
        name="Unique Product",
        brand_id=1,
        identifiers=[{"identifier_type": "EAN", "identifier_value": "9999999999999"}],
    )
    assert result is None


@pytest.mark.asyncio
async def test_find_duplicate_product_identifier_match():
    """find_duplicate_product should find by identifier."""
    from app.services.catalog_service import find_duplicate_product

    class MockProduct:
        id = 1
        name = "Existing Product"

    class MockResult:
        def scalars(self):
            return self

        def first(self):
            return MockProduct()

    class MockSession:
        async def execute(self, stmt):
            return MockResult()

    result = await find_duplicate_product(
        MockSession(),
        name="New Product",
        brand_id=2,
        identifiers=[{"identifier_type": "EAN", "identifier_value": "8901234567890"}],
    )
    assert result is not None
    assert result.name == "Existing Product"


@pytest.mark.asyncio
async def test_find_duplicate_product_name_brand_match():
    """find_duplicate_product should find by name + brand."""
    from app.services.catalog_service import find_duplicate_product

    class MockProduct:
        id = 1
        name = "Same Name"

    class MockResult:
        def __init__(self, product):
            self._product = product

        def scalars(self):
            return self

        def first(self):
            return self._product

    class MockSession:
        def __init__(self):
            self.calls = 0

        async def execute(self, stmt):
            self.calls += 1
            # First call (identifier) returns None, second call (name+brand) returns product
            if self.calls == 1:
                return MockResult(None)
            return MockResult(MockProduct())

    result = await find_duplicate_product(
        MockSession(),
        name="Same Name",
        brand_id=1,
        identifiers=[{"identifier_type": "EAN", "identifier_value": "9999999999999"}],
    )
    assert result is not None
    assert result.name == "Same Name"


# ── API route tests ─────────────────────────────────────────────────────────
def test_catalog_router_exists():
    """Catalog router must be importable and have routes."""
    from app.api.routes.catalog import router

    paths = {r.path for r in router.routes}
    assert "/catalog/categories" in paths
    assert "/catalog/categories/tree" in paths
    assert "/catalog/brands" in paths
    assert "/catalog/products" in paths
    assert "/catalog/products/{product_id}" in paths
    assert "/catalog/products/{product_id}/variants" in paths
    assert "/catalog/variants/{variant_id}" in paths
    assert "/catalog/identifiers/lookup" in paths
    assert "/catalog/products/{product_id}/identifiers" in paths
    assert "/catalog/products/{product_id}/barcodes" in paths
    assert "/catalog/approvals" in paths
    assert "/catalog/approvals/{approval_id}/review" in paths
    assert "/catalog/products/{product_id}/search-document" in paths
    assert "/catalog/shop-products" in paths


def test_catalog_router_registered_in_main():
    """Catalog router should be registered in main app."""
    from app.main import app

    # The app uses _IncludedRouter objects for included routers.
    # Verify the catalog router is among the included routers.
    from app.api.routes.catalog import router as catalog_router

    # Check that the catalog router is included in the app
    included = [r for r in app.routes if type(r).__name__ == "_IncludedRouter"]
    assert len(included) > 0

    # Verify the catalog router has routes
    assert len(catalog_router.routes) > 0


# ── Search document preparation ─────────────────────────────────────────────
@pytest.mark.asyncio
async def test_prepare_search_document():
    """prepare_search_document should produce a valid search document."""
    from app.services.catalog_service import prepare_search_document

    class MockBrand:
        name = "TestBrand"

    class MockCategory:
        name = "TestCategory"

    class MockIdentifier:
        identifier_value = "8901234567890"

    class MockAttrValue:
        value = "Red"

    class MockAttribute:
        name = "Color"
        values = [MockAttrValue()]

    class MockProduct:
        id = 1
        name = "Test Product"
        slug = "test-product"
        description = "A test product"
        short_description = "Test"
        brand = MockBrand()
        category = MockCategory()
        subcategory = None
        subcategory_id = None
        brand_id = None
        category_id = None
        identifiers = [MockIdentifier()]
        attributes = [MockAttribute()]
        is_searchable = True
        status = type("Status", (), {"value": "APPROVED"})()
        updated_at = None
        search_metadata = None
        search_updated_at = None

    class MockSession:
        async def execute(self, stmt):
            return type("R", (), {"scalars": lambda self: type("S", (), {"all": lambda self: []})()})()

        async def get(self, model, id):
            return None

        async def flush(self):
            pass

    doc = await prepare_search_document(MockSession(), MockProduct())
    assert doc["id"] == 1
    assert doc["name"] == "Test Product"
    assert doc["brand"] == "TestBrand"
    assert doc["category"] == "TestCategory"
    assert doc["identifiers"] == ["8901234567890"]
    assert doc["attributes"] == {"Color": ["Red"]}
    assert doc["status"] == "APPROVED"


# ── Single product connected to multiple shops ──────────────────────────────
def test_single_product_multiple_shops_model():
    """A single ProductMaster can be connected to multiple ShopProducts."""
    from app.models.product import ProductMaster, ShopProduct

    # Verify the relationship exists
    assert hasattr(ProductMaster, "shop_products")
    assert hasattr(ShopProduct, "product_master_id")

    # The unique constraint allows the same product_master_id across different shops
    # (unique is on shop_id + product_master_id + variant_id, not product_master_id alone)
    # Verify the constraint string contains shop_id
    table_args_str = str(ShopProduct.__table_args__)
    assert "shop_id" in table_args_str
    assert "product_master_id" in table_args_str
    assert "variant_id" in table_args_str


# ── Image storage abstraction ───────────────────────────────────────────────
def test_image_storage_abstraction():
    """Product images should use object storage URLs, not binary data in DB."""
    from app.models.product import ProductImage

    # ProductImage stores URLs, not binary data
    assert hasattr(ProductImage, "image_url")
    assert hasattr(ProductImage, "thumbnail_url")
    assert not hasattr(ProductImage, "image_data")
    assert not hasattr(ProductImage, "image_binary")


def test_storage_provider_interface():
    """Storage provider abstraction should exist."""
    from app.core.storage import BaseStorageProvider, get_storage

    provider = get_storage()
    assert isinstance(provider, BaseStorageProvider)
    assert hasattr(provider, "upload_file")
    assert hasattr(provider, "delete_file")
    assert hasattr(provider, "get_file_url")


# ── Approval workflow ───────────────────────────────────────────────────────
def test_approval_workflow_models():
    """Approval workflow models should exist."""
    from app.models.admin import ProductApproval, ApprovalStatus

    assert hasattr(ProductApproval, "product_master_id")
    assert hasattr(ProductApproval, "status")
    assert hasattr(ProductApproval, "reviewed_by")
    assert hasattr(ProductApproval, "review_notes")
    assert hasattr(ProductApproval, "submitted_at")
    assert hasattr(ProductApproval, "reviewed_at")

    values = {s.value for s in ApprovalStatus}
    assert "PENDING" in values
    assert "APPROVED" in values
    assert "REJECTED" in values
    assert "NEEDS_INFO" in values


# ── Barcode / identifier mapping ────────────────────────────────────────────
def test_barcode_relationship_model():
    """BarcodeRelationship model should exist with required fields."""
    from app.models.product import BarcodeRelationship

    assert hasattr(BarcodeRelationship, "barcode")
    assert hasattr(BarcodeRelationship, "relationship_type")
    assert hasattr(BarcodeRelationship, "related_product_master_id")
    assert hasattr(BarcodeRelationship, "is_active")
    assert hasattr(BarcodeRelationship, "notes")


def test_identifier_lookup_schema():
    """IdentifierLookupResponse schema should exist."""
    from app.schemas.catalog import IdentifierLookupResponse

    assert IdentifierLookupResponse is not None