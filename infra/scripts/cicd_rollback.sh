#!/usr/bin/env bash
# infra/scripts/cicd_rollback.sh — CI/CD rollback orchestrator (Phase 25).
#
# Triggered automatically by the pipeline when a staging/production deploy or
# its health verification fails, and available for manual use. Wraps the three
# existing rollback layers:
#
#   Layer 1 — application rollback (the live default):
#     compose target → `deploy_backend.sh rollback` on the instance, which
#     returns the checkout + stack to LAST_GOOD_SHA (recorded before every
#     deploy). The same script ALREADY auto-rolls-back on a failed /ready poll.
#     ECS  target   → re-point the service task definition to a previous image
#     (--image), i.e. re-run the image you were on before the bad deploy.
#   Layer 2 — database schema downgrade (schema-only, data preserved):
#     ./infra/scripts/rds_migrate_rollback.sh --steps N   (on a machine with the
#     backend venv + DATABASE_URL). Guarded: refuses at revision 0001 and when
#     RDS automated backups are off.
#   Layer 3 — full data restore:
#     ./infra/scripts/restore_db.sh / rds_restore.sh (Phase 5 logical backup /
#     RDS snapshot-PITR restore).
#
# Usage:
#   # compose target (default; run from CI runner — it calls SSM Run Command):
#   ./cicd_rollback.sh --target compose --instance-tag hyperlocal-production-app \
#       --region ap-south-1 [--app-dir /opt/hyperlocal]
#   # ECS target (run from CI runner with AWS creds):
#   ./cicd_rollback.sh --target ecs --cluster <c> --service <s> --family <f> \
#       --container api --image <previous-image-tag> --region <r>
#   # …or just print which manual database steps to run next:
#   ./cicd_rollback.sh --dry-run
set -euo pipefail

TARGET=""
REGION=""
APP_DIR="/opt/hyperlocal"
INSTANCE_TAG=""
SERVICE=""
FAMILY=""
CONTAINER=""
IMAGE=""
CLUSTER="${ECS_CLUSTER_NAME:-hyperlocal-cluster}"
DRY_RUN=0

while [ $# -gt 0 ]; do
  case "$1" in
    --target)   TARGET="${2:?target (compose|ecs) missing}"; shift 2 ;;
    --region)   REGION="${2:?region missing}"; shift 2 ;;
    --app-dir)  APP_DIR="${2:-/opt/hyperlocal}"; shift 2 ;;
    --instance-tag) INSTANCE_TAG="${2:-}"; shift 2 ;;
    --service)  SERVICE="${2:-}"; shift 2 ;;
    --family)   FAMILY="${2:-}"; shift 2 ;;
    --container) CONTAINER="${2:-}"; shift 2 ;;
    --image)    IMAGE="${2:-}"; shift 2 ;;
    --cluster)  CLUSTER="${2:-}"; shift 2 ;;
    --dry-run)  DRY_RUN=1; shift ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

log()  { printf '\033[1;34m[cicd-rollback]\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31m[cicd-rollback] ERROR:\033[0m %s\n' "$*" >&2; exit 1; }

if [ "$DRY_RUN" = "1" ]; then
  cat <<'EOF'
Dry-run: what the automatic rollback would do:
  1. compose target: SSM Run Command → deploy_backend.sh rollback on the
     instance. It git-resets to LAST_GOOD_SHA (recorded pre-deploy), rebuilds,
     `compose up -d`, and only returns success if /ready is healthy again.
  2. If the schema changed in the failed release, review whether the DB
     migration already ran: rds_migrate_rollback.sh --steps N (Layer 2).
  3. If data integrity is in question, restore from Phase 5 backups:
     infra/scripts/restore_db.sh <env> <backup> --replace --verify-architecture
     (Layer 3).
EOF
  exit 0
fi

[ "$TARGET" = "compose" ] || [ "$TARGET" = "ecs" ] || fail "--target must be compose|ecs"
[ -n "$REGION" ] || fail "--region is required"

case "$TARGET" in
  compose)
    [ -n "$INSTANCE_TAG" ] || INSTANCE_TAG="${CI_INSTANCE_TAG:-hyperlocal-production-app}"
    log "rolling back compose target ${INSTANCE_TAG} (${REGION})"
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    # deploy_backend.sh already auto-rolls-back on health failure; running
    # `rollback` again is idempotent and surfaces the last-good sha/state.
    "${SCRIPT_DIR}/aws_run_command.sh" \
      --instance-tag "$INSTANCE_TAG" --region "$REGION" \
      --command "cd ${APP_DIR} && ./infra/scripts/deploy_backend.sh rollback 2>&1 || { ./infra/scripts/deploy_backend.sh status; exit 1; }" \
      --comment "cicd-automatic-rollback"
    ;;
  ecs)
    [ -n "$SERVICE" ] && [ -n "$IMAGE" ] || fail "ecs rollback requires --service, --family, --container, --image"
    log "rolling ECS service ${SERVICE} back to ${IMAGE}"
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    "${SCRIPT_DIR}/ecs_deploy.sh" "$SERVICE" "$FAMILY" "$CONTAINER" "$IMAGE" "$REGION" "$CLUSTER"
    ;;
esac

cat <<'EOF'

Reminder — database layer (only if the failed release applied a migration):
  DATABASE_URL='...' ./infra/scripts/rds_migrate_rollback.sh --steps 1
Recovery from full data backup (Layer 3):
  ./infra/scripts/restore_db.sh <env> <backup> --target "<DATABASE_URL>" \
      --replace --verify-architecture
EOF
log "✅ rollback complete"