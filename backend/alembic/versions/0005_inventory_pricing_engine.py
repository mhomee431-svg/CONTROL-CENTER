"""Core Inventory and Pricing Engine

Revision ID: 0005
Revises: 0004
Create Date: 2026-08-21

This migration implements the Phase 19 Core Inventory and Pricing Engine:
- Added LIMITED_STOCK and UNKNOWN to stock_status enum
- Added customer_stock_status enum
- Added freshness_status enum
- Added shop-level SKU to shop_products
- Added is_active to shop_products
- Added freshness_status to shop_products
- Added MRP tracking to price_history (old_mrp, new_mrp)
- Added freshness tracking to inventory (freshness_status, freshness_checked_at)
- Added unique constraint on shop_products (shop_id, sku)
- Added MRP non-negative check constraint
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = "0005"
down_revision: Union[str, None] = "0004"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # === 1. Update stock_status enum (add LIMITED_STOCK, UNKNOWN) ===
    op.execute("ALTER TYPE stock_status RENAME TO stock_status_old")
    op.execute(
        "CREATE TYPE stock_status AS ENUM "
        "('IN_STOCK', 'LOW_STOCK', 'LIMITED_STOCK', 'OUT_OF_STOCK', 'UNKNOWN', 'PRE_ORDER', 'BACK_ORDER')"
    )
    # shop_products.stock_status and inventory.stock_status carry TEXT defaults
    # (0002 server_default='IN_STOCK'); drop the defaults before casting to the
    # new ENUM, re-apply after (Postgres can't auto-cast a text default).
    op.execute("ALTER TABLE shop_products ALTER COLUMN stock_status DROP DEFAULT")
    op.execute(
        "ALTER TABLE shop_products ALTER COLUMN stock_status "
        "TYPE stock_status USING stock_status::text::stock_status"
    )
    op.execute("ALTER TABLE shop_products ALTER COLUMN stock_status SET DEFAULT 'IN_STOCK'::stock_status")
    op.execute("ALTER TABLE inventory ALTER COLUMN stock_status DROP DEFAULT")
    op.execute(
        "ALTER TABLE inventory ALTER COLUMN stock_status "
        "TYPE stock_status USING stock_status::text::stock_status"
    )
    op.execute("ALTER TABLE inventory ALTER COLUMN stock_status SET DEFAULT 'IN_STOCK'::stock_status")
    op.execute("DROP TYPE stock_status_old")

    # === 2. Create customer_stock_status enum ===
    op.execute(
        "DO $$ BEGIN CREATE TYPE customer_stock_status AS ENUM "
        "('IN_STOCK', 'LIMITED_STOCK', 'OUT_OF_STOCK', 'UNKNOWN'); "
        "EXCEPTION WHEN duplicate_object THEN NULL; END $$;"
    )

    # === 3. Create freshness_status enum ===
    op.execute(
        "DO $$ BEGIN CREATE TYPE freshness_status AS ENUM "
        "('RECENTLY_UPDATED', 'STALE'); "
        "EXCEPTION WHEN duplicate_object THEN NULL; END $$;"
    )

    # === 4. Add shop-level SKU to shop_products ===
    op.add_column("shop_products", sa.Column("sku", sa.String(100), nullable=True))
    op.create_index("ix_shop_products_sku", "shop_products", ["sku"])
    op.create_unique_constraint("uq_shop_product_shop_sku", "shop_products", ["shop_id", "sku"])

    # === 5. Add is_active to shop_products ===
    op.add_column("shop_products", sa.Column("is_active", sa.Boolean(), server_default=sa.text("true"), nullable=False))
    op.create_index("ix_shop_products_is_active", "shop_products", ["is_active"])

    # === 6. Add freshness_status to shop_products ===
    op.add_column(
        "shop_products",
        sa.Column("freshness_status", sa.Enum(name="freshness_status", native_enum=False), nullable=True),
    )
    op.create_index("ix_shop_products_freshness_status", "shop_products", ["freshness_status"])

    # === 7. Add MRP non-negative check constraint ===
    op.execute("ALTER TABLE shop_products ADD CONSTRAINT ck_shop_products_mrp_non_negative CHECK (mrp >= 0)")

    # === 8. Add MRP tracking to price_history ===
    op.add_column("price_history", sa.Column("old_mrp", sa.Numeric(12, 2), nullable=True))
    op.add_column("price_history", sa.Column("new_mrp", sa.Numeric(12, 2), nullable=True))
    op.execute("ALTER TABLE price_history ADD CONSTRAINT ck_price_history_old_mrp_non_negative CHECK (old_mrp >= 0)")
    op.execute("ALTER TABLE price_history ADD CONSTRAINT ck_price_history_new_mrp_non_negative CHECK (new_mrp >= 0)")

    # === 9. Add freshness tracking to inventory ===
    op.add_column(
        "inventory",
        sa.Column("freshness_status", sa.Enum(name="freshness_status", native_enum=False), nullable=True),
    )
    op.add_column("inventory", sa.Column("freshness_checked_at", sa.DateTime(timezone=True), nullable=True))
    op.create_index("ix_inventory_freshness_status", "inventory", ["freshness_status"])


def downgrade() -> None:
    # === 1. Remove freshness tracking from inventory ===
    op.drop_index("ix_inventory_freshness_status", table_name="inventory")
    op.drop_column("inventory", "freshness_checked_at")
    op.drop_column("inventory", "freshness_status")

    # === 2. Remove MRP tracking from price_history ===
    op.execute("ALTER TABLE price_history DROP CONSTRAINT IF EXISTS ck_price_history_new_mrp_non_negative")
    op.execute("ALTER TABLE price_history DROP CONSTRAINT IF EXISTS ck_price_history_old_mrp_non_negative")
    op.drop_column("price_history", "new_mrp")
    op.drop_column("price_history", "old_mrp")

    # === 3. Remove MRP non-negative check constraint ===
    op.execute("ALTER TABLE shop_products DROP CONSTRAINT IF EXISTS ck_shop_products_mrp_non_negative")

    # === 4. Remove freshness_status from shop_products ===
    op.drop_index("ix_shop_products_freshness_status", table_name="shop_products")
    op.drop_column("shop_products", "freshness_status")

    # === 5. Remove is_active from shop_products ===
    op.drop_index("ix_shop_products_is_active", table_name="shop_products")
    op.drop_column("shop_products", "is_active")

    # === 6. Remove shop-level SKU from shop_products ===
    op.drop_constraint("uq_shop_product_shop_sku", "shop_products", type_="unique")
    op.drop_index("ix_shop_products_sku", table_name="shop_products")
    op.drop_column("shop_products", "sku")

    # === 7. Drop freshness_status enum ===
    op.execute("DROP TYPE IF EXISTS freshness_status")

    # === 8. Drop customer_stock_status enum ===
    op.execute("DROP TYPE IF EXISTS customer_stock_status")

    # === 9. Revert stock_status enum ===
    op.execute("ALTER TYPE stock_status RENAME TO stock_status_new")
    op.execute(
        "CREATE TYPE stock_status AS ENUM "
        "('IN_STOCK', 'LOW_STOCK', 'OUT_OF_STOCK', 'PRE_ORDER', 'BACK_ORDER')"
    )
    op.execute("ALTER TABLE shop_products ALTER COLUMN stock_status DROP DEFAULT")
    op.execute(
        "ALTER TABLE shop_products ALTER COLUMN stock_status "
        "TYPE stock_status USING stock_status::text::stock_status"
    )
    op.execute("ALTER TABLE shop_products ALTER COLUMN stock_status SET DEFAULT 'IN_STOCK'::stock_status")
    op.execute("ALTER TABLE inventory ALTER COLUMN stock_status DROP DEFAULT")
    op.execute(
        "ALTER TABLE inventory ALTER COLUMN stock_status "
        "TYPE stock_status USING stock_status::text::stock_status"
    )
    op.execute("ALTER TABLE inventory ALTER COLUMN stock_status SET DEFAULT 'IN_STOCK'::stock_status")
    op.execute("DROP TYPE stock_status_new")