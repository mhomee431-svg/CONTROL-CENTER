#!/usr/bin/env bash
# infra/scripts/backup_db.sh — Hyperlocal logical database backup (Phase 5).
#
# Produces a full logical backup set + sidecar manifest so a restore can be
# VERIFIED (never trusted blindly):
#   * <stamp>.pgc           pg_dump -Fc   (schema + data, compressed custom)
#   * <stamp>.schema.sql    pg_dump --schema-only (lightweight schema history)
#   * <stamp>.manifest.json alembic revision + per-table row counts
# `--mode snapshot` instead takes a manual AWS RDS snapshot (safe baseline).
#
# Usage:
#   ./backup_db.sh <environment>                   # logical dump to $BACKUP_DIR
#   ./backup_db.sh <environment> --mode snapshot   # manual RDS snapshot
#
# Environment:
#   DATABASE_URL   async/sync SQLAlchemy URL (normalized automatically)
#   PGDUMP_URL     libpq URL for pg_dump/psql (wins over DATABASE_URL)
#   BACKUP_DIR     artifact dir                     (default ./backups)
#   BACKUP_BUCKET  optional s3://bucket[/prefix]     (DR copy)
#   RETENTION_DAYS prune local artifacts older than N (default 7; 0=keep)
#   BACKUP_PREFIX  "daily"|"monthly"                 (S3 prefix)
#   PG_DUMP / PSQL binary overrides
set -euo pipefail

ENV_NAME="${1:?usage: backup_db.sh <environment> [--mode dump|snapshot]}"
MODE="${2:-dump}"
REGION="${AWS_REGION:-ap-south-1}"
PROJECT="${PROJECT_NAME:-hyperlocal}"
BACKUP_DIR="${BACKUP_DIR:-./backups}"
RETENTION_DAYS="${RETENTION_DAYS:-7}"
BACKUP_PREFIX="${BACKUP_PREFIX:-daily}"
S3_BUCKET="${BACKUP_BUCKET:-}"
PG_DUMP="${PG_DUMP:-pg_dump}"
PSQL="${PSQL:-psql}"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p "$BACKUP_DIR"

normalize_libpq() {  # asyncpg/psycopg forms → libpq form pg tools expect
  local url="$1"
  url="${url//postgresql+asyncpg:/postgresql:}"
  url="${url//postgres+psycopg:/postgresql:}"
  url="${url//ssl=require/sslmode=require}"
  echo "$url"
}

if [ -z "${PGDUMP_URL:-}" ]; then
  : "${DATABASE_URL:?set DATABASE_URL or PGDUMP_URL}"
  PGDUMP_URL="$(normalize_libpq "$DATABASE_URL")"
else
  PGDUMP_URL="$(normalize_libpq "$PGDUMP_URL")"
fi
DB_NAME="$("$PSQL" -At -c 'SELECT current_database()' "$PGDUMP_URL" | tr -d '\r' | head -1)"
: "${DB_NAME:?could not derive database name from URL}"
echo "── Phase 5 — backup (${MODE}) env=${ENV_NAME} db=${DB_NAME} ─────────────"

# ── 1. Manual RDS snapshot mode (pre-migration / pre-risk baseline) ──────────
if [ "$MODE" = "snapshot" ]; then
  INSTANCE="${PROJECT}-${ENV_NAME}-db"
  SNAP_ID="${PROJECT}-${ENV_NAME}-manual-$(date -u +%Y%m%dT%H%M%SZ)"
  if aws rds describe-db-snapshots --db-snapshot-identifier "$SNAP_ID" --region "$REGION" \
    --query 'DBSnapshots[0].DBSnapshotIdentifier' --output text >/dev/null 2>&1; then
    echo "!! Snapshot ${SNAP_ID} already exists — nothing to do."
    exit 2
  fi
  echo "==> Creating manual RDS snapshot ${SNAP_ID} from ${INSTANCE}"
  aws rds create-db-snapshot --db-instance-identifier "$INSTANCE" \
    --db-snapshot-identifier "$SNAP_ID" --region "$REGION" >/dev/null
  echo "    status: $(aws rds describe-db-snapshots --db-snapshot-identifier "$SNAP_ID" \
    --region "$REGION" --query 'DBSnapshots[0].Status' --output text) (creating)"
  echo "    NOTE: RDS automated backups + PITR already guard data."
  exit 0
fi

# ── 2. Logical backup set ─────────────────────────────────────────────────────
BASE="${BACKUP_DIR}/${PROJECT}_${ENV_NAME}_${STAMP}"
echo "==> pg_dump -Fc (schema + data) -> ${BASE}.pgc"
"$PG_DUMP" -Fc --no-owner --no-privileges "$PGDUMP_URL" > "${BASE}.pgc"
echo "==> pg_dump --schema-only -> ${BASE}.schema.sql"
"$PG_DUMP" --schema-only --no-owner --no-privileges "$PGDUMP_URL" > "${BASE}.schema.sql"

# ── 3. Manifest (revision + per-table row counts) ─────────────────────────────
REV="$("$PSQL" -At -c 'SELECT version_num FROM alembic_version LIMIT 1' "$PGDUMP_URL" | tr -d '\r' | head -1 || echo 'NO_ALEMBIC')"
{
  echo "{"
  echo "  \"created_at\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\","
  echo "  \"environment\": \"${ENV_NAME}\","
  echo "  \"database\": \"${DB_NAME}\","
  echo "  \"alembic_version\": \"${REV}\","
  echo "  \"dump_file\": \"$(basename "${BASE}.pgc")\","
  echo "  \"schema_file\": \"$(basename "${BASE}.schema.sql")\","
  echo "  \"tables\": ["
  FIRST=1
  "$PSQL" -At -c "SELECT table_name FROM information_schema.tables
       WHERE table_schema='public' AND table_type='BASE TABLE' ORDER BY 1" "$PGDUMP_URL" | tr -d '\r' |
  while IFS= read -r t; do
    [ -z "$t" ] && continue
    CNT="$("$PSQL" -At -c "SELECT count(*) FROM \"$t\"" "$PGDUMP_URL" | tr -d '\r' | head -1)"
    [ "$FIRST" = "1" ] || echo ","
    echo "    {\"table\": \"${t}\", \"rows\": ${CNT}}"
    FIRST=0
  done
  echo ""
  echo "  ]"
  echo "}"
} > "${BASE}.manifest.json"

# ── 4. Checksum + summary ────────────────────────────────────────────────────
SHA256="$(sha256sum "${BASE}.pgc" | awk '{print $1}')"
echo "  dump sha256: ${SHA256}  ($(wc -c < "${BASE}.pgc") bytes)  revision: ${REV}"

# ── 5. Optional S3 copy (DR layer, separate from RDS snapshots) ──────────────
if [ -n "$S3_BUCKET" ]; then
  DEST="${S3_BUCKET%/}/${BACKUP_PREFIX}/$(date -u +%Y/%m/%d)"
  aws s3 cp "${BASE}.pgc" "${DEST}/$(basename "${BASE}.pgc")" --no-progress >/dev/null
  aws s3 cp "${BASE}.manifest.json" "${DEST}/$(basename "${BASE}.manifest.json")" --no-progress >/dev/null
  echo "==> Uploaded to s3://${DEST}/"
fi

# ── 6. Local retention (prune old artifacts) ─────────────────────────────────
if [ "$RETENTION_DAYS" -gt 0 ]; then
  find "$BACKUP_DIR" -type f \( -name '*.pgc' -o -name '*.manifest.json' -o -name '*.schema.sql' \) \
    -mtime "+${RETENTION_DAYS}" -delete -print
fi

echo "✅ backup complete: ${BASE}.pgc (+ .schema.sql + .manifest.json)"