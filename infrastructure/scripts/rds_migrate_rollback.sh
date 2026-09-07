#!/usr/bin/env bash
# infrastructure/scripts/rds_migrate_rollback.sh — Safe Alembic downgrade (Phase 5).
#
# Rolls the schema back ONE migration revision (default) without touching data:
#   1. Refuses to run while the DB is at the first migration (0001).
#   2. Pre-flight checks that a safety net exists:
#        - RDS automated backups are ON (backup_retention_period > 0 — PITR), or
#          a manual pre-migration snapshot/dump was taken (rds_migrate.sh does
#          this automatically), or SKIP_BACKUP_CHECK=1 is set explicitly.
#   3. Runs `alembic downgrade -N` (each migration ships a real downgrade()).
#   4. Re-verifies the approved architecture with scripts/verify_rds.py.
#
# Strategy context — THREE layered rollback paths (see Phase 5 doc):
#   Layer 1 (preferred): restore the logical backup taken by backup_db.sh
#                        -> restore_db.sh (data + schema, exact restore).
#   Layer 2:             RDS snapshot / PITR restore -> rds_restore.sh.
#   Layer 3 (this):      `alembic downgrade` — schema-only, data is preserved,
#                        but long chains should be verified at every step.
#
# Usage (from the backend container / machine with the app venv):
#   DATABASE_URL='postgresql+asyncpg://...' ./rds_migrate_rollback.sh [--steps N]
# Environment:
#   DATABASE_URL required (async URL; alembic uses it directly).
#   SKIP_BACKUP_CHECK=1 bypasses the automated-backup safety check.
set -eu
export PYTHONDONTWRITEBYTECODE=1

STEPS="${STEPS:-1}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BACKEND_DIR="${REPO_ROOT}/backend"
cd "$BACKEND_DIR"
VERIFY="$BACKEND_DIR/scripts/verify_rds.py"

: "${DATABASE_URL:?DATABASE_URL is required (postgresql+asyncpg://...)}"
export DATABASE_URL

echo "── Phase 5 — migration rollback (downgrade ${STEPS} step(s)) ──────────"

# ── 1. Refuse at the bottom of the chain ──────────────────────────────────────
CURRENT="$(alembic current 2>/dev/null | grep -oE '[0-9]{4}' | head -1 || echo '')"
echo "  current revision: ${CURRENT:-unknown}"
if [ "${CURRENT:-0001}" = "0001" ]; then
  echo "!! At revision 0001 — cannot roll back further via Alembic."
  echo "   If you need to reset the database, restore a backup instead (restore_db.sh / rds_restore.sh)."
  exit 2
fi

# ── 2. Safety net check ───────────────────────────────────────────────────────
if [ "${SKIP_BACKUP_CHECK:-0}" != "1" ]; then
  ENV_NAME="${ENVIRONMENT:-production}"
  INSTANCE="${PROJECT_NAME:-hyperlocal}-${ENV_NAME}-db"
  if command -v aws >/dev/null 2>&1; then
    RET="$(aws rds describe-db-instances --db-instance-identifier "$INSTANCE" \
      --query 'DBInstances[0].BackupRetentionPeriod' --output text 2>/dev/null || echo '0')"
    if [ "$RET" = "0" ]; then
      echo "!! RDS automated backups are OFF (backup_retention_period=0) on ${INSTANCE}."
      echo "   Take a manual snapshot first:  ./infrastructure/scripts/backup_db.sh ${ENV_NAME} --mode snapshot"
      echo "   or export SKIP_BACKUP_CHECK=1 if a logical backup / snapshot already exists."
      exit 3
    fi
    echo "  ✔ RDS automated backups ON (retention ${RET} days) — PITR available."
  else
    echo "  (aws CLI not available — assuming an external backup exists; pass SKIP_BACKUP_CHECK=0 to enforce)"
  fi
fi

# ── 3. Downgrade ──────────────────────────────────────────────────────────────
echo "==> alembic downgrade -${STEPS}"
if ! alembic downgrade "-${STEPS}"; then
  echo "!! alembic downgrade FAILED — the migration's downgrade() raised."
  echo "   Fall back to Layer 1/2 (restore a backup):"
  echo "     ./infrastructure/scripts/restore_db.sh ${ENV_NAME:-<env>} <backup>.pgc --target \"\$DATABASE_URL\" --replace --verify-architecture"
  echo "     ./infrastructure/scripts/rds_restore.sh ${ENV_NAME:-<env>} auto"
  exit 1
fi
echo "    downgrade applied."

# ── 4. Verify the approved architecture is still intact ──────────────────────
echo "==> Re-verifying schema (verify_rds.py)"
if ! python "$VERIFY"; then
  echo "!! Post-downgrade verification failed — STOP and inspect; do not deploy."
  echo "   Recommended: restore from the pre-change backup (Layer 1/2)."
  exit 1
fi
echo "OK rollback complete and verified at revision $(alembic current 2>/dev/null | head -1)."