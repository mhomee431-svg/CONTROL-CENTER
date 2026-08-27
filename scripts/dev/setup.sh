#!/usr/bin/env bash
# setup.sh — One-command, idempotent local backend setup (Phase 1).
# Cross-platform (macOS/Linux/WSL). Windows users: use scripts/dev/setup.ps1.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BACKEND="$ROOT/Backend"
COMPOSE="$BACKEND/docker-compose.infra.yml"
PY="$BACKEND/.venv/bin/python"

echo "== [1/6] Python virtualenv ($BACKEND/.venv)"
if [ ! -x "$PY" ]; then
  python3 -m venv "$BACKEND/.venv"
fi

echo "== [2/6] Install backend dependencies"
"$PY" -m pip install --upgrade pip >/dev/null
"$PY" -m pip install -r "$BACKEND/requirements.txt"

echo "== [3/6] Ensure Backend/.env exists"
if [ ! -f "$BACKEND/.env" ]; then
  cp "$BACKEND/.env.example" "$BACKEND/.env"
  echo "  created .env from .env.example"
else
  echo "  .env already present (keeping it)"
fi

echo "== [4/6] Start PostGIS + Redis infra (Docker)"
if ! command -v docker >/dev/null 2>&1; then
  echo "ERROR: docker not found. Install Docker Desktop and re-run." >&2
  exit 1
fi
docker compose -f "$COMPOSE" up -d
sleep 5
docker compose -f "$COMPOSE" ps

echo "== [5/6] Run Alembic migrations (upgrade head)"
(cd "$BACKEND" && "$PY" -m alembic upgrade head)

echo "== [6/6] Setup complete"
echo
echo "Run the backend (terminal 1):"
echo "    cd $BACKEND"
echo "    source .venv/bin/activate"
echo "    uvicorn app.main:app --reload --port 8000"
echo
echo "Check readiness:  http://localhost:8000/ready"
echo "API docs:         http://localhost:8000/docs"
