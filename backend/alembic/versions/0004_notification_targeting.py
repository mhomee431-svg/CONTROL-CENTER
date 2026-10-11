"""Add scheduling, targeting and metadata columns to notification campaigns.

The Notification Center console exposes Scheduled / Draft campaigns, real
audience targeting (category, location, selected ids) and a metadata envelope.
None of that can be honest without somewhere to store it, so this adds:

  - scheduled_at  : when a SCHEDULED campaign should go out (UTC)
  - category      : optional category filter applied to the audience
  - location      : optional location filter applied to the audience
  - selected_ids  : explicit subject ids for "Selected" audiences
  - metadata_json : opaque composer metadata (never used to build a route)
  - reason        : operator justification captured when a draft is saved

Every column is nullable on purpose: existing rows predate the columns and must
be reported as "not set" rather than defaulted to a value nobody chose.

Revision ID: 0004_notification_targeting
Revises: 0003_feature_flag_environment
"""
from alembic import op
import sqlalchemy as sa

revision = "0004_notification_targeting"
down_revision = "0003_feature_flag_environment"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # Idempotent: a database materialised directly from the models already has
    # these columns, so detect before adding rather than failing the upgrade.
    bind = op.get_bind()
    columns = {col["name"] for col in sa.inspect(bind).get_columns("notification_campaigns")}

    if "scheduled_at" not in columns:
        op.add_column(
            "notification_campaigns",
            sa.Column("scheduled_at", sa.DateTime(timezone=True), nullable=True),
        )
    if "category" not in columns:
        op.add_column(
            "notification_campaigns",
            sa.Column("category", sa.String(length=128), nullable=True),
        )
    if "location" not in columns:
        op.add_column(
            "notification_campaigns",
            sa.Column("location", sa.String(length=128), nullable=True),
        )
    if "selected_ids" not in columns:
        op.add_column(
            "notification_campaigns",
            sa.Column("selected_ids", sa.JSON(), nullable=True),
        )
    if "metadata_json" not in columns:
        op.add_column(
            "notification_campaigns",
            sa.Column("metadata_json", sa.JSON(), nullable=True),
        )
    if "reason" not in columns:
        op.add_column(
            "notification_campaigns",
            sa.Column("reason", sa.String(length=512), nullable=True),
        )


def downgrade() -> None:
    bind = op.get_bind()
    columns = {col["name"] for col in sa.inspect(bind).get_columns("notification_campaigns")}
    for name in ("reason", "metadata_json", "selected_ids", "location", "category", "scheduled_at"):
        if name in columns:
            op.drop_column("notification_campaigns", name)
