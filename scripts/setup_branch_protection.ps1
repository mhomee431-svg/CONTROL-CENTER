# scripts/setup_branch_protection.ps1
# -- Apply the `develop` / `main` branch protection rules ---------------------
#
# Implements section 4 of docs/deployment/BRANCHING.md with the GitHub REST API:
#   * creates `develop` (from `main`) when it does not exist yet
#   * requires PRs + the CI status checks for both long-lived branches
#   * blocks force pushes and deletions, requires conversation resolution
#
# Usage:
#   $env:GITHUB_TOKEN = "<PAT with repo + administration scope>"   # classic PAT
#   powershell -ExecutionPolicy Bypass -File scripts/setup_branch_protection.ps1 -DryRun
#   powershell -ExecutionPolicy Bypass -File scripts/setup_branch_protection.ps1
#   # or: use the exact check names GitHub reports for the branch
#   powershell -ExecutionPolicy Bypass -File scripts/setup_branch_protection.ps1 -Discover
#
# Notes:
#   * Fine-grained PATs need "Administration: read and write" + "Contents: read
#     and write" on this repository.
#   * Status-check names must match the workflow job `name:` values exactly; CI
#     has to have run at least once for GitHub to offer them in the UI.
#   * This file is intentionally ASCII-only: Windows PowerShell 5.1 reads .ps1
#     files as ANSI, so a literal em dash inside a string would break parsing.
#     The em dash used by the check names is built from its code point instead.
param(
    [string]$Repo = "Akasharyan47/hyperlocal_app",
    [string]$Token = $env:GITHUB_TOKEN,
    [string]$BaseBranch = "main",
    [string[]]$Branches = @("develop", "main"),
    [string[]]$Checks,
    [switch]$Discover,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$ApiBase = "https://api.github.com/repos/$Repo"

# The PR gate is platform-ci.yml, so these are the checks a PR must satisfy.
# Override with -Checks, or use -Discover to take the names GitHub reports.
$PreferredChecks = @(
    "Backend quality gates",
    "Customer app checks",
    "Shopkeeper app checks",
    "Admin panel checks",
    "Shared Dart package checks"
)

function Resolve-RequiredChecks {
    param([string]$Branch)

    if ($Checks) { return $Checks }
    if (-not $Discover) { return $PreferredChecks }

    # Ask GitHub which checks actually report on this branch (read-only GET).
    try {
        $runs = Invoke-RestMethod -Method GET -Headers (New-Headers) `
            -Uri "$ApiBase/commits/$Branch/check-runs?per_page=100"
        $names = @($runs.check_runs | ForEach-Object { $_.name } | Where-Object { $_ } | Select-Object -Unique)
        if ($names.Count -eq 0) {
            Write-Host "  no check runs on '$Branch' yet - using the preferred list"
            return $PreferredChecks
        }
        $matched = @($names | Where-Object { $PreferredChecks -contains $_ })
        if ($matched.Count -gt 0) { return $matched }
        Write-Host "  discovered on '$Branch': $($names -join ', ')"
        return $names
    } catch {
        Write-Host "  discovery failed ($($_.Exception.Message)) - using the preferred list"
        return $PreferredChecks
    }
}

function New-Headers {
    @{
        Authorization          = "Bearer $Token"
        Accept                 = "application/vnd.github+json"
        "X-GitHub-Api-Version" = "2022-11-28"
    }
}

function Invoke-GitHub {
    param(
        [string]$Method,
        [string]$Uri,
        $Body
    )
    $params = @{
        Method  = $Method
        Uri     = $Uri
        Headers = (New-Headers)
    }
    if ($Body) {
        $params.Body = ($Body | ConvertTo-Json -Depth 12)
        $params.ContentType = "application/json"
    }
    if ($DryRun) {
        Write-Host "  [dry-run] $Method $Uri"
        if ($Body) { $Body | ConvertTo-Json -Depth 12 | Write-Host }
        return $null
    }
    return Invoke-RestMethod @params
}

# -- The gate: exactly these checks must be green before a merge --------------
function Get-BranchPolicy {
    param(
        [string]$Branch,
        [string[]]$CheckNames
    )

    # `main` releases must be built on top of the latest base branch.
    $strict = ($Branch -eq "main")

    @{
        required_status_checks           = @{
            strict   = $strict
            contexts = $CheckNames
        }
        enforce_admins                   = @{ enabled = $true }
        required_pull_request_reviews    = @{
            dismiss_stale_reviews           = $true
            require_code_owner_reviews      = $false
            required_approving_review_count = 1
        }
        required_conversation_resolution = $true
        required_linear_history          = $true
        allow_force_pushes               = $false
        allow_deletions                  = $false
        restrictions                     = $null
        block_creations                  = $false
    }
}

# -- Make sure the branch exists before protecting it ------------------------
function Ensure-Branch {
    param([string]$Branch)

    if ($DryRun) {
        Write-Host "  [dry-run] would ensure branch '$Branch' exists (base: $BaseBranch)"
        return
    }
    try {
        Invoke-GitHub -Method GET -Uri "$ApiBase/branches/$Branch" | Out-Null
        Write-Host "  branch '$Branch' already exists"
    } catch {
        Write-Host "  branch '$Branch' missing - creating it from '$BaseBranch'"
        $base = Invoke-GitHub -Method GET -Uri "$ApiBase/git/ref/heads/$BaseBranch"
        Invoke-GitHub -Method POST -Uri "$ApiBase/git/refs" -Body @{
            ref = "refs/heads/$Branch"
            sha = $base.object.sha
        } | Out-Null
        Write-Host "  created '$Branch' at $($base.object.sha)"
    }
}

# -- Main ---------------------------------------------------------------------
Write-Host "Branch protection for $Repo (develop = integration, main = production)"
Write-Host "See docs/deployment/BRANCHING.md section 4 for the rationale."

if (-not $Token) {
    Write-Host "ERROR: no token. Set `$env:GITHUB_TOKEN (classic PAT with 'repo';" -ForegroundColor Red
    Write-Host "       fine-grained: Administration read/write + Contents read/write)." -ForegroundColor Red
    exit 1
}

if ($DryRun) { Write-Host "DRY RUN - nothing will be changed on GitHub." -ForegroundColor Yellow }

$failed = @()
foreach ($branch in $Branches) {
    Write-Host ""
    Write-Host "-- $branch" -ForegroundColor Cyan

    Ensure-Branch -Branch $branch

    $required = @(Resolve-RequiredChecks -Branch $branch)
    Write-Host "  required checks: $($required -join ', ')"

    try {
        Invoke-GitHub -Method PUT -Uri "$ApiBase/branches/$branch/protection" -Body (Get-BranchPolicy -Branch $branch -CheckNames $required) | Out-Null
        if ($DryRun) {
            Write-Host "  [dry-run] would apply the protection rule above"
        } else {
            Write-Host "  protection applied (PR required, checks required, no force push, no deletion)"
        }
    } catch {
        Write-Host "  FAILED to protect '$branch': $($_.Exception.Message)" -ForegroundColor Red
        $failed += $branch
    }
}

if ($DryRun) {
    Write-Host ""
    Write-Host "Dry run complete. Re-run without -DryRun to apply." -ForegroundColor Yellow
    exit 0
}

if ($failed.Count -gt 0) {
    Write-Host ""
    Write-Host "Some branches are NOT protected: $($failed -join ', ')" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "Done. Still do these by hand (Settings -> Environment):" -ForegroundColor Green
Write-Host "  1. environment 'staging'    - no reviewers (fast feedback)"
Write-Host "  2. environment 'production' - Required reviewers ON (the release gate)"
Write-Host "  3. variables: STAGING_DEPLOY_ENABLED, STAGING_API_URL, PROD_API_URL (BRANCHING.md section 6)"
