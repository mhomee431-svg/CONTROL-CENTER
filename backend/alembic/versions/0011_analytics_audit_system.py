"""Analytics & Audit System — Phase 29

Revision ID: 0011
Revises: 0010
Create Date: 2026-08-26

Adds:
- analytics_events: unified append-only platform event stream
- analytics_daily_aggregates: rebuildable daily rollups
- audit_logs: prev_record_hash / record_hash tamper-evidence chain
- reports: result_json payload column
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = "0011"
down_revision: Union[str, None] = "0010"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "analytics_events",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("event_name", sa.String(60), nullable=False),
        sa.Column("actor_type", sa.String(20), nullable=False),
        sa.Column("actor_id", sa.Integer(), nullable=True),
        sa.Column("session_id", sa.String(64), nullable=True),
        sa.Column("shop_id", sa.Integer(), sa.ForeignKey("shops.id"), nullable=True),
        sa.Column("product_master_id", sa.Integer(), sa.ForeignKey("product_masters.id"), nullable=True),
        sa.Column("category_id", sa.Integer(), sa.ForeignKey("categories.id"), nullable=True),
        sa.Column("query", sa.String(255), nullable=True),
        sa.Column("metric_value", sa.Float(), nullable=True),
        sa.Column("props", sa.JSON(), nullable=True),
        sa.Column("device_type", sa.String(20), nullable=True),
        sa.Column("app_version", sa.String(20), nullable=True),
        sa.Column("occurred_at", sa.DateTime(timezone=True), nullable=False),
    )
    op.create_index("ix_analytics_events_id", "analytics_events", ["id"])
    op.create_index("ix_analytics_events_actor_id", "analytics_events", ["actor_id"])
    op.create_index("ix_analytics_events_session_id", "analytics_events", ["session_id"])
    op.create_index("ix_analytics_events_shop_id", "analytics_events", ["shop_id"])
    op.create_index("ix_analytics_events_category_id", "analytics_events", ["category_id"])
    op.create_index("ix_analytics_events_occurred_at", "analytics_events", ["occurred_at"])
    op.create_index("ix_analytics_events_name_time", "analytics_events", ["event_name", "occurred_at"])
    op.create_index("ix_analytics_events_actor_time", "analytics_events", ["actor_type", "occurred_at"])
    op.create_index("ix_analytics_events_shop_time", "analytics_events", ["shop_id", "occurred_at"])
    op.create_index("ix_analytics_events_product_time", "analytics_events", ["product_master_id", "occurred_at"])

    op.create_table(
        "analytics_daily_aggregates",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("aggregate_date", sa.Date(), nullable=False),
        sa.Column("event_name", sa.String(60), nullable=False),
        sa.Column("actor_type", sa.String(20), nullable=False),
        sa.Column("shop_id", sa.Integer(), sa.ForeignKey("shops.id"), nullable=True),
        sa.Column("product_master_id", sa.Integer(), nullable=True),
        sa.Column("category_id", sa.Integer(), nullable=True),
        sa.Column("event_count", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("distinct_sessions", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("distinct_actors", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("metric_sum", sa.Float(), nullable=False, server_default="0"),
        sa.Column("computed_at", sa.DateTime(timezone=True), nullable=False),
    )
    op.create_index("ix_analytics_agg_id", "analytics_daily_aggregates", ["id"])
    op.create_index("ix_analytics_agg_date_name", "analytics_daily_aggregates", ["aggregate_date", "event_name"])
    op.create_index("ix_analytics_agg_date_shop", "analytics_daily_aggregates", ["aggregate_date", "shop_id"])

    # Tamper-evident hash chaining on audit logs
    op.add_column("audit_logs", sa.Column("prev_record_hash", sa.String(64), nullable=True))
    op.add_column("audit_logs", sa.Column("record_hash", sa.String(64), nullable=True))
    op.create_index("ix_audit_logs_record_hash", "audit_logs", ["record_hash"])

    # Generated report payloads
    op.add_column("reports", sa.Column("result_json", sa.JSON(), nullable=True))


def downgrade() -> None:
    op.drop_column("reports", "result_json")
    op.drop_index("ix_audit_logs_record_hash", table_name="audit_logs")
    op.drop_column("audit_logs", "record_hash")
    op.drop_column("audit_logs", "prev_record_hash")
    op.drop_index("ix_analytics_agg_date_shop", table_name="analytics_daily_aggregates")
    op.drop_index("ix_analytics_agg_date_name", table_name="analytics_daily_aggregates")
    op.drop_index("ix_analytics_agg_id", table_name="analytics_daily_aggregates")
    op.drop_table("analytics_daily_aggregates")
    op.drop_index("ix_analytics_events_product_time", table_name="analytics_events")
    op.drop_index("ix_analytics_events_shop_time", table_name="analytics_events")
    op.drop_index("ix_analytics_events_actor_time", table_name="analytics_events")
    op.drop_index("ix_analytics_events_name_time", table_name="analytics_events")
    op.drop_index("ix_analytics_events_occurred_at", table_name="analytics_events")
    op.drop_index("ix_analytics_events_category_id", table_name="analytics_events")
    op.drop_index("ix_analytics_events_shop_id", table_name="analytics_events")
    op.drop_index("ix_analytics_events_session_id", table_name="analytics_events")
    op.drop_index("ix_analytics_events_actor_id", table_name="analytics_events")
    op.drop_index("ix_analytics_events_id", table_name="analytics_events")
    op.drop_table("analytics_events")
