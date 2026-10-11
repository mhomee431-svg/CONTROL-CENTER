"""Add the asynchronous export-job registry (Export Center).

The EXPORT CENTER rule requires large exports to run through backend jobs rather
than being generated in the browser. This table is the job registry the console
reads: what was requested, by whom, its status and its result once produced.

Revision ID: 0005_export_jobs
Revises: 0004_notification_targeting
"""
from alembic import op
import sqlalchemy as sa

revision = "0005_export_jobs"
down_revision = "0004_notification_targeting"
branch_labels = None
depends_on = None


def upgrade() -> None:
    bind = op.get_bind()
    existing = set(sa.inspect(bind).get_table_names())
    if "export_jobs" in existing:
        return

    op.create_table(
        "export_jobs",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("dataset", sa.String(length=48), nullable=False),
        sa.Column("filters_json", sa.JSON(), nullable=True),
        sa.Column("status", sa.String(length=32), nullable=False, server_default="QUEUED"),
        sa.Column("format", sa.String(length=16), nullable=True, server_default="CSV"),
        sa.Column("rows_exported", sa.Integer(), nullable=True),
        sa.Column("file_size_bytes", sa.Integer(), nullable=True),
        sa.Column("file_url", sa.String(length=512), nullable=True),
        sa.Column("error", sa.Text(), nullable=True),
        sa.Column("requested_by", sa.String(length=128), nullable=True),
        sa.Column("completed_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("reason", sa.String(length=512), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_export_jobs_status", "export_jobs", ["status"], unique=False)
    op.create_index("ix_export_jobs_dataset", "export_jobs", ["dataset"], unique=False)


def downgrade() -> None:
    bind = op.get_bind()
    existing = set(sa.inspect(bind).get_table_names())
    if "export_jobs" not in existing:
        return
    op.drop_index("ix_export_jobs_dataset", table_name="export_jobs")
    op.drop_index("ix_export_jobs_status", table_name="export_jobs")
    op.drop_table("export_jobs")
