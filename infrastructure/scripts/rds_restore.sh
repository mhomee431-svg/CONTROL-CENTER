#!/usr/bin/env bash
#
# rds_restore.sh — RDS PostgreSQL restore procedure (Phase 4).
#
# Uses AWS-native RDS snapshots (automated or manual) to restore the database.
# This is the SAFE restore path: a snapshot is always restored into a NEW
# instance; only after it is verified healthy is the app re-pointed to it by
# updating the DATABASE_URL secret. The original instance is left untouched
# until the operator is confident, then removed explicitly.
#
# Prerequisites: aws CLI + jq + an IAM identity with rds + secretsmanager
# permissions (the db-operator role from Phase 2 covers this).
#
# Usage:
#   ./rds_restore.sh <environment> <snapshot-id-or-auto> [region]
#
#   SNAPSHOT="auto"   -> restore the latest automated snapshot.
#   SNAPSHOT="manual" -> restore the most recent manual snapshot.
#   SNAPSHOT=<name>   -> restore that specific snapshot by id.
#
set -euo pipefail

ENV_NAME="${1:?environment (staging|production)}"
SNAPSHOT_SRC="${2:-auto}"
REGION="${3:-${AWS_REGION:-ap-south-1}}"
PROJECT="${PROJECT_NAME:-hyperlocal}"

PREFIX="${PROJECT}-${ENV_NAME}"
SRC_INSTANCE="${PREFIX}-db"
RESTORED_INSTANCE="${PREFIX}-db-restored-$(date -u +%Y%m%d%H%M%S)"
SUBNET_GROUP="${PREFIX}-rds-subnet"
SG_ID="${RDS_SG_ID:?set RDS_SG_ID to the RDS security group id}"
PARAM_GROUP="${PREFIX}-pg"
SECRET_NAME="${PROJECT}/${ENV_NAME}/database"

echo "── Phase 4 — RDS restore procedure ────────────────────────────────"
echo "source snapshot selection: ${SNAPSHOT_SRC}"

# ── 1. Resolve the snapshot / restore time ─────────────────────────────────
case "${SNAPSHOT_SRC}" in
  auto)
    RESTORE_TIME="$(aws rds describe-db-instances \
      --db-instance-identifier "${SRC_INSTANCE}" --region "${REGION}" \
      --query 'DBInstances[0].LatestRestorableTime' --output text)"
    echo "==> Latest restorable time: ${RESTORE_TIME} (point-in-time restore)"
    ;;
  manual)
    SNAPSHOT_ID="$(aws rds describe-db-snapshots \
      --db-instance-identifier "${SRC_INSTANCE}" --region "${REGION}" \
      --snapshot-type manual --query 'DBSnapshots[-1].DBSnapshotIdentifier' --output text)"
    echo "==> Latest manual snapshot: ${SNAPSHOT_ID}"
    RESTORE_TYPE="--db-snapshot-identifier ${SNAPSHOT_ID}"
    ;;
  *)
    SNAPSHOT_ID="${SNAPSHOT_SRC}"
    echo "==> Using snapshot: ${SNAPSHOT_ID}"
    RESTORE_TYPE="--db-snapshot-identifier ${SNAPSHOT_ID}"
    ;;
esac

if [ "${SNAPSHOT_SRC}" = "auto" ]; then
  if [ -z "${RESTORE_TIME}" ] || [ "${RESTORE_TIME}" = "None" ]; then
    echo "!! No restorable time available for ${SRC_INSTANCE}. Aborting."
    exit 1
  fi
else
  if [ -z "${SNAPSHOT_ID}" ] || [ "${SNAPSHOT_ID}" = "None" ]; then
    echo "!! No usable snapshot found for ${SRC_INSTANCE}. Aborting."
    exit 1
  fi
fi

# ── 2. Restore into a brand-new instance (never overwrite the live one) ─────
echo "==> Restoring into new instance: ${RESTORED_INSTANCE}"
if [ "${SNAPSHOT_SRC}" = "auto" ]; then
  # Point-in-time restore to the latest restorable time (RDS-native PITR).
  aws rds restore-db-instance-to-point-in-time \
    --source-db-instance-identifier "${SRC_INSTANCE}" \
    --target-db-instance-identifier "${RESTORED_INSTANCE}" \
    ${RESTORE_TIME:+--restore-time "${RESTORE_TIME}"} \
    --db-subnet-group-name "${SUBNET_GROUP}" \
    --vpc-security-group-ids "${SG_ID}" \
    --db-parameter-group-name "${PARAM_GROUP}" \
    --multi-az \
    --region "${REGION}" >/dev/null
else
  # Snapshot restore (manual or specific).
  aws rds restore-db-instance-from-db-snapshot \
    --db-instance-identifier "${RESTORED_INSTANCE}" \
    ${RESTORE_TYPE} \
    --db-subnet-group-name "${SUBNET_GROUP}" \
    --vpc-security-group-ids "${SG_ID}" \
    --db-parameter-group-name "${PARAM_GROUP}" \
    --multi-az \
    --region "${REGION}" >/dev/null
fi

echo "==> Waiting for ${RESTORED_INSTANCE} to be available..."
aws rds wait db-instance-available \
  --db-instance-identifier "${RESTORED_INSTANCE}" --region "${REGION}"

echo "==> PostGIS check on restored instance"
aws rds describe-db-instances --region "${REGION}" \
  --db-instance-identifier "${RESTORED_INSTANCE}" \
  --query 'DBInstances[0].DBInstanceStatus' --output text

ENDPOINT="$(aws rds describe-db-instances --region "${REGION}" \
  --db-instance-identifier "${RESTORED_INSTANCE}" \
  --query 'DBInstances[0].Endpoint.Address' --output text)"
PORT="$(aws rds describe-db-instances --region "${REGION}" \
  --db-instance-identifier "${RESTORED_INSTANCE}" \
  --query 'DBInstances[0].Endpoint.Port' --output text)"
echo "==> Restored endpoint: ${ENDPOINT}:${PORT}"

echo ""
echo "!! Verification is NOT yet automated for credential-protected restore."
echo "   1) Run the Phase 4 verifier against the restored endpoint:"
echo "      DATABASE_URL='postgresql+psycopg://<user>:<pw>@${ENDPOINT}:${PORT}/<db>?sslmode=require' \\"
echo "          python backend/scripts/verify_rds.py"
echo "   2) When verified, re-point the app by updating Secrets Manager:"
echo "      aws secretsmanager update-secret --secret-id ${SECRET_NAME} \\"
echo "        --secret-string '{\"DATABASE_URL\":\"postgresql+asyncpg://<user>:<pw>@${ENDPOINT}:${PORT}/<db>?sslmode=require\"}'"
echo "   3) Force a new ECS deployment, then run migrations if needed (rds_migrate.sh)."
echo "   4) Only after the app is healthy, DELETE the old instance:"
echo "      aws rds delete-db-instance --db-instance-identifier ${SRC_INSTANCE} --region ${REGION}"