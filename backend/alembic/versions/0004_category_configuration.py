"""Add category configuration columns.

The Category model gained three JSON columns for category configuration beyond
identity (the "CATEGORY CONFIGURATION" spec section):

  required_fields      - field names a listing in this category must supply
  optional_fields      - field names it may supply
  feature_capabilities - feature keys enabled for the category

They were added to the model without a migration, so any database created
before the change failed every `/admin/categories` query with
"no such column: categories.required_fields". This migration closes that gap.

All three are nullable and default to an empty list at the application layer,
so existing rows read back as an empty configuration rather than NULL.

Idempotent by inspection, matching 0003: a database whose schema was created
directly from the models already has the columns and must not fail the upgrade.

Revision ID: 0004_category_configuration
Revises: 0003_feature_flag_environment
"""
from alembic import op
import sqlalchemy as sa

revision = "0004_category_configuration"
down_revision = "0003_feature_flag_environment"
branch_labels = None
depends_on = None

_COLUMNS = (
    ("required_fields", sa.JSON()),
    ("optional_fields", sa.JSON()),
    ("feature_capabilities", sa.JSON()),
)


def upgrade() -> None:
    bind = op.get_bind()
    existing = {col["name"] for col in sa.inspect(bind).get_columns("categories")}
    for name, column_type in _COLUMNS:
        if name not in existing:
            op.add_column("categories", sa.Column(name, column_type, nullable=True))


def downgrade() -> None:
    bind = op.get_bind()
    existing = {col["name"] for col in sa.inspect(bind).get_columns("categories")}
    for name, _ in reversed(_COLUMNS):
        if name in existing:
            op.drop_column("categories", name)
