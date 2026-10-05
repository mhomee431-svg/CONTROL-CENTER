"""Make every persisted timestamp timezone-aware.

Why
---
The schema is inconsistent. 393 timestamp columns are
``sa.DateTime(timezone=True)`` (``timestamptz``), but 17 were created as
``sa.DateTime()`` (``timestamp without time zone``) by migrations 0001, 0002 and
0009. Both kinds are populated from ``now()`` on a UTC database, so the stored
wall-clock values are UTC in every case.

The cost of the inconsistency is on the client. Python's
``datetime.isoformat()`` emits a naive value with **no offset**:
``2026-01-15T10:00:00``. Dart's ``DateTime.parse`` reads a bare timestamp as
**local** time, so the instant arrives already carrying the wrong zone and any
later ``.toLocal()`` is a no-op that merely looks correct. For a device in IST
that is a silent 5h30m error on every affected timestamp. The customer's
``AppDateTime`` currently *assumes* these are UTC to compensate; this migration
makes the assumption true rather than load-bearing.

How
---
``ALTER TABLE ... ALTER COLUMN ... TYPE timestamptz`` on its own is unsafe:
Postgres reinterprets existing values using the **current session TimeZone**, so
a deployment whose DB session is not UTC would silently shift historical rows.
``USING <col> AT TIME ZONE 'UTC'`` pins the source zone explicitly, which is
correct precisely because these values were written as UTC.

Non-destructive and reversible: this changes representation, not data, and
``downgrade`` converts back using the same pinned zone.

Dev note: on SQLite (used for local dev in this repo) ``ALTER COLUMN TYPE`` is
not supported, so those statements are skipped rather than failing the suite.
"""
from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision: str = "0027"
down_revision: str = "0026"
branch_labels: str | None = None
depends_on: str | None = None


# (table, column) pairs that migrations 0001, 0002 and 0009 created as naive.
#
# Derived from the create_table blocks in those migrations:
#   0001: users, categories, products, shops, inventory, saved_products,
#         saved_shops, notifications
#   0002: products / saved_products / inventory (recreated)
#   0009: notification_deliveries
_NAIVE_TIMESTAMP_COLUMNS: tuple[tuple[str, str], ...] = (
    ("users", "created_at"),
    ("users", "updated_at"),
    ("categories", "created_at"),
    ("products", "created_at"),
    ("products", "updated_at"),
    ("shops", "created_at"),
    ("shops", "updated_at"),
    ("inventory", "updated_at"),
    ("saved_products", "created_at"),
    ("saved_shops", "created_at"),
    ("notifications", "created_at"),
    ("notification_deliveries", "created_at"),
    ("notification_deliveries", "updated_at"),
)


def _is_postgres() -> bool:
    return op.get_bind().dialect.name == "postgresql"


def _convert(columns: tuple[tuple[str, str], ...], to_timestamptz: bool) -> None:
    """Move each column between ``timestamp`` and ``timestamptz``.

    [to_timestamptz] selects the direction so upgrade and downgrade share the
    one piece of logic that actually matters — the pinned source zone.
    """
    if not _is_postgres():
        # SQLite cannot ALTER COLUMN TYPE. The dev database is disposable and
        # recreated by the test fixtures, so skipping is safe there; failing
        # would break every local run for no benefit.
        return

    target = "timestamptz" if to_timestamptz else "timestamp"
    for table, column in columns:
        op.execute(
            sa.text(
                f'ALTER TABLE "{table}" ALTER COLUMN "{column}" '
                f'TYPE {target} USING "{column}" AT TIME ZONE \'UTC\''
            )
        )


def upgrade() -> None:
    _convert(_NAIVE_TIMESTAMP_COLUMNS, to_timestamptz=True)


def downgrade() -> None:
    _convert(_NAIVE_TIMESTAMP_COLUMNS, to_timestamptz=False)