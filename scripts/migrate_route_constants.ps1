$ErrorActionPreference = 'Stop'

# ── Migrate every route literal used as a ROUTE REFERENCE to Routes.* ─────────
# Excluded on purpose:
#   route_names.dart  -> holds the canonical literals (self-reference corruption)
#   app_router.dart   -> already migrated; its `path:` values ARE the definitions
$app     = 'c:\Users\akash\OneDrive\Documents\hyperlocal_customer_app\apps\shopkeeper_app'
$libRoot = (Join-Path $app 'lib') + '\'
$q       = [char]39   # single quote
$d       = [char]36   # dollar

# Longest / most-specific first (no real collisions, but ordering is explicit)
$routes = [ordered]@{
  'shop-location'    = 'Routes.shopLocation'
  'shop-profile'     = 'Routes.shopProfile'
  'shop-settings'    = 'Routes.shopSettings'
  'shop-register'    = 'Routes.shopRegister'
  'inventory-import' = 'Routes.inventoryImport'
  'scan-barcode'     = 'Routes.scanBarcode'
  'notifications'    = 'Routes.notifications'
  'profile-create'   = 'Routes.profileCreate'
  'shops'            = 'Routes.shops'
  'insights'         = 'Routes.insights'
  'features'         = 'Routes.features'
  'support'          = 'Routes.support'
  'dashboard'        = 'Routes.dashboard'
  'products'         = 'Routes.products'
  'login'            = 'Routes.login'
  'offers'           = 'Routes.offers'
  'account'          = 'Routes.account'
  'pos'              = 'Routes.pos'
}

$skip = @('route_names.dart', 'app_router.dart')

$files = Get-ChildItem -Recurse -File -Filter *.dart $libRoot |
  Where-Object { $skip -notcontains $_.Name }

$totalEdits = 0

foreach ($f in $files) {
  $text = [System.IO.File]::ReadAllText($f.FullName)
  $orig = $text

  # (1) special case: parameterized drill-down template literal
  $special = $q + '/insights/drill-down/' + $d + '{metric.routeSegment}' + $q
  if ($text.Contains($special)) {
    $text = $text.Replace($special, 'Routes.insightsDrillDown(metric.routeSegment)')
  }

  # (2) flat route literals
  foreach ($key in $routes.Keys) {
    $needle = $q + '/' + $key + $q
    if ($text.Contains($needle)) {
      $text = $text.Replace($needle, $routes[$key])
    }
  }

  if ($text -eq $orig) { continue }

  # (3) ensure the import exists
  if (-not $text.Contains('core/router/route_names.dart')) {
    $rel    = $f.FullName.Substring($libRoot.Length)              # features\shell\x.dart
    $depth  = ($rel.Split('\')).Count - 1
    $prefix = '../' * $depth
    $imp    = 'import ' + $q + $prefix + 'core/router/route_names.dart' + $q + ';'

    $lines = $text -split "`r`n", 0
    $lastPkg = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
      if ($lines[$i] -match "^import 'package:") { $lastPkg = $i }
    }
    if ($lastPkg -lt 0) { throw "no package import anchor in $rel" }

    $out = @()
    $out += $lines[0..$lastPkg]
    $out += $imp
    if ($lastPkg + 1 -lt $lines.Count) { $out += $lines[($lastPkg + 1)..($lines.Count - 1)] }
    $text = ($out -join "`r`n")
    Write-Output ("  + import {0}  -> {1}" -f $imp, $rel)
  }

  [System.IO.File]::WriteAllText($f.FullName, $text)
  $totalEdits++
  Write-Output ("  MIGRATED  {0}" -f $f.FullName.Substring($libRoot.Length))
}

Write-Output ''
Write-Output "files migrated: $totalEdits"