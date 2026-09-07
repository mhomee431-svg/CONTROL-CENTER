"""Merchant Onboarding & Verification System — Database Migration

Creates tables for the tiered merchant onboarding system:
- merchant_categories (11 categories config)
- merchant_verification_requirements (category requirements config)
- merchant_onboardings (per-business onboarding state)
- business_identity_verifications (GSTIN/UDYAM records)
- bank_account_verifications (bank penny-drop records)
- category_document_verification (pharmacy/restaurant/transport docs)
- verification_attempts (audit trail)
- verification_provider_logs (provider interaction logs)

Revision ID: 0019
Revises: 0018_shop_location_metadata
Create Date: 2026-09-07
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = "0019"
down_revision: Union[str, None] = "0018"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade():
    # ── Merchant Categories ────────────────────────────────────────────
    op.create_table(
        "merchant_categories",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("code", sa.String(50), unique=True, nullable=False, index=True),
        sa.Column("name", sa.String(100), nullable=False),
        sa.Column("description", sa.Text(), nullable=True),
        sa.Column("is_active", sa.Boolean(), server_default="true", nullable=False),
        sa.Column("sort_order", sa.Integer(), server_default="0", nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default="now()", nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default="now()", nullable=False),
    )

    # ── Merchant Verification Requirements ─────────────────────────────
    op.create_table(
        "merchant_verification_requirements",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("category_id", sa.Integer(), sa.ForeignKey("merchant_categories.id", ondelete="CASCADE"), nullable=False, index=True),
        sa.Column("requirement_code", sa.String(50), nullable=False),
        sa.Column("requirement_name", sa.String(100), nullable=False),
        sa.Column("description", sa.Text(), nullable=True),
        sa.Column("is_required", sa.Boolean(), server_default="true", nullable=False),
        sa.Column("verification_method", sa.String(50), nullable=False),
        sa.Column("requires_admin_review", sa.Boolean(), server_default="false", nullable=False),
        sa.Column("is_active", sa.Boolean(), server_default="true", nullable=False),
        sa.Column("sort_order", sa.Integer(), server_default="0", nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default="now()", nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default="now()", nullable=False),
    )

    # ── Merchant Onboardings ───────────────────────────────────────────
    op.create_table(
        "merchant_onboardings",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("shop_id", sa.Integer(), sa.ForeignKey("shops.id", ondelete="CASCADE"), unique=True, nullable=False, index=True),
        sa.Column("user_id", sa.Integer(), sa.ForeignKey("users.id"), nullable=False, index=True),
        sa.Column("category_code", sa.String(50), nullable=False, index=True),
        sa.Column("status", sa.Enum("DRAFT", "PHONE_VERIFIED", "IDENTITY_PENDING", "IDENTITY_VERIFIED", "BANK_PENDING", "BANK_VERIFIED", "CATEGORY_DOCUMENTS_PENDING", "CATEGORY_DOCUMENTS_VERIFIED", "PENDING_ADMIN_REVIEW", "VERIFIED", "REJECTED", "SUSPENDED", "RESUBMISSION_REQUIRED", name="onboarding_status"), server_default="DRAFT", nullable=False),
        sa.Column("phone_verified", sa.Boolean(), server_default="false", nullable=False),
        sa.Column("phone_verified_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("identity_verified", sa.Boolean(), server_default="false", nullable=False),
        sa.Column("identity_verified_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("bank_verified", sa.Boolean(), server_default="false", nullable=False),
        sa.Column("bank_verified_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("category_verified", sa.Boolean(), server_default="false", nullable=False),
        sa.Column("category_verified_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("category_details", sa.JSON(), nullable=True),
        sa.Column("admin_reviewed", sa.Boolean(), server_default="false", nullable=False),
        sa.Column("admin_reviewed_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("admin_reviewed_by", sa.Integer(), sa.ForeignKey("users.id"), nullable=True),
        sa.Column("admin_review_notes", sa.Text(), nullable=True),
        sa.Column("rejection_reason", sa.Text(), nullable=True),
        sa.Column("rejection_code", sa.String(50), nullable=True),
        sa.Column("next_action", sa.String(100), nullable=True),
        sa.Column("idempotency_key", sa.String(100), unique=True, nullable=True, index=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default="now()", nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default="now()", nullable=False),
    )

    # ── Business Identity Verifications ────────────────────────────────
    op.create_table(
        "business_identity_verifications",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("onboarding_id", sa.Integer(), sa.ForeignKey("merchant_onboardings.id", ondelete="CASCADE"), nullable=False, index=True),
        sa.Column("verification_type", sa.Enum("GSTIN", "UDYAM", name="identity_verification_type"), nullable=False),
        sa.Column("identifier_hash", sa.String(128), nullable=True, index=True),
        sa.Column("identifier_last_four", sa.String(10), nullable=True),
        sa.Column("status", sa.Enum("PENDING", "VERIFIED", "FAILED", "REJECTED", "UNABLE_TO_VERIFY", name="identity_verification_status"), server_default="PENDING", nullable=False),
        sa.Column("provider", sa.String(50), nullable=True),
        sa.Column("provider_reference_id", sa.String(200), nullable=True, index=True),
        sa.Column("verified_name", sa.String(255), nullable=True),
        sa.Column("verified_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("failure_reason", sa.Text(), nullable=True),
        sa.Column("failure_code", sa.String(50), nullable=True),
        sa.Column("provider_metadata", sa.JSON(), nullable=True),
        sa.Column("attempt_number", sa.Integer(), server_default="1", nullable=False),
        sa.Column("is_latest_attempt", sa.Boolean(), server_default="true", nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default="now()", nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default="now()", nullable=False),
    )

    # ── Bank Account Verifications ─────────────────────────────────────
    op.create_table(
        "bank_account_verifications",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("onboarding_id", sa.Integer(), sa.ForeignKey("merchant_onboardings.id", ondelete="CASCADE"), nullable=False, index=True),
        sa.Column("account_number_hash", sa.String(128), nullable=True, index=True),
        sa.Column("account_number_last_four", sa.String(10), nullable=True),
        sa.Column("ifsc_code", sa.String(20), nullable=True),
        sa.Column("account_holder_name", sa.String(255), nullable=True),
        sa.Column("bank_name", sa.String(255), nullable=True),
        sa.Column("status", sa.String(30), server_default="PENDING", nullable=False),
        sa.Column("provider", sa.String(50), nullable=True),
        sa.Column("provider_reference_id", sa.String(200), nullable=True, index=True),
        sa.Column("verified_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("failure_reason", sa.Text(), nullable=True),
        sa.Column("failure_code", sa.String(50), nullable=True),
        sa.Column("penny_drop_amount", sa.Float(), nullable=True),
        sa.Column("penny_drop_status", sa.String(30), nullable=True),
        sa.Column("provider_metadata", sa.JSON(), nullable=True),
        sa.Column("attempt_number", sa.Integer(), server_default="1", nullable=False),
        sa.Column("is_latest_attempt", sa.Boolean(), server_default="true", nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default="now()", nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default="now()", nullable=False),
    )

    # ── Category Document Verifications ────────────────────────────────
    op.create_table(
        "category_document_verifications",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("onboarding_id", sa.Integer(), sa.ForeignKey("merchant_onboardings.id", ondelete="CASCADE"), nullable=False, index=True),
        sa.Column("document_type", sa.String(50), nullable=False),
        sa.Column("document_number_hash", sa.String(128), nullable=True, index=True),
        sa.Column("document_number_last_four", sa.String(10), nullable=True),
        sa.Column("document_url", sa.String(500), nullable=True),
        sa.Column("status", sa.String(30), server_default="PENDING", nullable=False),
        sa.Column("provider", sa.String(50), nullable=True),
        sa.Column("provider_reference_id", sa.String(200), nullable=True, index=True),
        sa.Column("verified_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("failure_reason", sa.Text(), nullable=True),
        sa.Column("failure_code", sa.String(50), nullable=True),
        sa.Column("requires_admin_review", sa.Boolean(), server_default="true", nullable=False),
        sa.Column("admin_reviewed", sa.Boolean(), server_default="false", nullable=False),
        sa.Column("admin_reviewed_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("admin_reviewed_by", sa.Integer(), sa.ForeignKey("users.id"), nullable=True),
        sa.Column("admin_review_notes", sa.Text(), nullable=True),
        sa.Column("provider_metadata", sa.JSON(), nullable=True),
        sa.Column("expiry_date", sa.DateTime(timezone=True), nullable=True),
        sa.Column("attempt_number", sa.Integer(), server_default="1", nullable=False),
        sa.Column("is_latest_attempt", sa.Boolean(), server_default="true", nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default="now()", nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default="now()", nullable=False),
    )

    # ── Verification Attempts ──────────────────────────────────────────
    op.create_table(
        "verification_attempts",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("onboarding_id", sa.Integer(), sa.ForeignKey("merchant_onboardings.id", ondelete="CASCADE"), nullable=False, index=True),
        sa.Column("attempt_type", sa.Enum("PHONE_OTP", "GSTIN_VERIFY", "UDYAM_VERIFY", "BANK_PENNY_DROP", "DRUG_LICENSE_VERIFY", "FSSAI_LICENSE_VERIFY", "DRIVING_LICENSE_VERIFY", "VEHICLE_RC_VERIFY", name="verification_attempt_type"), nullable=False),
        sa.Column("status", sa.Enum("INITIATED", "IN_PROGRESS", "SUCCESS", "FAILED", "TIMEOUT", "ERROR", name="verification_attempt_status"), server_default="INITIATED", nullable=False),
        sa.Column("request_id", sa.String(100), nullable=True, index=True),
        sa.Column("idempotency_key", sa.String(100), nullable=True, index=True),
        sa.Column("started_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("completed_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("duration_ms", sa.Integer(), nullable=True),
        sa.Column("error_message", sa.Text(), nullable=True),
        sa.Column("error_code", sa.String(50), nullable=True),
        sa.Column("provider_code", sa.String(50), nullable=True),
        sa.Column("provider_reference_id", sa.String(200), nullable=True),
        sa.Column("attempt_number", sa.Integer(), server_default="1", nullable=False),
        sa.Column("is_latest_attempt", sa.Boolean(), server_default="true", nullable=False),
        sa.Column("extra_data", sa.JSON(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default="now()", nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default="now()", nullable=False),
    )

    # ── Verification Provider Logs ─────────────────────────────────────
    op.create_table(
        "verification_provider_logs",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("attempt_id", sa.Integer(), sa.ForeignKey("verification_attempts.id", ondelete="SET NULL"), nullable=True, index=True),
        sa.Column("onboarding_id", sa.Integer(), sa.ForeignKey("merchant_onboardings.id", ondelete="SET NULL"), nullable=True, index=True),
        sa.Column("provider_code", sa.String(50), nullable=False, index=True),
        sa.Column("provider_environment", sa.String(20), server_default="sandbox", nullable=False),
        sa.Column("request_method", sa.String(10), nullable=True),
        sa.Column("request_url", sa.String(500), nullable=True),
        sa.Column("request_headers", sa.JSON(), nullable=True),
        sa.Column("request_body_reference", sa.String(200), nullable=True),
        sa.Column("response_status_code", sa.Integer(), nullable=True),
        sa.Column("response_body_reference", sa.String(200), nullable=True),
        sa.Column("response_time_ms", sa.Integer(), nullable=True),
        sa.Column("is_error", sa.Boolean(), server_default="false", nullable=False),
        sa.Column("error_type", sa.String(50), nullable=True),
        sa.Column("error_message", sa.Text(), nullable=True),
        sa.Column("provider_reference_id", sa.String(200), nullable=True, index=True),
        sa.Column("extra_data", sa.JSON(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default="now()", nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default="now()", nullable=False),
    )

    # ── Indexes ────────────────────────────────────────────────────────
    op.create_index("ix_merchant_onboardings_status", "merchant_onboardings", ["status"])
    op.create_index("ix_merchant_onboardings_user_id", "merchant_onboardings", ["user_id"])
    op.create_index("ix_business_identity_verifications_onboarding", "business_identity_verifications", ["onboarding_id"])
    op.create_index("ix_bank_account_verifications_onboarding", "bank_account_verifications", ["onboarding_id"])
    op.create_index("ix_category_document_verifications_onboarding", "category_document_verifications", ["onboarding_id"])
    op.create_index("ix_verification_attempts_onboarding", "verification_attempts", ["onboarding_id"])
    op.create_index("ix_verification_provider_logs_onboarding", "verification_provider_logs", ["onboarding_id"])


def downgrade():
    op.drop_index("ix_verification_provider_logs_onboarding", table_name="verification_provider_logs")
    op.drop_index("ix_verification_attempts_onboarding", table_name="verification_attempts")
    op.drop_index("ix_category_document_verifications_onboarding", table_name="category_document_verifications")
    op.drop_index("ix_bank_account_verifications_onboarding", table_name="bank_account_verifications")
    op.drop_index("ix_business_identity_verifications_onboarding", table_name="business_identity_verifications")
    op.drop_index("ix_merchant_onboardings_user_id", table_name="merchant_onboardings")
    op.drop_index("ix_merchant_onboardings_status", table_name="merchant_onboardings")
    op.drop_table("verification_provider_logs")
    op.drop_table("verification_attempts")
    op.drop_table("category_document_verifications")
    op.drop_table("bank_account_verifications")
    op.drop_table("business_identity_verifications")
    op.drop_table("merchant_onboardings")
    op.drop_table("merchant_verification_requirements")
    op.drop_table("merchant_categories")
    op.execute("DROP TYPE IF EXISTS onboarding_status")
    op.execute("DROP TYPE IF EXISTS identity_verification_type")
    op.execute("DROP TYPE IF EXISTS identity_verification_status")
    op.execute("DROP TYPE IF EXISTS verification_attempt_type")
    op.execute("DROP TYPE IF EXISTS verification_attempt_status")


