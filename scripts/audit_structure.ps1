$ErrorActionPreference = 'Stop'
$root = 'c:\Users\akash\OneDrive\Documents\hyperlocal_app\apps\shopkeeper_app'
Set-Location $root

$all = Get-ChildItem -Recurse -File -Filter *.dart | Where-Object { $_.FullName -notmatch '\\\.dart_tool\\' }
$libPrefix = Join-Path $root 'lib'
$libPrefix = $libPrefix + '\'
$libFiles = @($all | Where-Object { $_.FullName -match '\\lib\\' })

function RelLib($f) {
  $p = $f.FullName.Substring($libPrefix.Length)
  return $p.Replace('\', '/')
}

Write-Output "DART FILES: $($all.Count)   (lib: $($libFiles.Count))"
Write-Output ''
Write-Output '=== 1. ORPHANS - files never imported (by name) from any dart file ==='
$orphans = 0
$orphanLines = 0
foreach ($f in ($libFiles | Sort-Object FullName)) {
  $needle = $f.Name   # e.g. location_service.dart - matches BOTH relative and package imports
  $importers = @($all | Select-String -Pattern $needle -SimpleMatch | Where-Object { $_.Path -ne $f.FullName })
  if ($importers.Count -eq 0) {
    $n = (Get-Content $f.FullName).Count
    $orphans++
    $orphanLines += $n
    Write-Output ("  ORPHAN  {0}   ({1} lines)" -f (RelLib $f), $n)
  }
}
Write-Output ("  --> {0} orphaned files, {1} lines total" -f $orphans, $orphanLines)

Write-Output ''
Write-Output '=== 2. FEATURE LAYER CONFORMANCE (data / domain / presentation) ==='
$features = Get-ChildItem -Directory "$root\lib\features" | Sort-Object Name
foreach ($feat in $features) {
  $subs = @(Get-ChildItem -Directory $feat.FullName | Select-Object -ExpandProperty Name)
  $rootFiles = @(Get-ChildItem -File $feat.FullName | Select-Object -ExpandProperty Name)
  $layers = @()
  foreach ($l in @('data', 'domain', 'presentation')) { if ($subs -contains $l) { $layers += $l } }
  $flag = ''
  if ($rootFiles.Count -gt 0) { $flag += ' LOOSE_FILES' }
  if (($subs -contains 'controllers') -or ($subs -contains 'screens') -or ($subs -contains 'widgets')) { $flag += ' FLAT_LAYERS' }
  $missing = @()
  foreach ($l in @('data', 'domain', 'presentation')) { if ($layers -notcontains $l) { $missing += $l } }
  if ($missing.Count -gt 0) { $flag += " MISSING($($missing -join ','))" }
  Write-Output ("  {0,-20} layers=[{1}] subdirs=[{2}] rootFiles=[{3}]{4}" -f $feat.Name, ($layers -join ','), ($subs -join ','), ($rootFiles -join ','), $flag)
}

Write-Output ''
Write-Output '=== 3. core/ INVENTORY ==='
foreach ($f in (Get-ChildItem -Recurse -File "$root\lib\core" | Sort-Object FullName)) {
  Write-Output ("  lib/core/{0,-52} {1,5} lines" -f (RelLib $f).Replace('core/', ''), (Get-Content $f.FullName).Count)
}