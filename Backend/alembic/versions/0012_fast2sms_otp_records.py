"""Fast2SMS single-use OTP records

Revision ID: 0012
Revises: 0011
Create Date: 2026-08-29

Adds:
- otps: expiring, single-use OTP records for the Fast2SMS phone-auth flow.
  - phone_number (indexed)
  - otp_code    (salted HMAC-SHA256 digest — raw OTP is never stored)
  - expires_at  (5-minute validity window)
  - is_verified (default False; set True on successful verification)
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = "0012"
down_revision: Union[str, None] = "0011"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "otps",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("phone_number", sa.String(20), nullable=False),
        sa.Column("otp_code", sa.String(128), nullable=False),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("is_verified", sa.Boolean(), nullable=False, server_default=sa.text("false")),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.text("now()")),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.text("now()")),
    )
    op.create_index("ix_otps_id", "otps", ["id"])
    op.create_index("ix_otps_phone_number", "otps", ["phone_number"])
    op.create_index("ix_otps_expires_at", "otps", ["expires_at"])


def downgrade() -> None:
    op.drop_index("ix_otps_expires_at", table_name="otps")
    op.drop_index("ix_otps_phone_number", table_name="otps")
    op.drop_index("ix_otps_id", table_name="otps")
    op.drop_table("otps")