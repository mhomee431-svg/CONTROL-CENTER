"""Shopkeeper offer status transitions (adds DISABLED + PROMOTIONAL_PRICE).

Revision ID: 0023
Revises: 0022
Create Date: 2026-09-19
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = "0023"
down_revision: Union[str, None] = "0022"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade():
    bind = op.get_bind()
    dialect = bind.dialect.name if bind is not None else ""
    if dialect == "postgresql":
        op.execute("ALTER TYPE offer_status ADD VALUE IF NOT EXISTS 'DISABLED'")
        op.execute("ALTER TYPE offer_type ADD VALUE IF NOT EXISTS 'PROMOTIONAL_PRICE'")
    # SQLite stores enums as VARCHAR + CHECK constraints; nothing to alter.
    op.add_column(
        "offers",
        sa.Column("promotional_price", sa.Numeric(12, 2), nullable=True),
    )


def downgrade():
    op.drop_column("offers", "promotional_price")
