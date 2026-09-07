# dev.ps1 - Start the local backend for development.
#
#   * Ensures the PostGIS + Redis infra container stack is up
#   * Runs Alembic migrations (idempotent)
#   * Starts uvicorn with hot-reload on port 8000
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File scripts/dev/dev.ps1
$ErrorActionPreference = 'Stop'

$root    = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$backend = Join-Path $root 'backend'
$compose = Join-Path $backend 'docker-compose.infra.yml'
$py      = Join-Path $backend '.venv\Scripts\python.exe'

if (-not (Test-Path $py)) { Write-Host 'No venv yet - run scripts/dev/setup.ps1 first.' -ForegroundColor Yellow; exit 1 }

Write-Host "== Starting infra (PostGIS + Redis)" -ForegroundColor Cyan
docker compose -f $compose up -d
if ($LASTEXITCODE -ne 0) { Write-Host 'docker compose failed - is Docker Desktop running?' -ForegroundColor Red; exit 1 }
Start-Sleep -Seconds 3

Write-Host "== Running migrations" -ForegroundColor Cyan
Push-Location $backend
& $py -m alembic upgrade head
$code = $LASTEXITCODE
Pop-Location
if ($code -ne 0) { Write-Host 'Migration failed - is the DB healthy?' -ForegroundColor Red; exit 1 }

Write-Host "== Starting uvicorn (reload) on :8000" -ForegroundColor Green
Write-Host "   API:      http://localhost:8000"
Write-Host "   docs:     http://localhost:8000/docs"
Write-Host "   ready:    http://localhost:8000/ready"
Write-Host "   Ctrl+C to stop."
Push-Location $backend
& $py -m uvicorn app.main:app --reload --port 8000
