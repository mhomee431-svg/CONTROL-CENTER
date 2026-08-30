#!/usr/bin/env bash
# ── Hyperlocal backend — deploy / rollback / verify (runs ON the app EC2) ───
#
# Phase 11 deployment tooling for the free-tier single-instance architecture:
# the server checkout is a pure deployment artifact (no local edits), so
# deploys are `git reset --hard <ref>` + `docker compose build/up`, guarded by
# a /ready health poll with AUTOMATIC ROLLBACK to the last known-good commit.
#
# Usage (from /opt/hyperlocal or with APP_DIR set):
#   ./infra/scripts/deploy_backend.sh deploy [git-ref]   # default: origin/main
#   ./infra/scripts/deploy_backend.sh rollback           # → last good commit
#   ./infra/scripts/deploy_backend.sh verify             # full health battery
#   ./infra/scripts/deploy_backend.sh status             # sha + container states
#
# Env overrides: APP_DIR, COMPOSE_FILE (default docker-compose.cloud.yml),
# WAIT_SECONDS (default 180).
set -euo pipefail

APP_DIR="${APP_DIR:-/opt/hyperlocal}"
COMPOSE_FILE="${COMPOSE_FILE:-docker-compose.cloud.yml}"
READY_URL="${READY_URL:-http://127.0.0.1:8000/ready}"
HEALTH_URL="${HEALTH_URL:-http://127.0.0.1:8000/health}"
WAIT_SECONDS="${WAIT_SECONDS:-180}"
STATE_FILE="${APP_DIR}/.deploy_state" # LAST_GOOD_SHA=<sha-before-deploy>

log()  { printf '\033[1;34m[deploy]\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31m[deploy] ERROR:\033[0m %s\n' "$*" >&2; exit 1; }

cd "$APP_DIR" || fail "APP_DIR ${APP_DIR} not found"
[ -f "Backend/${COMPOSE_FILE}" ] || fail "Backend/${COMPOSE_FILE} missing"

compose()      { docker compose -f "Backend/${COMPOSE_FILE}" "$@"; }
current_sha()  { git rev-parse HEAD; }
last_good_sha() {
  [ -f "$STATE_FILE" ] && awk -F= '$1=="LAST_GOOD_SHA"{print $2}' "$STATE_FILE"
}

# Poll /ready (checks DB + Redis + PostGIS) until healthy or timeout.
wait_ready() {
  local deadline=$(( $(date +%s) + WAIT_SECONDS ))
  while [ "$(date +%s)" -lt "$deadline" ]; do
    if curl -fsS --max-time 5 "$READY_URL" >/dev/null 2>&1; then
      log "ready: OK ($(curl -fsS --max-time 5 "$READY_URL"))"
      return 0
    fi
    sleep 5
  done
  log "ready: FAILED after ${WAIT_SECONDS}s (last migrate logs:)"
  compose logs --tail 20 migrate || true
  return 1
}

cmd_deploy() {
  local target="${1:-origin/main}"
  local previous
  previous="$(current_sha)"

  log "deploying ${target} (current: $(current_sha))"
  git fetch --quiet origin
  git reset --hard "$target" >/dev/null

  # Record the pre-deploy commit BEFORE anything changes so a failed
  # health check (or a later `rollback`) can return here.
  echo "LAST_GOOD_SHA=${previous}" > "$STATE_FILE"
  [ "$previous" != "$(current_sha)" ] || log "note: commit unchanged, rebuilding anyway"

  log "building images..."
  compose build

  log "starting stack (one-shot migrate runs first)..."
  compose up -d

  if wait_ready; then
    log "✅ deployed $(current_sha)"
  else
    log "❌ health check failed — rolling back to ${previous}"
    cmd_rollback
    exit 1
  fi
}

cmd_rollback() {
  local target
  target="$(last_good_sha)"
  [ -n "$target" ] || fail "no LAST_GOOD_SHA recorded in ${STATE_FILE}"
  [ "$target" != "$(current_sha)" ] || fail "already at last-good ${target}"

  log "rolling back: $(current_sha) → ${target}"
  git reset --hard "$target" >/dev/null
  compose build
  compose up -d
  wait_ready || fail "rollback health check ALSO failed — inspect: journalctl -t hyperlocal-boot; compose logs api"
  log "✅ rolled back to ${target}"
}

cmd_status() {
  echo "deployed commit : $(current_sha)"
  echo "last good commit: $(last_good_sha || echo none)"
  compose ps
}

cmd_verify() {
  log "1/6 containers:";        compose ps
  log "2/6 liveness /health:";  curl -fsS --max-time 5 "$HEALTH_URL"; echo
  log "3/6 readiness /ready:";  curl -fsS --max-time 5 "$READY_URL"; echo
  log "4/6 redis:";             compose exec -T redis redis-cli ping
  log "5/6 applied migration:"; compose run --rm migrate alembic current | tail -2 || true
  log "6/6 api log tail:";      compose logs --tail 3 api | tail -3 || true
  log "✅ verify complete"
}

case "${1:-}" in
  deploy)   shift; cmd_deploy "$@" ;;
  rollback) cmd_rollback ;;
  status)   cmd_status ;;
  verify)   cmd_verify ;;
  *) sed -n '2,20p' "$0"; exit 2 ;;
esac
