"""Shop Location Metadata (Phase: Shop Location System).

Revision ID: 0018
Revises: 0017
Create Date: 2026-09-06

Adds the location-capture provenance/quality columns the shopkeeper location
capture flow needs, while keeping the single existing PostGIS `shops.location`
Geography(POINT, 4326) column as the canonical spatial anchor (no duplicate
location tables / columns). Mirrors the same metadata on `shop_addresses`.

All DDL is idempotent (``IF NOT EXISTS``) so it re-applies safely on an
existing AWS RDS Free Tier database.

Columns (shops):
  - accuracy_meters        Float  — GPS accuracy radius in meters at capture
  - location_captured_at   timestamptz — device timestamp of the fix
  - location_source        String — GPS | MANUAL | ADDRESS
  - location_type          String — SHOP_ENTRANCE | BUILDING_CENTER | OTHER
  - location_status        String — CAPTURED | CONFIRMED | CORRECTED | STALE
  - location_integrity_status String — NORMAL | SUSPICIOUS | UNKNOWN
  - location_verified      Boolean — shopkeeper confirmed the pin (NOT admin
                                    business verification; that is `is_verified`)

Index: defensive GiST on ``shops.location`` (creation already exists in 0014,
guaranteed present here as well).
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from geoalchemy2.types import Geography as GeographyType

# revision identifiers, used by Alembic.
revision: str = "0018"
down_revision: Union[str, None] = "0017"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def _add_column_if_not_exists(table_name: str, column: sa.Column) -> None:
    """Idempotent column addition for Postgres (no native IF NOT EXISTS for ADD COLUMN)."""
    bind = op.get_bind()
    existing = sa.inspect(bind).get_columns(table_name)
    if column.name not in {c["name"] for c in existing}:
        op.add_column(table_name, column)


def upgrade() -> None:
    # ── Shops location metadata ───────────────────────────────────────────────
    _add_column_if_not_exists(
        "shops", sa.Column("accuracy_meters", sa.Float(), nullable=True)
    )
    _add_column_if_not_exists(
        "shops",
        sa.Column("location_captured_at", sa.DateTime(timezone=True), nullable=True),
    )
    _add_column_if_not_exists(
        "shops",
        sa.Column(
            "location_source",
            sa.String(20),
            nullable=False,
            server_default="GPS",
        ),
    )
    _add_column_if_not_exists(
        "shops",
        sa.Column(
            "location_type",
            sa.String(30),
            nullable=False,
            server_default="SHOP_ENTRANCE",
        ),
    )
    _add_column_if_not_exists(
        "shops",
        sa.Column(
            "location_status",
            sa.String(20),
            nullable=False,
            server_default="CAPTURED",
        ),
    )
    _add_column_if_not_exists(
        "shops",
        sa.Column(
            "location_integrity_status",
            sa.String(20),
            nullable=False,
            server_default="UNKNOWN",
        ),
    )
    _add_column_if_not_exists(
        "shops",
        sa.Column("location_verified", sa.Boolean(), nullable=False, server_default=sa.text("false")),
    )

    # ── Addresses location metadata (parallel capture provenance) ─────────────
    _add_column_if_not_exists(
        "shop_addresses", sa.Column("accuracy_meters", sa.Float(), nullable=True)
    )
    _add_column_if_not_exists(
        "shop_addresses",
        sa.Column("location_source", sa.String(20), nullable=True),
    )
    _add_column_if_not_exists(
        "shop_addresses",
        sa.Column("location_captured_at", sa.DateTime(timezone=True), nullable=True),
    )

    # ── Defensive GiST on shops.location (idempotent) ────────────────────────
    op.execute(
        "CREATE INDEX IF NOT EXISTS ix_shops_location_gist "
        "ON shops USING GIST (location)"
    )

    # Indexes that speed up shopkeeper location-audit / admin review queries.
    op.execute(
        "CREATE INDEX IF NOT EXISTS ix_shops_location_status "
        "ON shops (location_status)"
    )
    op.execute(
        "CREATE INDEX IF NOT EXISTS ix_shops_location_integrity "
        "ON shops (location_integrity_status)"
    )


def downgrade() -> None:
    bind = op.get_bind()
    insp = sa.inspect(bind)

    existing_addr = {c["name"] for c in insp.get_columns("shop_addresses")}
    for col in ("location_captured_at", "location_source", "accuracy_meters"):
        if col in existing_addr:
            op.drop_column("shop_addresses", col)

    existing = {c["name"] for c in insp.get_columns("shops")}
    op.drop_index("ix_shops_location_integrity", table_name="shops", if_exists=True)
    op.drop_index("ix_shops_location_status", table_name="shops", if_exists=True)
    op.drop_index("ix_shops_location_gist", table_name="shops", if_exists=True)

    for col in (
        "location_integrity_status",
        "location_status",
        "location_type",
        "location_source",
        "location_captured_at",
        "accuracy_meters",
        "location_verified",
    ):
        if col in existing:
            op.drop_column("shops", col)
