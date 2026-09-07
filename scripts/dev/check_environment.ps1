# check_environment.ps1 - Verify the local toolchain against Phase-1 requirements.
#
# Usage:  powershell -ExecutionPolicy Bypass -File scripts/dev/check_environment.ps1
$ErrorActionPreference = 'Continue'

function Test-Cmd {
    param([string]$Name, [string[]]$VersionArgs, [string]$Required)
    $cmd = Get-Command $Name -ErrorAction SilentlyContinue
    if (-not $cmd) {
        Write-Host ("  [MISSING] {0}  (required: {1})" -f $Name, $Required) -ForegroundColor Red
        return
    }
    try {
        $v = (& $cmd.Source @VersionArgs 2>&1 | Select-Object -First 1)
        Write-Host ("  [OK]      {0,-10} {1}   (required: {2})" -f $Name, $v, $Required) -ForegroundColor Green
    } catch {
        Write-Host ("  [ERR]     {0}: could not read version" -f $Name) -ForegroundColor Yellow
    }
}

Write-Host "== Phase 1 - Local Development Environment ==" -ForegroundColor Cyan
Write-Host "Date: $(Get-Date -Format 'yyyy-MM-dd')"
Write-Host ""

Write-Host "Toolchain:" -ForegroundColor Cyan
Test-Cmd -Name docker    -VersionArgs @('--version')        -Required '^20+ (Desktop)'
Test-Cmd -Name python    -VersionArgs @('--version')        -Required '3.14'
Test-Cmd -Name node      -VersionArgs @('--version')        -Required '^16+'
Test-Cmd -Name git       -VersionArgs @('--version')        -Required '^2+'
Test-Cmd -Name flutter   -VersionArgs @('--version')        -Required '3.x stable'
Test-Cmd -Name dart      -VersionArgs @('--version')        -Required '3.x'
Test-Cmd -Name redis-cli -VersionArgs @('--version')        -Required '7+ (in container)'
Test-Cmd -Name psql      -VersionArgs @('--version')        -Required '16 (optional; client)'

Write-Host ""
Write-Host "Data services (must be reachable on localhost):" -ForegroundColor Cyan
$pgOpen = Get-NetTCPConnection -State Listen -LocalPort 5432 -ErrorAction SilentlyContinue
$rdOpen = Get-NetTCPConnection -State Listen -LocalPort 6379 -ErrorAction SilentlyContinue
if ($pgOpen) { Write-Host "  [OK]  PostgreSQL  listening on 5432" -ForegroundColor Green }
else         { Write-Host "  [OFF] PostgreSQL not listening on 5432 (start: docker compose -f backend/docker-compose.infra.yml up -d)" -ForegroundColor Yellow }
if ($rdOpen) { Write-Host "  [OK]  Redis       listening on 6379" -ForegroundColor Green }
else         { Write-Host "  [OFF] Redis not listening on 6379 (start: docker compose -f backend/docker-compose.infra.yml up -d)" -ForegroundColor Yellow }

Write-Host ""
Write-Host "Backend import smoke test:" -ForegroundColor Cyan
$backend = Join-Path $PSScriptRoot '..\..\backend'
Push-Location $backend
try {
    $envLine = (& python -c "import app.main; print(app.main.settings.ENVIRONMENT)" 2>$null | Select-Object -Last 1)
    Write-Host "  [OK]  app.main imports (env=$envLine)" -ForegroundColor Green
} catch {
    Write-Host "  [ERR]  backend import failed: $($_.Exception.Message)" -ForegroundColor Red
}
Pop-Location
Write-Host ""
Write-Host "Done. See backend/docs/PHASE1_LOCAL_DEVELOPMENT.md for next steps." -ForegroundColor Cyan
