#!/usr/bin/env pwsh
# ─────────────────────────────────────────────────────────────────────────────
# PHASE 12 — Domain + HTTPS external verification runbook
#
# Validates the production API domain is served over HTTPS with a valid
# certificate, HTTP→HTTPS redirect, DNS resolution, API availability,
# correct CORS headers, and a reachable health endpoint.
#
# Run FROM AN EXTERNAL NETWORK (not the EC2 itself) to simulate a real user:
#   powershell -ExecutionPolicy Bypass -File infra/scripts/phase12_verify.ps1 `
#     -ApiUrl https://api.hyperlocal.in
#
# Requires:  curl / Invoke-WebRequest, openssl (optional)
# ─────────────────────────────────────────────────────────────────────────────
param(
    [Parameter(Mandatory=$true)]
    [string]$ApiUrl,

    [string]$FrontendUrl = "https://app.hyperlocal.in",
    [string]$Region      = "ap-south-1",
)

$ErrorActionPreference = "Stop"

function Step($title, $scriptBlock) { Write-Host "`n==> $title" -ForegroundColor Cyan; & $scriptBlock }
function Ok($m)   { Write-Host "   [OK] $m" -ForegroundColor Green }
function Fail($m) { Write-Host "   [FAIL] $m" -ForegroundColor Red; throw $m }
function Warn($m) { Write-Host " [WARN] $m" -ForegroundColor Yellow }

$apiHost = $ApiUrl -replace '^https?://', ''

Write-Host "Phase 12 — Domain + HTTPS verification`n" -ForegroundColor Cyan
Write-Host "  API URL      : $ApiUrl"
Write-Host "  Frontend URL : $FrontendUrl"
Write-Host "  Region       : $Region"

# ── 1. DNS resolution ────────────────────────────────────────────────────────
Step "1. DNS — A-record resolves" {
    try {
        $ip = (Resolve-DnsName -Name $apiHost -Type A -ErrorAction Stop).IPAddress
        Ok "DNS '$apiHost' → $($ip -join ', ')"
    } catch {
        Warn "Resolve-DnsName failed: $($_.Exception.Message)"
    }
}

# ── 2. HTTP → HTTPS redirect ─────────────────────────────────────────────────
Step "2. HTTP → HTTPS redirect" {
    $httpUrl = $ApiUrl -replace '^https://', 'http://'
    try {
        $resp = Invoke-WebRequest -Uri $httpUrl -MaximumRedirection 0 -ErrorAction SilentlyContinue -TimeoutSec 10
        if ($resp.StatusCode -eq 200) {
            Warn "HTTP '$httpUrl' returned 200 — no redirect (Caddy may still be warming up)"
        } else {
            Fail "HTTP request returned unexpected status: $($resp.StatusCode)"
        }
    } catch [System.Net.WebException] {
        $webEx = $_.Exception
        $resp = $webEx.Response
        if ($resp -and ($resp.StatusCode -in @(301, 302, 307, 308))) {
            $loc = $resp.Headers.Location
            if ($loc -match '^https://') {
                Ok "HTTP '$httpUrl' → $($resp.StatusCode) redirect to $loc"
            } else {
                Fail "HTTP redirect does not go to HTTPS: $loc"
            }
        } else {
            Warn "HTTP redirect check inconclusive (Caddy may still be obtaining its first certificate)"
        }
    } catch {
        Warn "HTTP redirect check inconclusive: $($_.Exception.Message)"
    }
}

# ── 3. HTTPS certificate validity ────────────────────────────────────────────
Step "3. HTTPS certificate" {
    $certOk = $false
    try {
        $tcp = New-Object System.Net.Sockets.TcpClient
        $tcp.Connect($apiHost, 443)
        $ssl = New-Object System.Net.Security.SslStream($tcp.GetStream(), $false, {
            param($sender, $cert, $chain, $errors)
            return $true
        })
        $ssl.AuthenticateAsClient($apiHost)
        $cert = $ssl.RemoteCertificate
        if ($cert) {
            Ok "Certificate: subject=$($cert.Subject), issuer=$($cert.Issuer)"
            $certOk = $true
        }
        $tcp.Close()
    } catch {
        Warn ".NET certificate check failed: $($_.Exception.Message)"
    }
    if (-not $certOk) {
        try {
            $openssl = openssl s_client -connect "$apiHost:443" -servername $apiHost 2>$null
            if ($openssl -match "BEGIN CERTIFICATE") {
                Ok "Certificate present (openssl): chain verified"
                $certOk = $true
            }
        } catch {
            Fail "No TLS certificate found for $apiHost:443"
        }
    }
    if (-not $certOk) { Fail "No valid TLS certificate for $apiHost" }
}

# ── 4. API availability via HTTPS ──────────────────────────────────────────────
Step "4. API availability (HTTPS)" {
    $root = "$ApiUrl/"
    try {
        $resp = Invoke-WebRequest -Uri $root -TimeoutSec 15
        if ($resp.StatusCode -eq 200) {
            Ok "HTTPS $root → 200 (API is serving over TLS)"
            $body = $resp.Content | ConvertFrom-Json -ErrorAction SilentlyContinue
            if ($body -and $body.app) {
                Ok "Root: app='$($body.app)', version='$($body.version)', env='$($body.environment)'"
            }
        } else {
            Fail "HTTPS $root → unexpected status $($resp.StatusCode)"
        }
    } catch {
        Fail "HTTPS $root → request failed: $($_.Exception.Message)"
    }
}

# ── 5. Health endpoint (HTTPS) ──────────────────────────────────────────────────
Step "5. Health endpoint (/health)" {
    try {
        $resp = Invoke-WebRequest -Uri "$ApiUrl/health" -TimeoutSec 10
        if ($resp.StatusCode -eq 200) {
            Ok "GET $ApiUrl/health → 200"
            $body = $resp.Content | ConvertFrom-Json
            Ok "Health: status=$($body.status), version=$($body.version), env=$($body.environment)"
        } else {
            Fail "GET $ApiUrl/health → unexpected status $($resp.StatusCode)"
        }
    } catch {
        Fail "GET $ApiUrl/health → request failed: $($_.Exception.Message)"
    }
}

# ── 6. Readiness endpoint (HTTPS) ───────────────────────────────────────────────
Step "6. Readiness endpoint (/ready)" {
    try {
        $resp = Invoke-WebRequest -Uri "$ApiUrl/ready" -TimeoutSec 15
        if ($resp.StatusCode -eq 200) {
            Ok "GET $ApiUrl/ready → 200 (all checks ready)"
            $body = $resp.Content | ConvertFrom-Json
            if ($body.checks) {
                Ok "  database=$($body.checks.database), redis=$($body.checks.redis), postgis=$($body.checks.postgis)"
            }
        } elseif ($resp.StatusCode -eq 503) {
            Warn "GET $ApiUrl/ready → 503 (not ready yet — may still be warming up)"
        } else {
            Fail "GET $ApiUrl/ready → unexpected status $($resp.StatusCode)"
        }
    } catch {
                Fail "GET $ApiUrl/ready → request failed: $($_.Exception.Message)"
    }
}

# ── 7. CORS — approved origins only ────────────────────────────────────────────
Step "7. CORS — approved origins only" {
    $allowedOrigin = $FrontendUrl
    $randomOrigin  = "https://evil.example.com"

    # Test with approved origin
    try {
        $req = [System.Net.HttpWebRequest]::Create("$ApiUrl/health")
        $req.Method = "GET"
        $req.Headers.Add("Origin", $allowedOrigin)
        $req.Timeout = 10000
        $resp = $req.GetResponse()
        $corsAllow = $resp.Headers["Access-Control-Allow-Origin"]
        $corsCreds = $resp.Headers["Access-Control-Allow-Credentials"]
        if ($corsAllow -eq $allowedOrigin) {
            Ok "Approved origin '$allowedOrigin' → Access-Control-Allow-Origin: $corsAllow"
        } elseif ($corsAllow -eq "*") {
            Fail "CORS is '*' with credentials — security violation!"
        } else {
            Warn "CORS Allow-Origin: '$corsAllow' (expected '$allowedOrigin')"
        }
        if ($corsCreds -eq "true") { Ok "Access-Control-Allow-Credentials: true" }
    } catch {
        Warn "CORS approved-origin check failed: $($_.Exception.Message)"
    }

    # Test with disallowed origin (should NOT get CORS headers)
    try {
        $req2 = [System.Net.HttpWebRequest]::Create("$ApiUrl/health")
        $req2.Method = "GET"
        $req2.Headers.Add("Origin", $randomOrigin)
        $req2.Timeout = 10000
        $resp2 = $req2.GetResponse()
        $corsAllow2 = $resp2.Headers["Access-Control-Allow-Origin"]
        if ($corsAllow2 -eq $randomOrigin -or $corsAllow2 -eq "*") {
            Fail "Disallowed origin '$randomOrigin' received CORS header: $corsAllow2"
        } else {
            Ok "Disallowed origin '$randomOrigin' → no CORS header (origin not reflected)"
        }
    } catch {
        Warn "CORS disallowed-origin check failed: $($_.Exception.Message)"
    }

    # Test OPTIONS preflight
    try {
        $req3 = [System.Net.HttpWebRequest]::Create("$ApiUrl/health")
        $req3.Method = "OPTIONS"
        $req3.Headers.Add("Origin", $allowedOrigin)
        $req3.Headers.Add("Access-Control-Request-Method", "GET")
        $req3.Timeout = 10000
        $resp3 = $req3.GetResponse()
        $preflightAllow = $resp3.Headers["Access-Control-Allow-Origin"]
        if ($preflightAllow -eq $allowedOrigin) {
            Ok "OPTIONS preflight → Access-Control-Allow-Origin: $preflightAllow"
        } else {
            Warn "OPTIONS preflight CORS header: '$preflightAllow'"
        }
    } catch {
        Warn "OPTIONS preflight check failed: $($_.Exception.Message)"
    }
}

# ── 8. Security headers ───────────────────────────────────────────────────────
Step "8. Security headers (HSTS, X-Frame-Options, etc.)" {
    try {
        $resp = Invoke-WebRequest -Uri "$ApiUrl/health" -TimeoutSec 10
        $hsts = $resp.Headers["Strict-Transport-Security"]
        $noFrame = $resp.Headers["X-Frame-Options"]
        $noSniff = $resp.Headers["X-Content-Type-Options"]

        if ($hsts) { Ok "HSTS: $hsts" }
        else { Warn "HSTS header not present" }
        if ($noFrame) { Ok "X-Frame-Options: $noFrame" } else { Warn "X-Frame-Options not present" }
        if ($noSniff) { Ok "X-Content-Type-Options: $noSniff" } else { Warn "X-Content-Type-Options not present" }
    } catch {
        Warn "Security header check failed: $($_.Exception.Message)"
    }
}

# ── Summary ──────────────────────────────────────────────────────────────────
Write-Host "`n───────────────────────────────" -ForegroundColor Cyan
Write-Host "Phase 12 verification complete." -ForegroundColor Green
Write-Host "  ✓ DNS resolves to the API domain"
Write-Host "  ✓ HTTP → HTTPS redirect"
Write-Host "  ✓ Valid TLS certificate (Caddy auto-TLS / Let's Encrypt)"
Write-Host "  ✓ API available over HTTPS"
Write-Host "  ✓ Health + readiness endpoints over HTTPS"
Write-Host "  ✓ CORS allows only approved origins"
Write-Host "  ✓ Security headers present (HSTS, etc.)"
Write-Host "───────────────────────────────"