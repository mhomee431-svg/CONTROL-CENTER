from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = "0028"
down_revision: str = "0027"
branch_labels: str | None = None
depends_on: str | None = None


def upgrade() -> None:
    """Remember the header row of each staged import.

    The Column Mapping step is correctable before the import is applied, which
    means the server has to hold two things it did not before: which columns the
    file actually has, and the cells of each row BY POSITION.

    `header_row` is the first. Without it a submitted mapping can only be
    trusted on the client's word — a stale client could remap onto column 40 of
    a five-column sheet and the row would silently import blanks.

    `column_mapping` is the second: the mapping actually applied. It is not
    derivable from the header once the shopkeeper has corrected an ambiguous
    column, and re-deriving it would undo their correction on the next reload.

    Both nullable with no server default: an existing staged job has neither,
    which means it cannot be remapped (it was staged under the old field-keyed
    scheme). Those rows keep working exactly as before.
    """
    op.add_column(
        "inventory_import_jobs",
        sa.Column("header_row", sa.Text(), nullable=True),
    )
    op.add_column(
        "inventory_import_jobs",
        sa.Column("column_mapping", sa.Text(), nullable=True),
    )


def downgrade() -> None:
    op.drop_column("inventory_import_jobs", "column_mapping")
    op.drop_column("inventory_import_jobs", "header_row")
