"""Search & Geo-Discovery Engine

Revision ID: 0006
Revises: 0005
Create Date: 2026-08-22

This migration implements the Phase 20 Search & Geo-Discovery Engine:
- Enable pg_trgm extension for typo-tolerance
- Add search_index_entity_type enum
- Add search_index_sync_status enum
- Create search_indexes table (denormalized search layer)
- Create search_index_sync_runs table (sync tracking)
- Extend search_events with clicked_shop_product_id
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from geoalchemy2.types import Geography as GeographyType


# revision identifiers, used by Alembic.
revision: str = "0006"
down_revision: Union[str, None] = "0005"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # === 1. Enable pg_trgm for typo tolerance ===
    op.execute("CREATE EXTENSION IF NOT EXISTS pg_trgm")

    # === 2. Create search_index_entity_type enum ===
    op.execute(
        "DO $$ BEGIN CREATE TYPE search_index_entity_type AS ENUM "
        "('SHOP_PRODUCT', 'PRODUCT', 'SHOP', 'BRAND', 'CATEGORY'); "
        "EXCEPTION WHEN duplicate_object THEN NULL; END $$;"
    )

    # === 3. Create search_index_sync_status enum ===
    op.execute(
        "DO $$ BEGIN CREATE TYPE search_index_sync_status AS ENUM "
        "('RUNNING', 'COMPLETED', 'FAILED'); "
        "EXCEPTION WHEN duplicate_object THEN NULL; END $$;"
    )

    # === 4. Create search_indexes table ===
    op.create_table(
        "search_indexes",
        sa.Column("id", sa.Integer(), primary_key=True, index=True),
        # entity_type column reuses the type created by the idempotent DO block above —
        # create_type=False avoids "type already exists".
        sa.Column("entity_type", sa.Enum(name="search_index_entity_type", create_type=False), nullable=False, index=True),
        sa.Column("entity_id", sa.Integer(), nullable=False, index=True),
        sa.Column("product_id", sa.Integer(), nullable=True, index=True),
        sa.Column("shop_product_id", sa.Integer(), nullable=True, index=True),
        sa.Column("shop_id", sa.Integer(), nullable=True, index=True),
        sa.Column("brand_id", sa.Integer(), nullable=True, index=True),
        sa.Column("category_id", sa.Integer(), nullable=True, index=True),
        sa.Column("variant_id", sa.Integer(), nullable=True, index=True),
        sa.Column("product_name", sa.String(255), nullable=False),
        sa.Column("brand_name", sa.String(120), nullable=True),
        sa.Column("category_name", sa.String(100), nullable=True),
        sa.Column("subcategory_name", sa.String(100), nullable=True),
        sa.Column("variant_name", sa.String(255), nullable=True),
        sa.Column("search_text", sa.Text(), nullable=False),
        sa.Column("search_vector", sa.Text(), nullable=True),
        sa.Column("barcode", sa.String(100), nullable=True),
        sa.Column("sku", sa.String(100), nullable=True),
        sa.Column("is_product_searchable", sa.Boolean(), server_default=sa.text("true"), nullable=False),
        sa.Column("is_shop_visible", sa.Boolean(), server_default=sa.text("true"), nullable=False),
        sa.Column("price", sa.Numeric(12, 2), nullable=True),
        sa.Column("mrp", sa.Numeric(12, 2), nullable=True),
        sa.Column("is_available", sa.Boolean(), server_default=sa.text("false"), nullable=False, index=True),
        sa.Column("stock_status", sa.String(50), nullable=True, index=True),
        sa.Column("freshness_status", sa.String(50), nullable=True, index=True),
        sa.Column("last_inventory_update", sa.DateTime(timezone=True), nullable=True, index=True),
        sa.Column("shop_name", sa.String(255), nullable=True),
        sa.Column("shop_rating", sa.Float(), server_default=sa.text("0.0"), nullable=False),
        sa.Column("shop_review_count", sa.Integer(), server_default=sa.text("0"), nullable=False),
        sa.Column("is_shop_accepting_orders", sa.Boolean(), server_default=sa.text("true"), nullable=False),
        sa.Column("location", GeographyType(geometry_type="POINT", srid=4326, spatial_index=True), nullable=True),
        sa.Column("latitude", sa.Float(), nullable=True),
        sa.Column("longitude", sa.Float(), nullable=True),
        sa.Column("distance_km", sa.Float(), nullable=True),
        sa.Column("popularity_score", sa.Float(), server_default=sa.text("0.0"), nullable=False),
        sa.Column("is_synced", sa.Boolean(), server_default=sa.text("false"), nullable=False),
        sa.Column("last_synced_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.ForeignKeyConstraint(["product_id"], ["product_masters.id"]),
        sa.ForeignKeyConstraint(["shop_product_id"], ["shop_products.id"]),
        sa.ForeignKeyConstraint(["shop_id"], ["shops.id"]),
        sa.ForeignKeyConstraint(["brand_id"], ["brands.id"]),
        sa.ForeignKeyConstraint(["category_id"], ["categories.id"]),
        sa.ForeignKeyConstraint(["variant_id"], ["product_variants.id"]),
        sa.UniqueConstraint("entity_type", "entity_id", name="uq_search_index_entity"),
    )
    # GIN indexes
    op.execute(
        "CREATE INDEX ix_search_index_search_vector ON search_indexes "
        "USING GIN (search_vector)"
    )
    op.execute(
        "CREATE INDEX ix_search_index_search_text_trgm ON search_indexes "
        "USING GIN (search_text gin_trgm_ops)"
    )
    op.execute(
        "CREATE INDEX ix_search_index_barcode_trgm ON search_indexes "
        "USING GIN (barcode gin_trgm_ops)"
    )
    # Composite filter indexes
    op.create_index("ix_search_index_shop_available", "search_indexes", ["shop_id", "is_available"])
    op.create_index("ix_search_index_product_price", "search_indexes", ["product_id", "price"])
    op.create_index("ix_search_index_shop_rating", "search_indexes", ["shop_id", "shop_rating"])
    op.create_index("ix_search_index_product_freshness", "search_indexes", ["product_id", "freshness_status"])
    op.create_index("ix_search_index_category_brand", "search_indexes", ["category_id", "brand_id"])

    # === 5. Create search_index_sync_runs table ===
    op.create_table(
        "search_index_sync_runs",
        sa.Column("id", sa.Integer(), primary_key=True, index=True),
        sa.Column("sync_type", sa.String(30), nullable=False),
        sa.Column("status", sa.Enum(name="search_index_sync_status", create_type=False), nullable=False),
        sa.Column("total_processed", sa.Integer(), server_default=sa.text("0"), nullable=False),
        sa.Column("total_created", sa.Integer(), server_default=sa.text("0"), nullable=False),
        sa.Column("total_updated", sa.Integer(), server_default=sa.text("0"), nullable=False),
        sa.Column("total_removed", sa.Integer(), server_default=sa.text("0"), nullable=False),
        sa.Column("error_count", sa.Integer(), server_default=sa.text("0"), nullable=False),
        sa.Column("started_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.Column("completed_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("error_message", sa.Text(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
    )

    # === 6. Extend search_events with clicked_shop_product_id ===
    op.add_column("search_events", sa.Column("clicked_shop_product_id", sa.Integer(), nullable=True))
    op.create_foreign_key("fk_search_events_shop_product", "search_events", "shop_products", ["clicked_shop_product_id"], ["id"])


def downgrade() -> None:
    # === 6. Reverse search_events extension ===
    op.drop_constraint("fk_search_events_shop_product", "search_events", type_="foreignkey")
    op.drop_column("search_events", "clicked_shop_product_id")

    # === 5. Drop search_index_sync_runs table ===
    op.drop_table("search_index_sync_runs")

    # === 4. Drop search_indexes table + enums ===
    op.drop_index("ix_search_index_category_brand", table_name="search_indexes")
    op.drop_index("ix_search_index_product_freshness", table_name="search_indexes")
    op.drop_index("ix_search_index_shop_rating", table_name="search_indexes")
    op.drop_index("ix_search_index_product_price", table_name="search_indexes")
    op.drop_index("ix_search_index_shop_available", table_name="search_indexes")
    op.execute("DROP INDEX IF EXISTS ix_search_index_barcode_trgm")
    op.execute("DROP INDEX IF EXISTS ix_search_index_search_text_trgm")
    op.execute("DROP INDEX IF EXISTS ix_search_index_search_vector_gin")
    op.drop_table("search_indexes")
    op.execute("DROP TYPE IF EXISTS search_index_sync_status")
    op.execute("DROP TYPE IF EXISTS search_index_entity_type")

    # === 3. Drops pg_trgm (leave extension installed — may be used elsewhere) ===
    # Do NOT drop pg_trgm here — could break other features in the future
