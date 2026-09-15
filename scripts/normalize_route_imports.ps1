# Normalises the route_names.dart import placement.
#
# The earlier migration script inserted `import '.../route_names.dart';`
# immediately after the LAST package import, which put a RELATIVE import inside
# the package-import block (e.g. between `go_router` and the blank separator).
# flutter_lints does not enable `directives_ordering`, so `flutter analyze` stays
# green — but the placement contradicts the project's own convention
# (package block, blank line, relative block).
#
# This script moves the import to the top of the RELATIVE block and is
# idempotent. Line endings are preserved per file.
$ErrorActionPreference = 'Stop'
$base = 'c:\Users\akash\OneDrive\Documents\hyperlocal_customer_app\apps\shopkeeper_app\'

$files = @(
  'lib\features\account\presentation\screens\account_screen.dart',
  'lib\features\auth\presentation\screens\create_profile_screen.dart',
  'lib\features\auth\presentation\screens\register_screen.dart',
  'lib\features\auth\presentation\screens\reset_password_screen.dart',
  'lib\features\barcode\presentation\widgets\barcode_sheets.dart',
  'lib\features\dashboard\presentation\screens\dashboard_screen.dart',
  'lib\features\insights\presentation\screens\insights_drill_down_screen.dart',
  'lib\features\notifications\presentation\screens\notifications_screen.dart',
  'lib\features\products\presentation\widgets\product_sheets.dart',
  'lib\features\products\presentation\screens\products_screen.dart',
  'lib\features\shell\all_features_screen.dart',
  'lib\features\shops\presentation\screens\shops_screen.dart',
  'lib\features\shop_registration\presentation\screens\shop_registration_wizard.dart'
)

foreach ($rel in $files) {
  $path = $base + $rel
  $raw = [System.IO.File]::ReadAllText($path)
  $crlf = $raw.Contains("`r`n")
  $lines = $raw -split "`n"
  $eol = if ($crlf) { "`r" } else { '' }

  # 1. locate + remove any existing route_names import
  $importLine = $null
  $kept = New-Object System.Collections.Generic.List[string]
  foreach ($l in $lines) {
    if ($l.Trim() -match "^import\s+'[^']*route_names\.dart';$") {
      if ($null -eq $importLine) { $importLine = $l.Trim() + $eol }
      continue
    }
    $kept.Add($l)
  }
  if ($null -eq $importLine) {
    Write-Output ("  SKIP  {0}  (no route_names import)" -f $rel)
    continue
  }

  # 2. last package import + the blank line that closes that block
  $lastPkg = -1
  for ($i = 0; $i -lt $kept.Count; $i++) {
    if ($kept[$i].TrimStart().StartsWith("import 'package:")) { $lastPkg = $i }
  }
  if ($lastPkg -lt 0) {
    Write-Output ("  SKIP  {0}  (no package imports)" -f $rel)
    continue
  }
  $blank = -1
  for ($i = $lastPkg + 1; $i -lt $kept.Count; $i++) {
    if ($kept[$i].Trim() -eq '') { $blank = $i; break }
    if (-not $kept[$i].TrimStart().StartsWith('import ')) { break }
  }
  if ($blank -lt 0) {
    Write-Output ("  SKIP  {0}  (no blank line after package block)" -f $rel)
    continue
  }

  # 3. insert as the FIRST relative import (right after the blank separator)
  $kept.Insert($blank + 1, $importLine)
  [System.IO.File]::WriteAllText($path, ($kept -join "`n"))
  Write-Output ("  OK    {0}  (moved to relative block, crlf={1})" -f $rel, $crlf)
}
Write-Output 'done.'