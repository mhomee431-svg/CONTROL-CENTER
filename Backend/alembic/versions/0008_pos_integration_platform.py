"""POS Integration Platform — Phase 25 provider-agnostic sync engine

Revision ID: 0008
Revises: 0007
Create Date: 2026-08-25

Adds:
- enum values: pos_integration_status 'DISCONNECTED',
  pos_sync_status 'COMPLETED_WITH_ERRORS'
- POSIntegrations: sync configuration / schedule / incremental cursor /
  failure bookkeeping columns
- POSSyncJobs: idempotency key, retry bookkeeping
- pos_product_mappings table (POS Product → Identifier → Master/Variant
  → ShopProduct mapping with content fingerprint for duplicate prevention)
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = "0008"
down_revision: Union[str, None] = "0007"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # Enum values are additive and idempotent.
    op.execute(
        "ALTER TYPE pos_integration_status ADD VALUE IF NOT EXISTS 'DISCONNECTED'"
    )
    op.execute(
        "ALTER TYPE pos_sync_status ADD VALUE IF NOT EXISTS 'COMPLETED_WITH_ERRORS'"
    )

    # ── pos_integrations: sync configuration / schedule / incremental state ──
    op.add_column("pos_integrations", sa.Column("provider_code", sa.String(50), nullable=True))
    op.create_index("ix_pos_integrations_provider_code", "pos_integrations", ["provider_code"])
    op.add_column(
        "pos_integrations",
        sa.Column("sync_enabled", sa.Boolean(), nullable=False, server_default=sa.true()),
    )
    op.add_column(
        "pos_integrations",
        sa.Column("sync_interval_minutes", sa.Integer(), nullable=False, server_default="60"),
    )
    op.add_column(
        "pos_integrations",
        sa.Column("auto_create_products", sa.Boolean(), nullable=False, server_default=sa.true()),
    )
    op.add_column(
        "pos_integrations",
        sa.Column(
            "conflict_strategy", sa.String(30), nullable=False, server_default="PRESERVE_PLATFORM"
        ),
    )
    op.add_column("pos_integrations", sa.Column("incremental_cursor", sa.String(255), nullable=True))
    op.add_column(
        "pos_integrations", sa.Column("last_successful_sync_at", sa.DateTime(timezone=True), nullable=True)
    )
    op.add_column(
        "pos_integrations", sa.Column("consecutive_failures", sa.Integer(), nullable=False, server_default="0")
    )
    op.add_column("pos_integrations", sa.Column("disconnected_at", sa.DateTime(timezone=True), nullable=True))

    # ── pos_sync_jobs: idempotency + retry bookkeeping ──
    op.add_column("pos_sync_jobs", sa.Column("idempotency_key", sa.String(64), nullable=True))
    op.create_index("ix_pos_sync_jobs_idempotency_key", "pos_sync_jobs", ["idempotency_key"], unique=True)
    op.add_column(
        "pos_sync_jobs", sa.Column("trigger", sa.String(20), nullable=False, server_default="MANUAL")
    )
    op.add_column("pos_sync_jobs", sa.Column("retry_count", sa.Integer(), nullable=False, server_default="0"))
    op.add_column("pos_sync_jobs", sa.Column("next_retry_at", sa.DateTime(timezone=True), nullable=True))
    op.add_column(
        "pos_sync_jobs", sa.Column("duplicates_skipped", sa.Integer(), nullable=False, server_default="0")
    )

    # ── pos_product_mappings ──
    _create_mappings_table()


def _create_mappings_table() -> None:
    op.create_table(
        "pos_product_mappings",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("integration_id", sa.Integer(), sa.ForeignKey("pos_integrations.id"), nullable=False),
        sa.Column("shop_id", sa.Integer(), sa.ForeignKey("shops.id"), nullable=False),
        sa.Column("pos_product_code", sa.String(100), nullable=False),
        sa.Column("pos_sku", sa.String(100), nullable=True),
        sa.Column("barcode", sa.String(100), nullable=True),
        sa.Column("product_master_id", sa.Integer(), sa.ForeignKey("product_masters.id"), nullable=True),
        sa.Column("variant_id", sa.Integer(), sa.ForeignKey("product_variants.id"), nullable=True),
        sa.Column("shop_product_id", sa.Integer(), sa.ForeignKey("shop_products.id"), nullable=True),
        sa.Column("last_synced_hash", sa.String(64), nullable=True),
        sa.Column("last_synced_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("last_conflict_json", sa.JSON(), nullable=True),
        sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.true()),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=True),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=True),
        sa.UniqueConstraint("integration_id", "pos_product_code", name="uq_pos_mapping_integration_code"),
    )
    op.create_index("ix_pos_product_mappings_integration_id", "pos_product_mappings", ["integration_id"])
    op.create_index("ix_pos_product_mappings_shop_id", "pos_product_mappings", ["shop_id"])
    op.create_index("ix_pos_mappings_shop_product", "pos_product_mappings", ["shop_product_id"])
    op.create_index("ix_pos_mappings_barcode", "pos_product_mappings", ["barcode"])


def downgrade() -> None:
    op.drop_table("pos_product_mappings")
    op.drop_index("ix_pos_sync_jobs_idempotency_key", table_name="pos_sync_jobs")
    op.drop_column("pos_sync_jobs", "duplicates_skipped")
    op.drop_column("pos_sync_jobs", "next_retry_at")
    op.drop_column("pos_sync_jobs", "retry_count")
    op.drop_column("pos_sync_jobs", "trigger")
    op.drop_column("pos_sync_jobs", "idempotency_key")
    op.drop_column("pos_integrations", "disconnected_at")
    op.drop_column("pos_integrations", "consecutive_failures")
    op.drop_column("pos_integrations", "last_successful_sync_at")
    op.drop_column("pos_integrations", "incremental_cursor")
    op.drop_column("pos_integrations", "conflict_strategy")
    op.drop_column("pos_integrations", "auto_create_products")
    op.drop_column("pos_integrations", "sync_interval_minutes")
    op.drop_column("pos_integrations", "sync_enabled")
    op.drop_index("ix_pos_integrations_provider_code", table_name="pos_integrations")
    op.drop_column("pos_integrations", "provider_code")
