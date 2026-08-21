"""Expanded Database Architecture

Revision ID: 0002
Revises: 0001
Create Date: 2026-08-19

This migration implements the complete Phase 13 database architecture:
- PostGIS extension for geospatial queries
- Roles & permissions (RBAC)
- Expanded user model with lifecycle status
- Customers & customer addresses
- Expanded shop model with owner/manager/address/hours/holidays/documents/verification
- Complete product master/variant/image/attribute/identifier/price/offer model
- Search history/events/popular searches/barcode scans
- POS integrations/devices/sync jobs/sync logs
- Notification preferences & device tokens
- Admin actions/notes/product approvals/reports/complaints/audit logs
- Analytics (product views/shop views/product clicks/inventory events/system metrics)
- System settings & feature flags
- Subscriptions & payments

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
import geoalchemy2


# revision identifiers, used by Alembic.
revision: str = "0002"
down_revision: Union[str, None] = "0001"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


# Enum types that need to be created before tables
POOL_TYPES = [
    "user_status",
    "shop_status",
    "verification_status",
    "product_status",
    "shop_product_status",
    "stock_status",
    "inventory_source",
    "offer_status",
    "offer_type",
    "approval_status",
    "complaint_status",
    "pos_integration_status",
    "pos_sync_status",
    "subscription_status",
    "billing_cycle",
]


def upgrade() -> None:
    # === 1. Enable PostGIS extension ===
    op.execute("CREATE EXTENSION IF NOT EXISTS postgis")

    # === 2. Create enum types ===
    enums = [
        ("user_status", ["ACTIVE", "INACTIVE", "SUSPENDED", "BANNED", "PENDING_VERIFICATION"]),
        ("shop_status", ["PENDING", "ACTIVE", "SUSPENDED", "CLOSED", "REJECTED"]),
        ("verification_status", ["PENDING", "SUBMITTED", "UNDER_REVIEW", "VERIFIED", "REJECTED", "EXPIRED"]),
        ("product_status", ["DRAFT", "ACTIVE", "INACTIVE", "PENDING_APPROVAL", "REJECTED", "ARCHIVED"]),
        ("shop_product_status", ["ACTIVE", "INACTIVE", "DISCONTINUED", "PENDING_APPROVAL"]),
        ("stock_status", ["IN_STOCK", "LOW_STOCK", "OUT_OF_STOCK", "PRE_ORDER", "BACK_ORDER"]),
        ("inventory_source", ["MANUAL", "BARCODE_SCAN", "EXCEL_UPLOAD", "POS_INTEGRATION", "SYSTEM"]),
        ("offer_status", ["DRAFT", "ACTIVE", "PAUSED", "EXPIRED", "CANCELLED"]),
        ("offer_type", ["PERCENTAGE_DISCOUNT", "FLAT_DISCOUNT", "BUY_X_GET_Y", "BUNDLE", "FREE_SHIPPING"]),
        ("approval_status", ["PENDING", "APPROVED", "REJECTED", "NEEDS_INFO"]),
        ("complaint_status", ["OPEN", "IN_PROGRESS", "RESOLVED", "CLOSED", "REJECTED"]),
        ("pos_integration_status", ["ACTIVE", "INACTIVE", "SUSPENDED", "ERROR"]),
        ("pos_sync_status", ["PENDING", "RUNNING", "COMPLETED", "FAILED", "CANCELLED"]),
        ("subscription_status", ["ACTIVE", "PAST_DUE", "CANCELED", "TRIALING", "INCOMPLETE"]),
        ("billing_cycle", ["WEEKLY", "MONTHLY", "QUARTERLY", "ANNUAL"]),
    ]
    for name, vals in enums:
        values_str = ", ".join(f"'{v}'" for v in vals)
        op.execute(
            f"DO $$ BEGIN CREATE TYPE {name} AS ENUM ({values_str}); "
            "EXCEPTION WHEN duplicate_object THEN NULL; END $$;"
        )

    # === 3. Remove old incompatible tables/columns ===
    # Drop old inventory (references old products table)
    op.drop_table("inventory")
    # Drop old products table (replaced by product_masters)
    op.drop_table("products")
    # Remove latitude/longitude from shops, replace with location geography
    op.drop_column("shops", "latitude")
    op.drop_column("shops", "longitude")

    # === 4. Create roles & permissions ===
    op.create_table(
        "roles",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("name", sa.String(50), nullable=False),
        sa.Column("description", sa.String(255), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
    )
    op.create_index("ix_roles_id", "roles", ["id"])
    op.create_index("ix_roles_name", "roles", ["name"], unique=True)

    op.create_table(
        "permissions",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("name", sa.String(100), nullable=False),
        sa.Column("description", sa.String(255), nullable=True),
        sa.Column("resource", sa.String(50), nullable=False),
        sa.Column("action", sa.String(50), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
    )
    op.create_index("ix_permissions_id", "permissions", ["id"])
    op.create_index("ix_permissions_name", "permissions", ["name"], unique=True)

    op.create_table(
        "role_permissions",
        sa.Column("role_id", sa.Integer(), sa.ForeignKey("roles.id", ondelete="CASCADE"), primary_key=True),
        sa.Column("permission_id", sa.Integer(), sa.ForeignKey("permissions.id", ondelete="CASCADE"), primary_key=True),
    )

    # === 5. Update users table ===
    op.add_column("users", sa.Column("password_hash", sa.String(255), nullable=True))
    op.add_column("users", sa.Column("role_id", sa.Integer(), sa.ForeignKey("roles.id"), nullable=True))
    op.execute("ALTER TABLE users ADD COLUMN status user_status NOT NULL DEFAULT 'ACTIVE'")
    op.add_column("users", sa.Column("is_deleted", sa.Boolean(), server_default=sa.text("false"), nullable=False))
    op.add_column("users", sa.Column("deleted_at", sa.DateTime(timezone=True), nullable=True))
    op.add_column("users", sa.Column("last_login_at", sa.DateTime(timezone=True), nullable=True))
    op.add_column("users", sa.Column("last_login_ip", sa.String(45), nullable=True))
    op.create_index("ix_users_role_id", "users", ["role_id"])
    op.create_index("ix_users_email", "users", ["email"], unique=False)

    # === 6. Create customers & addresses ===
    op.create_table(
        "customers",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("user_id", sa.Integer(), sa.ForeignKey("users.id"), nullable=False),
        sa.Column("date_of_birth", sa.DateTime(timezone=True), nullable=True),
        sa.Column("gender", sa.String(20), nullable=True),
        sa.Column("preferred_language", sa.String(10), server_default="en"),
        sa.Column("default_address_id", sa.Integer(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.Column("is_deleted", sa.Boolean(), server_default=sa.text("false"), nullable=False),
        sa.Column("deleted_at", sa.DateTime(timezone=True), nullable=True),
        sa.UniqueConstraint("user_id", name="uq_customers_user_id"),
    )
    op.create_index("ix_customers_id", "customers", ["id"])
    op.create_index("ix_customers_user_id", "customers", ["user_id"])

    op.create_table(
        "customer_addresses",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("user_id", sa.Integer(), sa.ForeignKey("users.id"), nullable=False),
        sa.Column("customer_id", sa.Integer(), sa.ForeignKey("customers.id"), nullable=True),
        sa.Column("label", sa.String(50), nullable=True),
        sa.Column("address_line1", sa.String(255), nullable=False),
        sa.Column("address_line2", sa.String(255), nullable=True),
        sa.Column("city", sa.String(100), nullable=False),
        sa.Column("state", sa.String(100), nullable=False),
        sa.Column("pincode", sa.String(10), nullable=False),
        sa.Column("country", sa.String(100), server_default="India"),
        sa.Column("location", geoalchemy2.types.Geography(geometry_type="POINT", srid=4326), nullable=True),
        sa.Column("is_default", sa.Boolean(), server_default=sa.text("false")),
        sa.Column("is_verified", sa.Boolean(), server_default=sa.text("false")),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.Column("is_deleted", sa.Boolean(), server_default=sa.text("false"), nullable=False),
        sa.Column("deleted_at", sa.DateTime(timezone=True), nullable=True),
    )
    op.create_index("ix_customer_addresses_id", "customer_addresses", ["id"])
    op.create_index("ix_customer_addresses_user_id", "customer_addresses", ["user_id"])
    op.create_index("ix_customer_addresses_customer_id", "customer_addresses", ["customer_id"])
    op.create_index("ix_customer_addresses_pincode", "customer_addresses", ["pincode"])

    # === 7. Update shops table with location geography and new fields ===
    op.add_column("shops", sa.Column("email", sa.String(255), nullable=True))
    op.add_column("shops", sa.Column("website_url", sa.String(500), nullable=True))
    op.execute("ALTER TABLE shops ADD COLUMN status shop_status NOT NULL DEFAULT 'PENDING'")
    op.add_column("shops", sa.Column("is_featured", sa.Boolean(), server_default=sa.text("false")))
    op.add_column("shops", sa.Column("is_open_24x7", sa.Boolean(), server_default=sa.text("false")))
    op.add_column("shops", sa.Column("category", sa.String(100), nullable=True))
    op.add_column("shops", sa.Column("location", geoalchemy2.types.Geography(geometry_type="POINT", srid=4326), nullable=True))
    op.add_column("shops", sa.Column("verified_at", sa.DateTime(timezone=True), nullable=True))
    op.add_column("shops", sa.Column("last_inventory_update", sa.DateTime(timezone=True), nullable=True))
    op.add_column("shops", sa.Column("is_deleted", sa.Boolean(), server_default=sa.text("false"), nullable=False))
    op.add_column("shops", sa.Column("deleted_at", sa.DateTime(timezone=True), nullable=True))
    op.execute("ALTER TABLE shops ADD CONSTRAINT ck_shops_rating_range CHECK (rating >= 0 AND rating <= 5)")
    op.execute("ALTER TABLE shops ADD CONSTRAINT ck_shops_review_count_non_negative CHECK (review_count >= 0)")
    op.create_index("ix_shops_phone", "shops", ["phone"])
    op.create_index("ix_shops_category", "shops", ["category"])
    op.create_index("ix_shops_last_inventory_update", "shops", ["last_inventory_update"])

    # === 8. Create shop related tables ===
    op.create_table(
        "shop_owners",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("shop_id", sa.Integer(), sa.ForeignKey("shops.id"), nullable=False),
        sa.Column("user_id", sa.Integer(), sa.ForeignKey("users.id"), nullable=False),
        sa.Column("is_primary", sa.Boolean(), server_default=sa.text("false")),
        sa.Column("is_active", sa.Boolean(), server_default=sa.text("true")),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.Column("is_deleted", sa.Boolean(), server_default=sa.text("false"), nullable=False),
        sa.Column("deleted_at", sa.DateTime(timezone=True), nullable=True),
        sa.UniqueConstraint("shop_id", "user_id", name="uq_shop_owner_shop_user"),
    )
    op.create_index("ix_shop_owners_id", "shop_owners", ["id"])
    op.create_index("ix_shop_owners_shop_id", "shop_owners", ["shop_id"])
    op.create_index("ix_shop_owners_user_id", "shop_owners", ["user_id"])

    op.create_table(
        "shop_managers",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("shop_id", sa.Integer(), sa.ForeignKey("shops.id"), nullable=False),
        sa.Column("user_id", sa.Integer(), sa.ForeignKey("users.id"), nullable=False),
        sa.Column("permissions", sa.String(500), nullable=True),
        sa.Column("is_active", sa.Boolean(), server_default=sa.text("true")),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.Column("is_deleted", sa.Boolean(), server_default=sa.text("false"), nullable=False),
        sa.Column("deleted_at", sa.DateTime(timezone=True), nullable=True),
        sa.UniqueConstraint("shop_id", "user_id", name="uq_shop_manager_shop_user"),
    )
    op.create_index("ix_shop_managers_id", "shop_managers", ["id"])
    op.create_index("ix_shop_managers_shop_id", "shop_managers", ["shop_id"])
    op.create_index("ix_shop_managers_user_id", "shop_managers", ["user_id"])

    op.create_table(
        "shop_addresses",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("shop_id", sa.Integer(), sa.ForeignKey("shops.id"), nullable=False),
        sa.Column("address_line1", sa.String(255), nullable=False),
        sa.Column("address_line2", sa.String(255), nullable=True),
        sa.Column("city", sa.String(100), nullable=False),
        sa.Column("state", sa.String(100), nullable=False),
        sa.Column("pincode", sa.String(10), nullable=False),
        sa.Column("country", sa.String(100), server_default="India"),
        sa.Column("is_primary", sa.Boolean(), server_default=sa.text("true")),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.Column("is_deleted", sa.Boolean(), server_default=sa.text("false"), nullable=False),
        sa.Column("deleted_at", sa.DateTime(timezone=True), nullable=True),
    )
    op.create_index("ix_shop_addresses_id", "shop_addresses", ["id"])
    op.create_index("ix_shop_addresses_shop_id", "shop_addresses", ["shop_id"])
    op.create_index("ix_shop_addresses_city", "shop_addresses", ["city"])
    op.create_index("ix_shop_addresses_pincode", "shop_addresses", ["pincode"])

    op.create_table(
        "shop_hours",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("shop_id", sa.Integer(), sa.ForeignKey("shops.id"), nullable=False),
        sa.Column("day_of_week", sa.Integer(), nullable=False),
        sa.Column("open_time", sa.Time(), nullable=False),
        sa.Column("close_time", sa.Time(), nullable=False),
        sa.Column("is_closed", sa.Boolean(), server_default=sa.text("false")),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.UniqueConstraint("shop_id", "day_of_week", name="uq_shop_hours_shop_day"),
    )
    op.create_index("ix_shop_hours_id", "shop_hours", ["id"])
    op.create_index("ix_shop_hours_shop_id", "shop_hours", ["shop_id"])
    op.execute("ALTER TABLE shop_hours ADD CONSTRAINT ck_shop_hours_day_range CHECK (day_of_week >= 0 AND day_of_week <= 6)")

    op.create_table(
        "shop_holidays",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("shop_id", sa.Integer(), sa.ForeignKey("shops.id"), nullable=False),
        sa.Column("holiday_date", sa.Date(), nullable=False),
        sa.Column("reason", sa.String(255), nullable=True),
        sa.Column("is_recurring_yearly", sa.Boolean(), server_default=sa.text("false")),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
    )
    op.create_index("ix_shop_holidays_id", "shop_holidays", ["id"])
    op.create_index("ix_shop_holidays_shop_id", "shop_holidays", ["shop_id"])
    op.create_index("ix_shop_holidays_holiday_date", "shop_holidays", ["holiday_date"])

    op.create_table(
        "shop_documents",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("shop_id", sa.Integer(), sa.ForeignKey("shops.id"), nullable=False),
        sa.Column("document_type", sa.String(50), nullable=False),
        sa.Column("document_url", sa.String(500), nullable=False),
        sa.Column("document_number", sa.String(100), nullable=True),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("is_verified", sa.Boolean(), server_default=sa.text("false")),
        sa.Column("verified_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.Column("is_deleted", sa.Boolean(), server_default=sa.text("false"), nullable=False),
        sa.Column("deleted_at", sa.DateTime(timezone=True), nullable=True),
    )
    op.create_index("ix_shop_documents_id", "shop_documents", ["id"])
    op.create_index("ix_shop_documents_shop_id", "shop_documents", ["shop_id"])

    op.create_table(
        "shop_verifications",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("shop_id", sa.Integer(), sa.ForeignKey("shops.id"), nullable=False),
        sa.Column("status", sa.Enum(name="verification_status", native_enum=False), nullable=False, server_default="PENDING"),
        sa.Column("submitted_by", sa.Integer(), sa.ForeignKey("users.id"), nullable=True),
        sa.Column("reviewed_by", sa.Integer(), sa.ForeignKey("users.id"), nullable=True),
        sa.Column("review_notes", sa.Text(), nullable=True),
        sa.Column("submitted_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("reviewed_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("verified_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
    )
    op.create_index("ix_shop_verifications_id", "shop_verifications", ["id"])
    op.create_index("ix_shop_verifications_shop_id", "shop_verifications", ["shop_id"])

    # === 9. Update categories for new fields ===
    op.add_column("categories", sa.Column("slug", sa.String(120), nullable=False, server_default=""))
    op.add_column("categories", sa.Column("description", sa.Text(), nullable=True))
    op.add_column("categories", sa.Column("parent_id", sa.Integer(), sa.ForeignKey("categories.id"), nullable=True))
    op.add_column("categories", sa.Column("sort_order", sa.Integer(), server_default=sa.text("0")))
    op.add_column("categories", sa.Column("is_active", sa.Boolean(), server_default=sa.text("true")))
    op.add_column("categories", sa.Column("is_deleted", sa.Boolean(), server_default=sa.text("false"), nullable=False))
    op.add_column("categories", sa.Column("deleted_at", sa.DateTime(timezone=True), nullable=True))
    op.add_column("categories", sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False))
    op.create_index("ix_categories_slug", "categories", ["slug"], unique=True)
    op.create_index("ix_categories_parent_id", "categories", ["parent_id"])

    # === 10. Create brands table ===
    op.create_table(
        "brands",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("name", sa.String(120), nullable=False),
        sa.Column("slug", sa.String(140), nullable=False),
        sa.Column("description", sa.Text(), nullable=True),
        sa.Column("logo_url", sa.String(500), nullable=True),
        sa.Column("is_active", sa.Boolean(), server_default=sa.text("true")),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.Column("is_deleted", sa.Boolean(), server_default=sa.text("false"), nullable=False),
        sa.Column("deleted_at", sa.DateTime(timezone=True), nullable=True),
    )
    op.create_index("ix_brands_id", "brands", ["id"])
    op.create_index("ix_brands_name", "brands", ["name"], unique=True)
    op.create_index("ix_brands_slug", "brands", ["slug"], unique=True)

    # === 11. Create product_masters table (replaces old products) ===
    op.create_table(
        "product_masters",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("name", sa.String(255), nullable=False),
        sa.Column("slug", sa.String(280), nullable=False),
        sa.Column("description", sa.Text(), nullable=True),
        sa.Column("short_description", sa.String(500), nullable=True),
        sa.Column("category_id", sa.Integer(), sa.ForeignKey("categories.id"), nullable=True),
        sa.Column("brand_id", sa.Integer(), sa.ForeignKey("brands.id"), nullable=True),
        sa.Column("status", sa.Enum(name="product_status", native_enum=False), nullable=False, server_default="DRAFT"),
        sa.Column("is_active", sa.Boolean(), server_default=sa.text("true")),
        sa.Column("is_featured", sa.Boolean(), server_default=sa.text("false")),
        sa.Column("is_searchable", sa.Boolean(), server_default=sa.text("true")),
        sa.Column("base_unit", sa.String(50), nullable=True),
        sa.Column("base_quantity", sa.Float(), nullable=True),
        sa.Column("approved_by", sa.Integer(), sa.ForeignKey("users.id"), nullable=True),
        sa.Column("approved_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("search_metadata", sa.Text(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.Column("is_deleted", sa.Boolean(), server_default=sa.text("false"), nullable=False),
        sa.Column("deleted_at", sa.DateTime(timezone=True), nullable=True),
        sa.UniqueConstraint("slug", name="uq_product_masters_slug"),
        sa.CheckConstraint("length(name) > 0", name="ck_product_masters_name_not_empty"),
    )
    op.create_index("ix_product_masters_id", "product_masters", ["id"])
    op.create_index("ix_product_masters_name", "product_masters", ["name"])
    op.create_index("ix_product_masters_slug", "product_masters", ["slug"])
    op.create_index("ix_product_masters_category_id", "product_masters", ["category_id"])
    op.create_index("ix_product_masters_brand_id", "product_masters", ["brand_id"])

    op.create_table(
        "product_variants",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("product_master_id", sa.Integer(), sa.ForeignKey("product_masters.id"), nullable=False),
        sa.Column("sku", sa.String(100), nullable=False),
        sa.Column("name", sa.String(255), nullable=False),
        sa.Column("description", sa.Text(), nullable=True),
        sa.Column("attributes_json", sa.Text(), nullable=True),
        sa.Column("is_active", sa.Boolean(), server_default=sa.text("true")),
        sa.Column("sort_order", sa.Integer(), server_default=sa.text("0")),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.Column("is_deleted", sa.Boolean(), server_default=sa.text("false"), nullable=False),
        sa.Column("deleted_at", sa.DateTime(timezone=True), nullable=True),
        sa.UniqueConstraint("product_master_id", "sku", name="uq_product_variant_master_sku"),
    )
    op.create_index("ix_product_variants_id", "product_variants", ["id"])
    op.create_index("ix_product_variants_product_master_id", "product_variants", ["product_master_id"])
    op.create_index("ix_product_variants_sku", "product_variants", ["sku"], unique=True)

    op.create_table(
        "product_images",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("product_master_id", sa.Integer(), sa.ForeignKey("product_masters.id"), nullable=False),
        sa.Column("variant_id", sa.Integer(), sa.ForeignKey("product_variants.id"), nullable=True),
        sa.Column("image_url", sa.String(500), nullable=False),
        sa.Column("thumbnail_url", sa.String(500), nullable=True),
        sa.Column("alt_text", sa.String(255), nullable=True),
        sa.Column("sort_order", sa.Integer(), server_default=sa.text("0")),
        sa.Column("is_primary", sa.Boolean(), server_default=sa.text("false")),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
    )
    op.create_index("ix_product_images_id", "product_images", ["id"])
    op.create_index("ix_product_images_product_master_id", "product_images", ["product_master_id"])
    op.create_index("ix_product_images_variant_id", "product_images", ["variant_id"])

    op.create_table(
        "product_attributes",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("product_master_id", sa.Integer(), sa.ForeignKey("product_masters.id"), nullable=False),
        sa.Column("name", sa.String(100), nullable=False),
        sa.Column("is_variant_defining", sa.Boolean(), server_default=sa.text("false")),
        sa.Column("sort_order", sa.Integer(), server_default=sa.text("0")),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
    )
    op.create_index("ix_product_attributes_id", "product_attributes", ["id"])
    op.create_index("ix_product_attributes_product_master_id", "product_attributes", ["product_master_id"])

    op.create_table(
        "product_attribute_values",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("attribute_id", sa.Integer(), sa.ForeignKey("product_attributes.id"), nullable=False),
        sa.Column("value", sa.String(255), nullable=False),
        sa.Column("sort_order", sa.Integer(), server_default=sa.text("0")),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
    )
    op.create_index("ix_product_attribute_values_id", "product_attribute_values", ["id"])
    op.create_index("ix_product_attribute_values_attribute_id", "product_attribute_values", ["attribute_id"])

    op.create_table(
        "product_identifiers",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("product_master_id", sa.Integer(), sa.ForeignKey("product_masters.id"), nullable=False),
        sa.Column("identifier_type", sa.String(50), nullable=False),
        sa.Column("identifier_value", sa.String(100), nullable=False),
        sa.Column("is_primary", sa.Boolean(), server_default=sa.text("false")),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.UniqueConstraint("identifier_type", "identifier_value", name="uq_product_identifier_type_value"),
    )
    op.create_index("ix_product_identifiers_id", "product_identifiers", ["id"])
    op.create_index("ix_product_identifiers_product_master_id", "product_identifiers", ["product_master_id"])
    op.create_index("ix_product_identifiers_identifier_value", "product_identifiers", ["identifier_value"])
    op.create_index("ix_product_identifiers_type_value", "product_identifiers", ["identifier_type", "identifier_value"])

    # === 12. Create shop_products (core bridge) ===
    op.create_table(
        "shop_products",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("shop_id", sa.Integer(), sa.ForeignKey("shops.id"), nullable=False),
        sa.Column("product_master_id", sa.Integer(), sa.ForeignKey("product_masters.id"), nullable=False),
        sa.Column("variant_id", sa.Integer(), sa.ForeignKey("product_variants.id"), nullable=True),
        sa.Column("status", sa.Enum(name="shop_product_status", native_enum=False), nullable=False, server_default="ACTIVE"),
        sa.Column("price", sa.Numeric(12, 2), nullable=False),
        sa.Column("mrp", sa.Numeric(12, 2), nullable=True),
        sa.Column("is_available", sa.Boolean(), server_default=sa.text("true")),
        sa.Column("is_featured", sa.Boolean(), server_default=sa.text("false")),
        sa.Column("is_visible", sa.Boolean(), server_default=sa.text("true")),
        sa.Column("stock_status", sa.Enum(name="stock_status", native_enum=False), nullable=False, server_default="IN_STOCK"),
        sa.Column("last_inventory_update", sa.DateTime(timezone=True), nullable=True),
        sa.Column("last_price_update", sa.DateTime(timezone=True), nullable=True),
        sa.Column("source", sa.Enum(name="inventory_source", native_enum=False), nullable=False, server_default="MANUAL"),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.Column("is_deleted", sa.Boolean(), server_default=sa.text("false"), nullable=False),
        sa.Column("deleted_at", sa.DateTime(timezone=True), nullable=True),
        sa.UniqueConstraint("shop_id", "product_master_id", "variant_id", name="uq_shop_product_shop_master_variant"),
        sa.CheckConstraint("price >= 0", name="ck_shop_products_price_non_negative"),
    )
    op.create_index("ix_shop_products_id", "shop_products", ["id"])
    op.create_index("ix_shop_products_shop_id", "shop_products", ["shop_id"])
    op.create_index("ix_shop_products_product_master_id", "shop_products", ["product_master_id"])
    op.create_index("ix_shop_products_variant_id", "shop_products", ["variant_id"])
    op.create_index("ix_shop_products_is_available", "shop_products", ["is_available"])
    op.create_index("ix_shop_products_stock_status", "shop_products", ["stock_status"])
    op.create_index("ix_shop_products_last_inventory_update", "shop_products", ["last_inventory_update"])
    op.create_index("ix_shop_products_last_price_update", "shop_products", ["last_price_update"])

    # === 13. Create new inventory (references shop_products) ===
    op.create_table(
        "inventory",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("shop_product_id", sa.Integer(), sa.ForeignKey("shop_products.id"), nullable=False),
        sa.Column("quantity", sa.Integer(), server_default=sa.text("0"), nullable=False),
        sa.Column("reserved_quantity", sa.Integer(), server_default=sa.text("0"), nullable=False),
        sa.Column("available_quantity", sa.Integer(), server_default=sa.text("0"), nullable=False),
        sa.Column("is_available", sa.Boolean(), server_default=sa.text("true")),
        sa.Column("stock_status", sa.Enum(name="stock_status", native_enum=False), nullable=False, server_default="IN_STOCK"),
        sa.Column("low_stock_threshold", sa.Integer(), nullable=True),
        sa.Column("last_updated_by", sa.Integer(), sa.ForeignKey("users.id"), nullable=True),
        sa.Column("last_updated_source", sa.Enum(name="inventory_source", native_enum=False), nullable=False, server_default="MANUAL"),
        sa.Column("last_synced_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.UniqueConstraint("shop_product_id", name="uq_inventory_shop_product"),
        sa.CheckConstraint("quantity >= 0", name="ck_inventory_quantity_non_negative"),
    )
    op.create_index("ix_inventory_id", "inventory", ["id"])
    op.create_index("ix_inventory_shop_product_id", "inventory", ["shop_product_id"])
    op.create_index("ix_inventory_is_available", "inventory", ["is_available"])
    op.create_index("ix_inventory_stock_status", "inventory", ["stock_status"])

    op.create_table(
        "inventory_movements",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("inventory_id", sa.Integer(), sa.ForeignKey("inventory.id"), nullable=False),
        sa.Column("quantity_change", sa.Integer(), nullable=False),
        sa.Column("quantity_before", sa.Integer(), nullable=False),
        sa.Column("quantity_after", sa.Integer(), nullable=False),
        sa.Column("movement_type", sa.String(50), nullable=False),
        sa.Column("source", sa.Enum(name="inventory_source", native_enum=False), nullable=False, server_default="MANUAL"),
        sa.Column("reference_type", sa.String(50), nullable=True),
        sa.Column("reference_id", sa.Integer(), nullable=True),
        sa.Column("notes", sa.Text(), nullable=True),
        sa.Column("created_by", sa.Integer(), sa.ForeignKey("users.id"), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
    )
    op.create_index("ix_inventory_movements_id", "inventory_movements", ["id"])
    op.create_index("ix_inventory_movements_inventory_id", "inventory_movements", ["inventory_id"])

    op.create_table(
        "inventory_adjustments",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("inventory_id", sa.Integer(), sa.ForeignKey("inventory.id"), nullable=False),
        sa.Column("adjustment_type", sa.String(50), nullable=False),
        sa.Column("quantity_adjustment", sa.Integer(), nullable=False),
        sa.Column("reason", sa.Text(), nullable=True),
        sa.Column("approved_by", sa.Integer(), sa.ForeignKey("users.id"), nullable=True),
        sa.Column("approved_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
    )
    op.create_index("ix_inventory_adjustments_id", "inventory_adjustments", ["id"])
    op.create_index("ix_inventory_adjustments_inventory_id", "inventory_adjustments", ["inventory_id"])

    op.create_table(
        "price_history",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("shop_product_id", sa.Integer(), sa.ForeignKey("shop_products.id"), nullable=False),
        sa.Column("old_price", sa.Numeric(12, 2), nullable=False),
        sa.Column("new_price", sa.Numeric(12, 2), nullable=False),
        sa.Column("changed_by", sa.Integer(), sa.ForeignKey("users.id"), nullable=True),
        sa.Column("change_source", sa.Enum(name="inventory_source", native_enum=False), nullable=False, server_default="MANUAL"),
        sa.Column("effective_from", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.Column("effective_to", sa.DateTime(timezone=True), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.CheckConstraint("old_price >= 0", name="ck_price_history_old_price_non_negative"),
        sa.CheckConstraint("new_price >= 0", name="ck_price_history_new_price_non_negative"),
    )
    op.create_index("ix_price_history_id", "price_history", ["id"])
    op.create_index("ix_price_history_shop_product_id", "price_history", ["shop_product_id"])

    # === 14. Create offers ===
    op.create_table(
        "offers",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("shop_id", sa.Integer(), sa.ForeignKey("shops.id"), nullable=False),
        sa.Column("title", sa.String(255), nullable=False),
        sa.Column("description", sa.Text(), nullable=True),
        sa.Column("offer_type", sa.Enum(name="offer_type", native_enum=False), nullable=False),
        sa.Column("discount_value", sa.Numeric(12, 2), nullable=True),
        sa.Column("discount_percentage", sa.Float(), nullable=True),
        sa.Column("min_purchase_amount", sa.Numeric(12, 2), nullable=True),
        sa.Column("max_discount_amount", sa.Numeric(12, 2), nullable=True),
        sa.Column("buy_quantity", sa.Integer(), nullable=True),
        sa.Column("get_quantity", sa.Integer(), nullable=True),
        sa.Column("status", sa.Enum(name="offer_status", native_enum=False), nullable=False, server_default="DRAFT"),
        sa.Column("start_date", sa.DateTime(timezone=True), nullable=False),
        sa.Column("end_date", sa.DateTime(timezone=True), nullable=False),
        sa.Column("is_visible", sa.Boolean(), server_default=sa.text("true")),
        sa.Column("terms_conditions", sa.Text(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.Column("is_deleted", sa.Boolean(), server_default=sa.text("false"), nullable=False),
        sa.Column("deleted_at", sa.DateTime(timezone=True), nullable=True),
        sa.CheckConstraint("end_date > start_date", name="ck_offers_end_after_start"),
    )
    op.create_index("ix_offers_id", "offers", ["id"])
    op.create_index("ix_offers_shop_id", "offers", ["shop_id"])

    op.create_table(
        "offer_products",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("offer_id", sa.Integer(), sa.ForeignKey("offers.id"), nullable=False),
        sa.Column("shop_product_id", sa.Integer(), sa.ForeignKey("shop_products.id"), nullable=False),
        sa.Column("is_excluded", sa.Boolean(), server_default=sa.text("false")),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.UniqueConstraint("offer_id", "shop_product_id", name="uq_offer_product_offer_shop_product"),
    )
    op.create_index("ix_offer_products_id", "offer_products", ["id"])
    op.create_index("ix_offer_products_offer_id", "offer_products", ["offer_id"])
    op.create_index("ix_offer_products_shop_product_id", "offer_products", ["shop_product_id"])

    op.create_table(
        "offer_conditions",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("offer_id", sa.Integer(), sa.ForeignKey("offers.id"), nullable=False),
        sa.Column("condition_type", sa.String(50), nullable=False),
        sa.Column("condition_value", sa.String(255), nullable=False),
        sa.Column("operator", sa.String(20), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
    )
    op.create_index("ix_offer_conditions_id", "offer_conditions", ["id"])
    op.create_index("ix_offer_conditions_offer_id", "offer_conditions", ["offer_id"])

    # === 15. Search models ===
    op.create_table(
        "search_history",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("user_id", sa.Integer(), sa.ForeignKey("users.id"), nullable=False),
        sa.Column("query", sa.String(255), nullable=False),
        sa.Column("result_count", sa.Integer(), nullable=True),
        sa.Column("is_successful", sa.Boolean(), server_default=sa.text("true")),
        sa.Column("searched_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
    )
    op.create_index("ix_search_history_id", "search_history", ["id"])
    op.create_index("ix_search_history_user_id", "search_history", ["user_id"])
    op.create_index("ix_search_history_query", "search_history", ["query"])
    op.create_index("ix_search_history_user_query", "search_history", ["user_id", "query"])

    op.create_table(
        "search_events",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("user_id", sa.Integer(), sa.ForeignKey("users.id"), nullable=True),
        sa.Column("session_id", sa.String(100), nullable=True),
        sa.Column("query", sa.String(255), nullable=False),
        sa.Column("event_type", sa.String(50), nullable=False),
        sa.Column("result_count", sa.Integer(), nullable=True),
        sa.Column("clicked_product_id", sa.Integer(), sa.ForeignKey("product_masters.id"), nullable=True),
        sa.Column("clicked_shop_id", sa.Integer(), sa.ForeignKey("shops.id"), nullable=True),
        sa.Column("device_type", sa.String(20), nullable=True),
        sa.Column("app_version", sa.String(20), nullable=True),
        sa.Column("event_time", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
    )
    op.create_index("ix_search_events_id", "search_events", ["id"])
    op.create_index("ix_search_events_user_id", "search_events", ["user_id"])
    op.create_index("ix_search_events_session_id", "search_events", ["session_id"])

    op.create_table(
        "popular_searches",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("query", sa.String(255), nullable=False),
        sa.Column("search_count", sa.Integer(), server_default=sa.text("0"), nullable=False),
        sa.Column("result_count", sa.Integer(), nullable=True),
        sa.Column("is_active", sa.Boolean(), server_default=sa.text("true")),
        sa.Column("last_searched_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
    )
    op.create_index("ix_popular_searches_id", "popular_searches", ["id"])
    op.create_index("ix_popular_searches_query", "popular_searches", ["query"], unique=True)

    op.create_table(
        "barcode_scans",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("barcode", sa.String(100), nullable=False),
        sa.Column("barcode_type", sa.String(20), nullable=True),
        sa.Column("user_id", sa.Integer(), sa.ForeignKey("users.id"), nullable=True),
        sa.Column("shop_id", sa.Integer(), sa.ForeignKey("shops.id"), nullable=True),
        sa.Column("product_master_id", sa.Integer(), sa.ForeignKey("product_masters.id"), nullable=True),
        sa.Column("scan_source", sa.String(50), server_default="CUSTOMER_APP"),
        sa.Column("is_match_found", sa.Boolean(), server_default=sa.text("false")),
        sa.Column("scan_time", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
    )
    op.create_index("ix_barcode_scans_id", "barcode_scans", ["id"])
    op.create_index("ix_barcode_scans_barcode", "barcode_scans", ["barcode"])
    op.create_index("ix_barcode_scans_user_id", "barcode_scans", ["user_id"])
    op.create_index("ix_barcode_scans_shop_id", "barcode_scans", ["shop_id"])
    op.create_index("ix_barcode_scans_product_master_id", "barcode_scans", ["product_master_id"])

    # === 16. POS models ===
    op.create_table(
        "pos_integrations",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("shop_id", sa.Integer(), sa.ForeignKey("shops.id"), nullable=False),
        sa.Column("provider_name", sa.String(100), nullable=False),
        sa.Column("integration_type", sa.String(50), nullable=False),
        sa.Column("api_base_url", sa.String(500), nullable=True),
        sa.Column("api_key_encrypted", sa.Text(), nullable=True),
        sa.Column("api_secret_encrypted", sa.Text(), nullable=True),
        sa.Column("status", sa.Enum(name="pos_integration_status", native_enum=False), nullable=False, server_default="ACTIVE"),
        sa.Column("last_sync_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("last_sync_status", sa.String(20), nullable=True),
        sa.Column("config_json", sa.JSON(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.Column("is_deleted", sa.Boolean(), server_default=sa.text("false"), nullable=False),
        sa.Column("deleted_at", sa.DateTime(timezone=True), nullable=True),
    )
    op.create_index("ix_pos_integrations_id", "pos_integrations", ["id"])
    op.create_index("ix_pos_integrations_shop_id", "pos_integrations", ["shop_id"])

    op.create_table(
        "pos_devices",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("shop_id", sa.Integer(), sa.ForeignKey("shops.id"), nullable=False),
        sa.Column("integration_id", sa.Integer(), sa.ForeignKey("pos_integrations.id"), nullable=True),
        sa.Column("device_identifier", sa.String(100), nullable=False),
        sa.Column("device_name", sa.String(255), nullable=True),
        sa.Column("device_type", sa.String(50), nullable=True),
        sa.Column("is_active", sa.Boolean(), server_default=sa.text("true")),
        sa.Column("last_connected_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("firmware_version", sa.String(50), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.Column("is_deleted", sa.Boolean(), server_default=sa.text("false"), nullable=False),
        sa.Column("deleted_at", sa.DateTime(timezone=True), nullable=True),
        sa.UniqueConstraint("shop_id", "device_identifier", name="uq_pos_device_shop_identifier"),
    )
    op.create_index("ix_pos_devices_id", "pos_devices", ["id"])
    op.create_index("ix_pos_devices_shop_id", "pos_devices", ["shop_id"])
    op.create_index("ix_pos_devices_integration_id", "pos_devices", ["integration_id"])
    op.create_index("ix_pos_devices_device_identifier", "pos_devices", ["device_identifier"])

    op.create_table(
        "pos_sync_jobs",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("shop_id", sa.Integer(), sa.ForeignKey("shops.id"), nullable=False),
        sa.Column("integration_id", sa.Integer(), sa.ForeignKey("pos_integrations.id"), nullable=True),
        sa.Column("sync_type", sa.String(50), nullable=False),
        sa.Column("status", sa.Enum(name="pos_sync_status", native_enum=False), nullable=False, server_default="PENDING"),
        sa.Column("started_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("completed_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("items_processed", sa.Integer(), server_default=sa.text("0")),
        sa.Column("items_succeeded", sa.Integer(), server_default=sa.text("0")),
        sa.Column("items_failed", sa.Integer(), server_default=sa.text("0")),
        sa.Column("error_summary", sa.Text(), nullable=True),
        sa.Column("created_by", sa.Integer(), sa.ForeignKey("users.id"), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
    )
    op.create_index("ix_pos_sync_jobs_id", "pos_sync_jobs", ["id"])
    op.create_index("ix_pos_sync_jobs_shop_id", "pos_sync_jobs", ["shop_id"])
    op.create_index("ix_pos_sync_jobs_integration_id", "pos_sync_jobs", ["integration_id"])

    op.create_table(
        "pos_sync_logs",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("sync_job_id", sa.Integer(), sa.ForeignKey("pos_sync_jobs.id"), nullable=False),
        sa.Column("log_level", sa.String(20), server_default="INFO", nullable=False),
        sa.Column("message", sa.Text(), nullable=False),
        sa.Column("item_reference", sa.String(255), nullable=True),
        sa.Column("error_code", sa.String(50), nullable=True),
        sa.Column("stack_trace", sa.Text(), nullable=True),
        sa.Column("logged_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
    )
    op.create_index("ix_pos_sync_logs_id", "pos_sync_logs", ["id"])
    op.create_index("ix_pos_sync_logs_sync_job_id", "pos_sync_logs", ["sync_job_id"])

    # === 17. Notifications ===
    op.create_table(
        "notification_preferences",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("user_id", sa.Integer(), sa.ForeignKey("users.id"), nullable=False),
        sa.Column("push_enabled", sa.Boolean(), server_default=sa.text("true")),
        sa.Column("email_enabled", sa.Boolean(), server_default=sa.text("true")),
        sa.Column("sms_enabled", sa.Boolean(), server_default=sa.text("false")),
        sa.Column("price_alerts", sa.Boolean(), server_default=sa.text("true")),
        sa.Column("availability_alerts", sa.Boolean(), server_default=sa.text("true")),
        sa.Column("promotional", sa.Boolean(), server_default=sa.text("false")),
        sa.Column("deal_alerts", sa.Boolean(), server_default=sa.text("true")),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.UniqueConstraint("user_id", name="uq_notification_pref_user"),
    )
    op.create_index("ix_notification_preferences_id", "notification_preferences", ["id"])
    op.create_index("ix_notification_preferences_user_id", "notification_preferences", ["user_id"])

    op.create_table(
        "device_tokens",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("user_id", sa.Integer(), sa.ForeignKey("users.id"), nullable=False),
        sa.Column("token", sa.String(500), nullable=False),
        sa.Column("device_type", sa.String(20), server_default="android", nullable=False),
        sa.Column("platform", sa.String(50), nullable=True),
        sa.Column("is_active", sa.Boolean(), server_default=sa.text("true")),
        sa.Column("last_used_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("app_version", sa.String(20), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.UniqueConstraint("token", name="uq_device_tokens_token"),
    )
    op.create_index("ix_device_tokens_id", "device_tokens", ["id"])
    op.create_index("ix_device_tokens_user_id", "device_tokens", ["user_id"])
    op.create_index("ix_device_tokens_token", "device_tokens", ["token"])

    # Update notifications table
    op.add_column("notifications", sa.Column("read_at", sa.DateTime(timezone=True), nullable=True))
    op.add_column("notifications", sa.Column("sent_at", sa.DateTime(timezone=True), nullable=True))
    op.add_column("notifications", sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False))
    op.execute("CREATE INDEX ix_notifications_user_read ON notifications (user_id, is_read)")

    # === 18. Admin models ===
    op.create_table(
        "admin_actions",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("admin_user_id", sa.Integer(), sa.ForeignKey("users.id"), nullable=False),
        sa.Column("action_type", sa.String(50), nullable=False),
        sa.Column("target_type", sa.String(50), nullable=False),
        sa.Column("target_id", sa.Integer(), nullable=False),
        sa.Column("action_data", sa.JSON(), nullable=True),
        sa.Column("description", sa.Text(), nullable=True),
        sa.Column("ip_address", sa.String(45), nullable=True),
        sa.Column("performed_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
    )
    op.create_index("ix_admin_actions_id", "admin_actions", ["id"])
    op.create_index("ix_admin_actions_admin_user_id", "admin_actions", ["admin_user_id"])
    op.create_index("ix_admin_actions_action_type", "admin_actions", ["action_type"])

    op.create_table(
        "admin_notes",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("admin_user_id", sa.Integer(), sa.ForeignKey("users.id"), nullable=False),
        sa.Column("entity_type", sa.String(50), nullable=False),
        sa.Column("entity_id", sa.Integer(), nullable=False),
        sa.Column("note", sa.Text(), nullable=False),
        sa.Column("is_private", sa.Boolean(), server_default=sa.text("true")),
        sa.Column("created_by", sa.Integer(), sa.ForeignKey("users.id"), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
    )
    op.create_index("ix_admin_notes_id", "admin_notes", ["id"])
    op.create_index("ix_admin_notes_admin_user_id", "admin_notes", ["admin_user_id"])
    op.create_index("ix_admin_notes_entity_id", "admin_notes", ["entity_id"])

    op.create_table(
        "product_approvals",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("product_master_id", sa.Integer(), sa.ForeignKey("product_masters.id"), nullable=False),
        sa.Column("shop_id", sa.Integer(), sa.ForeignKey("shops.id"), nullable=True),
        sa.Column("submitted_by", sa.Integer(), sa.ForeignKey("users.id"), nullable=True),
        sa.Column("status", sa.Enum(name="approval_status", native_enum=False), nullable=False, server_default="PENDING"),
        sa.Column("requested_by", sa.Integer(), sa.ForeignKey("users.id"), nullable=True),
        sa.Column("reviewed_by", sa.Integer(), sa.ForeignKey("users.id"), nullable=True),
        sa.Column("review_notes", sa.Text(), nullable=True),
        sa.Column("submitted_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("reviewed_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("submission_data", sa.JSON(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
    )
    op.create_index("ix_product_approvals_id", "product_approvals", ["id"])
    op.create_index("ix_product_approvals_product_master_id", "product_approvals", ["product_master_id"])
    op.create_index("ix_product_approvals_shop_id", "product_approvals", ["shop_id"])

    op.create_table(
        "reports",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("report_type", sa.String(50), nullable=False),
        sa.Column("report_name", sa.String(255), nullable=False),
        sa.Column("parameters_json", sa.JSON(), nullable=True),
        sa.Column("generated_by", sa.Integer(), sa.ForeignKey("users.id"), nullable=True),
        sa.Column("file_url", sa.String(500), nullable=True),
        sa.Column("status", sa.String(20), server_default="PENDING", nullable=False),
        sa.Column("started_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("completed_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("error_message", sa.Text(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
    )
    op.create_index("ix_reports_id", "reports", ["id"])
    op.create_index("ix_reports_report_type", "reports", ["report_type"])

    op.create_table(
        "complaints",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("complainant_user_id", sa.Integer(), sa.ForeignKey("users.id"), nullable=True),
        sa.Column("complaint_type", sa.String(50), nullable=False),
        sa.Column("subject", sa.String(255), nullable=False),
        sa.Column("description", sa.Text(), nullable=False),
        sa.Column("entity_type", sa.String(50), nullable=True),
        sa.Column("entity_id", sa.Integer(), nullable=True),
        sa.Column("status", sa.Enum(name="complaint_status", native_enum=False), nullable=False, server_default="OPEN"),
        sa.Column("priority", sa.String(20), server_default="MEDIUM"),
        sa.Column("assigned_to", sa.Integer(), sa.ForeignKey("users.id"), nullable=True),
        sa.Column("resolution_notes", sa.Text(), nullable=True),
        sa.Column("resolved_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
    )
    op.create_index("ix_complaints_id", "complaints", ["id"])
    op.create_index("ix_complaints_complainant_user_id", "complaints", ["complainant_user_id"])

    op.create_table(
        "audit_logs",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("user_id", sa.Integer(), sa.ForeignKey("users.id"), nullable=True),
        sa.Column("action", sa.String(50), nullable=False),
        sa.Column("entity_type", sa.String(50), nullable=False),
        sa.Column("entity_id", sa.Integer(), nullable=True),
        sa.Column("old_values", sa.JSON(), nullable=True),
        sa.Column("new_values", sa.JSON(), nullable=True),
        sa.Column("ip_address", sa.String(45), nullable=True),
        sa.Column("user_agent", sa.String(255), nullable=True),
        sa.Column("request_id", sa.String(100), nullable=True),
        sa.Column("description", sa.Text(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
    )
    op.create_index("ix_audit_logs_id", "audit_logs", ["id"])
    op.create_index("ix_audit_logs_user_id", "audit_logs", ["user_id"])
    op.create_index("ix_audit_logs_entity_type", "audit_logs", ["entity_type"])
    op.create_index("ix_audit_logs_entity_id", "audit_logs", ["entity_id"])
    op.create_index("ix_audit_logs_request_id", "audit_logs", ["request_id"])
    op.create_index("ix_audit_logs_entity_time", "audit_logs", ["entity_type", "entity_id", "created_at"])

    # === 19. Analytics models ===
    op.create_table(
        "product_views",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("product_master_id", sa.Integer(), sa.ForeignKey("product_masters.id"), nullable=False),
        sa.Column("user_id", sa.Integer(), sa.ForeignKey("users.id"), nullable=True),
        sa.Column("session_id", sa.String(100), nullable=True),
        sa.Column("device_type", sa.String(20), nullable=True),
        sa.Column("app_version", sa.String(20), nullable=True),
        sa.Column("viewed_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
    )
    op.create_index("ix_product_views_id", "product_views", ["id"])
    op.create_index("ix_product_views_product_master_id", "product_views", ["product_master_id"])
    op.create_index("ix_product_views_user_id", "product_views", ["user_id"])
    op.create_index("ix_product_views_session_id", "product_views", ["session_id"])

    op.create_table(
        "shop_views",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("shop_id", sa.Integer(), sa.ForeignKey("shops.id"), nullable=False),
        sa.Column("user_id", sa.Integer(), sa.ForeignKey("users.id"), nullable=True),
        sa.Column("session_id", sa.String(100), nullable=True),
        sa.Column("device_type", sa.String(20), nullable=True),
        sa.Column("app_version", sa.String(20), nullable=True),
        sa.Column("viewed_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
    )
    op.create_index("ix_shop_views_id", "shop_views", ["id"])
    op.create_index("ix_shop_views_shop_id", "shop_views", ["shop_id"])
    op.create_index("ix_shop_views_user_id", "shop_views", ["user_id"])
    op.create_index("ix_shop_views_session_id", "shop_views", ["session_id"])

    op.create_table(
        "product_clicks",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("product_master_id", sa.Integer(), sa.ForeignKey("product_masters.id"), nullable=False),
        sa.Column("user_id", sa.Integer(), sa.ForeignKey("users.id"), nullable=True),
        sa.Column("session_id", sa.String(100), nullable=True),
        sa.Column("source", sa.String(50), server_default="SEARCH", nullable=False),
        sa.Column("clicked_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.Column("query", sa.String(255), nullable=True),
        sa.Column("shop_id", sa.Integer(), sa.ForeignKey("shops.id"), nullable=True),
        sa.Column("shop_product_id", sa.Integer(), sa.ForeignKey("shop_products.id"), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
    )
    op.create_index("ix_product_clicks_id", "product_clicks", ["id"])
    op.create_index("ix_product_clicks_product_master_id", "product_clicks", ["product_master_id"])
    op.create_index("ix_product_clicks_user_id", "product_clicks", ["user_id"])
    op.create_index("ix_product_clicks_session_id", "product_clicks", ["session_id"])
    op.create_index("ix_product_clicks_shop_id", "product_clicks", ["shop_id"])

    op.create_table(
        "inventory_events",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("shop_product_id", sa.Integer(), sa.ForeignKey("shop_products.id"), nullable=False),
        sa.Column("event_type", sa.String(50), nullable=False),
        sa.Column("quantity_change", sa.Integer(), nullable=False),
        sa.Column("source", sa.Enum(name="inventory_source", native_enum=False), nullable=False, server_default="MANUAL"),
        sa.Column("reference_type", sa.String(50), nullable=True),
        sa.Column("reference_id", sa.Integer(), nullable=True),
        sa.Column("notes", sa.Text(), nullable=True),
        sa.Column("created_by", sa.Integer(), sa.ForeignKey("users.id"), nullable=True),
        sa.Column("occurred_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
    )
    op.create_index("ix_inventory_events_id", "inventory_events", ["id"])
    op.create_index("ix_inventory_events_shop_product_id", "inventory_events", ["shop_product_id"])

    op.create_table(
        "system_metrics",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("metric_name", sa.String(100), nullable=False),
        sa.Column("metric_value", sa.Float(), nullable=False),
        sa.Column("unit", sa.String(20), server_default="percent"),
        sa.Column("shop_id", sa.Integer(), sa.ForeignKey("shops.id"), nullable=True),
        sa.Column("source", sa.String(50), server_default="PROMETHEUS"),
        sa.Column("recorded_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
    )
    op.create_index("ix_system_metrics_id", "system_metrics", ["id"])
    op.create_index("ix_system_metrics_metric_name", "system_metrics", ["metric_name"])
    op.create_index("ix_system_metrics_shop_id", "system_metrics", ["shop_id"])

    # === 20. System models ===
    op.create_table(
        "system_settings",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("key", sa.String(100), nullable=False),
        sa.Column("value", sa.Text(), nullable=False),
        sa.Column("value_type", sa.String(20), server_default="string"),
        sa.Column("description", sa.Text(), nullable=True),
        sa.Column("is_secret", sa.Boolean(), server_default=sa.text("false")),
        sa.Column("updated_by", sa.Integer(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
    )
    op.create_index("ix_system_settings_id", "system_settings", ["id"])
    op.create_index("ix_system_settings_key", "system_settings", ["key"], unique=True)

    op.create_table(
        "feature_flags",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("name", sa.String(100), nullable=False),
        sa.Column("description", sa.Text(), nullable=True),
        sa.Column("is_enabled", sa.Boolean(), server_default=sa.text("false")),
        sa.Column("default_enabled", sa.Boolean(), server_default=sa.text("false")),
        sa.Column("rollout_percentage", sa.Integer(), server_default=sa.text("100")),
        sa.Column("scope", sa.String(20), server_default="GLOBAL"),
        sa.Column("target_ids_json", sa.JSON(), nullable=True),
        sa.Column("conditions_json", sa.JSON(), nullable=True),
        sa.Column("updated_by", sa.Integer(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
    )
    op.create_index("ix_feature_flags_id", "feature_flags", ["id"])
    op.create_index("ix_feature_flags_name", "feature_flags", ["name"], unique=True)

    # === 21. Subscriptions & Payments ===
    op.create_table(
        "subscription_plans",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("name", sa.String(100), nullable=False),
        sa.Column("description", sa.Text(), nullable=True),
        sa.Column("price_monthly", sa.Float(), nullable=False),
        sa.Column("price_annual", sa.Float(), nullable=False),
        sa.Column("currency", sa.String(10), server_default="INR", nullable=False),
        sa.Column("billing_cycle", sa.Enum(name="billing_cycle", native_enum=False), nullable=False, server_default="MONTHLY"),
        sa.Column("is_active", sa.Boolean(), server_default=sa.text("true")),
        sa.Column("features_json", sa.JSON(), nullable=True),
        sa.Column("max_shops", sa.Integer(), nullable=True),
        sa.Column("max_products", sa.Integer(), nullable=True),
        sa.Column("trial_days", sa.Integer(), server_default=sa.text("0")),
        sa.Column("sort_order", sa.Integer(), server_default=sa.text("0")),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
    )
    op.create_index("ix_subscription_plans_id", "subscription_plans", ["id"])
    op.create_index("ix_subscription_plans_name", "subscription_plans", ["name"], unique=True)

    op.create_table(
        "subscriptions",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("user_id", sa.Integer(), sa.ForeignKey("users.id"), nullable=False),
        sa.Column("shop_id", sa.Integer(), sa.ForeignKey("shops.id"), nullable=True),
        sa.Column("plan_id", sa.Integer(), sa.ForeignKey("subscription_plans.id"), nullable=False),
        sa.Column("status", sa.Enum(name="subscription_status", native_enum=False), nullable=False, server_default="ACTIVE"),
        sa.Column("is_auto_renew", sa.Boolean(), server_default=sa.text("true")),
        sa.Column("current_period_start", sa.DateTime(timezone=True), nullable=True),
        sa.Column("current_period_end", sa.DateTime(timezone=True), nullable=True),
        sa.Column("cancel_at_period_end", sa.Boolean(), server_default=sa.text("false")),
        sa.Column("trial_ends_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("created_by", sa.Integer(), sa.ForeignKey("users.id"), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
    )
    op.create_index("ix_subscriptions_id", "subscriptions", ["id"])
    op.create_index("ix_subscriptions_user_id", "subscriptions", ["user_id"])
    op.create_index("ix_subscriptions_shop_id", "subscriptions", ["shop_id"])
    op.create_index("ix_subscriptions_plan_id", "subscriptions", ["plan_id"])

    op.create_table(
        "payments",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("subscription_id", sa.Integer(), sa.ForeignKey("subscriptions.id"), nullable=False),
        sa.Column("payment_provider", sa.String(100), nullable=False),
        sa.Column("transaction_id", sa.String(255), nullable=True),
        sa.Column("amount", sa.Float(), nullable=False),
        sa.Column("currency", sa.String(10), server_default="INR", nullable=False),
        sa.Column("status", sa.String(20), server_default="PENDING", nullable=False),
        sa.Column("payment_method", sa.String(50), nullable=False),
        sa.Column("paid_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("refunded_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("failure_reason", sa.Text(), nullable=True),
        sa.Column("payment_metadata", sa.JSON(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
    )
    op.create_index("ix_payments_id", "payments", ["id"])
    op.create_index("ix_payments_subscription_id", "payments", ["subscription_id"])
    op.create_index("ix_payments_transaction_id", "payments", ["transaction_id"], unique=True)


def downgrade() -> None:
    """Reverse the migration - drop all new tables and restore old schema."""
    # Drop tables in reverse dependency order
    op.drop_table("payments")
    op.drop_table("subscriptions")
    op.drop_table("subscription_plans")
    op.drop_table("feature_flags")
    op.drop_table("system_settings")
    op.drop_table("system_metrics")
    op.drop_table("inventory_events")
    op.drop_table("product_clicks")
    op.drop_table("shop_views")
    op.drop_table("product_views")
    op.drop_table("audit_logs")
    op.drop_table("complaints")
    op.drop_table("reports")
    op.drop_table("product_approvals")
    op.drop_table("admin_notes")
    op.drop_table("admin_actions")
    op.drop_table("device_tokens")
    op.drop_table("notification_preferences")
    op.drop_table("pos_sync_logs")
    op.drop_table("pos_sync_jobs")
    op.drop_table("pos_devices")
    op.drop_table("pos_integrations")
    op.drop_table("barcode_scans")
    op.drop_table("popular_searches")
    op.drop_table("search_events")
    op.drop_table("search_history")
    op.drop_table("offer_conditions")
    op.drop_table("offer_products")
    op.drop_table("offers")
    op.drop_table("price_history")
    op.drop_table("inventory_adjustments")
    op.drop_table("inventory_movements")
    op.drop_table("inventory")
    op.drop_table("shop_products")
    op.drop_table("product_identifiers")
    op.drop_table("product_attribute_values")
    op.drop_table("product_attributes")
    op.drop_table("product_images")
    op.drop_table("product_variants")
    op.drop_table("product_masters")
    op.drop_table("brands")
    op.drop_table("shop_verifications")
    op.drop_table("shop_documents")
    op.drop_table("shop_holidays")
    op.drop_table("shop_hours")
    op.drop_table("shop_addresses")
    op.drop_table("shop_managers")
    op.drop_table("shop_owners")
    op.drop_table("customers")
    op.drop_table("customer_addresses")
    op.drop_table("role_permissions")
    op.drop_table("permissions")
    op.drop_table("roles")

    # Drop enum types
    for name in [
        "user_status", "shop_status", "verification_status", "product_status",
        "shop_product_status", "stock_status", "inventory_source", "offer_status",
        "offer_type", "approval_status", "complaint_status", "pos_integration_status",
        "pos_sync_status", "subscription_status", "billing_cycle"
    ]:
        op.execute(f"DROP TYPE IF EXISTS {name}")

    # Drop columns added to existing tables
    op.drop_column("notifications", "sent_at")
    op.drop_column("notifications", "read_at")
    op.drop_column("shops", "subscription")  # No-op since subscription is relationship-only
    op.drop_index("ix_shops_phone", table_name="shops") if op.get_bind().dialect.has_index(op.get_bind(), "shops", "ix_shops_phone") else None
    op.drop_column("shops", "location")
    op.drop_column("shops", "category")
    op.drop_column("shops", "is_open_24x7")
    op.drop_column("shops", "is_featured")
    op.drop_column("shops", "status")
    op.drop_column("shops", "website_url")
    op.drop_column("shops", "email")
    op.drop_column("shops", "last_inventory_update")
    op.drop_column("shops", "verified_at")
    op.drop_column("users", "last_login_ip")
    op.drop_column("users", "last_login_at")
    op.drop_column("users", "role_id")
    op.drop_column("users", "password_hash")

    # Restore old columns
    op.add_column("shops", sa.Column("latitude", sa.Float(), nullable=False, server_default="0"))
    op.add_column("shops", sa.Column("longitude", sa.Float(), nullable=False, server_default="0"))

    # Restore old products table
    op.create_table(
        "products",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("name", sa.String(255), nullable=False),
        sa.Column("brand", sa.String(120), nullable=True),
        sa.Column("description", sa.Text(), nullable=True),
        sa.Column("category_id", sa.Integer(), sa.ForeignKey("categories.id"), nullable=True),
        sa.Column("image_url", sa.String(500), nullable=True),
        sa.Column("created_at", sa.DateTime(), server_default=sa.text("now()")),
        sa.Column("updated_at", sa.DateTime(), server_default=sa.text("now()")),
    )
    op.create_index("ix_products_id", "products", ["id"])
    op.create_index("ix_products_name", "products", ["name"])
    op.create_index("ix_products_brand", "products", ["brand"])
    op.create_index("ix_products_category_id", "products", ["category_id"])

    # Restore old inventory
    op.create_table(
        "inventory",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("product_id", sa.Integer(), sa.ForeignKey("products.id"), nullable=False),
        sa.Column("shop_id", sa.Integer(), sa.ForeignKey("shops.id"), nullable=False),
        sa.Column("price", sa.Float(), nullable=False),
        sa.Column("quantity", sa.Integer(), server_default=sa.text("0")),
        sa.Column("is_available", sa.Boolean(), server_default=sa.text("true")),
        sa.Column("stock_status", sa.String(20), server_default="IN_STOCK"),
        sa.Column("updated_at", sa.DateTime(), server_default=sa.text("now()")),
        sa.UniqueConstraint("product_id", "shop_id", name="uq_inventory_product_shop"),
    )
    op.create_index("ix_inventory_id", "inventory", ["id"])
    op.create_index("ix_inventory_product_id", "inventory", ["product_id"])
    op.create_index("ix_inventory_shop_id", "inventory", ["shop_id"])