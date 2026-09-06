#!/usr/bin/env bash
# infra/scripts/cicd_smoke_test.sh — post-deploy smoke battery for the CI/CD pipeline.
#
# Exercises a deployed environment over HTTPS:
#   1. GET /health     → 200, status=healthy, environment matches --expect-env
#   2. GET /ready      → 200, OR 503 that still reports database+redis+postgis true
#                        (queue/storage may be offline in a minimal environment)
#   3. GET /openapi.json → 200 (the API actually serves its contract)
#   4. OPTIONAL deployment identity: --sha <short-sha> verifies
#      /health deployment.commit equals it (when not "unknown")
#   5. OPTIONAL on-host status: --ssm-instance-tag + --region run the
#      deploy_backend.sh status battery and compare git HEAD to --sha
#
# Usage:
#   ./cicd_smoke_test.sh --url https://api.staging.hyperlocal.in \
#       --expect-env staging [--sha abc1234] \
#       [--ssm-instance-tag hyperlocal-staging-app --region ap-south-1]
#
# Requirements: curl + jq. Exits non-zero on the first failing check.
set -euo pipefail

URL=""
EXPECT_ENV=""
SHA=""
SSM_TAG=""
REGION=""
ROOT_WAIT="${ROOT_WAIT:-300}"  # seconds to wait for the host to become reachable

while [ $# -gt 0 ]; do
  case "$1" in
    --url)            URL="${2:?url missing}"; shift 2 ;;
    --expect-env)     EXPECT_ENV="${2:-}"; shift 2 ;;
    --sha)            SHA="${2:-}"; shift 2 ;;
    --ssm-instance-tag) SSM_INSTANCE_TAG="${2:-}"; shift 2 ;;
    --region)         REGION="${2:-}"; shift 2 ;;
    --wait)           ROOT_WAIT="${2:-300}"; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

[ -n "$URL" ] || { echo "ERR: --url is required" >&2; exit 2; }
URL="${URL%/}"
command -v curl >/dev/null 2>&1 || { echo "ERR: curl not installed" >&2; exit 2; }
command -v jq  >/dev/null 2>&1 || { echo "ERR: jq not installed" >&2; exit 2; }

pass() { printf '\033[1;32m  ✔ %s\033[0m\n' "$*"; }
fail() { printf '\033[1;31m  ✘ %s\033[0m\n' "$*" >&2; exit 1; }

# ── 0. wait until the host answers at all ─────────────────────────────────────
echo "▶ smoke testing ${URL} (up to $((ROOT_WAIT / 60))m)"
deadline=$(( $(date +%s) + ROOT_WAIT ))
until curl -fsS --max-time 10 "${URL}/health" -o /dev/null 2>/dev/null; do
  if [ "$(date +%s)" -ge "$deadline" ]; then
    fail "/health never became reachable within ${ROOT_WAIT}s"
  fi
  sleep 5
done

# --- 2. /health -----------------------------------------------------------------
HEALTH="$(curl -fsS --max-time 15 "${URL}/health" || fail "/health returned non-200")"
echo "  /health → $(printf '%s' "$HEALTH" | jq -c .)"
[ "$(printf '%s' "$HEALTH" | jq -r '.status')" = "healthy" ] || fail "health.status != healthy"
if [ -n "$EXPECT_ENV" ]; then
  [ "$(printf '%s' "$HEALTH" | jq -r '.environment')" = "$EXPECT_ENV" ] \
    || fail "health.environment != ${EXPECT_ENV}"
fi
if [ -n "$SHA" ]; then
  COMMIT="$(printf '%s' "$HEALTH" | jq -r '.deployment.commit // ""')"
  if [ -n "$COMMIT" ] && [ "$COMMIT" != "unknown" ] && [ "$COMMIT" != "$SHA" ]; then
    fail "deployment.commit ${COMMIT} != expected ${SHA}"
  fi
fi
pass "/health OK"

# ── 3. /ready (critical components only) ─────────────────────────────────────
READY_BODY="$(curl -sS --max-time 15 -w '\n%{http_code}' "${URL}/ready" || true)"
READY_CODE="$(printf '%s' "$READY_BODY" | tail -1)"
READY_JSON="$(printf '%s' "$READY_BODY" | sed '$d')"
printf '  /ready [HTTP %s]\n' "$READY_CODE"
if [ "$(printf '%s' "$READY_JSON" | jq -r '.checks.database')" != "true" ] ||
   [ "$(printf '%s' "$READY_JSON" | jq -r '.checks.redis')" != "true" ] ||
   [ "$(printf '%s' "$READY_JSON" | jq -r '.checks.postgis')" != "true" ]; then
  printf '%s\n' "$READY_JSON" | jq . >&2
  fail "database/redis/postgis not all ready"
fi
[ "$READY_CODE" = "200" ] || echo "  (note: /ready returned $READY_CODE — queue/storage component not ready; critical components are)"
pass "/ready critical components OK"

# ── 4. openapi contract ───────────────────────────────────────────────────────
curl -fsS --max-time 15 "${URL}/openapi.json" | jq -e '.openapi' >/dev/null 2>&1 \
  || fail "/openapi.json missing or invalid"
pass "/openapi.json served"

# ── 5. on-server deploy status (git HEAD == --sha) ──────────────────────────
if [ -n "$SSM_INSTANCE_TAG" ] && [ -n "$SHA" ]; then
  [ -n "$REGION" ] || { echo "ERR: --region required with --ssm-instance-tag" >&2; exit 2; }
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  OUTPUT="$("${SCRIPT_DIR}/aws_run_command.sh" \
    --instance-tag "$SSM_INSTANCE_TAG" --region "$REGION" \
    --command "cd /opt/hyperlocal && git rev-parse HEAD" \
    --comment "cicd-smoke-test sha check")"
  HEAD_SHA="$(printf '%s\n' "$OUTPUT" | tail -1)"
  # Compare a 12-char prefix: github.sha is the full 40-hex commit id.
  [ "${HEAD_SHA:0:12}" = "${SHA:0:12}" ] || fail "server git HEAD ${HEAD_SHA:-?} != expected ${SHA}"
  pass "server checkout at ${HEAD_SHA}"
fi

echo "✅ smoke test passed"
exit 0