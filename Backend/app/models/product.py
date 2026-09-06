"""Product Master, Variant, Image, Attribute, Identifier, ShopProduct, Inventory, Price, Offer models."""
from datetime import datetime
from sqlalchemy import (
    String, Float, Integer, DateTime, Boolean, Text, ForeignKey, Enum, Numeric, UniqueConstraint, CheckConstraint, Index
)
from sqlalchemy.orm import Mapped, mapped_column, relationship
import enum

from app.database.session import Base
from app.models.base import TimestampMixin, SoftDeleteMixin


class ProductStatus(str, enum.Enum):
    DRAFT = "DRAFT"
    PENDING_REVIEW = "PENDING_REVIEW"
    APPROVED = "APPROVED"
    REJECTED = "REJECTED"
    INACTIVE = "INACTIVE"
    ARCHIVED = "ARCHIVED"


class ShopProductStatus(str, enum.Enum):
    ACTIVE = "ACTIVE"
    INACTIVE = "INACTIVE"
    DISCONTINUED = "DISCONTINUED"
    PENDING_REVIEW = "PENDING_REVIEW"
    APPROVED = "APPROVED"
    REJECTED = "REJECTED"


class StockStatus(str, enum.Enum):
    IN_STOCK = "IN_STOCK"
    LOW_STOCK = "LOW_STOCK"
    LIMITED_STOCK = "LIMITED_STOCK"
    OUT_OF_STOCK = "OUT_OF_STOCK"
    UNKNOWN = "UNKNOWN"
    PRE_ORDER = "PRE_ORDER"
    BACK_ORDER = "BACK_ORDER"


class CustomerStockStatus(str, enum.Enum):
    """Customer-facing stock statuses returned by search / product detail."""
    IN_STOCK = "IN_STOCK"
    LIMITED_STOCK = "LIMITED_STOCK"
    OUT_OF_STOCK = "OUT_OF_STOCK"
    UNKNOWN = "UNKNOWN"


class FreshnessStatus(str, enum.Enum):
    """Inventory freshness classification based on stale-data rules."""
    RECENTLY_UPDATED = "RECENTLY_UPDATED"
    STALE = "STALE"


class InventorySource(str, enum.Enum):
    MANUAL = "MANUAL"
    BARCODE_SCAN = "BARCODE_SCAN"
    EXCEL_UPLOAD = "EXCEL_UPLOAD"
    POS_INTEGRATION = "POS_INTEGRATION"
    SYSTEM = "SYSTEM"


class OfferStatus(str, enum.Enum):
    DRAFT = "DRAFT"
    ACTIVE = "ACTIVE"
    PAUSED = "PAUSED"
    EXPIRED = "EXPIRED"
    CANCELLED = "CANCELLED"


class OfferType(str, enum.Enum):
    PERCENTAGE_DISCOUNT = "PERCENTAGE_DISCOUNT"
    FLAT_DISCOUNT = "FLAT_DISCOUNT"
    BUY_X_GET_Y = "BUY_X_GET_Y"
    BUNDLE = "BUNDLE"
    FREE_SHIPPING = "FREE_SHIPPING"


class Category(Base, TimestampMixin, SoftDeleteMixin):
    __tablename__ = "categories"
    __table_args__ = (
        CheckConstraint("length(name) > 0", name="ck_categories_name_not_empty"),
    )

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    name: Mapped[str] = mapped_column(String(100), unique=True, nullable=False, index=True)
    slug: Mapped[str] = mapped_column(String(120), unique=True, nullable=False, index=True)
    description: Mapped[str | None] = mapped_column(Text)
    icon_url: Mapped[str | None] = mapped_column(String(500))
    parent_id: Mapped[int | None] = mapped_column(ForeignKey("categories.id"), index=True)
    sort_order: Mapped[int] = mapped_column(Integer, default=0)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)
    is_subcategory: Mapped[bool] = mapped_column(Boolean, default=False)

    parent = relationship("Category", remote_side=[id], back_populates="children")
    children = relationship("Category", back_populates="parent", cascade="all, delete-orphan")
    products = relationship(
        "ProductMaster",
        back_populates="category",
        foreign_keys="ProductMaster.category_id",
    )


class Brand(Base, TimestampMixin, SoftDeleteMixin):
    __tablename__ = "brands"

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    name: Mapped[str] = mapped_column(String(120), unique=True, nullable=False, index=True)
    slug: Mapped[str] = mapped_column(String(140), unique=True, nullable=False, index=True)
    description: Mapped[str | None] = mapped_column(Text)
    logo_url: Mapped[str | None] = mapped_column(String(500))
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)

    products = relationship("ProductMaster", back_populates="brand")


class ProductMaster(Base, TimestampMixin, SoftDeleteMixin):
    __tablename__ = "product_masters"
    __table_args__ = (
        CheckConstraint("length(name) > 0", name="ck_product_masters_name_not_empty"),
        Index("ix_product_masters_name_brand", "name", "brand_id"),
    )

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    name: Mapped[str] = mapped_column(String(255), nullable=False, index=True)
    slug: Mapped[str] = mapped_column(String(280), unique=True, nullable=False, index=True)
    description: Mapped[str | None] = mapped_column(Text)
    short_description: Mapped[str | None] = mapped_column(String(500))
    category_id: Mapped[int | None] = mapped_column(ForeignKey("categories.id"), index=True)
    subcategory_id: Mapped[int | None] = mapped_column(ForeignKey("categories.id"), index=True)
    brand_id: Mapped[int | None] = mapped_column(ForeignKey("brands.id"), index=True)
    status: Mapped[ProductStatus] = mapped_column(
        Enum(ProductStatus, name="product_status"), nullable=False, default=ProductStatus.DRAFT
    )
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)
    is_featured: Mapped[bool] = mapped_column(Boolean, default=False)
    is_searchable: Mapped[bool] = mapped_column(Boolean, default=True)
    base_unit: Mapped[str | None] = mapped_column(String(50))  # e.g. "kg", "piece", "pack"
    base_quantity: Mapped[float | None] = mapped_column(Float)
    approved_by: Mapped[int | None] = mapped_column(ForeignKey("users.id"))
    approved_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    rejected_by: Mapped[int | None] = mapped_column(ForeignKey("users.id"))
    rejected_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    rejection_reason: Mapped[str | None] = mapped_column(Text)
    search_metadata: Mapped[str | None] = mapped_column(Text)  # JSON for search engine
    search_updated_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))

    # Pharmacy / healthcare compliance (Master Spec §36, migration 0017)
    prescription_required: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    regulatory_class: Mapped[str] = mapped_column(
        String(30), nullable=False, server_default="UNCLASSIFIED"
    )
    requires_license_type: Mapped[str | None] = mapped_column(String(30))
    is_restricted: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    compliance_notes: Mapped[str | None] = mapped_column(Text)

    category = relationship("Category", back_populates="products", foreign_keys=[category_id])
    subcategory = relationship("Category", foreign_keys=[subcategory_id])
    brand = relationship("Brand", back_populates="products")
    variants = relationship("ProductVariant", back_populates="product_master", cascade="all, delete-orphan")
    images = relationship("ProductImage", back_populates="product_master", cascade="all, delete-orphan")
    attributes = relationship("ProductAttribute", back_populates="product_master", cascade="all, delete-orphan")
    identifiers = relationship("ProductIdentifier", back_populates="product_master", cascade="all, delete-orphan")
    barcode_relationships = relationship(
        "BarcodeRelationship",
        back_populates="product_master",
        foreign_keys="BarcodeRelationship.product_master_id",
        cascade="all, delete-orphan",
    )
    shop_products = relationship("ShopProduct", back_populates="product_master", cascade="all, delete-orphan")
    saved_by_users = relationship("SavedProduct", back_populates="product", cascade="all, delete-orphan")
    approvals = relationship("ProductApproval", back_populates="product", cascade="all, delete-orphan")
    views = relationship("ProductView", back_populates="product", cascade="all, delete-orphan")
    clicks = relationship("ProductClick", back_populates="product", cascade="all, delete-orphan")


class ProductVariant(Base, TimestampMixin, SoftDeleteMixin):
    __tablename__ = "product_variants"
    __table_args__ = (
        UniqueConstraint("product_master_id", "sku", name="uq_product_variant_master_sku"),
    )

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    product_master_id: Mapped[int] = mapped_column(ForeignKey("product_masters.id"), index=True, nullable=False)
    sku: Mapped[str] = mapped_column(String(100), unique=True, nullable=False, index=True)
    name: Mapped[str] = mapped_column(String(255), nullable=False)
    description: Mapped[str | None] = mapped_column(Text)
    attributes_json: Mapped[str | None] = mapped_column(Text)  # JSON: {"color": "Red", "size": "M"}
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)
    sort_order: Mapped[int] = mapped_column(Integer, default=0)

    product_master = relationship("ProductMaster", back_populates="variants")
    images = relationship("ProductImage", back_populates="variant")
    shop_products = relationship("ShopProduct", back_populates="variant")


class ProductImage(Base, TimestampMixin):
    __tablename__ = "product_images"

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    product_master_id: Mapped[int] = mapped_column(ForeignKey("product_masters.id"), index=True, nullable=False)
    variant_id: Mapped[int | None] = mapped_column(ForeignKey("product_variants.id"), index=True)
    image_url: Mapped[str] = mapped_column(String(500), nullable=False)
    thumbnail_url: Mapped[str | None] = mapped_column(String(500))
    alt_text: Mapped[str | None] = mapped_column(String(255))
    sort_order: Mapped[int] = mapped_column(Integer, default=0)
    is_primary: Mapped[bool] = mapped_column(Boolean, default=False)

    product_master = relationship("ProductMaster", back_populates="images")
    variant = relationship("ProductVariant", back_populates="images")


class ProductAttribute(Base, TimestampMixin):
    __tablename__ = "product_attributes"

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    product_master_id: Mapped[int] = mapped_column(ForeignKey("product_masters.id"), index=True, nullable=False)
    name: Mapped[str] = mapped_column(String(100), nullable=False)  # e.g. "Color", "Size", "Weight"
    is_variant_defining: Mapped[bool] = mapped_column(Boolean, default=False)
    sort_order: Mapped[int] = mapped_column(Integer, default=0)

    product_master = relationship("ProductMaster", back_populates="attributes")
    values = relationship("ProductAttributeValue", back_populates="attribute", cascade="all, delete-orphan")


class ProductAttributeValue(Base, TimestampMixin):
    __tablename__ = "product_attribute_values"

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    attribute_id: Mapped[int] = mapped_column(ForeignKey("product_attributes.id"), index=True, nullable=False)
    value: Mapped[str] = mapped_column(String(255), nullable=False)
    sort_order: Mapped[int] = mapped_column(Integer, default=0)

    attribute = relationship("ProductAttribute", back_populates="values")


class IdentifierType(str, enum.Enum):
    EAN = "EAN"
    UPC = "UPC"
    ISBN = "ISBN"
    GTIN = "GTIN"
    ASIN = "ASIN"
    SKU = "SKU"
    MPN = "MPN"
    MODEL_NUMBER = "MODEL_NUMBER"
    JAN = "JAN"
    ITF = "ITF"
    CUSTOM = "CUSTOM"


class ProductIdentifier(Base, TimestampMixin):
    __tablename__ = "product_identifiers"
    __table_args__ = (
        UniqueConstraint("identifier_type", "identifier_value", name="uq_product_identifier_type_value"),
        Index("ix_product_identifiers_type_value", "identifier_type", "identifier_value"),
    )

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    product_master_id: Mapped[int] = mapped_column(ForeignKey("product_masters.id"), index=True, nullable=False)
    identifier_type: Mapped[IdentifierType] = mapped_column(
        Enum(IdentifierType, name="identifier_type"), nullable=False, default=IdentifierType.EAN
    )
    identifier_value: Mapped[str] = mapped_column(String(100), nullable=False, index=True)
    is_primary: Mapped[bool] = mapped_column(Boolean, default=False)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)

    product_master = relationship("ProductMaster", back_populates="identifiers")


class BarcodeRelationship(Base, TimestampMixin):
    __tablename__ = "barcode_relationships"
    __table_args__ = (
        UniqueConstraint("barcode", "relationship_type", name="uq_barcode_relationship_type"),
        Index("ix_barcode_relationships_barcode", "barcode"),
    )

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    product_master_id: Mapped[int] = mapped_column(ForeignKey("product_masters.id"), index=True, nullable=False)
    barcode: Mapped[str] = mapped_column(String(100), nullable=False)
    relationship_type: Mapped[str] = mapped_column(String(50), nullable=False)  # PRIMARY, ALTERNATE, PARENT_CHILD, BUNDLE
    related_product_master_id: Mapped[int | None] = mapped_column(ForeignKey("product_masters.id"), index=True)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)
    notes: Mapped[str | None] = mapped_column(Text)

    product_master = relationship("ProductMaster", back_populates="barcode_relationships", foreign_keys=[product_master_id])
    related_product = relationship("ProductMaster", foreign_keys=[related_product_master_id])


class ShopProduct(Base, TimestampMixin, SoftDeleteMixin):
    __tablename__ = "shop_products"
    __table_args__ = (
        UniqueConstraint("shop_id", "product_master_id", "variant_id", name="uq_shop_product_shop_master_variant"),
        UniqueConstraint("shop_id", "sku", name="uq_shop_product_shop_sku"),
        CheckConstraint("price >= 0", name="ck_shop_products_price_non_negative"),
        CheckConstraint("mrp >= 0", name="ck_shop_products_mrp_non_negative"),
    )

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    shop_id: Mapped[int] = mapped_column(ForeignKey("shops.id"), index=True, nullable=False)
    product_master_id: Mapped[int] = mapped_column(ForeignKey("product_masters.id"), index=True, nullable=False)
    variant_id: Mapped[int | None] = mapped_column(ForeignKey("product_variants.id"), index=True)
    sku: Mapped[str | None] = mapped_column(String(100), index=True)  # Shop-level SKU where applicable
    status: Mapped[ShopProductStatus] = mapped_column(
        Enum(ShopProductStatus, name="shop_product_status"), nullable=False, default=ShopProductStatus.ACTIVE
    )
    price: Mapped[float] = mapped_column(Numeric(12, 2), nullable=False)
    mrp: Mapped[float | None] = mapped_column(Numeric(12, 2))
    is_active: Mapped[bool] = mapped_column(Boolean, default=True, index=True)
    is_available: Mapped[bool] = mapped_column(Boolean, default=True, index=True)
    is_featured: Mapped[bool] = mapped_column(Boolean, default=False)
    is_visible: Mapped[bool] = mapped_column(Boolean, default=True)
    stock_status: Mapped[StockStatus] = mapped_column(
        Enum(StockStatus, name="stock_status"), nullable=False, default=StockStatus.IN_STOCK, index=True
    )
    freshness_status: Mapped[FreshnessStatus | None] = mapped_column(
        Enum(FreshnessStatus, name="freshness_status"), nullable=True, index=True
    )
    last_inventory_update: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), index=True)
    last_price_update: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), index=True)
    source: Mapped[InventorySource] = mapped_column(
        Enum(InventorySource, name="inventory_source"), nullable=False, default=InventorySource.MANUAL
    )

    shop = relationship("Shop", back_populates="shop_products")
    product_master = relationship("ProductMaster", back_populates="shop_products")
    variant = relationship("ProductVariant", back_populates="shop_products")
    inventory = relationship("Inventory", back_populates="shop_product", uselist=False, cascade="all, delete-orphan")
    price_history = relationship("PriceHistory", back_populates="shop_product", cascade="all, delete-orphan")
    offer_products = relationship("OfferProduct", back_populates="shop_product", cascade="all, delete-orphan")
    inventory_events = relationship("InventoryEvent", back_populates="shop_product", cascade="all, delete-orphan")


class Inventory(Base, TimestampMixin):
    __tablename__ = "inventory"
    __table_args__ = (
        UniqueConstraint("shop_product_id", name="uq_inventory_shop_product"),
        CheckConstraint("quantity >= 0", name="ck_inventory_quantity_non_negative"),
    )

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    shop_product_id: Mapped[int] = mapped_column(ForeignKey("shop_products.id"), index=True, nullable=False)
    quantity: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    reserved_quantity: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    available_quantity: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    is_available: Mapped[bool] = mapped_column(Boolean, default=True, index=True)
    stock_status: Mapped[StockStatus] = mapped_column(
        Enum(StockStatus, name="stock_status"), nullable=False, default=StockStatus.IN_STOCK, index=True
    )
    low_stock_threshold: Mapped[int | None] = mapped_column(Integer)
    last_updated_by: Mapped[int | None] = mapped_column(ForeignKey("users.id"))
    last_updated_source: Mapped[InventorySource] = mapped_column(
        Enum(InventorySource, name="inventory_source"), nullable=False, default=InventorySource.MANUAL
    )
    last_synced_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    freshness_status: Mapped[FreshnessStatus | None] = mapped_column(
        Enum(FreshnessStatus, name="freshness_status"), nullable=True, index=True
    )
    freshness_checked_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))

    shop_product = relationship("ShopProduct", back_populates="inventory")
    movements = relationship("InventoryMovement", back_populates="inventory", cascade="all, delete-orphan")
    adjustments = relationship("InventoryAdjustment", back_populates="inventory", cascade="all, delete-orphan")


class InventoryMovement(Base, TimestampMixin):
    __tablename__ = "inventory_movements"

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    inventory_id: Mapped[int] = mapped_column(ForeignKey("inventory.id"), index=True, nullable=False)
    quantity_change: Mapped[int] = mapped_column(Integer, nullable=False)  # +ve for in, -ve for out
    quantity_before: Mapped[int] = mapped_column(Integer, nullable=False)
    quantity_after: Mapped[int] = mapped_column(Integer, nullable=False)
    movement_type: Mapped[str] = mapped_column(String(50), nullable=False)  # SALE, RESTOCK, RETURN, DAMAGE, ADJUSTMENT
    source: Mapped[InventorySource] = mapped_column(
        Enum(InventorySource, name="inventory_source"), nullable=False, default=InventorySource.MANUAL
    )
    reference_type: Mapped[str | None] = mapped_column(String(50))  # e.g. "pos_sync", "barcode_scan", "excel_upload"
    reference_id: Mapped[int | None] = mapped_column(Integer)
    notes: Mapped[str | None] = mapped_column(Text)
    created_by: Mapped[int | None] = mapped_column(ForeignKey("users.id"))

    inventory = relationship("Inventory", back_populates="movements")


class InventoryAdjustment(Base, TimestampMixin):
    __tablename__ = "inventory_adjustments"

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    inventory_id: Mapped[int] = mapped_column(ForeignKey("inventory.id"), index=True, nullable=False)
    adjustment_type: Mapped[str] = mapped_column(String(50), nullable=False)  # STOCK_COUNT, DAMAGE, EXPIRY, THEFT
    quantity_adjustment: Mapped[int] = mapped_column(Integer, nullable=False)
    reason: Mapped[str | None] = mapped_column(Text)
    approved_by: Mapped[int | None] = mapped_column(ForeignKey("users.id"))
    approved_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))

    inventory = relationship("Inventory", back_populates="adjustments")


class PriceHistory(Base, TimestampMixin):
    __tablename__ = "price_history"
    __table_args__ = (
        CheckConstraint("old_price >= 0", name="ck_price_history_old_price_non_negative"),
        CheckConstraint("new_price >= 0", name="ck_price_history_new_price_non_negative"),
        CheckConstraint("old_mrp >= 0", name="ck_price_history_old_mrp_non_negative"),
        CheckConstraint("new_mrp >= 0", name="ck_price_history_new_mrp_non_negative"),
    )

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    shop_product_id: Mapped[int] = mapped_column(ForeignKey("shop_products.id"), index=True, nullable=False)
    old_price: Mapped[float] = mapped_column(Numeric(12, 2), nullable=False)
    new_price: Mapped[float] = mapped_column(Numeric(12, 2), nullable=False)
    old_mrp: Mapped[float | None] = mapped_column(Numeric(12, 2))
    new_mrp: Mapped[float | None] = mapped_column(Numeric(12, 2))
    changed_by: Mapped[int | None] = mapped_column(ForeignKey("users.id"))
    change_source: Mapped[InventorySource] = mapped_column(
        Enum(InventorySource, name="inventory_source"), nullable=False, default=InventorySource.MANUAL
    )
    effective_from: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, default=datetime.utcnow)
    effective_to: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))

    shop_product = relationship("ShopProduct", back_populates="price_history")


class Offer(Base, TimestampMixin, SoftDeleteMixin):
    __tablename__ = "offers"
    __table_args__ = (
        CheckConstraint("end_date > start_date", name="ck_offers_end_after_start"),
    )

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    shop_id: Mapped[int] = mapped_column(ForeignKey("shops.id"), index=True, nullable=False)
    title: Mapped[str] = mapped_column(String(255), nullable=False)
    description: Mapped[str | None] = mapped_column(Text)
    offer_type: Mapped[OfferType] = mapped_column(
        Enum(OfferType, name="offer_type"), nullable=False
    )
    discount_value: Mapped[float | None] = mapped_column(Numeric(12, 2))
    discount_percentage: Mapped[float | None] = mapped_column(Float)
    min_purchase_amount: Mapped[float | None] = mapped_column(Numeric(12, 2))
    max_discount_amount: Mapped[float | None] = mapped_column(Numeric(12, 2))
    buy_quantity: Mapped[int | None] = mapped_column(Integer)
    get_quantity: Mapped[int | None] = mapped_column(Integer)
    status: Mapped[OfferStatus] = mapped_column(
        Enum(OfferStatus, name="offer_status"), nullable=False, default=OfferStatus.DRAFT
    )
    start_date: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    end_date: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    is_visible: Mapped[bool] = mapped_column(Boolean, default=True)
    terms_conditions: Mapped[str | None] = mapped_column(Text)

    shop = relationship("Shop", back_populates="offers")
    offer_products = relationship("OfferProduct", back_populates="offer", cascade="all, delete-orphan")
    conditions = relationship("OfferCondition", back_populates="offer", cascade="all, delete-orphan")


class OfferProduct(Base, TimestampMixin):
    __tablename__ = "offer_products"
    __table_args__ = (
        UniqueConstraint("offer_id", "shop_product_id", name="uq_offer_product_offer_shop_product"),
    )

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    offer_id: Mapped[int] = mapped_column(ForeignKey("offers.id"), index=True, nullable=False)
    shop_product_id: Mapped[int] = mapped_column(ForeignKey("shop_products.id"), index=True, nullable=False)
    is_excluded: Mapped[bool] = mapped_column(Boolean, default=False)

    offer = relationship("Offer", back_populates="offer_products")
    shop_product = relationship("ShopProduct", back_populates="offer_products")


class OfferCondition(Base, TimestampMixin):
    __tablename__ = "offer_conditions"

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    offer_id: Mapped[int] = mapped_column(ForeignKey("offers.id"), index=True, nullable=False)
    condition_type: Mapped[str] = mapped_column(String(50), nullable=False)  # MIN_QTY, MIN_AMOUNT, CATEGORY, BRAND
    condition_value: Mapped[str] = mapped_column(String(255), nullable=False)
    operator: Mapped[str | None] = mapped_column(String(20))  # >=, <=, ==, IN

    offer = relationship("Offer", back_populates="conditions")