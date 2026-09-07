#!/usr/bin/env bash
# infrastructure/scripts/aws_run_command.sh — SSM Run Command helper for the CI/CD pipeline.
#
# Runs a shell command on an EC2 instance WITHOUT any SSH port (the free-tier
# stack's shell is SSM-only) and streams the invocation output back. Exits
# non-zero when the command fails, times out, or is cancelled — so a deploy
# script failure fails the GitHub Actions job that called it.
#
# Usage:
#   ./aws_run_command.sh \
#     --instance-tag hyperlocal-production-app \
#     --region ap-south-1 \
#     --command "cd /opt/hyperlocal && ./infrastructure/scripts/deploy_backend.sh deploy <sha> 2>&1" \
#     [--timeout 900] [--document AWS-RunShellScript] [--comment "deploy <sha>"]
#
#   # …or target a concrete instance id instead of a Name tag:
#   ./aws_run_command.sh --instance-id i-0123456789abcdef0 --region ap-south-1 --command "..."
#
# Requirements: aws CLI (with ssm:SendCommand + ssm:GetCommandInvocation,
# ec2:DescribeInstances for tag lookup) and jq on the invoking machine.
set -euo pipefail

REGION=""
INSTANCE_TAG=""
INSTANCE_ID=""
COMMAND=""
DOCUMENT="AWS-RunShellScript"
TIMEOUT="900"
COMMENT="hyperlocal-ci-script"

while [ $# -gt 0 ]; do
  case "$1" in
    --region)        REGION="${2:?region missing}"; shift 2 ;;
    --instance-tag)  INSTANCE_TAG="${2:?instance-tag missing}"; shift 2 ;;
    --instance-id)   INSTANCE_ID="${2:?instance-id missing}"; shift 2 ;;
    --command)       COMMAND="${2:?command missing}"; shift 2 ;;
    --document)      DOCUMENT="${2:-AWS-RunShellScript}"; shift 2 ;;
    --timeout)       TIMEOUT="${2:-900}"; shift 2 ;;
    --comment)       COMMENT="${2:-hyperlocal-ci-script}"; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

[ -n "$COMMAND" ] || { echo "ERR: --command is required" >&2; exit 2; }
[ -n "$REGION" ] || { echo "ERR: --region is required" >&2; exit 2; }
command -v aws >/dev/null 2>&1 || { echo "ERR: aws CLI not installed" >&2; exit 2; }
command -v jq  >/dev/null 2>&1 || { echo "ERR: jq not installed" >&2; exit 2; }

# ── 1. Resolve the target instance (tag → id) ───────────────────────────────
if [ -z "$INSTANCE_ID" ]; then
  [ -n "$INSTANCE_TAG" ] || { echo "ERR: --instance-id or --instance-tag is required" >&2; exit 2; }
  echo "▶ resolving instance with Name=${INSTANCE_TAG} …"
  INSTANCE_ID="$(aws ec2 describe-instances \
    --region "$REGION" \
    --filters "Name=tag:Name,Values=${INSTANCE_TAG}" "Name=instance-state-name,Values=running" \
    --query 'Reservations[].Instances[].[InstanceId,LaunchTime]' \
    --output text | sort -k2 -r | head -1 | awk '{print $1}')"
  [ -n "$INSTANCE_ID" ] || { echo "ERR: no running instance named ${INSTANCE_TAG} in ${REGION}" >&2; exit 3; }
  echo "  → ${INSTANCE_ID}"
fi

# ── 2. Send the command ─────────────────────────────────────────────────────
PARAMS="$(jq -n --arg c "$COMMAND" --argjson t "$TIMEOUT" '{commands:[$c], timeoutSeconds:[$t]}')"
SEND="$(aws ssm send-command \
  --region "$REGION" \
  --instance-ids "$INSTANCE_ID" \
  --document-name "$DOCUMENT" \
  --comment "$COMMENT" \
  --parameters "$PARAMS" \
  --timeout-seconds "$TIMEOUT")"

CMD_ID="$(printf '%s' "$SEND" | jq -r '.Command.CommandId')"
echo "▶ sent command ${CMD_ID} → ${INSTANCE_ID} (timeout ${TIMEOUT}s)"

# ── 3. Poll the invocation until a terminal state ───────────────────────────
START="$(date +%s)"
DEADLINE=$(( START + TIMEOUT + 120 ))
STATUS="Pending"
while [ "$STATUS" = "Pending" ] || [ "$STATUS" = "InProgress" ] || [ "$STATUS" = "Delayed" ]; do
  NOW="$(date +%s)"
  if [ "$NOW" -ge "$DEADLINE" ]; then
    echo "!! timed out waiting for invocation ${CMD_ID}" >&2
    exit 4
  fi
  INV="$(aws ssm get-command-invocation \
    --region "$REGION" --command-id "$CMD_ID" --instance-id "$INSTANCE_ID" 2>/dev/null || true)"
  STATUS="$(printf '%s' "$INV" | jq -r '.Status // "Unknown"')"
  if [ "$STATUS" = "Unknown" ]; then
    sleep 5          # invocation not registered yet
  else
    sleep 10
  fi
done

# ── 4. Surface the output ───────────────────────────────────────────────────
printf '%s' "$INV" | jq -r '.StandardOutputContent // ""'
ERR_OUT="$(printf '%s' "$INV" | jq -r '.StandardErrorContent // ""')"
if [ -n "$ERR_OUT" ]; then
  echo "── stderr ──" >&2
  printf '%s\n' "$ERR_OUT" >&2
fi

echo "── status: ${STATUS} (response code: $(printf '%s' "$INV" | jq -r '.ResponseCode // "n/a"')) ──"
case "$STATUS" in
  Success)   exit 0 ;;
  TimedOut)  echo "!! SSM command timed out (invocation = TimedOut)" >&2; exit 4 ;;
  Cancelled) echo "!! SSM command was cancelled" >&2; exit 5 ;;
  Failed)    echo "!! SSM command failed on the instance" >&2; exit 1 ;;
  *)         echo "!! unexpected invocation status: ${STATUS}" >&2; exit 1 ;;
esac