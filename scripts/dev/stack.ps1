# scripts/dev/stack.ps1
# ---------------------------------------------------------------------------
# One-command local FULL-STACK manager (mirrors the AWS topology in containers:
# PostGIS + Redis + API + Celery worker + Celery beat + one-shot migrations).
#
# Usage (from repo root):
#   powershell -ExecutionPolicy Bypass -File scripts/dev/stack.ps1 up      # build + start + wait healthy + self-test
#   powershell -ExecutionPolicy Bypass -File scripts/dev/stack.ps1 status  # container table with health
#   powershell -ExecutionPolicy Bypass -File scripts/dev/stack.ps1 test    # hit /health and /ready
#   powershell -ExecutionPolicy Bypass -File scripts/dev/stack.ps1 logs    # tail all logs (Ctrl+C to exit)
#   powershell -ExecutionPolicy Bypass -File scripts/dev/stack.ps1 down    # stop + remove containers
#
# For NATIVE hot-reload development instead use scripts/dev/dev.ps1 (infra-only
# compose + local uvicorn). Do not run both stacks simultaneously - they share
# host ports 5432/6379.
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('up', 'down', 'status', 'test', 'logs', 'restart')]
    [string]$Action = 'up'
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$composeFile = Join-Path $repo 'Backend\docker-compose.yml'

function Invoke-Compose {
    param([string[]]$ComposeArgs)
    & docker compose -f $composeFile @ComposeArgs
    if ($LASTEXITCODE -ne 0) {
        throw ("docker compose failed: " + ($ComposeArgs -join ' '))
    }
}

function Test-Stack {
    foreach ($endpoint in @('/health', '/ready')) {
        $url = "http://localhost:8000$endpoint"
        try {
            $resp = Invoke-RestMethod -Uri $url -TimeoutSec 10
            $body = $resp | ConvertTo-Json -Compress -Depth 4
            Write-Host "[OK]   GET $endpoint -> $body" -ForegroundColor Green
            if ($endpoint -eq '/ready' -and $resp.status -eq 'degraded') {
                Write-Host "       /ready reports degraded - check db/postgis/redis components above" -ForegroundColor Yellow
            }
        }
        catch {
            Write-Host "[FAIL] GET $endpoint -> $($_.Exception.Message)" -ForegroundColor Red
            Write-Host "       Hint: run scripts/dev/stack.ps1 logs" -ForegroundColor Yellow
            exit 1
        }
    }
}

# 0. Preflight - fail fast with an actionable message when Docker is missing.
$dockerCmd = Get-Command docker -ErrorAction SilentlyContinue
if (-not $dockerCmd) {
    Write-Host "[X] Docker Desktop is NOT installed." -ForegroundColor Red
    Write-Host "    Install it once (free):  winget install -e --id Docker.DockerDesktop"
    Write-Host "    Then start Docker Desktop from the Start Menu and re-run this script."
    exit 1
}
docker info *> $null
if ($LASTEXITCODE -ne 0) {
    Write-Host "[X] Docker daemon is not running. Start Docker Desktop first." -ForegroundColor Red
    exit 1
}

switch ($Action) {

    'up' {
        Write-Host "== Building and starting full stack (db, redis, migrate, api, worker, beat)" -ForegroundColor Cyan
        Invoke-Compose @('up', '-d', '--build')

        Write-Host "== Waiting for API container to become healthy..." -ForegroundColor Cyan
        $deadline = (Get-Date).AddMinutes(5)
        while ((Get-Date) -lt $deadline) {
            $raw = docker inspect --format '{{json .State.Health.Status}}' hyperlocal-backend-api-1 2> $null
            $status = 'missing'
            if ($raw) { $status = ($raw -join '').Trim('"') }
            if ($status -eq 'healthy') { break }
            Write-Host "   api health: $status" -ForegroundColor DarkGray
            Start-Sleep -Seconds 5
        }

        Write-Host "== Running self-test" -ForegroundColor Cyan
        Test-Stack
        Write-Host ""
        Write-Host "   API:   http://localhost:8000" -ForegroundColor Green
        Write-Host "   docs:  http://localhost:8000/docs" -ForegroundColor Green
        Write-Host "   logs:  scripts/dev/stack.ps1 logs" -ForegroundColor Green
    }

    'down'    { Invoke-Compose @('down') }
    'restart' { Invoke-Compose @('restart') }
    'logs'    { Invoke-Compose @('logs', '-f', '--tail=100') }
    'status'  { Invoke-Compose @('ps') }
    'test'    { Test-Stack }
}