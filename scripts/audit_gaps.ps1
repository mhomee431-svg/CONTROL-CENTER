# audit_gaps.ps1 — read-only completeness audit for the Shopkeeper Flutter app.
# Reports: orphan lib files, unused/undeclared ApiEndpoints, dead route constants.
# Writes NOTHING except stdout.

$app = Join-Path $PSScriptRoot '..\apps\shopkeeper_app'
Set-Location $app

$dart = Get-ChildItem lib, test -Recurse -File -Filter *.dart
$importLines = $dart | Select-String -Pattern "^import '"

Write-Output '=== ORPHAN lib FILES (no file imports them) ==='
foreach ($f in (Get-ChildItem lib -Recurse -File -Filter *.dart)) {
  if ($f.Name -in @('main.dart', 'app.dart', 'firebase_options.dart')) { continue }
  $base = $f.BaseName
  $hits = ($importLines | Where-Object {
      $_.Path -ne $f.FullName -and $_.Line -like "*$base.dart*"
    }).Count
  if ($hits -eq 0) { Write-Output ("  ORPHAN: " + $f.FullName.Replace((Get-Location).Path + '\', '')) }
}

Write-Output ''
Write-Output '=== ROUTE CONSTANTS NEVER REFERENCED OUTSIDE route_names.dart ==='
$routeNames = Get-ChildItem lib -Recurse -File -Filter route_names.dart
$others = $dart | Where-Object { $_.FullName -ne $routeNames.FullName }
foreach ($m in (Select-String -Path $routeNames.FullName -Pattern 'static (?:const|String) (\w+)').Matches) {
  $name = $m.Groups[1].Value
  $used = ($others | Select-String -Pattern ("Routes\." + $name + "\b")).Count
  if ($used -eq 0) { Write-Output "  UNUSED: Routes.$name" }
}

Write-Output ''
Write-Output '=== ApiEndpoints MEMBERS WITH NO CALL SITE ==='
$ep = Get-ChildItem lib -Recurse -File -Filter api_endpoints.dart
$epOthers = $dart | Where-Object { $_.FullName -ne $ep.FullName }
foreach ($m in (Select-String -Path $ep.FullName -Pattern 'static (?:const|String) (\w+)').Matches) {
  $name = $m.Groups[1].Value
  $used = ($epOthers | Select-String -Pattern ("ApiEndpoints\." + $name + "\b")).Count
  if ($used -eq 0) { Write-Output "  UNCALLED: ApiEndpoints.$name" }
}

Write-Output ''
Write-Output '=== HARDCODED URL LITERALS IN FEATURES ==='
Get-ChildItem lib\features -Recurse -File -Filter *.dart |
  Select-String -SimpleMatch '/api/v1' |
  ForEach-Object { Write-Output ("  " + $_.Path.Replace((Get-Location).Path + '\', '') + ':' + $_.LineNumber + '  ' + $_.Line.Trim()) }

Write-Output ''
Write-Output '=== SUSPECT FAKE / SAMPLE DATA ==='
Get-ChildItem lib -Recurse -File -Filter *.dart |
  Select-String -Pattern 'Lorem|Sample |sampleProduct|dummyData|hardcoded' |
  ForEach-Object { Write-Output ("  " + $_.Path.Replace((Get-Location).Path + '\', '') + ':' + $_.LineNumber + '  ' + $_.Line.Trim()) }