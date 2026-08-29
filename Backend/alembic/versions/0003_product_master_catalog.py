"""Product Master Catalog

Revision ID: 0003
Revises: 0002
Create Date: 2026-08-21

This migration implements the Phase 17 Product Master Catalog:
- Updated product lifecycle states (DRAFT, PENDING_REVIEW, APPROVED, REJECTED, INACTIVE, ARCHIVED)
- Added subcategory support to product_masters
- Added rejection tracking fields to product_masters
- Added search_updated_at to product_masters
- Added is_subcategory flag to categories
- Added IdentifierType enum and updated product_identifiers
- Added barcode_relationships table
- Added composite index on product_masters (name, brand_id)
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = "0003"
down_revision: Union[str, None] = "0002"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # === 1. Create identifier_type enum ===
    op.execute(
        "DO $$ BEGIN CREATE TYPE identifier_type AS ENUM "
        "('EAN', 'UPC', 'ISBN', 'GTIN', 'ASIN', 'SKU', 'MPN', 'MODEL_NUMBER', 'JAN', 'ITF', 'CUSTOM'); "
        "EXCEPTION WHEN duplicate_object THEN NULL; END $$;"
    )

    # === 2. Update product_status enum (add PENDING_REVIEW, APPROVED; remove ACTIVE, PENDING_APPROVAL) ===
    op.execute("ALTER TYPE product_status RENAME TO product_status_old")
    op.execute(
        "CREATE TYPE product_status AS ENUM "
        "('DRAFT', 'PENDING_REVIEW', 'APPROVED', 'REJECTED', 'INACTIVE', 'ARCHIVED')"
    )
    # product_masters.status carries a TEXT default ('DRAFT') from 0002 —
    # Postgres can't auto-cast it to the new ENUM, so drop the default first,
    # cast, then re-apply the default (now with the literal).
    op.execute("ALTER TABLE product_masters ALTER COLUMN status DROP DEFAULT")
    op.execute(
        "ALTER TABLE product_masters ALTER COLUMN status "
        "TYPE product_status USING status::text::product_status"
    )
    op.execute("ALTER TABLE product_masters ALTER COLUMN status SET DEFAULT 'DRAFT'::product_status")
    op.execute("DROP TYPE product_status_old")

    # === 3. Update shop_product_status enum (add PENDING_REVIEW, APPROVED, REJECTED; remove PENDING_APPROVAL) ===
    op.execute("ALTER TYPE shop_product_status RENAME TO shop_product_status_old")
    op.execute(
        "CREATE TYPE shop_product_status AS ENUM "
        "('ACTIVE', 'INACTIVE', 'DISCONTINUED', 'PENDING_REVIEW', 'APPROVED', 'REJECTED')"
    )
    # same DROP DEFAULT / cast / SET DEFAULT dance for shop_products.status
    op.execute("ALTER TABLE shop_products ALTER COLUMN status DROP DEFAULT")
    op.execute(
        "ALTER TABLE shop_products ALTER COLUMN status "
        "TYPE shop_product_status USING status::text::shop_product_status"
    )
    op.execute("ALTER TABLE shop_products ALTER COLUMN status SET DEFAULT 'ACTIVE'::shop_product_status")
    op.execute("DROP TYPE shop_product_status_old")

    # === 4. Add subcategory support to product_masters ===
    op.add_column("product_masters", sa.Column("subcategory_id", sa.Integer(), sa.ForeignKey("categories.id"), nullable=True))
    op.create_index("ix_product_masters_subcategory_id", "product_masters", ["subcategory_id"])

    # === 5. Add rejection tracking fields ===
    op.add_column("product_masters", sa.Column("rejected_by", sa.Integer(), sa.ForeignKey("users.id"), nullable=True))
    op.add_column("product_masters", sa.Column("rejected_at", sa.DateTime(timezone=True), nullable=True))
    op.add_column("product_masters", sa.Column("rejection_reason", sa.Text(), nullable=True))

    # === 6. Add search_updated_at ===
    op.add_column("product_masters", sa.Column("search_updated_at", sa.DateTime(timezone=True), nullable=True))

    # === 7. Add composite index on name + brand ===
    op.create_index("ix_product_masters_name_brand", "product_masters", ["name", "brand_id"])

    # === 8. Add is_subcategory to categories ===
    op.add_column("categories", sa.Column("is_subcategory", sa.Boolean(), server_default=sa.text("false"), nullable=False))

    # === 9. Update product_identifiers to use identifier_type enum ===
    op.execute(
        "ALTER TABLE product_identifiers ALTER COLUMN identifier_type "
        "TYPE identifier_type USING identifier_type::text::identifier_type"
    )
    op.add_column("product_identifiers", sa.Column("is_active", sa.Boolean(), server_default=sa.text("true"), nullable=False))

    # === 10. Create barcode_relationships table ===
    op.create_table(
        "barcode_relationships",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("product_master_id", sa.Integer(), sa.ForeignKey("product_masters.id"), nullable=False),
        sa.Column("barcode", sa.String(100), nullable=False),
        sa.Column("relationship_type", sa.String(50), nullable=False),
        sa.Column("related_product_master_id", sa.Integer(), sa.ForeignKey("product_masters.id"), nullable=True),
        sa.Column("is_active", sa.Boolean(), server_default=sa.text("true"), nullable=False),
        sa.Column("notes", sa.Text(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.UniqueConstraint("barcode", "relationship_type", name="uq_barcode_relationship_type"),
    )
    op.create_index("ix_barcode_relationships_id", "barcode_relationships", ["id"])
    op.create_index("ix_barcode_relationships_product_master_id", "barcode_relationships", ["product_master_id"])
    op.create_index("ix_barcode_relationships_barcode", "barcode_relationships", ["barcode"])
    op.create_index("ix_barcode_relationships_related_product_master_id", "barcode_relationships", ["related_product_master_id"])


def downgrade() -> None:
    # === 1. Drop barcode_relationships table ===
    op.drop_table("barcode_relationships")

    # === 2. Remove is_active from product_identifiers ===
    op.drop_column("product_identifiers", "is_active")

    # === 3. Revert identifier_type to string ===
    op.execute(
        "ALTER TABLE product_identifiers ALTER COLUMN identifier_type TYPE VARCHAR(50) "
        "USING identifier_type::text"
    )
    op.execute("DROP TYPE IF EXISTS identifier_type")

    # === 4. Remove is_subcategory from categories ===
    op.drop_column("categories", "is_subcategory")

    # === 5. Drop composite index ===
    op.drop_index("ix_product_masters_name_brand", table_name="product_masters")

    # === 6. Remove search_updated_at ===
    op.drop_column("product_masters", "search_updated_at")

    # === 7. Remove rejection tracking fields ===
    op.drop_column("product_masters", "rejection_reason")
    op.drop_column("product_masters", "rejected_at")
    op.drop_column("product_masters", "rejected_by")

    # === 8. Remove subcategory support ===
    op.drop_index("ix_product_masters_subcategory_id", table_name="product_masters")
    op.drop_column("product_masters", "subcategory_id")

    # === 9. Revert shop_product_status enum ===
    op.execute("ALTER TYPE shop_product_status RENAME TO shop_product_status_new")
    op.execute(
        "CREATE TYPE shop_product_status AS ENUM "
        "('ACTIVE', 'INACTIVE', 'DISCONTINUED', 'PENDING_APPROVAL')"
    )
    op.execute(
        "ALTER TABLE shop_products ALTER COLUMN status "
        "TYPE shop_product_status USING status::text::shop_product_status"
    )
    op.execute("DROP TYPE shop_product_status_new")

    # === 10. Revert product_status enum ===
    op.execute("ALTER TYPE product_status RENAME TO product_status_new")
    op.execute(
        "CREATE TYPE product_status AS ENUM "
        "('DRAFT', 'ACTIVE', 'INACTIVE', 'PENDING_APPROVAL', 'REJECTED', 'ARCHIVED')"
    )
    op.execute(
        "ALTER TABLE product_masters ALTER COLUMN status "
        "TYPE product_status USING status::text::product_status"
    )
    op.execute("DROP TYPE product_status_new")