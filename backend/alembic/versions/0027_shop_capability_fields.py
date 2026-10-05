from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = "0027"
down_revision: str = "0026"
branch_labels: str | None = None
depends_on: str | None = None


def upgrade() -> None:
    """Store the capability-driven fields a shopkeeper actually submitted.

    A JSON document rather than a column per field, and that is the whole point:
    the fields are category-driven, so a pharmacy submits `prescription_required`
    while a tour operator submits `service_area` and neither should need a
    migration when the other trade appears. The backend registry decides which
    keys are valid; this column is only the durable landing place for the
    approved subset.

    Server default '{}' so existing rows read as "submitted nothing" instead of
    NULL, which would otherwise make every read branch handle two shapes.
    """
    op.add_column(
        "shops",
        sa.Column(
            "capability_fields",
            sa.Text(),
            nullable=False,
            server_default="{}",
        ),
    )


def downgrade() -> None:
    op.drop_column("shops", "capability_fields")