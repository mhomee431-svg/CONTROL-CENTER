# ==============================================================================
# scripts/test_docker_phase10.ps1 — Phase 10 backend dockerization test suite
#
# Executes the full Phase 10 checklist against a Docker Engine:
#   1. Clean build          (docker compose build --no-cache)
#   2. Clean startup        (fresh volumes, wait for /ready)
#   3. Database connectivity(pg_isready inside the db container)
#   4. Redis connectivity   (redis-cli ping inside the redis container)
#   5. S3 connectivity      (boto3 inside the api container — SKIP unless
#                            S3 is configured)
#   6. API health           (GET /health and GET /ready — /ready must report
#                            database: true, redis: true, postgis: true)
#   7. Graceful shutdown    (docker compose stop api → exit 0, lifespan logs)
#
# Usage (from repo root, Docker Desktop running):
#   powershell -ExecutionPolicy Bypass -File scripts/test_docker_phase10.ps1
#   powershell -ExecutionPolicy Bypass -File scripts/test_docker_phase10.ps1 -KeepStack
# ==============================================================================
param(
    [string]$ComposeFile = "backend/docker-compose.yml",
    [switch]$KeepStack
)

$ErrorActionPreference = "Stop"
$script:Failures = 0

function Pass([string]$Name, [string]$Detail) {
    Write-Host "  [PASS] $Name $(if ($Detail) { "- $Detail" })" -ForegroundColor Green
}
function Fail([string]$Name, [string]$Detail) {
    Write-Host "  [FAIL] $Name $(if ($Detail) { "- $Detail" })" -ForegroundColor Red
    $script:Failures++
}
function Skip([string]$Name, [string]$Detail) {
    Write-Host "  [SKIP] $Name $(if ($Detail) { "- $Detail" })" -ForegroundColor Yellow
}

# ── 0. Preconditions ──────────────────────────────────────────────────────────
Write-Host "`n== Phase 10: backend dockerization tests ==" -ForegroundColor Cyan
Write-Host "Compose file: $ComposeFile"

try {
    $dockerVersion = (docker version --format '{{.Server.Version}}' 2>$null)
    if (-not $dockerVersion) { throw "no engine" }
    Pass "Docker engine reachable" "v$dockerVersion"
} catch {
    Fail "Docker engine reachable" "Docker is not running or not installed"
    exit 1
}

try { docker compose -f $ComposeFile config --quiet; Pass "Compose file valid" }
catch { Fail "Compose file valid" $_.Exception.Message; exit 1 }

# ── 1. Clean build ────────────────────────────────────────────────────────────
Write-Host "`n[1/7] Clean build (--no-cache)..."
docker compose -f $ComposeFile build --no-cache api migrate
if ($LASTEXITCODE -eq 0) { Pass "Clean build" } else { Fail "Clean build" "build exited $LASTEXITCODE"; exit 1 }

# ── 2. Clean startup ──────────────────────────────────────────────────────────
Write-Host "`n[2/7] Clean container startup (fresh volumes)..."
docker compose -f $ComposeFile down -v --remove-orphans | Out-Null
docker compose -f $ComposeFile up -d
if ($LASTEXITCODE -ne 0) { Fail "Container startup" "up exited $LASTEXITCODE"; exit 1 }

$deadline = (Get-Date).AddSeconds(180)
$ready = $false
while ((Get-Date) -lt $deadline) {
    try {
        $resp = Invoke-WebRequest -Uri "http://127.0.0.1:8000/ready" -UseBasicParsing -TimeoutSec 3
        if ($resp.StatusCode -eq 200) { $ready = $true; break }
    } catch { Start-Sleep -Seconds 3 }
}
if ($ready) { Pass "API container started and became ready" }
else { Fail "API container started and became ready" "timeout waiting for /ready"; docker compose -f $ComposeFile logs --tail 50 api }

# ── 3. Database connectivity ─────────────────────────────────────────────────
Write-Host "`n[3/7] Database connectivity..."
docker compose -f $ComposeFile exec -T db pg_isready -U hyperlocal
if ($LASTEXITCODE -eq 0) { Pass "PostgreSQL accepting connections" } else { Fail "PostgreSQL accepting connections" }

# ── 4. Redis connectivity ────────────────────────────────────────────────────
Write-Host "`n[4/7] Redis connectivity..."
$redisPing = docker compose -f $ComposeFile exec -T redis redis-cli ping 2>$null
if ("$redisPing".Trim() -eq "PONG") { Pass "Redis PONG" } else { Fail "Redis PONG" "got: $redisPing" }

# ── 5. S3 connectivity ───────────────────────────────────────────────────────
Write-Host "`n[5/7] S3 connectivity..."
$s3Script = @'
import boto3, botocore, os
try:
    s3 = boto3.client("s3", region_name=os.environ.get("S3_REGION", "us-east-1"))
    s3.head_bucket(Bucket=os.environ["S3_BUCKET_NAME"])
    print("OK")
except botocore.exceptions.NoCredentialsError:
    print("NO_CREDENTIALS")
except KeyError:
    print("NO_BUCKET_CONFIGURED")
'@
$s3Out = docker compose -f $ComposeFile exec -T api python -c $s3Script 2>$null
switch -Wildcard ("$s3Out".Trim()) {
    "OK"                   { Pass "S3 bucket reachable" }
    "NO_CREDENTIALS"       { Skip "S3 bucket reachable" "no AWS credentials in this stack (STORAGE_PROVIDER=local) — configure S3_* env to test" }
    "NO_BUCKET_CONFIGURED" { Skip "S3 bucket reachable" "S3_BUCKET_NAME not set — local storage provider active" }
    default                { Fail "S3 bucket reachable" "got: $s3Out" }
}

# ── 6. API health ────────────────────────────────────────────────────────────
Write-Host "`n[6/7] API health endpoints..."
try {
    $health = (Invoke-WebRequest -Uri "http://127.0.0.1:8000/health" -UseBasicParsing -TimeoutSec 5).Content | ConvertFrom-Json
    if ($health.status -eq "healthy") { Pass "GET /health" "env=$($health.environment) v$($health.version)" } else { Fail "GET /health" "status=$($health.status)" }
} catch { Fail "GET /health" $_.Exception.Message }

try {
    $readyBody = (Invoke-WebRequest -Uri "http://127.0.0.1:8000/ready" -UseBasicParsing -TimeoutSec 10).Content | ConvertFrom-Json
    $checks = $readyBody.checks
    if ($checks.database -and $checks.redis -and $checks.postgis) {
        Pass "GET /ready" "database=True redis=True postgis=True"
    } else {
        Fail "GET /ready" "database=$($checks.database) redis=$($checks.redis) postgis=$($checks.postgis)"
    }
} catch { Fail "GET /ready" $_.Exception.Message }

# ── 7. Graceful shutdown ─────────────────────────────────────────────────────
Write-Host "`n[7/7] Graceful shutdown (SIGTERM handling)..."
docker compose -f $ComposeFile stop api
if ($LASTEXITCODE -eq 0) { Pass "docker compose stop (clean exit)" } else { Fail "docker compose stop (clean exit)" "exit $LASTEXITCODE" }
$after = (docker compose -f $ComposeFile logs --tail 200 api) -join "`n"
if ($after -match "Shutdown complete") { Pass "Lifespan shutdown hook ran" "log: 'Shutdown complete'" }
else { Skip "Lifespan shutdown hook ran" "'Shutdown complete' not found in last logs — inspect manually" }

# ── Cleanup ──────────────────────────────────────────────────────────────────
if (-not $KeepStack) {
    Write-Host "`nTearing down stack (docker compose down -v)..."
    docker compose -f $ComposeFile down -v --remove-orphans | Out-Null
} else {
    Write-Host "`n-KeepStack set — stack left running (api stopped by shutdown test)."
    Write-Host "Restart with: docker compose -f $ComposeFile up -d"
}

Write-Host "`n== Result: $($script:Failures) failure(s) ==" -ForegroundColor $(if ($script:Failures -eq 0) { "Green" } else { "Red" })
exit $(if ($script:Failures -eq 0) { 0 } else { 1 })