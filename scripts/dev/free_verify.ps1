# scripts/dev/free_verify.ps1
# ---------------------------------------------------------------------------
# Post-deploy verification for the FREE-TIER cloud instance (infra/free).
#
#   powershell -ExecutionPolicy Bypass -File scripts/dev/free_verify.ps1
#   powershell -ExecutionPolicy Bypass -File scripts/dev/free_verify.ps1 -PublicIp 1.2.3.4
#
# With no args, reads terraform output via AWS CLI (run from infra/free).
[CmdletBinding()]
param([string]$PublicIp = '')

$ErrorActionPreference = 'Stop'

if (-not $PublicIp) {
    $tfDir = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'infra\free'
    if (-not (Get-Command aws -ErrorAction SilentlyContinue)) {
        Write-Host "[X] AWS CLI not found and no -PublicIp given." -ForegroundColor Red
        exit 1
    }
    Push-Location $tfDir
    try { $PublicIp = (terraform output -raw public_ip) } finally { Pop-Location }
}
if (-not $PublicIp) {
    Write-Host "[X] Could not resolve public IP. Pass -PublicIp <ip>." -ForegroundColor Red
    exit 1
}

Write-Host "== Verifying free-tier instance @ http://$PublicIp" -ForegroundColor Cyan
foreach ($endpoint in @('/health', '/ready', '/docs')) {
    $url = "http://$PublicIp$endpoint"
    try {
        if ($endpoint -eq '/docs') {
            $resp = Invoke-WebRequest -Uri $url -TimeoutSec 15 -UseBasicParsing
            Write-Host ("[OK]   GET {0,-6} HTTP {1}" -f $endpoint, $resp.StatusCode) -ForegroundColor Green
        }
        else {
            $body = Invoke-RestMethod -Uri $url -TimeoutSec 15
            Write-Host ("[OK]   GET {0,-6} {1}" -f $endpoint, ($body | ConvertTo-Json -Compress -Depth 4)) -ForegroundColor Green
            if ($endpoint -eq '/ready' -and $body.status -eq 'degraded') {
                Write-Host "       degraded - check db/postgis/redis components above" -ForegroundColor Yellow
            }
        }
    }
    catch {
        Write-Host ("[FAIL] GET {0,-6} {1}" -f $endpoint, $_.Exception.Message) -ForegroundColor Red
        Write-Host "       If first deploy: build takes ~5-8 min. Get logs:" -ForegroundColor Yellow
        Write-Host "       EC2 console -> Connect (Session Manager) -> journalctl -t hyperlocal-boot -f" -ForegroundColor Yellow
        exit 1
    }
}
Write-Host ""
Write-Host "ALL GREEN - app is live on port 80" -ForegroundColor Green
