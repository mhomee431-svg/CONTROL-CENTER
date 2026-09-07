"""Product Master Catalog schemas for API serialization."""
from datetime import datetime
from typing import List, Optional
from pydantic import BaseModel, Field, ConfigDict

from app.models.product import ProductStatus, ShopProductStatus, StockStatus, IdentifierType


# ── Category ────────────────────────────────────────────────────────────────
class CategoryBase(BaseModel):
    name: str = Field(..., min_length=1, max_length=100)
    slug: str = Field(..., min_length=1, max_length=120)
    description: Optional[str] = None
    icon_url: Optional[str] = None
    parent_id: Optional[int] = None
    sort_order: int = 0
    is_active: bool = True


class CategoryCreate(CategoryBase):
    pass


class CategoryUpdate(BaseModel):
    name: Optional[str] = Field(None, min_length=1, max_length=100)
    slug: Optional[str] = Field(None, min_length=1, max_length=120)
    description: Optional[str] = None
    icon_url: Optional[str] = None
    parent_id: Optional[int] = None
    sort_order: Optional[int] = None
    is_active: Optional[bool] = None


class CategoryResponse(BaseModel):
    id: int
    name: str
    slug: str
    description: Optional[str] = None
    icon_url: Optional[str] = None
    parent_id: Optional[int] = None
    sort_order: int
    is_active: bool
    is_subcategory: bool
    created_at: datetime
    updated_at: datetime

    model_config = ConfigDict(from_attributes=True)


class CategoryTreeResponse(CategoryResponse):
    """Category with nested children for hierarchy."""
    children: List["CategoryTreeResponse"] = []


# ── Brand ───────────────────────────────────────────────────────────────────
class BrandCreate(BaseModel):
    name: str = Field(..., min_length=1, max_length=120)
    slug: str = Field(..., min_length=1, max_length=140)
    description: Optional[str] = None
    logo_url: Optional[str] = None
    is_active: bool = True


class BrandUpdate(BaseModel):
    name: Optional[str] = Field(None, min_length=1, max_length=120)
    slug: Optional[str] = Field(None, min_length=1, max_length=140)
    description: Optional[str] = None
    logo_url: Optional[str] = None
    is_active: Optional[bool] = None


class BrandResponse(BaseModel):
    id: int
    name: str
    slug: str
    description: Optional[str] = None
    logo_url: Optional[str] = None
    is_active: bool
    created_at: datetime
    updated_at: datetime

    model_config = ConfigDict(from_attributes=True)


# ── Product Identifier ──────────────────────────────────────────────────────
class ProductIdentifierCreate(BaseModel):
    identifier_type: IdentifierType
    identifier_value: str = Field(..., min_length=1, max_length=100)
    is_primary: bool = False


class ProductIdentifierResponse(BaseModel):
    id: int
    product_master_id: int
    identifier_type: IdentifierType
    identifier_value: str
    is_primary: bool
    is_active: bool
    created_at: datetime

    model_config = ConfigDict(from_attributes=True)


# ── Barcode Relationship ────────────────────────────────────────────────────
class BarcodeRelationshipCreate(BaseModel):
    barcode: str = Field(..., min_length=1, max_length=100)
    relationship_type: str = Field(..., min_length=1, max_length=50)
    related_product_master_id: Optional[int] = None
    notes: Optional[str] = None


class BarcodeRelationshipResponse(BaseModel):
    id: int
    product_master_id: int
    barcode: str
    relationship_type: str
    related_product_master_id: Optional[int] = None
    is_active: bool
    notes: Optional[str] = None
    created_at: datetime

    model_config = ConfigDict(from_attributes=True)


# ── Product Attribute ───────────────────────────────────────────────────────
class ProductAttributeValueCreate(BaseModel):
    value: str = Field(..., min_length=1, max_length=255)
    sort_order: int = 0


class ProductAttributeValueResponse(BaseModel):
    id: int
    attribute_id: int
    value: str
    sort_order: int
    created_at: datetime

    model_config = ConfigDict(from_attributes=True)


class ProductAttributeCreate(BaseModel):
    name: str = Field(..., min_length=1, max_length=100)
    is_variant_defining: bool = False
    sort_order: int = 0
    values: List[ProductAttributeValueCreate] = []


class ProductAttributeResponse(BaseModel):
    id: int
    product_master_id: int
    name: str
    is_variant_defining: bool
    sort_order: int
    values: List[ProductAttributeValueResponse] = []
    created_at: datetime

    model_config = ConfigDict(from_attributes=True)


# ── Product Image ───────────────────────────────────────────────────────────
class ProductImageCreate(BaseModel):
    image_url: str = Field(..., min_length=1, max_length=500)
    thumbnail_url: Optional[str] = None
    alt_text: Optional[str] = None
    sort_order: int = 0
    is_primary: bool = False
    variant_id: Optional[int] = None


class ProductImageResponse(BaseModel):
    id: int
    product_master_id: int
    variant_id: Optional[int] = None
    image_url: str
    thumbnail_url: Optional[str] = None
    alt_text: Optional[str] = None
    sort_order: int
    is_primary: bool
    created_at: datetime

    model_config = ConfigDict(from_attributes=True)


# ── Product Variant ─────────────────────────────────────────────────────────
class ProductVariantCreate(BaseModel):
    sku: str = Field(..., min_length=1, max_length=100)
    name: str = Field(..., min_length=1, max_length=255)
    description: Optional[str] = None
    attributes_json: Optional[str] = None
    is_active: bool = True
    sort_order: int = 0


class ProductVariantUpdate(BaseModel):
    sku: Optional[str] = Field(None, min_length=1, max_length=100)
    name: Optional[str] = Field(None, min_length=1, max_length=255)
    description: Optional[str] = None
    attributes_json: Optional[str] = None
    is_active: Optional[bool] = None
    sort_order: Optional[int] = None


class ProductVariantResponse(BaseModel):
    id: int
    product_master_id: int
    sku: str
    name: str
    description: Optional[str] = None
    attributes_json: Optional[str] = None
    is_active: bool
    sort_order: int
    created_at: datetime
    updated_at: datetime

    model_config = ConfigDict(from_attributes=True)


# ── Product Master ──────────────────────────────────────────────────────────
class ProductMasterCreate(BaseModel):
    name: str = Field(..., min_length=1, max_length=255)
    slug: str = Field(..., min_length=1, max_length=280)
    description: Optional[str] = None
    short_description: Optional[str] = None
    category_id: Optional[int] = None
    subcategory_id: Optional[int] = None
    brand_id: Optional[int] = None
    base_unit: Optional[str] = None
    base_quantity: Optional[float] = None
    is_featured: bool = False
    is_searchable: bool = True
    identifiers: List[ProductIdentifierCreate] = []
    attributes: List[ProductAttributeCreate] = []
    variants: List[ProductVariantCreate] = []
    images: List[ProductImageCreate] = []


class ProductMasterUpdate(BaseModel):
    name: Optional[str] = Field(None, min_length=1, max_length=255)
    slug: Optional[str] = Field(None, min_length=1, max_length=280)
    description: Optional[str] = None
    short_description: Optional[str] = None
    category_id: Optional[int] = None
    subcategory_id: Optional[int] = None
    brand_id: Optional[int] = None
    base_unit: Optional[str] = None
    base_quantity: Optional[float] = None
    is_featured: Optional[bool] = None
    is_searchable: Optional[bool] = None


class ProductMasterResponse(BaseModel):
    id: int
    name: str
    slug: str
    description: Optional[str] = None
    short_description: Optional[str] = None
    category_id: Optional[int] = None
    subcategory_id: Optional[int] = None
    brand_id: Optional[int] = None
    status: ProductStatus
    is_active: bool
    is_featured: bool
    is_searchable: bool
    base_unit: Optional[str] = None
    base_quantity: Optional[float] = None
    approved_by: Optional[int] = None
    approved_at: Optional[datetime] = None
    rejected_by: Optional[int] = None
    rejected_at: Optional[datetime] = None
    rejection_reason: Optional[str] = None
    search_metadata: Optional[str] = None
    search_updated_at: Optional[datetime] = None
    created_at: datetime
    updated_at: datetime

    model_config = ConfigDict(from_attributes=True)


class ProductDetailResponse(ProductMasterResponse):
    """Full product detail with nested relationships."""
    category: Optional[CategoryResponse] = None
    subcategory: Optional[CategoryResponse] = None
    brand: Optional[BrandResponse] = None
    variants: List[ProductVariantResponse] = []
    images: List[ProductImageResponse] = []
    attributes: List[ProductAttributeResponse] = []
    identifiers: List[ProductIdentifierResponse] = []
    barcode_relationships: List[BarcodeRelationshipResponse] = []


# ── Shop Product ────────────────────────────────────────────────────────────
class ShopProductCreate(BaseModel):
    shop_id: int
    product_master_id: int
    variant_id: Optional[int] = None
    price: float = Field(..., ge=0)
    mrp: Optional[float] = Field(None, ge=0)
    is_available: bool = True
    is_featured: bool = False
    is_visible: bool = True
    stock_status: StockStatus = StockStatus.IN_STOCK


class ShopProductResponse(BaseModel):
    id: int
    shop_id: int
    product_master_id: int
    variant_id: Optional[int] = None
    status: ShopProductStatus
    price: float
    mrp: Optional[float] = None
    is_available: bool
    is_featured: bool
    is_visible: bool
    stock_status: StockStatus
    last_inventory_update: Optional[datetime] = None
    last_price_update: Optional[datetime] = None
    created_at: datetime
    updated_at: datetime

    model_config = ConfigDict(from_attributes=True)


# ── Approval Workflow ───────────────────────────────────────────────────────
class ProductApprovalCreate(BaseModel):
    product_master_id: int
    shop_id: Optional[int] = None
    submission_data: Optional[dict] = None


class ProductApprovalReview(BaseModel):
    status: str  # APPROVED, REJECTED, NEEDS_INFO
    review_notes: Optional[str] = None


class ProductApprovalResponse(BaseModel):
    id: int
    product_master_id: int
    shop_id: Optional[int] = None
    submitted_by: Optional[int] = None
    status: str
    requested_by: Optional[int] = None
    reviewed_by: Optional[int] = None
    review_notes: Optional[str] = None
    submitted_at: Optional[datetime] = None
    reviewed_at: Optional[datetime] = None
    created_at: datetime
    updated_at: datetime

    model_config = ConfigDict(from_attributes=True)


# ── Search Index ────────────────────────────────────────────────────────────
class ProductSearchDocument(BaseModel):
    """Prepared document for search indexing."""
    id: int
    name: str
    slug: str
    description: Optional[str] = None
    short_description: Optional[str] = None
    brand: Optional[str] = None
    category: Optional[str] = None
    subcategory: Optional[str] = None
    identifiers: List[str] = []
    attributes: dict = {}
    is_searchable: bool
    status: str
    updated_at: datetime


# ── Identifier Lookup ───────────────────────────────────────────────────────
class IdentifierLookupResponse(BaseModel):
    product: ProductMasterResponse
    identifier_type: IdentifierType
    identifier_value: str
    is_primary: bool