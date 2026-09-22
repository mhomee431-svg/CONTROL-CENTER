"""Add optional support-attachment columns to `complaints`.

Revision ID: 0025
Revises: 0024
Create Date: 2026-09-21

*Report an issue* previously had to omit screenshots because the shared
``complaints`` table had nowhere to put one. These two nullable columns close
that gap WITHOUT touching any existing row or query:

  * ``attachment_key``  — the server-minted media key (``support/{user_id}/...``)
    from the Phase 7 signed-upload pipeline. A KEY is stored, never a presigned
    URL: URLs expire, and the read URL is minted at serialization time.
  * ``attachment_meta`` — the metadata the storage layer reported for that
    object (filename / content_type / size_bytes), so a ticket shows what was
    actually uploaded rather than what the client claimed.

Both are nullable, so customer complaints and every pre-existing row are
unaffected.
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision: str = "0025"
down_revision: Union[str, None] = "0024"
branch_labels: Union[str, None] = None
depends_on: Union[str, None] = None


def upgrade() -> None:
    op.add_column(
        "complaints",
        sa.Column("attachment_key", sa.String(512), nullable=True),
    )
    op.add_column(
        "complaints",
        sa.Column("attachment_meta", sa.JSON(), nullable=True),
    )


def downgrade() -> None:
    op.drop_column("complaints", "attachment_meta")
    op.drop_column("complaints", "attachment_key")
