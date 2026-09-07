#!/usr/bin/env sh
# Hyperlocal backend container entrypoint.
#
# Order of operations:
#   1. If USE_AWS_SECRETS=true, hydrate the environment from AWS Secrets
#      Manager BEFORE anything imports app settings (config is read at
#      import time). Values are exported into this shell, never painted to
#      stdout.
#   2. If RUN_MIGRATIONS=true, run `alembic upgrade head` (idempotent).
#   3. exec the real command (default CMD = uvicorn; override for
#      worker / beat / migrate-only tasks).
set -eu

export PYTHONDONTWRITEBYTECODE=1
export PYTHONUNBUFFERED=1

# 1. Optional: load secrets from AWS Secrets Manager (default credential chain / IAM role).
if [ "${USE_AWS_SECRETS:-false}" = "true" ]; then
  echo "[entrypoint] Hydrating environment from AWS Secrets Manager..."
  # `--export` prints shell-safe `export KEY='value'` lines (values not logged).
  secrets_env="$(python -m app.core.aws_secrets --export)"
  eval "${secrets_env}"
fi

# 2. Optional: run database migrations (idempotent).
if [ "${RUN_MIGRATIONS:-false}" = "true" ]; then
  echo "[entrypoint] Running database migrations (alembic upgrade head)..."
  alembic upgrade head
fi

# 3. exec the requested command (keeps PID 1 = app process for Docker stop).
echo "[entrypoint] Starting: $*"
exec "$@"