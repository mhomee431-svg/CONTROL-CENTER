"""Add environment and changed_by to feature flags.

The Feature Flags console shows, for each flag: Flag, Status, Environment,
Last Changed and Changed By. `environment` and `changed_by` are new columns;
`updated_at` (from TimestampMixin) already supplies "Last Changed".

Both columns are nullable on purpose: existing rows predate the columns and
must be reported as "not set" rather than defaulted to a value nobody chose.

Revision ID: 0003_feature_flag_environment
Revises: 0002_operational_events
"""
from alembic import op
import sqlalchemy as sa

revision = "0003_feature_flag_environment"
down_revision = "0002_operational_events"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # Idempotent: a database that already carries these columns (e.g. one whose
    # schema was created directly from the SQLAlchemy models) must not fail the
    # upgrade. Detect before adding, so `upgrade` is safe to run against both a
    # migrated database and a freshly materialised one.
    bind = op.get_bind()
    columns = {col["name"] for col in sa.inspect(bind).get_columns("feature_flags")}
    if "environment" not in columns:
        op.add_column(
            "feature_flags",
            sa.Column("environment", sa.String(length=32), nullable=True),
        )
    if "changed_by" not in columns:
        op.add_column(
            "feature_flags",
            sa.Column("changed_by", sa.String(length=128), nullable=True),
        )


def downgrade() -> None:
    bind = op.get_bind()
    columns = {col["name"] for col in sa.inspect(bind).get_columns("feature_flags")}
    if "changed_by" in columns:
        op.drop_column("feature_flags", "changed_by")
    if "environment" in columns:
        op.drop_column("feature_flags", "environment")
