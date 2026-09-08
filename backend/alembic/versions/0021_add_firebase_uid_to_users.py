"""Add firebase_uid to users — Firebase Authentication migration

Adds the firebase_uid column to the users table as the stable external
identity identifier from Firebase Authentication. This replaces phone_number
as the primary link between Firebase and the application user.

Revision ID: 0021
Revises: 0020
Create Date: 2026-09-08
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = "0021"
down_revision: Union[str, None] = "0020"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade():
    # Add firebase_uid column to users table
    op.add_column(
        "users",
        sa.Column("firebase_uid", sa.String(128), nullable=True),
    )
    # Create unique index on firebase_uid
    op.create_index(
        "ix_users_firebase_uid",
        "users",
        ["firebase_uid"],
        unique=True,
    )
    # Create index for faster lookups
    op.create_index(
        "ix_users_firebase_uid_not_null",
        "users",
        ["firebase_uid"],
        unique=False,
        postgresql_where=sa.text("firebase_uid IS NOT NULL"),
    )


def downgrade():
    op.drop_index("ix_users_firebase_uid_not_null", table_name="users")
    op.drop_index("ix_users_firebase_uid", table_name="users")
    op.drop_column("users", "firebase_uid")
