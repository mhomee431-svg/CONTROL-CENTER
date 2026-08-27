# test.ps1 - Run the backend pytest suite.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File scripts/dev/test.ps1
#   powershell -ExecutionPolicy Bypass -File scripts/dev/test.ps1 -Filter foundation
param(
    [string]$Filter = $null
)

$ErrorActionPreference = 'Stop'
$root    = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$backend = Join-Path $root 'Backend'
$py      = Join-Path $backend '.venv\Scripts\python.exe'

if (-not (Test-Path $py)) {
    Write-Host 'No venv yet - run scripts/dev/setup.ps1 first.' -ForegroundColor Yellow
    exit 1
}

$args = @('pytest', '-q')
if ($Filter) { $args += @('-k', $Filter) }

Push-Location $backend
& $py @args
$code = $LASTEXITCODE
Pop-Location
exit $code
