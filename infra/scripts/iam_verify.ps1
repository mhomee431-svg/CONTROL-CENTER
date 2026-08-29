#!/usr/bin/env pwsh
# ─────────────────────────────────────────────────────────────────────────────
# PHASE 2 — IAM verification runbook (run AFTER you grant access)
# Validates:  authentication → role assumption → permissions → service access
#            → and "no unnecessary privilege" checks.
#
# Requires:  aws CLI (v2) configured with a bootstrap (or operator) profile.
# Usage:     powershell -ExecutionPolicy Bypass -File infra/scripts/iam_verify.ps1
#            -Region ap-south-1 -AccountId 123456789012 -OpRole <operator-role-arn>
#            -CiRole <ci-deploy-role-arn> -BootstrapProfile hyperlocal-bootstrap
# ─────────────────────────────────────────────────────────────────────────────
param(
    [string]$Region = "ap-south-1",
    [string]$AccountId = $env:AWS_IAM_ACCOUNT_ID,
    [string]$OpRole = $env:OP_ROLE_ARN,
    [string]$CiRole = $env:CI_ROLE_ARN,
    [string]$BootstrapProfile = "hyperlocal-bootstrap"
)

$ErrorActionPreference = "Stop"
function Step($title, $scriptBlock) { Write-Host "`n==> $title" -ForegroundColor Cyan; & $scriptBlock }
function Ok($m)   { Write-Host "   [OK] $m" -ForegroundColor Green }
function Warn($m) { Write-Host " [WARN] $m" -ForegroundColor Yellow }

if (-not (Get-Command aws -ErrorAction SilentlyContinue)) { throw "aws CLI not installed." }

# ── 1. AUTHENTICATION (prove we are NOT root) ────────────────────────────────
Step "1. Authentication & account identity" {
    $id  = aws sts get-caller-identity --region $Region --output json | ConvertFrom-Json
    $ar = $id.Arn
    Ok "Caller: $ar"
    if ($ar -match ":root$") { Warn "Caller is the ROOT principal — not allowed for runtime/ops. Reconsider." }
    else                     { Ok "Caller is a non-root principal." }
}

# ── 2. ROLE ASSUMPTION (operator) ────────────────────────────────────────────
Step "2. Assume operator role" {
    if (-not $OpRole) { Warn "OP_ROLE_ARN not set; skipping role assumption."; return }
    $creds = aws sts assume-role --role-arn $OpRole --role-session-name iam-verify --region $Region --output json |
             ConvertFrom-Json
    if ($creds.Credentials) { Ok "Assumed operator role; expiry $($creds.Credentials.Expiration)" }
    else { throw "Failed to assume operator role." }
}

# ── 3. PERMISSIONS — simulate required actions vs the CI/CD role ──────────────
Step "3. Permission simulation (required service access)" {
    if (-not $CiRole) { Warn "CI_ROLE_ARN not set; skipping simulation."; return }
    $actions = @("ecr:PutImage", "ecr:GetAuthorizationToken", "ecs:RegisterTaskDefinition", "ecs:UpdateService")
    foreach ($a in $actions) {
        $r = aws iam simulate-principal-policy --policy-source-arn $CiRole --action-names $a --region $Region --output json |
             ConvertFrom-Json
        $allowed = ($r.EvaluationResults | Where-Object { $_.EvalActionName -eq $a }).EvalDecision
        if ($allowed -eq "allowed") { Ok  "${a} -> Allowed" } else { Warn "${a} -> $allowed (check)" }
    }
}

# ── 4. SERVICE ACCESS (smoke against real endpoints) ──────────────────────────
Step "4. Service access smoke test" {
    $token = aws ecr get-authorization-token --region $Region --output text 2>$null
    if ($LASTEXITCODE -eq 0) { Ok "ECR GetAuthorizationToken works." } else { Warn "ECR token failed." }

    $seg = aws iam get-account-password-policy --output json 2>$null
    if ($LASTEXITCODE -eq 0) { Ok "Account password policy present." } else { Warn "No password policy yet." }
}

# ── 5. NO UNNECESSARY PRIVILEGE (report the effective policy) ────────────────
Step "5. Effective policy inventory (check for wildcards / broad grants)" {
    if (-not $CiRole) { Warn "CI_ROLE_ARN not set; skipping."; return }
    $name = ($CiRole -split "/")[-1]
    aws iam get-role-policy --role-name $name --policy-name "hyperlocal-cicd-deploy" --output json 2>$null |
        ConvertFrom-Json |
        ForEach-Object { $_.PolicyDocument.Statement } |
        Where-Object { $_.Resource -contains "*" } |
        ForEach-Object { Warn "Wildcard resource in: $($_.Sid)" }
    Ok "Inspection complete. Review any flagged statements against the PHASE2 doc 'least-privilege matrix'."
}

Write-Host "`nPhase 2 verification complete." -ForegroundColor Green