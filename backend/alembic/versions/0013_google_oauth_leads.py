"""Google OAuth + User Interactions (Leads)

Revision ID: 0013
Revises: 0012
Create Date: 2026-08-29

Adds:
- users.google_id            : unique, indexed — Google OAuth subject identifier
- users.phone_number         : now nullable (Google-only signups have no phone)
- user_interactions          : immutable create-only customer action leads
    - user_id            FK users.id
    - shop_id            FK shops.id
    - action_type        enum(call_view|message|rating)
    - message_content    (inquiry / review text)
    - rating             (1..5 CHECK constraint)
    - created_at / updated_at
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = "0013"
down_revision: Union[str, None] = "0012"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # ── users: google_id + nullable phone ───────────────────────────────────────
    op.add_column(
        "users",
        sa.Column("google_id", sa.String(64), nullable=True),
    )
    op.alter_column(
        "users", "phone_number",
        existing_type=sa.String(20),
        nullable=True,
    )
    op.create_index("ix_users_google_id", "users", ["google_id"], unique=True)

    # ── interaction_action_type enum (idempotent — project pattern) ─────────────
    op.execute(
        "DO $$ BEGIN "
        "CREATE TYPE interaction_action_type AS ENUM "
        "('CALL_VIEW','MESSAGE','RATING'); "
        "EXCEPTION WHEN duplicate_object THEN NULL; "
        "END $$;"
    )

    # ── user_interactions (immutable leads) ────────────────────────────────────
    op.create_table(
        "user_interactions",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column(
            "user_id",
            sa.Integer(),
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column(
            "shop_id",
            sa.Integer(),
            sa.ForeignKey("shops.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column(
            "action_type",
            sa.Enum(
                "CALL_VIEW", "MESSAGE", "RATING",
                name="interaction_action_type",
                native_enum=False,
                create_type=False,
            ),
            nullable=False,
        ),
        sa.Column("message_content", sa.Text(), nullable=True),
        sa.Column("rating", sa.Integer(), nullable=True),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.text("now()"),
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.text("now()"),
        ),
        sa.CheckConstraint("rating >= 1 AND rating <= 5", name="ck_interactions_rating_range"),
    )
    op.create_index("ix_user_interactions_id", "user_interactions", ["id"])
    op.create_index("ix_user_interactions_user_id", "user_interactions", ["user_id"])
    op.create_index("ix_user_interactions_shop_id", "user_interactions", ["shop_id"])
    op.create_index(
        "ix_user_interactions_action_type", "user_interactions", ["action_type"]
    )
    op.create_index(
        "ix_user_interactions_shop_created",
        "user_interactions",
        ["shop_id", "created_at"],
    )
    op.create_index(
        "ix_user_interactions_user_created",
        "user_interactions",
        ["user_id", "created_at"],
    )


def downgrade() -> None:
    op.drop_index("ix_user_interactions_user_created", table_name="user_interactions")
    op.drop_index("ix_user_interactions_shop_created", table_name="user_interactions")
    op.drop_index("ix_user_interactions_action_type", table_name="user_interactions")
    op.drop_index("ix_user_interactions_shop_id", table_name="user_interactions")
    op.drop_index("ix_user_interactions_user_id", table_name="user_interactions")
    op.drop_index("ix_user_interactions_id", table_name="user_interactions")
    op.drop_table("user_interactions")
    # The enum type is shared across PG — created by an earlier migration DO block
    # in this project; leaving the type in place is consistent with prior enums.

    op.drop_index("ix_users_google_id", table_name="users")
    op.alter_column(
        "users", "phone_number",
        existing_type=sa.String(20),
        nullable=False,
    )
    op.drop_column("users", "google_id")