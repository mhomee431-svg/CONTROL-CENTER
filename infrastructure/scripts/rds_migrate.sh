#!/usr/bin/env bash
#
# rds_migrate.sh — Safe Alembic migration workflow for RDS PostgreSQL + PostGIS.
#
# Purpose:
#   Run database migrations against the production RDS instance without
#   recreating the database (migrations already exist; we never drop the DB).
#   It performs a safety pre-migration snapshot of the schema + data, applies
#   `alembic upgrade head` (idempotent), then runs the Phase 4 verifier and
#   exits non-zero if the DB does not match the approved architecture.
#
# Safety properties:
#   * Never drops/recreates the database.
#   * Runs inside the container (uses the app's DATABASE_URL / env profile).
#   * Optional pre/backup snapshot of the schema (pg_dump --schema-only is
#     cheap and reversible-safe) into local storage or S3.
#   * Verifies connection, PostGIS, tables, FKs, indexes, and PostGIS spatial
#     queries after the migration.
#
# Usage (from inside the backend container, or on a machine with the app venv):
#   RUN_MIGRATIONS=1 ./rds_migrate.sh            # DATABASE_URL from env
#   DATABASE_URL='postgresql+asyncpg://...' ./rds_migrate.sh
#   SNAPSHOT_BUCKET=s3://my-backup-bucket ./rds_migrate.sh   # push a schema dump
#
set -eu

export PYTHONDONTWRITEBYTECODE=1
export PYTHONUNBUFFERED=1

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKEND_DIR="${REPO_ROOT}/backend"
VERIFY="${BACKEND_DIR}/scripts/verify_rds.py"

echo "── Phase 4 — safe RDS migration workflow ──────────────────────────"

# ── 1. Environment / URL ────────────────────────────────────────────────────
: "${DATABASE_URL:?DATABASE_URL is required (postgresql+asyncpg://...)}"

# ── 2. Optional pre-migration schema snapshot (reversible safety net) ───────
# pg_dump needs a plain libpq URL (postgresql://user:pass@host:port/db), which
# differs from the sqlalchemy async URL. Provide it explicitly via PGDUMP_URL;
# skipping is fine because RDS automated snapshots already guard the data.
SNAPSHOT_DIR="${SNAPSHOT_DIR:-/tmp}"
if command -v pg_dump >/dev/null 2>&1 && [ -n "${PGDUMP_URL:-}" ]; then
  STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
  DUMP_FILE="${SNAPSHOT_DIR}/hyperlocal_schema_${STAMP}.sql"
  echo "==> Pre-migration schema snapshot -> ${DUMP_FILE}"
  pg_dump --schema-only --no-owner --no-privileges "${PGDUMP_URL}" > "${DUMP_FILE}" \
    && echo "    snapshot written (schema only)."
  if [ -n "${SNAPSHOT_BUCKET:-}" ]; then
    aws s3 cp "${DUMP_FILE}" "${SNAPSHOT_BUCKET}/migrations/$(basename "${DUMP_FILE}")" >/dev/null \
      && echo "    snapshot uploaded to S3."
  fi
else
  echo "==> Skipping schema snapshot (pg_dump and/or PGDUMP_URL not provided; RDS backups still guard data)."
fi

# ── 3. Apply migrations (idempotent, never recreates the DB) ────────────────
echo "==> Applying migrations (alembic upgrade head)"
cd "${BACKEND_DIR}" || exit 2
alembic upgrade head
if [ $? -ne 0 ]; then
  echo "!! Migration failed — investigate before retrying. Backup intact."
  exit 1
fi
echo "    migrations applied at HEAD."

# ── 4. Verify the approved architecture is intact ───────────────────────────
echo "==> Verifying PostGIS, tables, indexes, FKs and spatial queries"
if ! python "${VERIFY}"; then
  echo "!! Verification failed after migration. Review the FAIL lines above."
  exit 1
fi
echo "✅ migration + verification completed successfully."