$ErrorActionPreference = 'Stop'
$root = 'c:\Users\akash\OneDrive\Documents\hyperlocal_app\apps\shopkeeper_app'
Set-Location $root

$files = Get-ChildItem -Recurse -File -Filter *.dart lib, test

Write-Output '=== A. Dead "/" route literals (go/push/replace to bare slash) ==='
$hit = 0
foreach ($f in $files) {
  $i = 0
  foreach ($line in (Get-Content -Encoding UTF8 $f.FullName)) {
    $i++
    if ($line -match "(go|push|replace)\(" -and $line -match "['""]/['""]") {
      $hit++
      Write-Output ("  {0}:{1}: {2}" -f $f.Name, $i, $line.Trim())
    }
  }
}
if ($hit -eq 0) { Write-Output '  (none)' }

Write-Output ''
Write-Output '=== B. Routes.* constant usage count per file ==='
foreach ($f in (Get-ChildItem -Recurse -File -Filter *.dart lib)) {
  $c = (Select-String -Path $f.FullName -SimpleMatch 'Routes.').Count
  if ($c -gt 0) { Write-Output ("  {0,-52} {1,3}" -f $f.Name, $c) }
}

Write-Output ''
Write-Output '=== C. Any remaining hardcoded route literal in lib (excluding route_names.dart) ==='
$names = @('/dashboard','/products','/notifications','/account','/welcome','/login','/register',
  '/splash','/profile-create','/shop-register','/shops','/shop-profile','/shop-settings',
  '/shop-location','/scan-barcode','/inventory-import','/offers','/pos','/insights',
  '/features','/support','/account-status','/forgot-password','/reset-password','/insights/drill-down')
$found = 0
foreach ($f in (Get-ChildItem -Recurse -File -Filter *.dart lib)) {
  if ($f.Name -eq 'route_names.dart') { continue }
  foreach ($n in $names) {
    $m = Select-String -Path $f.FullName -SimpleMatch ("'" + $n + "'")
    foreach ($x in $m) {
      $found++
      Write-Output ("  {0}:{1}: {2}" -f $f.Name, $x.LineNumber, $x.Line.Trim())
    }
  }
}
if ($found -eq 0) { Write-Output '  (none - all navigation uses Routes.* constants)' }