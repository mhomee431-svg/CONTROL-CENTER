"""Shop Management System

Revision ID: 0004
Revises: 0003
Create Date: 2026-08-21

This migration implements the Phase 18 Shop Management System:
- Updated shop_status enum with full lifecycle (REGISTERED, DOCUMENTS_SUBMITTED, PENDING_VERIFICATION, VERIFIED, REJECTED, SUSPENDED, ACTIVE, CLOSED)
- Added shop_category enum
- Added shop profile fields (slug, tagline, cover_image_url, logo_url, alternate_phone, whatsapp_number, etc.)
- Added shop operational fields (delivery, pickup, min_order, gstin, fssai, etc.)
- Added shop lifecycle tracking fields (rejection_reason, suspension_reason, suspended_at, reactivated_at, closed_at)
- Added address fields (landmark, latitude, longitude, is_verified)
- Added document fields (verified_by, rejection_reason)
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = "0004"
down_revision: Union[str, None] = "0003"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # === 1. Update shop_status enum with full lifecycle ===
    op.execute("ALTER TYPE shop_status RENAME TO shop_status_old")
    op.execute(
        "CREATE TYPE shop_status AS ENUM "
        "('REGISTERED', 'DOCUMENTS_SUBMITTED', 'PENDING_VERIFICATION', 'VERIFIED', "
        "'REJECTED', 'SUSPENDED', 'ACTIVE', 'CLOSED')"
    )
    op.execute(
        "ALTER TABLE shops ALTER COLUMN status "
        "TYPE shop_status USING status::text::shop_status"
    )
    op.execute("DROP TYPE shop_status_old")

    # === 2. Create shop_category enum ===
    op.execute(
        "DO $$ BEGIN CREATE TYPE shop_category AS ENUM "
        "('GROCERY', 'ELECTRONICS', 'PHARMACY', 'HARDWARE', 'FASHION', 'RESTAURANT', "
        "'BAKERY', 'DAIRY', 'MEAT', 'VEGETABLES', 'STATIONERY', 'TOYS', 'BEAUTY', 'OTHER'); "
        "EXCEPTION WHEN duplicate_object THEN NULL; END $$;"
    )

    # === 3. Add shop profile fields ===
    op.add_column("shops", sa.Column("slug", sa.String(280), nullable=True))
    op.add_column("shops", sa.Column("tagline", sa.String(255), nullable=True))
    op.add_column("shops", sa.Column("cover_image_url", sa.String(500), nullable=True))
    op.add_column("shops", sa.Column("logo_url", sa.String(500), nullable=True))
    op.add_column("shops", sa.Column("alternate_phone", sa.String(20), nullable=True))
    op.add_column("shops", sa.Column("whatsapp_number", sa.String(20), nullable=True))
    op.add_column("shops", sa.Column("is_accepting_orders", sa.Boolean(), server_default=sa.text("true"), nullable=False))
    op.add_column("shops", sa.Column("category", sa.Enum(name="shop_category", native_enum=False), nullable=True))
    op.add_column("shops", sa.Column("subcategories", sa.String(500), nullable=True))
    op.add_column("shops", sa.Column("latitude", sa.Float(), nullable=True))
    op.add_column("shops", sa.Column("longitude", sa.Float(), nullable=True))

    # === 4. Add shop lifecycle tracking fields ===
    op.add_column("shops", sa.Column("rejection_reason", sa.Text(), nullable=True))
    op.add_column("shops", sa.Column("suspension_reason", sa.Text(), nullable=True))
    op.add_column("shops", sa.Column("suspended_at", sa.DateTime(timezone=True), nullable=True))
    op.add_column("shops", sa.Column("reactivated_at", sa.DateTime(timezone=True), nullable=True))
    op.add_column("shops", sa.Column("closed_at", sa.DateTime(timezone=True), nullable=True))

    # === 5. Add shop operational fields ===
    op.add_column("shops", sa.Column("min_order_amount", sa.Float(), server_default=sa.text("0"), nullable=True))
    op.add_column("shops", sa.Column("delivery_radius_km", sa.Float(), server_default=sa.text("5"), nullable=True))
    op.add_column("shops", sa.Column("delivery_fee", sa.Float(), server_default=sa.text("0"), nullable=True))
    op.add_column("shops", sa.Column("free_delivery_above", sa.Float(), server_default=sa.text("0"), nullable=True))
    op.add_column("shops", sa.Column("is_delivery_available", sa.Boolean(), server_default=sa.text("true"), nullable=False))
    op.add_column("shops", sa.Column("is_pickup_available", sa.Boolean(), server_default=sa.text("true"), nullable=False))
    op.add_column("shops", sa.Column("gstin", sa.String(50), nullable=True))
    op.add_column("shops", sa.Column("fssai_license", sa.String(50), nullable=True))
    op.add_column("shops", sa.Column("established_year", sa.Integer(), nullable=True))
    op.add_column("shops", sa.Column("created_by", sa.Integer(), sa.ForeignKey("users.id"), nullable=True))

    # === 6. Create indexes ===
    op.create_index("ix_shops_slug", "shops", ["slug"], unique=True)
    op.create_index("ix_shops_category", "shops", ["category"])
    op.create_index("ix_shops_created_by", "shops", ["created_by"])

    # === 7. Add address fields ===
    op.add_column("shop_addresses", sa.Column("landmark", sa.String(255), nullable=True))
    op.add_column("shop_addresses", sa.Column("latitude", sa.Float(), nullable=True))
    op.add_column("shop_addresses", sa.Column("longitude", sa.Float(), nullable=True))
    op.add_column("shop_addresses", sa.Column("is_verified", sa.Boolean(), server_default=sa.text("false"), nullable=False))

    # === 8. Add document fields ===
    op.add_column("shop_documents", sa.Column("verified_by", sa.Integer(), sa.ForeignKey("users.id"), nullable=True))
    op.add_column("shop_documents", sa.Column("rejection_reason", sa.Text(), nullable=True))


def downgrade() -> None:
    # === 1. Remove document fields ===
    op.drop_column("shop_documents", "rejection_reason")
    op.drop_column("shop_documents", "verified_by")

    # === 2. Remove address fields ===
    op.drop_column("shop_addresses", "is_verified")
    op.drop_column("shop_addresses", "longitude")
    op.drop_column("shop_addresses", "latitude")
    op.drop_column("shop_addresses", "landmark")

    # === 3. Drop indexes ===
    op.drop_index("ix_shops_created_by", table_name="shops")
    op.drop_index("ix_shops_category", table_name="shops")
    op.drop_index("ix_shops_slug", table_name="shops")

    # === 4. Remove shop operational fields ===
    op.drop_column("shops", "created_by")
    op.drop_column("shops", "established_year")
    op.drop_column("shops", "fssai_license")
    op.drop_column("shops", "gstin")
    op.drop_column("shops", "is_pickup_available")
    op.drop_column("shops", "is_delivery_available")
    op.drop_column("shops", "free_delivery_above")
    op.drop_column("shops", "delivery_fee")
    op.drop_column("shops", "delivery_radius_km")
    op.drop_column("shops", "min_order_amount")

    # === 5. Remove shop lifecycle tracking fields ===
    op.drop_column("shops", "closed_at")
    op.drop_column("shops", "reactivated_at")
    op.drop_column("shops", "suspended_at")
    op.drop_column("shops", "suspension_reason")
    op.drop_column("shops", "rejection_reason")

    # === 6. Remove shop profile fields ===
    op.drop_column("shops", "longitude")
    op.drop_column("shops", "latitude")
    op.drop_column("shops", "subcategories")
    op.drop_column("shops", "category")
    op.drop_column("shops", "is_accepting_orders")
    op.drop_column("shops", "whatsapp_number")
    op.drop_column("shops", "alternate_phone")
    op.drop_column("shops", "logo_url")
    op.drop_column("shops", "cover_image_url")
    op.drop_column("shops", "tagline")
    op.drop_column("shops", "slug")

    # === 7. Drop shop_category enum ===
    op.execute("DROP TYPE IF EXISTS shop_category")

    # === 8. Revert shop_status enum ===
    op.execute("ALTER TYPE shop_status RENAME TO shop_status_new")
    op.execute(
        "CREATE TYPE shop_status AS ENUM "
        "('PENDING', 'ACTIVE', 'SUSPENDED', 'CLOSED', 'REJECTED')"
    )
    op.execute(
        "ALTER TABLE shops ALTER COLUMN status "
        "TYPE shop_status USING status::text::shop_status"
    )
    op.execute("DROP TYPE shop_status_new")