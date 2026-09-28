"""Search History, Search Events, Popular Searches, Barcode Scans, Search Index models."""
from datetime import datetime
from sqlalchemy import (
    String, Integer, DateTime, Boolean, Text, Float, ForeignKey,
    UniqueConstraint, Index, Numeric, Enum as SAEnum,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship
from geoalchemy2 import Geography
import enum

from app.database.session import Base
from app.models.base import TimestampMixin


# ── Enums ──────────────────────────────────────────────────────────────────
class SearchIndexEntityType(str, enum.Enum):
    """Type of entity represented by a search-index entry."""
    SHOP_PRODUCT = "SHOP_PRODUCT"   # A product available at a specific shop
    PRODUCT = "PRODUCT"             # Master product (un-scoped)
    SHOP = "SHOP"                   # A shop itself
    BRAND = "BRAND"                 # A brand
    CATEGORY = "CATEGORY"           # A category


class SearchIndexSyncStatus(str, enum.Enum):
    RUNNING = "RUNNING"
    COMPLETED = "COMPLETED"
    FAILED = "FAILED"


# ── Search History (existing) ───────────────────────────────────────────────
class SearchHistory(Base, TimestampMixin):
    __tablename__ = "search_history"
    __table_args__ = (
        Index("ix_search_history_user_query", "user_id", "query"),
    )

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id"), index=True, nullable=False)
    query: Mapped[str] = mapped_column(String(255), nullable=False, index=True)
    result_count: Mapped[int | None] = mapped_column(Integer)
    is_successful: Mapped[bool] = mapped_column(Boolean, default=True)
    searched_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, default=datetime.utcnow)

    user = relationship("User", back_populates="search_history")


# ── Search Events (extended) ────────────────────────────────────────────────
class SearchEvent(Base, TimestampMixin):
    __tablename__ = "search_events"

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    user_id: Mapped[int | None] = mapped_column(ForeignKey("users.id"), index=True)
    session_id: Mapped[str | None] = mapped_column(String(100), index=True)
    query: Mapped[str] = mapped_column(String(255), nullable=False)
    event_type: Mapped[str] = mapped_column(String(50), nullable=False)  # SEARCH, SUGGESTION_CLICK, RESULT_CLICK, CONVERSION
    result_count: Mapped[int | None] = mapped_column(Integer)
    clicked_product_id: Mapped[int | None] = mapped_column(ForeignKey("product_masters.id"))
    clicked_shop_id: Mapped[int | None] = mapped_column(ForeignKey("shops.id"))
    clicked_shop_product_id: Mapped[int | None] = mapped_column(ForeignKey("shop_products.id"))
    device_type: Mapped[str | None] = mapped_column(String(20))
    app_version: Mapped[str | None] = mapped_column(String(20))
    event_time: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, default=datetime.utcnow)


# ── Popular Search (existing) ───────────────────────────────────────────────
class PopularSearch(Base, TimestampMixin):
    __tablename__ = "popular_searches"

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    query: Mapped[str] = mapped_column(String(255), unique=True, nullable=False, index=True)
    search_count: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    result_count: Mapped[int | None] = mapped_column(Integer)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)
    last_searched_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


# ── Barcode Scan (existing) ─────────────────────────────────────────────────
class BarcodeScan(Base, TimestampMixin):
    __tablename__ = "barcode_scans"

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    barcode: Mapped[str] = mapped_column(String(100), nullable=False, index=True)
    barcode_type: Mapped[str | None] = mapped_column(String(20))  # EAN-13, UPC-A, QR, etc.
    user_id: Mapped[int | None] = mapped_column(ForeignKey("users.id"), index=True)
    shop_id: Mapped[int | None] = mapped_column(ForeignKey("shops.id"), index=True)
    product_master_id: Mapped[int | None] = mapped_column(ForeignKey("product_masters.id"), index=True)
    scan_source: Mapped[str] = mapped_column(String(50), default="CUSTOMER_APP")  # CUSTOMER_APP, SHOPKEEPER_APP
    is_match_found: Mapped[bool] = mapped_column(Boolean, default=False)
    scan_time: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, default=datetime.utcnow)


# ── Search Index (Phase 20) ────────────────────────────────────────────────
class SearchIndex(Base, TimestampMixin):
    """
    Denormalized search layer — the optimized index that serves discovery.

    PostgreSQL remains the source of truth. This table is the materialized,
    search-optimized projection kept in-sync via the SearchIndexer.
    """

    __tablename__ = "search_indexes"
    __table_args__ = (
        # Unique: one product+shop combination (or entity-level entry)
        UniqueConstraint("entity_type", "entity_id", name="uq_search_index_entity"),
        # GIN indexes for full-text and trigram typo tolerance
        Index("ix_search_index_search_vector", "search_vector", postgresql_using="gin"),
        Index(
            "ix_search_index_search_text_trgm", "search_text",
            postgresql_using="gin", postgresql_ops={"search_text": "gin_trgm_ops"},
        ),
        Index(
            "ix_search_index_discovery_text_trgm", "discovery_text",
            postgresql_using="gin", postgresql_ops={"discovery_text": "gin_trgm_ops"},
        ),
        Index(
            "ix_search_index_barcode_trgm", "barcode",
            postgresql_using="gin", postgresql_ops={"barcode": "gin_trgm_ops"},
        ),
        # Common composite filter indexes
        Index("ix_search_index_shop_available", "shop_id", "is_available"),
        Index("ix_search_index_product_price", "product_id", "price"),
        Index("ix_search_index_shop_rating", "shop_id", "shop_rating"),
        Index("ix_search_index_product_freshness", "product_id", "freshness_status"),
        Index("ix_search_index_category_brand", "category_id", "brand_id"),
    )

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    # ── Entity identification ─────────────────────────────────────────────
    entity_type: Mapped[SearchIndexEntityType] = mapped_column(
        SAEnum(SearchIndexEntityType, name="search_index_entity_type"), nullable=False, index=True
    )
    entity_id: Mapped[int] = mapped_column(Integer, nullable=False, index=True)

    # ── FK fields (useful for joins / filters) ────────────────────────────
    product_id: Mapped[int | None] = mapped_column(ForeignKey("product_masters.id"), index=True)
    shop_product_id: Mapped[int | None] = mapped_column(ForeignKey("shop_products.id"), index=True)
    shop_id: Mapped[int | None] = mapped_column(ForeignKey("shops.id"), index=True)
    brand_id: Mapped[int | None] = mapped_column(ForeignKey("brands.id"), index=True)
    category_id: Mapped[int | None] = mapped_column(ForeignKey("categories.id"), index=True)
    variant_id: Mapped[int | None] = mapped_column(ForeignKey("product_variants.id"), index=True)

    # ── Searchable text fields ────────────────────────────────────────────
    product_name: Mapped[str] = mapped_column(String(255), nullable=False)
    brand_name: Mapped[str | None] = mapped_column(String(120))
    category_name: Mapped[str | None] = mapped_column(String(100))
    subcategory_name: Mapped[str | None] = mapped_column(String(100))
    variant_name: Mapped[str | None] = mapped_column(String(255))
    search_text: Mapped[str] = mapped_column(Text, nullable=False)  # legacy all-field projection
    # Canonical discovery document: product name + brand + taxonomy + variant
    # + SKU/identifiers. Descriptions/specifications are intentionally excluded.
    # Nullable only to allow a zero-downtime production backfill; indexer-created
    # rows always populate it.
    discovery_text: Mapped[str | None] = mapped_column(Text)
    search_vector: Mapped[str | None] = mapped_column(Text)  # legacy compatibility projection
    barcode: Mapped[str | None] = mapped_column(String(100))
    sku: Mapped[str | None] = mapped_column(String(100))

    # ── Discovery visibility ──────────────────────────────────────────────
    is_product_searchable: Mapped[bool] = mapped_column(Boolean, default=True)
    is_shop_visible: Mapped[bool] = mapped_column(Boolean, default=True)

    # ── Availability & pricing ───────────────────────────────────────────
    price: Mapped[float | None] = mapped_column(Numeric(12, 2))
    mrp: Mapped[float | None] = mapped_column(Numeric(12, 2))
    is_available: Mapped[bool] = mapped_column(Boolean, default=False, index=True)
    stock_status: Mapped[str | None] = mapped_column(String(50), index=True)  # customer-facing value
    freshness_status: Mapped[str | None] = mapped_column(String(50), index=True)
    last_inventory_update: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), index=True)

    # ── Shop metadata ─────────────────────────────────────────────────────
    shop_name: Mapped[str | None] = mapped_column(String(255))
    shop_rating: Mapped[float] = mapped_column(Float, default=0.0)
    shop_review_count: Mapped[int] = mapped_column(Integer, default=0)
    is_shop_accepting_orders: Mapped[bool] = mapped_column(Boolean, default=True)

    # ── Geo (denormalized from shop.location) ─────────────────────────────
    location: Mapped[object] = mapped_column(
        Geography(geometry_type="POINT", srid=4326, spatial_index=True), nullable=True
    )
    latitude: Mapped[float | None] = mapped_column(Float)
    longitude: Mapped[float | None] = mapped_column(Float)
    distance_km: Mapped[float | None] = mapped_column(Float)

    # ── Popularity / relevance signal ─────────────────────────────────────
    popularity_score: Mapped[float] = mapped_column(Float, default=0.0)

    # ── Sync state ────────────────────────────────────────────────────────
    is_synced: Mapped[bool] = mapped_column(Boolean, default=False)
    last_synced_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))

    def __repr__(self) -> str:
        return f"<SearchIndex(id={self.id}, type={self.entity_type}, entity={self.entity_id}, name={self.product_name})>"


class SearchIndexSync(Base, TimestampMixin):
    """Tracks a search-index build/sync run (full or incremental)."""

    __tablename__ = "search_index_sync_runs"

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    sync_type: Mapped[str] = mapped_column(String(30), nullable=False)  # FULL | INCREMENTAL
    status: Mapped[SearchIndexSyncStatus] = mapped_column(
        SAEnum(SearchIndexSyncStatus, name="search_index_sync_status"),
        nullable=False,
        default=SearchIndexSyncStatus.RUNNING,
    )
    total_processed: Mapped[int] = mapped_column(Integer, default=0)
    total_created: Mapped[int] = mapped_column(Integer, default=0)
    total_updated: Mapped[int] = mapped_column(Integer, default=0)
    total_removed: Mapped[int] = mapped_column(Integer, default=0)
    error_count: Mapped[int] = mapped_column(Integer, default=0)
    started_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, default=datetime.utcnow)
    completed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    error_message: Mapped[str | None] = mapped_column(Text)