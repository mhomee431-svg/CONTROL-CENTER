"""Merge category-configuration and export-job migration heads.

Revision ID: 0006_merge_category_export_jobs
Revises: 0004_category_configuration, 0005_export_jobs
"""

revision = "0006_merge_category_export_jobs"
down_revision = ("0004_category_configuration", "0005_export_jobs")
branch_labels = None
depends_on = None


def upgrade() -> None:
    pass


def downgrade() -> None:
    pass
