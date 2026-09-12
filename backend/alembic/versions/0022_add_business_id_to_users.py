"""Add business_id to users — Unique Business ID for shopkeeper accounts.

Adds the business_id column to the users table as the unique shopkeeper
identity identifier for the interim phone+password auth phase. Each
shopkeeper gets a stable ID (e.g. SHOP_919000000011) mapped to their phone
number. Backfilled lazily on first login for legacy accounts.

Revision ID: 0022
Revises: 0021
Create Date: 2026-09-11
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = "0022"
down_revision: Union[str, None] = "0021"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade():
    # Add business_id column to users table
    op.add_column(
        "users",
        sa.Column("business_id", sa.String(64), nullable=True),
    )
    # Create unique index on business_id
    op.create_index(
        "ix_users_business_id",
        "users",
        ["business_id"],
        unique=True,
    )


def downgrade():
    op.drop_index("ix_users_business_id", table_name="users")
    op.drop_column("users", "business_id")