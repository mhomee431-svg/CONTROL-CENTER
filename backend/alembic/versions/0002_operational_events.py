"""Add the durable operational event feed.

Revision ID: 0002_operational_events
Revises: 0001_initial_schema
"""
from alembic import op
import sqlalchemy as sa

revision = "0002_operational_events"
down_revision = "0001_initial_schema"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "operational_events",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("type", sa.String(length=48), nullable=False),
        sa.Column("title", sa.String(length=200), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        "ix_operational_events_created_at",
        "operational_events",
        ["created_at"],
        unique=False,
    )
    op.create_index(
        "ix_operational_events_type",
        "operational_events",
        ["type"],
        unique=False,
    )


def downgrade() -> None:
    op.drop_index("ix_operational_events_type", table_name="operational_events")
    op.drop_index("ix_operational_events_created_at", table_name="operational_events")
    op.drop_table("operational_events")
