# device_shop_location_test.ps1 - On-device verification of the shop-location
# capture flow: real GPS fix, permission dialog, manual correction, drift prompt.
#
# The script drives everything adb can drive (install, launch, permission
# grant/revoke, GPS on/off, logcat evidence) and prints the checkpoints that
# need a human tap. Full protocol: docs/testing/SHOP_LOCATION_DEVICE_TEST.md
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File scripts/dev/device_shop_location_test.ps1
#   powershell -ExecutionPolicy Bypass -File scripts/dev/device_shop_location_test.ps1 -DeviceId TKIBRWQO8P7P7LGQ -SkipBuild
#   powershell -ExecutionPolicy Bypass -File scripts/dev/device_shop_location_test.ps1 -Scenario gpsOn
param(
    [string]$DeviceId = $null,
    [switch]$SkipBuild,
    [string]$ApiBaseUrl = 'http://127.0.0.1:8000',
    [ValidateSet('all', 'permissionDenied', 'gpsOn', 'gpsOff')]
    [string]$Scenario = 'all',
    [int]$WaitSeconds = 30
)

$ErrorActionPreference = 'Stop'

$root   = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$app    = Join-Path $root 'apps\shopkeeper_app'
$apk    = Join-Path $app 'build\app\outputs\flutter-apk\app-debug.apk'
$outDir = Join-Path $root 'build\device-shop-location'
$pkg    = 'com.hyperlocal.app'
$activity = 'com.hyperlocal.hyperlocal_shopkeeper_app.MainActivity'
$fine   = 'android.permission.ACCESS_FINE_LOCATION'
$coarse = 'android.permission.ACCESS_COARSE_LOCATION'

function Resolve-Adb {
    $candidate = Join-Path $env:LOCALAPPDATA 'Android\Sdk\platform-tools\adb.exe'
    if (Test-Path $candidate) { return $candidate }
    $cmd = Get-Command adb -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    throw 'adb not found. Install Android platform-tools or add adb to PATH.'
}

$adb = Resolve-Adb

function Get-Devices {
    $lines = (& $adb devices) | Select-Object -Skip 1
    return @($lines | Where-Object { $_ -match '\sdevice$' } |
        ForEach-Object { ($_ -split '\s+')[0] })
}

$devices = Get-Devices
if ($devices.Count -eq 0) {
    Write-Host 'No Android device detected.' -ForegroundColor Red
    Write-Host '  1. Connect the phone over USB.'
    Write-Host '  2. Settings > Developer options > USB debugging = ON.'
    Write-Host '  3. Accept the "Allow USB debugging" prompt on the phone.'
    Write-Host '  4. Re-run this script.'
    exit 1
}

$device = if ($DeviceId) { $DeviceId } else { $devices[0] }
if ($devices -notcontains $device) {
    Write-Host "Device '$device' not found. Connected: $($devices -join ', ')" -ForegroundColor Red
    exit 1
}

function Adb {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$AdbArgs)
    return (& $adb -s $device @AdbArgs)
}

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
New-Item -ItemType Directory -Path $outDir -Force | Out-Null

Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ' Shop-location on-device test' -ForegroundColor Cyan
Write-Host " device : $device" -ForegroundColor Cyan
Write-Host " api    : $ApiBaseUrl" -ForegroundColor Cyan
Write-Host " output : $outDir" -ForegroundColor Cyan
Write-Host '============================================================' -ForegroundColor Cyan

# ── Build & install ──────────────────────────────────────────────────────────
if (-not $SkipBuild) {
    Write-Host "`nBuilding debug APK (SHOPKEEPER_API_BASE_URL=$ApiBaseUrl)..." -ForegroundColor Yellow
    Push-Location $app
    & flutter build apk --debug "--dart-define=SHOPKEEPER_API_BASE_URL=$ApiBaseUrl"
    $buildCode = $LASTEXITCODE
    Pop-Location
    if ($buildCode -ne 0) { Write-Host 'Build failed.' -ForegroundColor Red; exit $buildCode }
}
if (-not (Test-Path $apk)) {
    Write-Host "APK missing: $apk (run without -SkipBuild)" -ForegroundColor Red
    exit 1
}

Write-Host "`nInstalling APK..." -ForegroundColor Yellow
& $adb -s $device install -r $apk
if ($LASTEXITCODE -ne 0) { Write-Host 'Install failed.' -ForegroundColor Red; exit 1 }

# A physical device reaches the dev backend through the USB reverse tunnel.
& $adb -s $device reverse 'tcp:8000' 'tcp:8000' | Out-Null

function Set-LocationMode {
    param([int]$Mode)
    Adb shell settings put secure location_mode $Mode | Out-Null
    $now = (Adb shell settings get secure location_mode) -join ''
    Write-Host "  GPS location_mode = $($now.Trim())"
}

function Set-Permission {
    param([switch]$Grant)
    foreach ($perm in @($fine, $coarse)) {
        if ($Grant) { Adb shell pm grant $pkg $perm | Out-Null }
        else {
            # Ignore failures: a permission the app never requested cannot be revoked.
            Adb shell pm revoke $pkg $perm 2>&1 | Out-Null
        }
    }
    $state = (Adb shell dumpsys package $pkg |
        Select-String -Pattern "$([regex]::Escape($fine)): granted=(true|false)") -join ' '
    Write-Host "  $($state.Trim())"
}

$results = New-Object System.Collections.Generic.List[object]

function Invoke-Scenario {
    param(
        [string]$Name,
        [scriptblock]$Prepare,
        [string]$HumanSteps,
        [string[]]$Expect = @(),
        [string[]]$Forbid = @()
    )
    Write-Host "`n=== $Name ===" -ForegroundColor Cyan
    & $Prepare
    Start-Sleep -Seconds 2
    Adb shell am force-stop $pkg | Out-Null
    Adb logcat -c | Out-Null
    Adb shell am start -n "$pkg/$activity" | Out-Null
    Start-Sleep -Seconds 5

    Write-Host $HumanSteps -ForegroundColor Yellow
    Read-Host '  Press Enter when the on-screen result is visible'

    $log = (Adb logcat -d -v brief) -join "`n"
    $logFile = Join-Path $outDir ("$stamp-" + ($Name -replace '[^A-Za-z0-9]+', '_') + '.log')
    Set-Content -Path $logFile -Value $log -Encoding UTF8

    $missing = @($Expect | Where-Object { $log -notmatch $_ })
    $leaked = @($Forbid | Where-Object { $log -match $_ })
    $ok = ($missing.Count -eq 0) -and ($leaked.Count -eq 0)

    if ($ok) { Write-Host "  PASS  (log: $logFile)" -ForegroundColor Green }
    else {
        Write-Host "  FAIL  (log: $logFile)" -ForegroundColor Red
        foreach ($m in $missing) { Write-Host "    missing evidence: $m" -ForegroundColor Red }
        foreach ($l in $leaked) { Write-Host "    unexpected evidence: $l" -ForegroundColor Red }
    }
    $results.Add([pscustomobject]@{
        Scenario = $Name
        Result   = if ($ok) { 'PASS' } else { 'FAIL' }
        Log      = $logFile
    })
}

$runAll = ($Scenario -eq 'all')

try {
    if ($runAll -or $Scenario -eq 'permissionDenied') {
        Invoke-Scenario -Name 'permissionDenied' -Prepare {
            Write-Host '  revoking location permissions' -ForegroundColor DarkGray
            Set-Permission
            Set-LocationMode -Mode 3
        } -HumanSteps @'
  Now on the phone:
    1. Sign in, open "Register Your Shop" and reach step 3 "Shop Location".
    2. Tap "Get Current Location".
    3. When Android asks, tap DENY.
  Expected UI: "Permission denied" card with Retry; no coordinates shown.
'@ -Expect @(
            '\[LOC\] serviceEnabled=true',
            '\[LOC\] requestPermission=LocationPermission\.denied',
            '\[STARTUP\] API Base URL'
        )
    }

    if ($runAll -or $Scenario -eq 'gpsOn') {
        Invoke-Scenario -Name 'gpsOn' -Prepare {
            Write-Host '  granting location permissions' -ForegroundColor DarkGray
            Set-Permission -Grant
            Set-LocationMode -Mode 3
        } -HumanSteps @'
  Now on the phone:
    1. Reach step 3 "Shop Location" again and tap "Get Current Location".
    2. Allow the permission prompt (Precise location ON).
    3. Wait until the map step shows the accuracy chip.
  Expected UI: "Location found" + a real accuracy radius (e.g. "Accuracy: 7 m"),
  never "100% accurate"; pin + coordinate fields filled.
'@ -Expect @(
            '\[LOC\] checkPermission=LocationPermission\.(whileInUse|always)',
            '\[LOC\] (Using last-known position|Fresh GPS fix:)',
            '\[LOC\] acquireBestLocation started'
        )
    }

    if ($runAll -or $Scenario -eq 'gpsOff') {
        Invoke-Scenario -Name 'gpsOff' -Prepare {
            Write-Host '  permission granted, device GPS turned off' -ForegroundColor DarkGray
            Set-Permission -Grant
            Set-LocationMode -Mode 0
        } -HumanSteps @'
  Now on the phone:
    1. Reach step 3 "Shop Location" and tap "Get Current Location".
  Expected UI: "Location services are turned off. Please enable GPS and try again."
  with Retry; no coordinates, no fabricated fix.
'@ -Expect @('\[LOC\] serviceEnabled=false') -Forbid @('\[LOC\] Fresh GPS fix:')
    }
}
finally {
    Write-Host "`nRestoring device state..." -ForegroundColor DarkGray
    Set-LocationMode -Mode 3
    Set-Permission -Grant
    Adb shell am force-stop $pkg | Out-Null
}

Write-Host "`n================ RESULT ================" -ForegroundColor Cyan
$results | Format-Table -AutoSize
$results | ConvertTo-Json -Depth 4 |
    Set-Content (Join-Path $outDir "$stamp-result.json") -Encoding UTF8

Write-Host @'

Hands-on checkpoints adb cannot assert (verify visually, log them in the doc):
  [ ] Map tiles render (requires MAPS_API_KEY - see docs/testing/SHOP_LOCATION_DEVICE_TEST.md)
  [ ] "Getting location..." spinner, then "Location found"
  [ ] Accuracy shown as a real radius + tier, never "100% accurate"
  [ ] Drag the shop pin >150 m away -> "This pin is about N m away ..." prompt
  [ ] "Yes, this is my shop entrance" -> Next is allowed
  [ ] Manual Latitude/Longitude entry applies the pin (map + fields agree)
  [ ] Adjusted pin shows "Location accuracy: unknown for the adjusted pin"
  [ ] Address text stays editable and does not move the pin
'@ -ForegroundColor Yellow

if ($results.Result -contains 'FAIL') { exit 1 }
exit 0
