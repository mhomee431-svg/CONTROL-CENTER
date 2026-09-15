$ErrorActionPreference = 'Stop'
$root = 'c:\Users\akash\OneDrive\Documents\hyperlocal_customer_app\apps\shopkeeper_app'
Set-Location $root

$all = Get-ChildItem -Recurse -File -Filter *.dart | Where-Object { $_.FullName -notmatch '\\\.dart_tool\\' }

Write-Output '=== A. Who imports the shops/data location stack? ==='
$locFiles = @('directions_service', 'geocoding_service', 'gstin_decoder', 'location_accuracy_config',
  'location_service', 'lookup_repository', 'map_providers_config', 'pincode_api_service',
  'pincode_lookup', 'place_autocomplete_service', 'map_picker_screen')
foreach ($n in $locFiles) {
  $self = "$n.dart"
  $importers = @($all | Select-String -Pattern "import .*$n" | Where-Object { $_.Filename -ne $self })
  $names = ($importers | ForEach-Object { $_.Filename } | Sort-Object -Unique) -join ', '
  Write-Output ("  {0,-28} importedBy=[{1}]" -f $n, $names)
}

Write-Output ''
Write-Output '=== B. Route string literal duplication (literal "/route" occurrences) ==='
$routes = @('/dashboard', '/products', '/notifications', '/account', '/welcome', '/login', '/register',
  '/splash', '/profile-create', '/shop-register', '/shops', '/shop-profile', '/shop-settings',
  '/shop-location', '/scan-barcode', '/inventory-import', '/offers', '/pos', '/insights',
  '/features', '/support', '/account-status', '/forgot-password', '/reset-password')
foreach ($r in $routes) {
  $hits = @($all | Select-String -Pattern ("'" + $r + "'") -SimpleMatch)
  $files = ($hits | ForEach-Object { $_.Filename } | Sort-Object -Unique)
  Write-Output ("  {0,-20} uses={1,3}  files=[{2}]" -f $r, $hits.Count, ($files -join ', '))
}

Write-Output ''
Write-Output '=== C. features/shops/data file sizes ==='
foreach ($f in (Get-ChildItem -File "$root\lib\features\shops\data" | Sort-Object Name)) {
  Write-Output ("  {0,-36} {1,4} lines" -f $f.Name, (Get-Content $f.FullName).Count)
}