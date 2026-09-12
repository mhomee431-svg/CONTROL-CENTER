# live_reload.ps1 — Send a keystroke to a running `flutter run` live session
# started by live_run.ps1.
# ------------------------------------------------------------------------------
# Usage:
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts\dev\live_reload.ps1 `
#     -Name shopkeeper           # same -Name used with live_run.ps1
#     -Key R                     # r = hot reload, R = hot restart, q = quit
# ------------------------------------------------------------------------------

param(
    [Parameter(Mandatory = $true)][string]$Name,
    [string]$Key = "r"
)

$cmdFile = Join-Path $env:TEMP "hls_live_${Name}.cmd"
if (-not (Test-Path $cmdFile)) {
    Write-Error "Live session '$Name' is not running (missing $cmdFile). Start it with live_run.ps1 first."
    exit 1
}

Set-Content -Path $cmdFile -Value $Key -ErrorAction Stop
Write-Host "Sent [$Key] to live session '$Name'."