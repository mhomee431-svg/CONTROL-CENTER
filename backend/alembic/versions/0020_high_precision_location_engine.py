"""High-Precision Location Engine - PostGIS spatial index hardening

Revision ID: 0020
Revises: 0019
Create Date: 2026-09-07

Ensures the PostGIS extension is enabled and the primary GIST spatial
index exists on the shops.location column for fast ST_DWithin radius
queries. Also creates a btree index on (status, is_verified,
is_accepting_orders, is_deleted) to accelerate the WHERE clause that
accompanies every nearby-shop query.
"""
from typing import Sequence, Union

from alembic import op


# revision identifiers, used by Alembic.
revision: str = "0020"
down_revision: Union[str, None] = "0019"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # Ensure PostGIS is present (idempotent).
    op.execute("CREATE EXTENSION IF NOT EXISTS postgis")

    # GIST spatial index on the shops.location geography column.
    # (If the ORM already created one via spatial_index=True, this is a no-op-safe
    #  "IF NOT EXISTS" guard is not supported for GIST in older PG, so check
    #  via a DO block before creating.)
    op.execute(
        """
        DO $$
        BEGIN
            IF NOT EXISTS (
                SELECT 1 FROM pg_indexes
                WHERE tablename = 'shops' AND indexname = 'idx_shops_location_gist'
            ) THEN
                CREATE INDEX idx_shops_location_gist ON shops USING GIST (location);
            END IF;
        END $$;
        """
    )

    # Composite filter index for the shop-discovery WHERE clause.
    op.execute(
        """
        DO $$
        BEGIN
            IF NOT EXISTS (
                SELECT 1 FROM pg_indexes
                WHERE tablename = 'shops'
                  AND indexname = 'ix_shops_geo_filter'
            ) THEN
                CREATE INDEX idx_shops_geo_filter ON shops
                    (status, is_verified, is_accepting_orders, is_deleted);
            END IF;
        END $$;
        """
    )


def downgrade() -> None:
    op.execute("DROP INDEX IF EXISTS idx_shops_geo_filter")
    op.execute("DROP INDEX IF EXISTS idx_shops_location_gist")