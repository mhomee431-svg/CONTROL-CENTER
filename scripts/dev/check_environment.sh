#!/usr/bin/env bash
# check_environment.sh — Verify the local toolchain against Phase-1 requirements.
# Cross-platform (macOS/Linux/WSL). Windows users: use scripts/dev/check_environment.ps1
echo "== Phase 1 — Local Development Environment =="
check() { # name required ...args
  local name="$1" required="$2"; shift 2
  if command -v "$name" >/dev/null 2>&1; then
    local v; v="$($name "$@" 2>&1 | head -n1)"
    echo "  [OK]      $name  $v   (required: $required)"
  else
    echo "  [MISSING] $name   (required: $required)"
  fi
}

check docker    '^20+ (Desktop)'   --version
check python    '3.14'             --version
check node      '^16+'             --version
check git       '^2+'              --version
check flutter   '3.x stable'       --version
check dart      '3.x'              --version
check redis-cli '7+ (in container)' --version
check psql      '16 (optional)'    --version
echo ""
echo "Done. See backend/docs/PHASE1_LOCAL_DEVELOPMENT.md for next steps."
