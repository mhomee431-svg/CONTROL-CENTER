"""Notification System — Phase 27 typed architecture

Revision ID: 0009
Revises: 0008
Create Date: 2026-08-26

Adds:
- notifications: audience, deep_link, dedupe_key, delivery_status,
  delivery_attempts, last_attempt_at, provider_message_id, last_error
- device_tokens: failure_count
- notification_deliveries: per-device delivery attempt history
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = "0009"
down_revision: Union[str, None] = "0008"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # ── notifications: typed architecture + delivery tracking ────────────────
    op.add_column("notifications", sa.Column("audience", sa.String(20), nullable=True))
    op.add_column("notifications", sa.Column("deep_link", sa.String(500), nullable=True))
    op.add_column("notifications", sa.Column("dedupe_key", sa.String(255), nullable=True))
    op.add_column(
        "notifications",
        sa.Column("delivery_status", sa.String(20), nullable=False, server_default="PENDING"),
    )
    op.add_column(
        "notifications",
        sa.Column("delivery_attempts", sa.Integer(), nullable=False, server_default="0"),
    )
    op.add_column("notifications", sa.Column("last_attempt_at", sa.DateTime(timezone=True), nullable=True))
    op.add_column("notifications", sa.Column("provider_message_id", sa.String(255), nullable=True))
    op.add_column("notifications", sa.Column("last_error", sa.Text(), nullable=True))
    op.create_index("ix_notifications_dedupe", "notifications", ["user_id", "dedupe_key"])

    # ── device_tokens: failure bookkeeping for invalid-token handling ────────
    op.add_column(
        "device_tokens",
        sa.Column("failure_count", sa.Integer(), nullable=False, server_default="0"),
    )

    # ── notification_deliveries: per-device attempt history ──────────────────
    op.create_table(
        "notification_deliveries",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column(
            "notification_id",
            sa.Integer(),
            sa.ForeignKey("notifications.id"),
            nullable=False,
        ),
        sa.Column(
            "device_token_id",
            sa.Integer(),
            sa.ForeignKey("device_tokens.id"),
            nullable=False,
        ),
        sa.Column("status", sa.String(20), nullable=False, server_default="PENDING"),
        sa.Column("attempts", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("provider_message_id", sa.String(255), nullable=True),
        sa.Column("error", sa.Text(), nullable=True),
        sa.Column("permanent_failure", sa.Boolean(), nullable=False, server_default=sa.text("false")),
        sa.Column("attempted_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("delivered_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("created_at", sa.DateTime(), nullable=False, server_default=sa.text("now()")),
        sa.Column("updated_at", sa.DateTime(), nullable=False, server_default=sa.text("now()")),
        sa.UniqueConstraint("notification_id", "device_token_id", name="uq_notif_delivery_notif_token"),
    )
    op.create_index("ix_notification_deliveries_id", "notification_deliveries", ["id"])
    op.create_index(
        "ix_notification_deliveries_notification_id", "notification_deliveries", ["notification_id"]
    )
    op.create_index(
        "ix_notification_deliveries_device_token_id", "notification_deliveries", ["device_token_id"]
    )
    op.create_index("ix_notif_delivery_status", "notification_deliveries", ["status"])


def downgrade() -> None:
    op.drop_index("ix_notif_delivery_status", table_name="notification_deliveries")
    op.drop_index("ix_notification_deliveries_device_token_id", table_name="notification_deliveries")
    op.drop_index("ix_notification_deliveries_notification_id", table_name="notification_deliveries")
    op.drop_index("ix_notification_deliveries_id", table_name="notification_deliveries")
    op.drop_table("notification_deliveries")

    op.drop_column("device_tokens", "failure_count")

    op.drop_index("ix_notifications_dedupe", table_name="notifications")
    op.drop_column("notifications", "last_error")
    op.drop_column("notifications", "provider_message_id")
    op.drop_column("notifications", "last_attempt_at")
    op.drop_column("notifications", "delivery_attempts")
    op.drop_column("notifications", "delivery_status")
    op.drop_column("notifications", "dedupe_key")
    op.drop_column("notifications", "deep_link")
    op.drop_column("notifications", "audience")