# scripts/dev/free_db.ps1
# ---------------------------------------------------------------------------
# PHASE 4 — FREE CLOUD POSTGRESQL + POSTGIS — one-command workflow
#
#   provision -> migrate (alembic upgrade head) -> verify -> seed sample data
#
# Examples
#   # Cost-free Neon (default; create an API key at console.neon.tech)
#   powershell -ExecutionPolicy Bypass -File scripts/dev/free_db.ps1 `
#     -Provider neon -ApiKey "$env:NEON_API_KEY" -Region aws-ap-south-1
#
#   # Supabase free plan
#   powershell -ExecutionPolicy Bypass -File scripts/dev/free_db.ps1 `
#     -Provider supabase -AccessToken "$env:SUPABASE_ACCESS_TOKEN" -Region ap-south-1
#
#   # Adopt an existing Neon/Supabase/RDS URL (async or sync)
#   powershell -ExecutionPolicy Bypass -File scripts/dev/free_db.ps1 `
#     -Provider import -Url "postgresql+asyncpg://u:p@host:5432/db?ssl=require"
#
#   # Already provisioned already -> just migrate + verify + seed
#   powershell -ExecutionPolicy Bypass -File scripts/dev/free_db.ps1 -MigrateOnly
#
# Idempotent: re-running reuses the project/database and never drops anything.
# ---------------------------------------------------------------------------
[CmdletBinding()]
param(
    [ValidateSet('neon', 'supabase', 'import')]
    [string]$Provider = 'neon',
    [string]$ApiKey = '',
    [string]$AccessToken = '',
    [string]$Org = '',
    [string]$Url = '',
    [string]$Region = '',
    [string]$DbName = 'hyperlocal',
    [int]$PgVersion = 16,
    [switch]$MigrateOnly,   # skip provisioning, reuse the URL from .env.free / -Url
    [switch]$NoVerify,      # skip the Phase-4 architecture verifier
    [switch]$NoSeed,        # skip the sample-data seeder
    [switch]$Reset          # wipe this seeder's rows before reseeding
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$backend  = Join-Path $repoRoot 'backend'
$py       = 'python'

function Invoke-Py([string]$Description, [string[]]$Args) {
    Write-Host "`n== $Description" -ForegroundColor Cyan
    Write-Host "   python $Args" -ForegroundColor DarkGray
    & $py @Args
    if ($LASTEXITCODE -ne 0) { throw "Failed: $Description (exit $LASTEXITCODE)" }
}

function Resolve-EnvUrl {
    $envFile = Join-Path $backend '.env.free'
    if (Test-Path $envFile) {
        $line = Get-Content $envFile | Where-Object { $_ -match '^DATABASE_URL=' } | Select-Object -First 1
        if ($line) { return ($line -replace '^DATABASE_URL=', '').Trim() }
    }
    throw 'DATABASE_URL not found in backend/.env.free. Provision first (or pass -Url).'
}

# ── 1. Provision (idempotent; skipped for -MigrateOnly or when -Url given) ──
if ($MigrateOnly -or $Url) {
    Write-Host '== Provisioning step skipped (reusing existing connection)' -ForegroundColor Yellow
} else {
    $provArgs = @()
    switch ($Provider) {
        'neon' {
            if (-not $ApiKey -and -not $env:NEON_API_KEY) {
                throw 'Neon needs -ApiKey (or $env:NEON_API_KEY).'
            }
            $key = if ($ApiKey) { $ApiKey } else { $env:NEON_API_KEY }
            $provArgs = @('scripts/provision_free_db.py', 'neon', '--api-key', $key,
                          '--region', $Region, '--db', $DbName)
            if ($Org) { $provArgs += @('--org', $Org) }
        }
        'supabase' {
            if (-not $AccessToken -and -not $env:SUPABASE_ACCESS_TOKEN) {
                throw 'Supabase needs -AccessToken (or $env:SUPABASE_ACCESS_TOKEN).'
            }
            $tok = if ($AccessToken) { $AccessToken } else { $env:SUPABASE_ACCESS_TOKEN }
            $provArgs = @('scripts/provision_free_db.py', 'supabase', '--access-token', $tok,
                          '--region', $Region)
            if ($Org) { $provArgs += @('--org', $Org) }
        }
        'import' {
            if (-not $Url) { throw 'Provider "import" needs -Url.' }
            $provArgs = @('scripts/provision_free_db.py', 'import', '--url', $Url)
        }
    }
    if (-not $Url) {   # import reuses -Url instead of re-reading
        Push-Location $backend
        try { Invoke-Py 'Provisioning free cloud database' $provArgs }
        finally { Pop-Location }
    }
}

# ── Resolve the async connection URL ─────────────────────────────────────────
if (-not $Url) { $Url = Resolve-EnvUrl }
Write-Host "`nUsing database: $($Url -replace '://[^@]+@', '://***:***@')" -ForegroundColor Green

# ── 2. Migrate + verify ──────────────────────────────────────────────────────
$migArgs = @('scripts/migrate_free_db.py', '--url', $Url)
if ($NoVerify) { $migArgs += '--no-verify' }
Push-Location $backend
try { Invoke-Py 'Running Alembic migrations + Phase-4 verifier' $migArgs }
finally { Pop-Location }

# ── 3. Seed real sample hyperlocal data ──────────────────────────────────────
if (-not $NoSeed) {
    $seedArgs = @('scripts/seed_free_data.py', '--url', $Url)
    if ($Reset) { $seedArgs += '--reset' }
    Push-Location $backend
    try { Invoke-Py 'Seeding sample hyperlocal data' $seedArgs }
    finally { Pop-Location }
}

Write-Host @"

ALL GREEN — free cloud PostgreSQL provisioned, migrated, verified and seeded.
  DB      : $($Url -replace '://[^@]+@', '://***:***@')
  Next    : point the app at the DB by exporting the URL or using backend/.env.free
  Verify  : cd backend && python scripts/verify_rds.py --url `"$Url`"
"@ -ForegroundColor Green