#!/usr/bin/env bash
# dev.sh — Start the local backend for development.
# Cross-platform (macOS/Linux/WSL). Windows users: use scripts/dev/dev.ps1
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BACKEND="$ROOT/backend"
COMPOSE="$BACKEND/docker-compose.infra.yml"
PY="$BACKEND/.venv/bin/python"

if [ ! -x "$PY" ]; then
  echo "No venv yet — run scripts/dev/setup.sh first." >&2
  exit 1
fi

echo "== Starting infra (PostGIS + Redis)"
docker compose -f "$COMPOSE" up -d
sleep 3

echo "== Running migrations"
(cd "$BACKEND" && "$PY" -m alembic upgrade head)

echo "== Starting uvicorn (reload) on :8000"
echo "   API:   http://localhost:8000"
echo "   docs:  http://localhost:8000/docs"
echo "   ready: http://localhost:8000/ready"
echo "   Ctrl+C to stop."
(cd "$BACKEND" && "$PY" -m uvicorn app.main:app --reload --port 8000)
