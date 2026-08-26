"""Subscription & Payment Monetization — Phase 28

Revision ID: 0010
Revises: 0009
Create Date: 2026-08-26

Adds:
- payments: provider_order_id, billing_cycle, invoice_number, refund_id
- payment_events: webhook idempotency ledger (unique per provider+event_id)

Note: ``subscription_status`` is a non-native enum (VARCHAR), so the new
EXPIRED value requires no database-level change.
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = "0010"
down_revision: Union[str, None] = "0009"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # ── payments: monetization columns ───────────────────────────────────────
    op.add_column("payments", sa.Column("provider_order_id", sa.String(255), nullable=True))
    op.add_column("payments", sa.Column("billing_cycle", sa.String(20), nullable=True))
    op.add_column("payments", sa.Column("invoice_number", sa.String(50), nullable=True))
    op.add_column("payments", sa.Column("refund_id", sa.String(255), nullable=True))
    op.create_index("ix_payments_provider_order_id", "payments", ["provider_order_id"], unique=True)
    op.create_index("ix_payments_invoice_number", "payments", ["invoice_number"], unique=True)

    # ── payment_events: webhook idempotency ledger ───────────────────────────
    op.create_table(
        "payment_events",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("provider", sa.String(100), nullable=False),
        sa.Column("event_id", sa.String(255), nullable=False),
        sa.Column("event_type", sa.String(100), nullable=True),
        sa.Column("payment_id", sa.Integer(), sa.ForeignKey("payments.id"), nullable=True),
        sa.Column("payload", sa.JSON(), nullable=True),
        sa.Column("received_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.UniqueConstraint("provider", "event_id", name="uq_payment_events_provider_event"),
    )
    op.create_index("ix_payment_events_id", "payment_events", ["id"])
    op.create_index("ix_payment_events_provider", "payment_events", ["provider"])
    op.create_index("ix_payment_events_event_id", "payment_events", ["event_id"])
    op.create_index("ix_payment_events_payment_id", "payment_events", ["payment_id"])


def downgrade() -> None:
    op.drop_index("ix_payment_events_payment_id", table_name="payment_events")
    op.drop_index("ix_payment_events_event_id", table_name="payment_events")
    op.drop_index("ix_payment_events_provider", table_name="payment_events")
    op.drop_index("ix_payment_events_id", table_name="payment_events")
    op.drop_table("payment_events")

    op.drop_index("ix_payments_invoice_number", table_name="payments")
    op.drop_index("ix_payments_provider_order_id", table_name="payments")
    op.drop_column("payments", "refund_id")
    op.drop_column("payments", "invoice_number")
    op.drop_column("payments", "billing_cycle")
    op.drop_column("payments", "provider_order_id")
