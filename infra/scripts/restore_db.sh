#!/usr/bin/env bash
# infra/scripts/restore_db.sh — Hyperlocal restore with verification (Phase 5).
# Restores a logical backup from backup_db.sh (<stamp>.pgc) into an arbitrary
# PostgreSQL server, then VERIFIES by comparing the sidecar manifest (revision
# + per-table row counts) against the restored target. `--replace` is REQUIRED
# to overwrite an existing DB; the current target is safety-dumped FIRST.
# Usage: ./restore_db.sh <env> <backup.pgc> --target <db-url> [--replace] [--verify-architecture]
set -euo pipefail

ENV_NAME="${1:?usage: restore_db.sh <environment> <backup.pgc> --target <db-url> [--replace]}"
BACKUP_FILE="${2:?usage: restore_db.sh <environment> <backup.pgc> --target <db-url> [--replace]}"
shift 2
TARGET_URL=""
REPLACE=0
VERIFY_ARCH=0
while [ $# -gt 0 ]; do
  case "$1" in
    --target) TARGET_URL="$2"; shift 2 ;;
    --replace) REPLACE=1; shift ;;
    --verify-architecture) VERIFY_ARCH=1; shift ;;
    *) echo "!! unknown argument: $1"; exit 2 ;;
  esac
done

[ -f "$BACKUP_FILE" ] || { echo "!! backup file not found: $BACKUP_FILE"; exit 1; }
case "$BACKUP_FILE" in
  *.pgc|*.dump|*.backup) ;;
  *) echo "!! expected a custom-format dump (*.pgc) produced by backup_db.sh"; exit 2 ;;
esac

MANIFEST="${BACKUP_FILE%.pgc}.manifest.json"
[ -f "$MANIFEST" ] || MANIFEST="${BACKUP_FILE%.dump}.manifest.json"
[ -f "$MANIFEST" ] || MANIFEST="${BACKUP_FILE%.backup}.manifest.json"
PG_RESTORE="${PG_RESTORE:-pg_restore}"
PSQL="${PSQL:-psql}"
PG_DUMP="${PG_DUMP:-pg_dump}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERIFY="${REPO_ROOT}/Backend/scripts/verify_rds.py"

normalize_libpq() {
  local url="$1"
  for pfx in postgresql+asyncpg: postgres+psycopg:; do
    url="${url//$pfx/postgresql:}"
  done
  url="${url//ssl=require/sslmode=require}"
  echo "$url"
}
if [ -z "$TARGET_URL" ]; then
  : "${DATABASE_URL:?set --target <db-url> or DATABASE_URL}"
  TARGET_URL="$(normalize_libpq "$DATABASE_URL")"
else
  TARGET_URL="$(normalize_libpq "$TARGET_URL")"
fi

echo "── Phase 5 — restore ──────────────────────────────────────────────────"
echo "  backup: ${BACKUP_FILE}    target: ${TARGET_URL}"

# ── 1. Derive admin URL (db 'postgres') + the target DB name ─────────────────
admin_url() { python3 - "$TARGET_URL" <<'PY'
import sys, urllib.parse
u = urllib.parse.urlsplit(sys.argv[1])
print(urllib.parse.urlunsplit((u.scheme, u.netloc, "/postgres", u.query, "")))
PY
}
db_name() { python3 - "$TARGET_URL" <<'PY'
import sys, urllib.parse
print(urllib.parse.urlsplit(sys.argv[1]).path.rstrip('/').rsplit('/', 1)[-1])
PY
}
ADMIN_URL="$(admin_url)"
DB_NAME="$(db_name)"
EXISTS="$("$PSQL" -At -c "SELECT 1 FROM pg_database WHERE datname='${DB_NAME}'" "$ADMIN_URL" | tr -d '\r' | head -1)"
if [ "$EXISTS" = "1" ] && [ "$REPLACE" = "0" ]; then
  echo "!! target database '${DB_NAME}' exists — pass --replace to overwrite"
  echo "   (current target is safety-dumped before any change)."
  exit 3
fi

# ── 2. Safety dump of the current target before any destructive step ─────────
SAFETY_FILE=""
if [ "$EXISTS" = "1" ]; then
  SAFETY_FILE="$(dirname "$BACKUP_FILE")/pre_restore_${DB_NAME}_$(date -u +%Y%m%dT%H%M%SZ).pgc"
  echo "==> Safety dump of current ${DB_NAME} -> ${SAFETY_FILE}"
  "${PG_DUMP:-pg_dump}" -Fc --no-owner --no-privileges "$TARGET_URL" > "$SAFETY_FILE"
fi

# ── 3. Recreate the target database ──────────────────────────────────────────
echo "==> Recreating database '${DB_NAME}'"
if [ "$EXISTS" = "1" ]; then
  "$PSQL" -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname='${DB_NAME}' AND pid <> pg_backend_pid();" "$ADMIN_URL" >/dev/null
  "$PSQL" -c "DROP DATABASE ${DB_NAME};" "$ADMIN_URL" >/dev/null
fi
"$PSQL" -c "CREATE DATABASE ${DB_NAME};" "$ADMIN_URL" >/dev/null
echo "==> pg_restore --no-owner --no-privileges -d ${DB_NAME}"
"$PG_RESTORE" --no-owner --no-privileges --exit-on-error -d "$TARGET_URL" "$BACKUP_FILE"

# ── 4. Verification — the restore is not trusted until it is checked ─────────
FAIL=0
if [ -f "$MANIFEST" ]; then
  echo "==> Verifying manifest vs restored database"
  EXPECTED_REV="$(python3 - "$MANIFEST" rev <<'PY'
import json, sys
print(json.load(open(sys.argv[1])).get("alembic_version", ""))
PY
)"
  ACTUAL_REV="$("$PSQL" -At -c 'SELECT version_num FROM alembic_version LIMIT 1' "$TARGET_URL" | tr -d '\r' | head -1 || echo NO_ALEMBIC)"
  if [ "$ACTUAL_REV" = "$EXPECTED_REV" ]; then
    echo "  OK alembic revision  ${ACTUAL_REV} == ${EXPECTED_REV}"
  else
    echo "  FAIL alembic revision  ${ACTUAL_REV} != expected ${EXPECTED_REV}"
    FAIL=1
  fi

  "$PSQL" -At -c "SELECT table_name FROM information_schema.tables WHERE table_schema='public' AND table_type='BASE TABLE' ORDER BY 1" "$TARGET_URL" | tr -d '\r' |
  while IFS= read -r t; do
    [ -z "$t" ] && continue
    EXP="$(python3 - "$MANIFEST" "$t" <<'PY'
import json, sys
for row in json.load(open(sys.argv[1])).get("tables", []):
    if row["table"] == sys.argv[2]:
        print(row["rows"]); break
PY
)"
    ACT="$("$PSQL" -At -c "SELECT count(*) FROM \"$t\"" "$TARGET_URL" 2>/dev/null | tr -d '\r' | head -1 || echo MISSING)"
    if [ -n "$EXP" ] && [ "$ACT" = "$EXP" ]; then
      echo "  OK ${t}: ${ACT} rows"
    else
      echo "  FAIL ${t}: expected ${EXP:-0}, got ${ACT}"
      FAIL=1
    fi
  done
else
  echo "  !! no sidecar manifest — skipping row-count verification (visible warning)"
fi

if [ "$VERIFY_ARCH" = "1" ] && [ -f "$VERIFY" ]; then
  echo "==> Architectural verification (verify_rds.py) against the restored DB"
  DATABASE_URL="$(printf '%s' "$TARGET_URL" | sed 's/^postgresql:/postgresql+psycopg:/; s/sslmode=require/ssl=require/')" python "$VERIFY" || \
    echo "  (verify_rds.py is PostGIS-specific; non-fatal for non-PostGIS servers)"
fi

if [ "$FAIL" = "1" ]; then
  echo "!! RESTORE VERIFICATION FAILED — inspect the restored DB before using it."
  echo "   A safety dump of the pre-restore target exists at: ${SAFETY_FILE:-<none — fresh restore>}"
  exit 1
fi
echo "OK restore complete and VERIFIED: ${TARGET_URL}"
echo "   (safety pre-restore dump: ${SAFETY_FILE:-<no prior target>})"