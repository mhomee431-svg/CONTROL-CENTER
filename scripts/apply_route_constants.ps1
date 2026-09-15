param([Parameter(Mandatory)][string[]]$Files)
$ErrorActionPreference = 'Stop'

# Map of literal route strings to Routes.* constant names.
# Each entry: @{ literal = constant }
$map = @{
  "'/splash'"            = 'Routes.splash'
  "'/welcome'"           = 'Routes.welcome'
  "'/login'"             = 'Routes.login'
  "'/register'"          = 'Routes.register'
  "'/forgot-password'"   = 'Routes.forgotPassword'
  "'/reset-password'"    = 'Routes.resetPassword'
  "'/profile-create'"    = 'Routes.profileCreate'
  "'/account-status'"    = 'Routes.accountStatus'
  "'/shop-register'"     = 'Routes.shopRegister'
  "'/shops'"             = 'Routes.shops'
  "'/shop-profile'"      = 'Routes.shopProfile'
  "'/shop-settings'"     = 'Routes.shopSettings'
  "'/shop-location'"     = 'Routes.shopLocation'
  "'/scan-barcode'"      = 'Routes.scanBarcode'
  "'/inventory-import'"  = 'Routes.inventoryImport'
  "'/offers'"            = 'Routes.offers'
  "'/pos'"               = 'Routes.pos'
  "'/insights'"          = 'Routes.insights'
  "'/features'"          = 'Routes.features'
  "'/support'"           = 'Routes.support'
  "'/dashboard'"         = 'Routes.dashboard'
  "'/products'"          = 'Routes.products'
  "'/notifications'"     = 'Routes.notifications'
  "'/account'"           = 'Routes.account'
}

# Special case: the drill-down dynamic route. Replace
#   '/insights/drill-down/${metric.routeSegment}'
#   -> Routes.insightsDrillDown(metric.routeSegment)
$drillDownOld = "'/insights/drill-down/\$" + "{metric.routeSegment}'"
$drillDownNew = 'Routes.insightsDrillDown(metric.routeSegment)'

$root = 'C:\Users\akash\OneDrive\Documents\hyperlocal_customer_app\apps\shopkeeper_app'
foreach ($rel in $Files) {
  $full = Join-Path $root $rel
  if (-not (Test-Path $full)) { Write-Output "SKIP (not found): $rel"; continue }
  $c = Get-Content -Encoding UTF8 $full
  # Track if import needed
  $needsImport = $false
  $importLine = "import '../../../../core/router/route_names.dart';"
  # Determine import path depth from file location
  $depth = ($rel -split '\\').Count - 1  # number of subdir segments
  # files are under lib/features/... so relative import is ../../../../core/router for 4-deep
  # Compute: from lib/features/X/presentation/screens/ → ../../../core
  $importPath = '../../../../core/router/route_names.dart'
  if ($c -notcontains $importLine) {
    # try alternate depths
    $parts = $rel -split '\\'
    $coreIdx = $parts.IndexOf('features')
    # lib/features/... → need to go up to lib, then core/router
    $upsToLib = ($parts.Count - $coreIdx)  # segments after features
    $importPath = ('../' * ($upsToLib + 1)) + 'core/router/route_names.dart'
    $importLine = "import '$importPath';"
  }
  $changed = $false
  for ($i = 0; $i -lt $c.Count; $i++) {
    if ($c[$i] -eq $drillDownOld) {
      $c[$i] = $c[$i] -replace [regex]::Escape($drillDownOld), $drillDownNew
      $needsImport = $true; $changed = $true
    }
    foreach ($kv in $map.GetEnumerator()) {
      if ($c[$i] -match [regex]::Escape($kv.Key)) {
        $c[$i] = $c[$i] -replace [regex]::Escape($kv.Key), $kv.Value
        $needsImport = $true; $changed = $true
      }
    }
  }
  if ($needsImport -and ($c | Where-Object { $_ -match "route_names.dart" }).Count -eq 0) {
    # insert import after the last existing import that starts with package or relative
    $insertAt = 0
    for ($i = 0; $i -lt $c.Count; $i++) {
      if ($c[$i] -match "^import ") { $insertAt = $i + 1 }
      elseif ($c[$i] -match '^\s*$' -and $insertAt -gt 0) { break }
    }
    $c = $c[0..$insertAt] + $importLine + $c[($insertAt + 1)..($c.Count - 1)]
  }
  if ($changed) {
    Set-Content -Encoding UTF8 -Path $full -Value $c
    Write-Output "UPDATED: $rel"
  } else {
    Write-Output "UNCHANGED: $rel"
  }
}
