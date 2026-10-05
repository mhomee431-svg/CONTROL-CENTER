<#
.SYNOPSIS
    Pre-flight check for Firebase Phone Auth - the parts verifiable WITHOUT a
    physical device.

.DESCRIPTION
    Firebase Phone Auth has platform requirements that fail late and quietly: a
    wrong SHA fingerprint means the SMS is delivered but never auto-filled, which
    looks identical to "the SMS is slow". This turns the locally-checkable
    items into one repeatable command, to be re-run after every keystore
    rotation or Console change rather than rediscovered on a customer's phone.

    It does NOT create, modify or repair anything. It only reports.

    It CANNOT check, and this matters:
      * whether the "Phone" provider is ENABLED in the Firebase Console;
      * whether a real device receives and auto-fills an SMS;
      * quota. Phone Auth is metered, and a silent failure after ~10 daily SMS
        is a quota block, not a bug.
    If no keystore exists, the SHA check reports SKIPPED, which is NOT a pass.

.PARAMETER AppRoot
    Path to the customer_app package. Defaults to one level up.
#>
[CmdletBinding()]
param(
    # Left null deliberately: `$PSScriptRoot` is not reliably populated inside a
    # `param()` default when the script is launched via `powershell -File`, which
    # produced "Cannot bind argument to parameter 'Path' because it is an empty
    # string" before the script body ever ran. Resolved below instead.
    [string]$AppRoot = ''
)

if ([string]::IsNullOrWhiteSpace($AppRoot)) {
    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
    $AppRoot = (Resolve-Path (Join-Path $scriptDir '..')).Path
}

$results = @()
function Add-Result($Check, $Status, $Detail) {
    $script:results += [PSCustomObject]@{ Check = $Check; Status = $Status; Detail = $Detail }
}

Write-Host "Firebase Phone Auth pre-flight`nApp root: $AppRoot`n" -ForegroundColor Cyan

#  1. Dart packages 
$pubspecPath = Join-Path $AppRoot 'pubspec.yaml'
$pubspec = if (Test-Path $pubspecPath) { Get-Content $pubspecPath -Raw } else { '' }
foreach ($pkg in @('firebase_core', 'firebase_auth', 'firebase_messaging')) {
    $ok = $pubspec -match "$pkg\s*:"
    Add-Result 'package' $(if ($ok) { 'PASS' } else { 'FAIL' }) "$pkg declared: $ok"
}

#  2. Android google-services.json 
$gjPath = Join-Path $AppRoot 'android\app\google-services.json'
$gj = $null
if (-not (Test-Path $gjPath)) {
    Add-Result 'android.config' 'FAIL' 'google-services.json MISSING - the Gradle plugin has nothing to read'
} else {
    $raw = Get-Content $gjPath -Raw
    $gj = $raw | ConvertFrom-Json
    $client = $gj.client[0]
    $apiKey = $client.api_key[0].current_key
    Add-Result 'android.config' 'PASS' "project=$($gj.project_info.project_id)"
    Add-Result 'android.package' 'PASS' $client.client_info.android_client_info.package_name
    Add-Result 'android.apiKey' $(if ($apiKey) { 'PASS' } else { 'FAIL' }) 'Identity Toolkit key present'

    # A client AIza key ships in every build by design; a service-account
    # private_key must never be in the repo.
    $isAdmin = ($raw -match '"private_key"') -or ($raw -match '"type"\s*:\s*"service_account"')
    Add-Result 'android.credentials' $(if ($isAdmin) { 'FAIL' } else { 'PASS' }) `
        'client config only, no Admin service account'
}

#  3. Gradle wiring 
$appGradlePath = Join-Path $AppRoot 'android\app\build.gradle.kts'
$settingsPath = Join-Path $AppRoot 'android\settings.gradle.kts'
if (Test-Path $appGradlePath) {
    $g = Get-Content $appGradlePath -Raw
    Add-Result 'android.plugin' $(if ($g -match 'com\.google\.gms\.google-services') { 'PASS' } else { 'FAIL' }) `
        'plugin applied in app module'
    Add-Result 'android.sdk' $(if ($g -match 'com\.google\.firebase:firebase-auth') { 'PASS' } else { 'FAIL' }) `
        'firebase-auth dependency declared'

    $minSdk = [regex]::Match($g, 'minSdk\s*=\s*maxOf\(flutter\.minSdkVersion,\s*(\d+)\)').Groups[1].Value
    Add-Result 'android.minSdk' $(if ($minSdk -and [int]$minSdk -ge 23) { 'PASS' } else { 'FAIL' }) `
        "minSdk=$minSdk (Firebase Auth needs >= 23)"
}
if (Test-Path $settingsPath) {
    $s = Get-Content $settingsPath -Raw
    Add-Result 'android.pluginClasspath' $(if ($s -match 'com\.google\.gms\.google-services') { 'PASS' } else { 'FAIL' }) `
        'plugin version resolved in settings'
}
#  4. SHA fingerprints 
# The check that most often fails silently. Auto-retrieval matches the SHA of
# the SIGNING KEY, so a release build on a new upload key receives the SMS and
# still makes the customer type the code by hand - which reads as "SMS slow"
# rather than "SHA not registered".
$registeredShas = @()
if ($gj) {
    foreach ($oc in $gj.client[0].oauth_client) {
        if ($oc.android_info.certificate_hash) {
            $registeredShas += $oc.android_info.certificate_hash.ToUpper()
        }
    }
}
Add-Result 'sha.registered' $(if ($registeredShas.Count -gt 0) { 'PASS' } else { 'FAIL' }) `
    "$($registeredShas.Count) fingerprint(s) in google-services.json"

$keystoreCandidates = @()
$debugKs = Join-Path $env:USERPROFILE '.android\debug.keystore'
if (Test-Path $debugKs) { $keystoreCandidates += @{ Name = 'debug'; Path = $debugKs } }

$gradleProps = Join-Path $AppRoot 'android\key.properties'
if (Test-Path $gradleProps) {
    $storeFileLine = Get-Content $gradleProps | Where-Object { $_ -match '^storeFile' } | Select-Object -First 1
    if ($storeFileLine) {
        $sf = ($storeFileLine -split '=', 2)[1].Trim()
        $resolved = Join-Path $AppRoot "android\$sf"
        if (Test-Path $resolved) {
            $keystoreCandidates += @{ Name = 'release'; Path = $resolved }
        }
    }
}

if ($keystoreCandidates.Count -eq 0) {
    Add-Result 'sha.match' 'SKIP' `
        'no keystore to compare - build once (creates debug.keystore) or add android/key.properties. SKIPPED is NOT a pass.'
} else {
    foreach ($ks in $keystoreCandidates) {
        $actual = @()
        foreach ($pw in @('android', '')) {
            $out = if ($pw) { & keytool -list -v -keystore $ks.Path -storepass $pw -alias androiddebugkey 2>$null } else { & keytool -list -v -keystore $ks.Path 2>$null }
            if ($out) {
                foreach ($line in $out) {
                    if ($line -match '(SHA1|SHA256):\s*([0-9A-Fa-f:]+)') {
                        $actual += $Matches[2].ToUpper().Replace(':', '')
                    }
                }
            }
            if ($actual.Count -gt 0) { break }
        }
        $matched = @($actual | Where-Object { $registeredShas -contains $_ })
        if ($matched.Count -gt 0) {
            Add-Result "sha.match.$($ks.Name)" 'PASS' "$($ks.Name) key is registered: $($matched -join ', ')"
        } else {
            Add-Result "sha.match.$($ks.Name)" 'FAIL' `
                "$($ks.Name) fingerprints ($($actual -join ', ')) are NOT registered - auto-retrieval will silently not fire"
        }
    }
}

#  5. iOS 
$iosPlist = Join-Path $AppRoot 'ios\Runner\GoogleService-Info.plist'
$opts = Join-Path $AppRoot 'lib\firebase_options.dart'
$iosReady = (Test-Path $iosPlist) -or (Test-Path $opts)
Add-Result 'ios.config' $(if ($iosReady) { 'PASS' } else { 'FAIL' }) `
    $(if ($iosReady) { 'iOS Firebase config found' } else {
        'NO GoogleService-Info.plist and NO lib/firebase_options.dart - Firebase.initializeApp() throws on iOS'
    })

#  6. Report 
$results | Format-Table -AutoSize -Wrap
$failed = @($results | Where-Object { $_.Status -eq 'FAIL' })
$skipped = @($results | Where-Object { $_.Status -eq 'SKIP' })

Write-Host ''
if ($failed.Count -gt 0) {
    Write-Host "RESULT: $($failed.Count) check(s) FAILED" -ForegroundColor Red
} else {
    Write-Host 'RESULT: all local checks passed' -ForegroundColor Green
}
if ($skipped.Count -gt 0) {
    Write-Host "$($skipped.Count) check(s) SKIPPED (unknown, not passing)" -ForegroundColor Yellow
}

Write-Host @'

STILL REQUIRES A HUMAN - this script cannot check these:

  [ ] Firebase Console: is the "Phone" sign-in provider ENABLED?
      (Authentication > Sign-in method > Phone)
  [ ] Real device: does the SMS arrive, and is it AUTO-FILLED?
      Needs a physical handset + real SIM. Test a RELEASE build too: auto-
      retrieval matches the UPLOAD key's SHA, not the debug key's.
  [ ] Real device: quota. Phone Auth is metered; failure after ~10 daily SMS
      is a quota block, not a bug.
  [ ] Play Console: SHA-1 under App Integrity / Device Verification, if used.
'@ -ForegroundColor Yellow

    $minSdk = [regex]::Match($g, 'minSdk\s*=\s*maxOf\(flutter\.minSdkVersion,\s*(\d+)\)').Groups[1].Value
    Add-Result 'android.minSdk' $(if ($minSdk -and [int]$minSdk -ge 23) { 'PASS' } else { 'FAIL' }) `
        "minSdk=$minSdk (Firebase Auth needs >= 23)"
