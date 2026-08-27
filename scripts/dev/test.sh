#!/usr/bin/env bash
# test.sh — Run the backend pytest suite.
# Usage: scripts/dev/test.sh [optional -k filter]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BACKEND="$ROOT/Backend"
PY="$BACKEND/.venv/bin/python"

if [ ! -x "$PY" ]; then
  echo "No venv yet — run scripts/dev/setup.sh first." >&2
  exit 1
fi

(cd "$BACKEND" && "$PY" -m pytest -q "$@")
