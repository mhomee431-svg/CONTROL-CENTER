"""Reviews & Pharmacy Compliance — Master Spec §§19-20, 36, 49.

Revision ID: 0017
Revises: 0016
Create Date: 2026-09-05

Delivers the reviews domain and pharmacy/healthcare compliance columns from
DATABASE SCHEMA DESIGN.txt (Domain 16):

- ``reviews``  : moderated, verified-customer reviews for shops & products.
  A review targets EITHER a shop OR a product (never both), enforced by CHECK.
- ``product_masters`` compliance columns: ``prescription_required``,
  ``regulatory_class``, ``requires_license_type``, ``is_restricted``,
  ``compliance_notes``. Partial index on ``prescription_required``.

Rx-class products are DISCOVERY ONLY: the platform never sells, checks-out, or
books prescription medicines. These columns gate discovery-only flows.
"""

from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = "0017"
down_revision: Union[str, None] = "0016"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def _timestamps() -> list[sa.Column]:
    return [
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.text("now()")),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.text("now()")),
    ]


def _soft_delete() -> list[sa.Column]:
    return [
        sa.Column("is_deleted", sa.Boolean(), nullable=False, server_default=sa.text("false")),
        sa.Column("deleted_at", sa.DateTime(timezone=True), nullable=True),
    ]


def upgrade() -> None:
    # --- reviews: moderated, verified-customer reviews ------------------
    op.create_table(
        "reviews",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("user_id", sa.Integer(), sa.ForeignKey("users.id"), nullable=False),
        sa.Column("shop_id", sa.Integer(), sa.ForeignKey("shops.id"), nullable=True),
        sa.Column("product_master_id", sa.Integer(), sa.ForeignKey("product_masters.id"), nullable=True),
        sa.Column("rating", sa.Integer(), nullable=False),
        sa.Column("title", sa.String(255), nullable=True),
        sa.Column("body", sa.Text(), nullable=True),
        sa.Column("is_verified_purchase", sa.Boolean(), nullable=False, server_default="false"),
        sa.Column("status", sa.String(20), nullable=False, server_default="PENDING"),
        sa.Column("moderated_by", sa.Integer(), sa.ForeignKey("users.id"), nullable=True),
        sa.Column("moderated_at", sa.Date(), nullable=True),
        *_soft_delete(),
        *_timestamps(),
        sa.CheckConstraint("rating >= 1 AND rating <= 5", name="ck_reviews_rating_range"),
        sa.CheckConstraint(
            "shop_id IS NOT NULL OR product_master_id IS NOT NULL",
            name="ck_reviews_target_required",
        ),
        sa.CheckConstraint(
            "status IN ('PENDING', 'APPROVED', 'REJECTED', 'HIDDEN')",
            name="ck_reviews_status",
        ),
    )
    op.create_index("ix_reviews_user_id", "reviews", ["user_id"])
    op.create_index("ix_reviews_shop_id", "reviews", ["shop_id"])
    op.create_index("ix_reviews_product_master_id", "reviews", ["product_master_id"])
    op.create_index("ix_reviews_status", "reviews", ["status"])
    op.create_index("ix_reviews_shop_status", "reviews", ["shop_id", "status"])
    op.create_index("ix_reviews_product_status", "reviews", ["product_master_id", "status"])

    # --- product_masters: pharmacy/healthcare compliance columns --------
    op.add_column(
        "product_masters",
        sa.Column("prescription_required", sa.Boolean(), nullable=False, server_default="false"),
    )
    op.add_column(
        "product_masters",
        sa.Column("regulatory_class", sa.String(30), nullable=False, server_default="UNCLASSIFIED"),
    )
    op.add_column(
        "product_masters",
        sa.Column("requires_license_type", sa.String(30), nullable=True),
    )
    op.add_column(
        "product_masters",
        sa.Column("is_restricted", sa.Boolean(), nullable=False, server_default="false"),
    )
    op.add_column(
        "product_masters",
        sa.Column("compliance_notes", sa.Text(), nullable=True),
    )

    # CHECK constraint for regulatory_class values
    op.create_check_constraint(
        "ck_product_masters_regulatory_class",
        "product_masters",
        "regulatory_class IN ('OTC', 'RX', 'SCHEDULED', 'DEVICE', 'SUPPLEMENT', 'UNCLASSIFIED')",
    )

    # Partial index: fast lookup of prescription-required products
    op.create_index(
        "ix_product_masters_prescription_required",
        "product_masters",
        ["prescription_required"],
        postgresql_where=sa.text("prescription_required = true"),
    )


def downgrade() -> None:
    op.drop_column("product_masters", "compliance_notes")
    op.drop_column("product_masters", "is_restricted")
    op.drop_column("product_masters", "requires_license_type")
    op.drop_column("product_masters", "regulatory_class")
    op.drop_column("product_masters", "prescription_required")
    op.drop_table("reviews")
