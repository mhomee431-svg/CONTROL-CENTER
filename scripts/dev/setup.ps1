# setup.ps1 - One-command, idempotent local backend setup (Phase 1).
#
#   * Creates a Python virtualenv and installs Backend/requirements.txt
#   * Bootstraps Backend/.env from .env.example (never overwrites existing)
#   * Starts the PostGIS + Redis infra stack (Docker required)
#   * Runs Alembic migrations to head
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File scripts/dev/setup.ps1
$ErrorActionPreference = 'Stop'

$root    = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$backend = Join-Path $root 'Backend'
$compose = Join-Path $backend 'docker-compose.infra.yml'

function Fail { param([string]$m) Write-Host "ERROR: $m" -ForegroundColor Red; exit 1 }

Write-Host "== [1/6] Python virtualenv ($backend\.venv)" -ForegroundColor Cyan
if (-not (Get-Command python -ErrorAction SilentlyContinue)) { Fail 'python not found on PATH' }
$venv = Join-Path $backend '.venv'
$py   = Join-Path $venv 'Scripts\python.exe'
if (-not (Test-Path $py)) {
    python -m venv $venv
    if (-not (Test-Path $py)) { Fail 'failed to create venv' }
}
Write-Host "  venv ready: $py"

Write-Host "== [2/6] Install backend dependencies" -ForegroundColor Cyan
& $py -m pip install --upgrade pip | Out-Null
& $py -m pip install -r (Join-Path $backend 'requirements.txt')
if ($LASTEXITCODE -ne 0) { Fail 'pip install failed' }

Write-Host "== [3/6] Ensure Backend/.env exists" -ForegroundColor Cyan
$envFile = Join-Path $backend '.env'
if (-not (Test-Path $envFile)) {
    Copy-Item (Join-Path $backend '.env.example') $envFile
    Write-Host "  created .env from .env.example"
} else {
    Write-Host "  .env already present (keeping it)"
}

Write-Host "== [4/6] Start PostGIS + Redis infra (Docker)" -ForegroundColor Cyan
if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    Fail 'docker not found. Install Docker Desktop (with WSL2 backend) and start it, then re-run.'
}
docker compose -f $compose up -d
if ($LASTEXITCODE -ne 0) { Fail 'docker compose up failed - is Docker Desktop running?' }
Write-Host "  infra stack requested. Check: docker compose -f $compose ps"
Write-Host "  waiting for db/redis to become healthy..."
Start-Sleep -Seconds 5
docker compose -f $compose ps

Write-Host "== [5/6] Run Alembic migrations (upgrade head)" -ForegroundColor Cyan
Push-Location $backend
& $py -m alembic upgrade head
$code = $LASTEXITCODE
Pop-Location
if ($code -ne 0) { Fail 'alembic upgrade head failed - is the DB healthy?' }

Write-Host "== [6/6] Setup complete" -ForegroundColor Green
Write-Host ""
Write-Host "Run the backend (terminal 1):"
Write-Host "    cd $backend"
Write-Host "    .\.venv\Scripts\Activate.ps1"
Write-Host "    uvicorn app.main:app --reload --port 8000"
Write-Host ""
Write-Host "Check readiness:  http://localhost:8000/ready   (should be ready)"
Write-Host "API docs:         http://localhost:8000/docs"
