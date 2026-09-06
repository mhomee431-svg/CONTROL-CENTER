#!/usr/bin/env bash
# infra/scripts/cicd_migrate.sh — safe, gated database migration (Phase 25 CI/CD).
#
# Runs on a target that holds a backend checkout (the app EC2 instance, invoked
# through SSM Run Command by the pipeline, or a local/dev machine). It:
#   1. Refuses to run when a migration-safety report says DANGEROUS unless the
#      migration was explicitly approved (MIGRATION_APPROVED=yes / --approved).
#   2. Takes a pre-migration schema snapshot (pg_dump --schema-only) when
#      pg_dump exists — uploaded to S3 when SNAPSHOT_BUCKET is set.
#   3. Applies `alembic upgrade head` (via the compose `migrate` one-shot on a
#      Compose target, or a local venv alembic otherwise). Idempotent.
#   4. Re-prints the applied revision (alembic current) for the pipeline audit.
#
# Usage (on the server where /opt/hyperlocal is the checkout):
#   MIGRATION_APPROVED=yes ./cicd_migrate.sh
#   ./cicd_migrate.sh --check-only          # only report pending status
# Env:
#   APP_DIR, DATABASE_URL (else read from Backend/.env), PGDUMP_URL,
#   SNAPSHOT_BUCKET, MIGRATION_APPROVED, COMPOSE_FILE
set -euo pipefail

APP_DIR="${APP_DIR:-/opt/hyperlocal}"
COMPOSE_FILE="${COMPOSE_FILE:-docker-compose.cloud.yml}"
SNAPSHOT_BUCKET="${SNAPSHOT_BUCKET:-}"
MIGRATION_APPROVED="${MIGRATION_APPROVED:-no}"
CHECK_ONLY="${CHECK_ONLY:-no}"

while [ $# -gt 0 ]; do
  case "$1" in
    --check-only) CHECK_ONLY=1; shift ;;
    --approved)   MIGRATION_APPROVED=yes; shift ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

log()  { printf '\033[1;34m[cicd-migrate]\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31m[cicd-migrate] ERROR:\033[0m %s\n' "$*" >&2; exit 1; }

[ -d "$APP_DIR" ] || fail "APP_DIR ${APP_DIR} not found"

# ── 1. Resolve DATABASE_URL ──────────────────────────────────────────────────
if [ -z "${DATABASE_URL:-}" ] && [ -f "$APP_DIR/Backend/.env" ]; then
  DB_LINE="$(grep -E '^DATABASE_URL=' "$APP_DIR/Backend/.env" | tail -1 || true)"
  if [ -n "$DB_LINE" ]; then
    # shellcheck disable=SC2001
    DATABASE_URL="$(printf '%s' "$DB_LINE" | sed 's/^DATABASE_URL=//; s/^urn:env://')"
  fi
fi
[ -n "${DATABASE_URL:-}" ] || fail "DATABASE_URL not set and not found in Backend/.env"

# ── 2. Migration-safety gate (defense in depth on the server) ────────────────
SAFETY_REPORT="$APP_DIR/Backend/migration_safety_report.json"
if [ -f "$SAFETY_REPORT" ] && [ -x "$(command -v jq || true)" ]; then
  VERDICT="$(jq -r '.verdict // "safe"' "$SAFETY_REPORT")"
  if [ "$VERDICT" = "dangerous" ]; then
    case "$MIGRATION_APPROVED" in
      yes|true|1) log "DANGEROUS migration detected but explicitly approved — proceeding." ;;
      *) fail "migration_safety_report.json says DANGEROUS and MIGRATION_APPROVED != yes. Refusing to auto-migrate." ;;
    esac
  fi
fi

# ── 3. alembic helpers (compose one-shot on the server, local venv otherwise) ─
if [ -f "$APP_DIR/Backend/${COMPOSE_FILE}" ] && command -v docker >/dev/null 2>&1; then
  USE_COMPOSE=1
else
  USE_COMPOSE=0
fi

alembic_current() {
  if [ "$USE_COMPOSE" = "1" ]; then
    docker compose -f "$APP_DIR/Backend/${COMPOSE_FILE}" run --rm migrate \
      alembic current 2>&1 || true
  else
    (cd "$APP_DIR/Backend" && alembic current 2>&1) || true
  fi
}

alembic_upgrade_head() {
  if [ "$USE_COMPOSE" = "1" ]; then
    docker compose -f "$APP_DIR/Backend/${COMPOSE_FILE}" run --rm migrate alembic upgrade head
  else
    (cd "$APP_DIR/Backend" && alembic upgrade head)
  fi
}

CURRENT_OUT="$(alembic_current)"
log "current applied revision:"
printf '%s\n' "$CURRENT_OUT" | sed 's/^/    /'

# ── 4. --check-only: report whether migrations are pending ───────────────────
if [ "$CHECK_ONLY" = "1" ]; then
  # `alembic current` reports "(head)" when the DB is already at the last revision.
  if printf '%s\n' "$CURRENT_OUT" | grep -q '(head)'; then
    log "MIGRATIONS_PENDING=no"
  else
    log "MIGRATIONS_PENDING=yes"
  fi
  exit 0
fi

# ── 5. Pre-migration schema snapshot ─────────────────────────────────────────
PGDUMP_URL="${PGDUMP_URL:-}"
if [ -z "$PGDUMP_URL" ]; then
  PGDUMP_URL="$(printf '%s' "$DATABASE_URL" \
    | sed 's/^postgresql+asyncpg:/postgresql:/; s/^postgresql+psycopg:/postgresql:/')"
fi
if command -v pg_dump >/dev/null 2>&1; then
  STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
  DUMP_FILE="${SNAPSHOT_DIR:-/tmp}/hyperlocal_schema_${STAMP}.sql"
  log "pre-migration schema snapshot → ${DUMP_FILE}"
  if pg_dump --schema-only --no-owner --no-privileges "$PGDUMP_URL" > "$DUMP_FILE"; then
    if [ -n "$SNAPSHOT_BUCKET" ] && command -v aws >/dev/null 2>&1; then
      aws s3 cp "$DUMP_FILE" "${SNAPSHOT_BUCKET}/migrations/$(basename "$DUMP_FILE")" >/dev/null \
        && log "snapshot uploaded to ${SNAPSHOT_BUCKET}/migrations/"
    fi
  else
    log "snapshot skipped (pg_dump failed — RDS automated backups still guard data)"
  fi
else
  log "pg_dump unavailable — skipping schema snapshot (RDS backups still guard data)."
fi

# ── 6. Apply migrations (idempotent) ─────────────────────────────────────────
log "applying migrations (alembic upgrade head) …"
alembic_upgrade_head
log "post-upgrade revision:"
alembic_current | sed 's/^/    /'
log "✅ migration step complete"