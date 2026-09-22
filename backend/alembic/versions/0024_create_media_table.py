"""Create the Phase 2/3 media lifecycle table (PENDING/UPLOADED/PROCESSING/READY/FAILED).

Revision ID: 0024
Revises: 0023
Create Date: 2026-09-21
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision: str = "0024"
down_revision: Union[str, None] = "0023"
branch_labels: Union[str, None] = None
depends_on: Union[str, None] = None


def upgrade() -> None:
    op.create_table(
        "media",
        sa.Column("id", sa.Integer, primary_key=True),
        # Server-minted key: {prefix}/{scope}/{YYYY}/{MM}/{uuid8}_{name}.{ext}
        sa.Column("key", sa.String(512), nullable=False, unique=True),
        sa.Column("category", sa.String(32), nullable=True, index=True),
        sa.Column("scope", sa.String(64), nullable=True, index=True),
        sa.Column("shop_id", sa.Integer, nullable=True, index=True),
        sa.Column("user_id", sa.Integer, nullable=True, index=True),
        sa.Column("declared_size_bytes", sa.Integer, nullable=True),
        sa.Column("content_type", sa.String(100), nullable=True),
        sa.Column("size_bytes", sa.Integer, nullable=True),
        sa.Column(
            "state",
            sa.String(16),
            nullable=False,
            server_default="PENDING",
            index=True,
        ),
        sa.Column("processed_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("error_code", sa.String(64), nullable=True),
        sa.Column("error_message", sa.Text, nullable=True),
        sa.Column("quarantine_key", sa.String(512), nullable=True),
        # Shared mixin columns (TimestampMixin/SoftDeleteMixin have no DB-level
        # enum dependencies, so they are safe on a plain Postgres instance).
        sa.Column(
            "created_at", sa.DateTime(timezone=True),
            nullable=False, server_default=sa.func.now(),
        ),
        sa.Column(
            "updated_at", sa.DateTime(timezone=True),
            nullable=False, server_default=sa.func.now(),
        ),
        sa.Column(
            "is_deleted", sa.Boolean, nullable=False, server_default=sa.text("false")
        ),
        sa.Column("deleted_at", sa.DateTime(timezone=True), nullable=True),
    )
    op.create_index("ix_media_key", "media", ["key"], unique=True)
    op.create_index("ix_media_scope", "media", ["scope"])
    op.create_index("ix_media_state", "media", ["state"])
    op.create_index("ix_media_shop_id", "media", ["shop_id"])


def downgrade() -> None:
    op.drop_index("ix_media_shop_id", table_name="media")
    op.drop_index("ix_media_state", table_name="media")
    op.drop_index("ix_media_scope", table_name="media")
    op.drop_index("ix_media_key", table_name="media")
    op.drop_table("media")
