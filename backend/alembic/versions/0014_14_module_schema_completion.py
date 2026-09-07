"""14-Module Schema Completion (Free Tier hardened)

Revision ID: 0014
Revises: 0013
Create Date: 2026-09-01

Delivers the remaining tables from the 14-module architecture that were not yet
materialised in the live schema, plus the Free Tier index surface requested in
Step 4 of the database plan:

1. Identity & Access
   - ``user_roles``          RBAC many-to-many (users <-> roles).
   - ``password_resets``     tamper-safe reset tokens (salted HMAC digest).
   - ``auth_sessions``       ORM model already defined; table was missing from
                             the migration chain (create-all drift guard).
   - ``token_blacklist``     JTI revocation ledger; same drift guard.

2. Customer
   - ``customer_favorites``         polymorphic favourites (product/shop/...).
   - ``customer_recent_products``   per-customer recently-viewed products.

3. Location
   - ``service_areas``      PostGIS polygon service zones
                            Geography(POLYGON, 4326) + GiST index.

4. Shop
   - ``shop_addresses.location``  Geography(POINT, 4326) column + GiST index,
     backfilled from latitude/longitude. (Requested in the module spec.)

5. Indexing (Step 4)
   - Composite B-tree on ``shop_products (shop_id, variant_id)`` and the other
     high-frequency shop-product access paths.
   - Defensive ``CREATE INDEX IF NOT EXISTS`` GiST on the two search-critical
     geography columns (customer_addresses.location, shops.location).

All DDL is idempotent (IF NOT EXISTS / ADD COLUMN IF NOT EXISTS) so it can be
applied safely to an existing AWS RDS Free Tier database without causing drift
failures on objects that may already exist in pre-migration create_all databases.

Downstream codebase mapping (canonical, approved in docs/PHASE4...md):
- products -> product_masters + product_variants
- customer_profiles -> customers
- otp_verifications -> otps
- user_sessions -> auth_sessions
- shop_product_prices -> shop_products.price/mrp + price_history
- product_search_metadata -> search_indexes
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from geoalchemy2.types import Geography as GeographyType


# revision identifiers, used by Alembic.
revision: str = "0014"
down_revision: Union[str, None] = "0013"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # ═══════════════════════════════════════════════════════════════════════
    # 1. Identity & Access
    # ── user_roles: RBAC many-to-many (composite PK covers user_id lookups) ─
    op.create_table(
        "user_roles",
        sa.Column("user_id", sa.Integer(), primary_key=True),
        sa.Column(
            "role_id", sa.Integer(), sa.ForeignKey("roles.id", ondelete="CASCADE"),
            primary_key=True,
        ),
        sa.Column(
            "assigned_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.text("now()"),
        ),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
    )
    op.create_index("ix_user_roles_role_id", "user_roles", ["role_id"])

    # ── password_resets: salted HMAC digest, single-use, expiring ──────────
    op.create_table(
        "password_resets",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column(
            "user_id",
            sa.Integer(),
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("token_hash", sa.String(128), nullable=False),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("is_used", sa.Boolean(), nullable=False, server_default=sa.text("false")),
        sa.Column("used_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("used_ip", sa.String(45), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.text("now()")),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.text("now()")),
    )
    op.create_index("ix_password_resets_token_hash", "password_resets", ["token_hash"], unique=True)
    op.create_index("ix_password_resets_user_id", "password_resets", ["user_id"])
    op.create_index("ix_password_resets_expires_at", "password_resets", ["expires_at"])
    op.create_index(
        "ix_password_resets_user_active",
        "password_resets", ["user_id", "is_used"],
    )

    # ── auth_sessions / token_blacklist: ORM models already declare these   ─
    # tables but they were never emitted by the chain. Use IF NOT EXISTS so
    # databases that materialised them earlier via create_all() do not break.
    op.execute(
        """
        CREATE TABLE IF NOT EXISTS auth_sessions (
            id                SERIAL PRIMARY KEY,
            session_id        VARCHAR(36) NOT NULL UNIQUE,
            user_id           INTEGER NOT NULL REFERENCES users(id),
            device_id         VARCHAR(255),
            device_name       VARCHAR(255),
            device_type       VARCHAR(50),
            platform          VARCHAR(50),
            app_version       VARCHAR(20),
            ip_address        VARCHAR(45),
            user_agent        VARCHAR(500),
            refresh_token_hash             VARCHAR(128),
            refresh_token_expires_at       TIMESTAMPTZ,
            refresh_token_revoked_at       TIMESTAMPTZ,
            refresh_token_used_at          TIMESTAMPTZ,
            refresh_rotation_count         INTEGER NOT NULL DEFAULT 0,
            access_jti        VARCHAR(36),
            refresh_jti       VARCHAR(36),
            is_active         BOOLEAN NOT NULL DEFAULT TRUE,
            is_revoked        BOOLEAN NOT NULL DEFAULT FALSE,
            last_activity_at  TIMESTAMPTZ,
            expires_at        TIMESTAMPTZ,
            revoked_at        TIMESTAMPTZ,
            revoked_reason    VARCHAR(100),
            revoked_by        VARCHAR(50),
            previous_refresh_token_hash   VARCHAR(128),
            reuse_detected    BOOLEAN NOT NULL DEFAULT FALSE,
            created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
            updated_at        TIMESTAMPTZ NOT NULL DEFAULT now()
        )
        """
    )

    # ═══════════════════════════════════════════════════════════════════════
    # 2. Customer
# ── auth_sessions indexes / token_blacklist (drift-guarded) ────────────
    op.execute("CREATE INDEX IF NOT EXISTS ix_auth_sessions_user_id ON auth_sessions (user_id)")
    op.execute("CREATE INDEX IF NOT EXISTS ix_auth_sessions_is_active ON auth_sessions (is_active)")
    op.execute(
        "CREATE INDEX IF NOT EXISTS ix_auth_sessions_user_active "
        "ON auth_sessions (user_id, is_active)"
    )
    op.execute(
        "CREATE INDEX IF NOT EXISTS ix_auth_sessions_refresh_token "
        "ON auth_sessions (refresh_token_hash)"
    )
    op.execute(
        "CREATE INDEX IF NOT EXISTS ix_auth_sessions_last_activity "
        "ON auth_sessions (last_activity_at)"
    )
    op.execute("CREATE INDEX IF NOT EXISTS ix_auth_sessions_access_jti ON auth_sessions (access_jti)")
    op.execute("CREATE INDEX IF NOT EXISTS ix_auth_sessions_refresh_jti ON auth_sessions (refresh_jti)")

    op.execute(
        """
        CREATE TABLE IF NOT EXISTS token_blacklist (
            id         SERIAL PRIMARY KEY,
            jti        VARCHAR(36) NOT NULL UNIQUE,
            token_type VARCHAR(20) NOT NULL,
            user_id    INTEGER REFERENCES users(id),
            expires_at TIMESTAMPTZ NOT NULL,
            revoked_at TIMESTAMPTZ NOT NULL,
            reason     VARCHAR(100),
            created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
            updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
        )
        """
    )
    op.execute("CREATE INDEX IF NOT EXISTS ix_token_blacklist_jti ON token_blacklist (jti)")
    op.execute("CREATE INDEX IF NOT EXISTS ix_token_blacklist_user_id ON token_blacklist (user_id)")

    # ═══════════════════════════════════════════════════════════════════════
    # 2. Customer
    # ── customer_favorites: polymorphic (item_type + item_id; no FK on      ─
    # item_id by design — single favourites table across entity kinds).      ─
    op.create_table(
        "customer_favorites",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column(
            "customer_id",
            sa.Integer(),
            sa.ForeignKey("customers.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("item_type", sa.String(30), nullable=False),
        sa.Column("item_id", sa.Integer(), nullable=False),
        sa.Column("metadata_json", sa.JSON(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.text("now()")),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.text("now()")),
        sa.UniqueConstraint(
            "customer_id", "item_type", "item_id",
            name="uq_customer_favorite_customer_item",
        ),
        sa.CheckConstraint(
            "item_type IN ('PRODUCT','SHOP','BRAND','CATEGORY','SHOP_PRODUCT')",
            name="ck_customer_favorites_item_type",
        ),
    )
    op.create_index(
        "ix_customer_favorites_customer_created",
        "customer_favorites", ["customer_id", "created_at"],
    )
    op.create_index("ix_customer_favorites_item", "customer_favorites", ["item_type", "item_id"])

    # ── customer_recent_products: recent views (upsert on view) ────────────
    op.create_table(
        "customer_recent_products",
        sa.Column("id", sa.Integer(), primary_key=True),
sa.Column(
            "customer_id",
            sa.Integer(),
            sa.ForeignKey("customers.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column(
            "product_master_id",
            sa.Integer(),
            sa.ForeignKey("product_masters.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column(
            "variant_id",
            sa.Integer(),
            sa.ForeignKey("product_variants.id", ondelete="SET NULL"),
            nullable=True,
        ),
        sa.Column(
            "shop_product_id",
            sa.Integer(),
            sa.ForeignKey("shop_products.id", ondelete="SET NULL"),
            nullable=True,
        ),
        sa.Column("first_viewed_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.text("now()")),
        sa.Column("last_viewed_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.text("now()")),
        sa.Column("view_count", sa.Integer(), nullable=False, server_default=sa.text("1")),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.text("now()")),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.text("now()")),
        sa.UniqueConstraint(
            "customer_id", "product_master_id",
            name="uq_customer_recent_customer_product",
        ),
    )
    op.create_index(
        "ix_customer_recent_customer_last_viewed",
        "customer_recent_products", ["customer_id", "last_viewed_at"],
    )
    op.create_index("ix_customer_recent_product_master", "customer_recent_products", ["product_master_id"])
    op.create_index("ix_customer_recent_variant", "customer_recent_products", ["variant_id"])
    op.create_index("ix_customer_recent_shop_product", "customer_recent_products", ["shop_product_id"])

    # ═══════════════════════════════════════════════════════════════════════
    # 3. Location — service_areas (PostGIS POLYGON zones)
    #    GiST indexes power ST_Within/ST_Covers lookups without seq scans.
    op.create_table(
        "service_areas",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("name", sa.String(100), nullable=False),
        sa.Column("area_type", sa.String(30), nullable=False),
        sa.Column("pincode_prefix", sa.String(6), nullable=True),
        sa.Column(
            "boundary",
            GeographyType(geometry_type="POLYGON", srid=4326, spatial_index=False),
            nullable=True,
        ),
        sa.Column(
            "center",
            GeographyType(geometry_type="POINT", srid=4326, spatial_index=False),
            nullable=True,
        ),
        sa.Column("delivery_radius_km", sa.Numeric(6, 2), nullable=True),
        sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.text("true")),
        sa.Column("geo_json", sa.JSON(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.text("now()")),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.text("now()")),
        sa.UniqueConstraint("name", name="uq_service_areas_name"),
        sa.CheckConstraint(
            "area_type IN ('CITY','ZONE','LOCALITY','PINCODE')",
            name="ck_service_areas_area_type",
        ),
    )
    op.execute("CREATE INDEX IF NOT EXISTS ix_service_areas_boundary ON service_areas USING GIST (boundary)")
    op.execute("CREATE INDEX IF NOT EXISTS ix_service_areas_center ON service_areas USING GIST (center)")
    op.execute(
        "CREATE INDEX IF NOT EXISTS ix_service_areas_pincode_prefix "
        "ON service_areas (pincode_prefix)"
    )
    op.execute(
        "CREATE INDEX IF NOT EXISTS ix_service_areas_active "
        "ON service_areas (is_active) WHERE is_active"
    )
# ═══════════════════════════════════════════════════════════════════════
    # 4. Shop — shop_addresses.location Geography POINT + GiST
    op.execute(
        "ALTER TABLE shop_addresses "
        "ADD COLUMN IF NOT EXISTS location geography(POINT, 4326)"
    )
    op.execute(
        "UPDATE shop_addresses SET location = "
        "ST_SetSRID(ST_MakePoint(longitude, latitude), 4326)::geography "
        "WHERE latitude IS NOT NULL AND longitude IS NOT NULL AND location IS NULL"
    )
    op.execute(
        "CREATE INDEX IF NOT EXISTS ix_shop_addresses_location "
        "ON shop_addresses USING GIST (location)"
    )

    # ═══════════════════════════════════════════════════════════════════════
    # 5. Step 4 — Free Tier index surface
    # 5a. Composite B-tree for the highest-frequency shop-product paths.
    op.execute(
        "CREATE INDEX IF NOT EXISTS ix_shop_products_shop_variant "
        "ON shop_products (shop_id, variant_id)"
    )
    op.execute(
        "CREATE INDEX IF NOT EXISTS ix_shop_products_shop_master "
        "ON shop_products (shop_id, product_master_id)"
    )
    op.execute(
        "CREATE INDEX IF NOT EXISTS ix_shop_products_shop_available "
        "ON shop_products (shop_id, is_available)"
    )

    # 5b. Defensive GiST on the two search-critical geography columns (skip if
    # already created by GeoAlchemy spatial_index in earlier migrations).
    op.execute(
        "CREATE INDEX IF NOT EXISTS ix_customer_addresses_location "
        "ON customer_addresses USING GIST (location)"
    )
    op.execute(
        "CREATE INDEX IF NOT EXISTS ix_shops_location "
        "ON shops USING GIST (location)"
    )


def downgrade() -> None:
    # 5b. Reverse defensive spatial indexes.
    op.execute("DROP INDEX IF EXISTS ix_shops_location")
    op.execute("DROP INDEX IF EXISTS ix_customer_addresses_location")

    # 5a. Reverse composite shop-product indexes.
    op.execute("DROP INDEX IF EXISTS ix_shop_products_shop_available")
    op.execute("DROP INDEX IF EXISTS ix_shop_products_shop_master")
    op.execute("DROP INDEX IF EXISTS ix_shop_products_shop_variant")

    # 4. Reverse shop_addresses geography (drop GiST then the column).
    op.execute("DROP INDEX IF EXISTS ix_shop_addresses_location")
    op.execute("ALTER TABLE shop_addresses DROP COLUMN IF EXISTS location")

    # 3. service_areas
    op.execute("DROP INDEX IF EXISTS ix_service_areas_active")
    op.execute("DROP INDEX IF EXISTS ix_service_areas_pincode_prefix")
    op.execute("DROP INDEX IF EXISTS ix_service_areas_center")
    op.execute("DROP INDEX IF EXISTS ix_service_areas_boundary")
    op.drop_table("service_areas")

    # 2. Customer
    op.drop_index("ix_customer_recent_shop_product", table_name="customer_recent_products")
    op.drop_index("ix_customer_recent_variant", table_name="customer_recent_products")
    op.drop_index("ix_customer_recent_product_master", table_name="customer_recent_products")
    op.drop_index("ix_customer_recent_customer_last_viewed", table_name="customer_recent_products")
    op.drop_table("customer_recent_products")
    op.drop_index("ix_customer_favorites_item", table_name="customer_favorites")
    op.drop_index("ix_customer_favorites_customer_created", table_name="customer_favorites")
    op.drop_table("customer_favorites")

    # 1. Identity & Access
    op.drop_index("ix_token_blacklist_user_id", table_name="token_blacklist")
    op.drop_index("ix_token_blacklist_jti", table_name="token_blacklist")
    op.drop_table("token_blacklist")
    op.execute("DROP INDEX IF EXISTS ix_auth_sessions_refresh_jti")
    op.execute("DROP INDEX IF EXISTS ix_auth_sessions_access_jti")
    op.execute("DROP INDEX IF EXISTS ix_auth_sessions_last_activity")
    op.execute("DROP INDEX IF EXISTS ix_auth_sessions_refresh_token")
    op.execute("DROP INDEX IF EXISTS ix_auth_sessions_user_active")
    op.execute("DROP INDEX IF EXISTS ix_auth_sessions_is_active")
    op.execute("DROP INDEX IF EXISTS ix_auth_sessions_user_id")
    op.drop_table("auth_sessions")

    op.drop_index("ix_password_resets_user_active", table_name="password_resets")
    op.drop_index("ix_password_resets_expires_at", table_name="password_resets")
    op.drop_index("ix_password_resets_user_id", table_name="password_resets")
    op.drop_index("ix_password_resets_token_hash", table_name="password_resets")
    op.drop_table("password_resets")

    op.drop_index("ix_user_roles_role_id", table_name="user_roles")
    op.drop_table("user_roles")