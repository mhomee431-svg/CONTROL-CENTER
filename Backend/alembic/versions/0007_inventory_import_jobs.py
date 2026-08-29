"""Inventory Import Jobs — Phase 24 Excel inventory intake

Revision ID: 0007
Revises: 0006
Create Date: 2026-08-25

Creates:
- inventory_import_job_status enum
- inventory_import_jobs table (one uploaded workbook per job, idempotency key)
- inventory_import_rows table (row-level validation / processing outcomes)
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = "0007"
down_revision: Union[str, None] = "0006"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.execute(
        "DO $$ BEGIN CREATE TYPE inventory_import_job_status AS ENUM "
        "('VALIDATING', 'AWAITING_CONFIRMATION', 'QUEUED', 'PROCESSING', "
        "'COMPLETED', 'PARTIAL', 'FAILED'); "
        "EXCEPTION WHEN duplicate_object THEN NULL; END $$;"
    )

    op.create_table(
        "inventory_import_jobs",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("shop_id", sa.Integer(), sa.ForeignKey("shops.id"), nullable=False),
        sa.Column("uploaded_by", sa.Integer(), sa.ForeignKey("users.id")),
        sa.Column("filename", sa.String(255)),
        sa.Column("file_size_bytes", sa.Integer()),
        sa.Column("idempotency_key", sa.String(64)),
        sa.Column(
            "status",
            sa.Enum(
                "VALIDATING", "AWAITING_CONFIRMATION", "QUEUED", "PROCESSING",
                "COMPLETED", "PARTIAL", "FAILED",
                name="inventory_import_job_status", native_enum=False,
            ),
            nullable=False,
            server_default="VALIDATING",
        ),
        sa.Column("total_rows", sa.Integer(), server_default="0"),
        sa.Column("valid_rows", sa.Integer(), server_default="0"),
        sa.Column("error_rows", sa.Integer(), server_default="0"),
        sa.Column("processed_rows", sa.Integer(), server_default="0"),
        sa.Column("failed_rows", sa.Integer(), server_default="0"),
        sa.Column("error_message", sa.Text()),
        sa.Column("started_at", sa.DateTime(timezone=True)),
        sa.Column("completed_at", sa.DateTime(timezone=True)),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
    )
    op.create_index("ix_inventory_import_jobs_id", "inventory_import_jobs", ["id"])
    op.create_index("ix_inventory_import_jobs_shop_id", "inventory_import_jobs", ["shop_id"])
    op.create_index("ix_inventory_import_jobs_status", "inventory_import_jobs", ["status"])
    op.create_index("ix_inventory_import_jobs_idempotency_key", "inventory_import_jobs", ["idempotency_key"])
    op.create_index(
        "ix_inventory_import_jobs_shop_key",
        "inventory_import_jobs",
        ["shop_id", "idempotency_key"],
    )

    op.create_table(
        "inventory_import_rows",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column(
            "job_id",
            sa.Integer(),
            sa.ForeignKey("inventory_import_jobs.id"),
            nullable=False,
        ),
        sa.Column("row_number", sa.Integer(), nullable=False),
        sa.Column("status", sa.String(20), nullable=False, server_default="PENDING"),
        sa.Column("raw_data", sa.Text()),
        sa.Column("normalized_data", sa.Text()),
        sa.Column("error_code", sa.String(60)),
        sa.Column("error_field", sa.String(60)),
        sa.Column("error_message", sa.Text()),
        sa.Column("product_master_id", sa.Integer()),
        sa.Column("variant_id", sa.Integer()),
        sa.Column("shop_product_id", sa.Integer()),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
    )
    op.create_index("ix_inventory_import_rows_id", "inventory_import_rows", ["id"])
    op.create_index("ix_inventory_import_rows_job_id", "inventory_import_rows", ["job_id"])
    op.create_index("ix_inventory_import_rows_status", "inventory_import_rows", ["status"])


def downgrade() -> None:
    op.drop_table("inventory_import_rows")
    op.drop_table("inventory_import_jobs")
    op.execute("DROP TYPE IF EXISTS inventory_import_job_status")
