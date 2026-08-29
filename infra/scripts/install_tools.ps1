# One-time toolchain bootstrap for Phase 2 verification (no admin required).
# Downloads portable AWS CLI v2 + Terraform into <repo>/.tools and unzips them.
param(
    [string]$Root = (Join-Path (Split-Path $PSScriptRoot -Parent) ".tools"),
    [string]$Marker = "$PSScriptRoot\.tools-install-ok"
)
$ErrorActionPreference = "Stop"
New-Item -ItemType Directory -Force -Path $Root | Out-Null

# --- AWS CLI v2 (self-contained zip) ---
$awsZip = Join-Path $Root "awscliv2.zip"
if (-not (Test-Path (Join-Path $Root "aws\dist\aws.exe"))) {
    if (-not (Test-Path $awsZip) -or (Get-Item $awsZip).Length -lt 1MB) {
        Invoke-WebRequest -Uri "https://awscli.amazonaws.com/AWSCLIV2.zip" -OutFile $awsZip
    }
    Expand-Archive -Path $awsZip -DestinationPath (Join-Path $Root "aws") -Force
}

# --- Terraform (portable zip) ---
$tfZip = Join-Path $Root "terraform.zip"
if (-not (Test-Path (Join-Path $Root "terraform.exe"))) {
    if (-not (Test-Path $tfZip) -or (Get-Item $tfZip).Length -lt 1MB) {
        Invoke-WebRequest -Uri "https://releases.hashicorp.com/terraform/1.9.8/terraform_1.9.8_windows_amd64.zip" -OutFile $tfZip
    }
    Expand-Archive -Path $tfZip -DestinationPath $Root -Force
}

Set-Content -Path $Marker -Value (Get-Date).ToString("s")
Write-Output "DONE $((Get-ChildItem (Join-Path $Root 'aws\dist\aws.exe')).FullName) ; $((Get-ChildItem (Join-Path $Root 'terraform.exe')).FullName)"