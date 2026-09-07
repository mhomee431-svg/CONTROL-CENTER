#!/usr/bin/env bash
#
# Zero-downtime ECS service deployment for a shipped container image.
# Usage (aws CLI + jq pre-installed):
#   ./ecs_deploy.sh <service> <task-family> <container-name> <image> <region> [cluster]
#
#   e.g. ./ecs_deploy.sh hyperlocal-production-web hyperlocal-production-web api \
#           123456789012.dkr.ecr.us-east-1.amazonaws.com/hyperlocal-backend:abc123 \
#           us-east-1
#   CLUSTER default: env ECS_CLUSTER_NAME or "hyperlocal-cluster"

set -euo pipefail

SERVICE="${1:?service}"
FAMILY="${2:?task family}"
CONTAINER="${3:?container name}"
IMAGE="${4:?image}"
REGION="${5:?region}"
CLUSTER="${CLUSTER:-${ECS_CLUSTER_NAME:-hyperlocal-cluster}}"

echo "▶ Deploying ${CONTAINER}:${IMAGE} to service ${SERVICE}"

TASK_JSON="$(aws ecs describe-task-definition --task-definition "${FAMILY}" --region "${REGION}")"

NEW_TASK="$(printf '%s' "${TASK_JSON}" \
  | jq '.taskDefinition | { family, taskRoleArn, executionRoleArn, networkMode, containerDefinitions, requiresCompatibilities, cpu, memory, volumes }' \
  | jq --arg img "${IMAGE}" --arg c "${CONTAINER}" \
        '.containerDefinitions |= map(if .name == $c then .image = $img else . end)')"

REVISION="$(printf '%s' "${NEW_TASK}" | jq -c . | \
  aws ecs register-task-definition --region "${REGION}" --cli-input-json "$(cat)" | jq -r '.taskDefinition.revision')"

echo "▶ Registered ${FAMILY}:${REVISION}; updating service"
aws ecs update-service \
  --cluster "${CLUSTER}" \
  --service "${SERVICE}" \
  --task-definition "${FAMILY}:${REVISION}" \
  --force-new-deployment \
  --region "${REGION}" >/dev/null

echo "✅ ${SERVICE} is rolling to revision ${REVISION}"