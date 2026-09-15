$ErrorActionPreference = 'Stop'
$root = 'c:\Users\akash\OneDrive\Documents\hyperlocal_customer_app\apps\shopkeeper_app'
Set-Location $root
$all = Get-ChildItem -Recurse -File -Filter *.dart lib,test

Write-Output '=== A. ApiEndpoints members: declared vs actually CALLED ==='
$epFile = 'lib\core\network\api_endpoints.dart'
$src = Get-Content $epFile -Raw
$names = [regex]::Matches($src, 'static\s+(?:const\s+)?String\s+(\w+)\s*[=(]') |
  ForEach-Object { $_.Groups[1].Value }
foreach ($n in ($names | Sort-Object -Unique)) {
  $uses = @($all | Select-String -Pattern "ApiEndpoints\.$n\b")
  # exclude the declaration file itself
  $ext = @($uses | Where-Object { $_.Filename -ne 'api_endpoints.dart' })
  if ($ext.Count -eq 0) {
    Write-Output ("  UNUSED   ApiEndpoints.{0}" -f $n)
  } else {
    $files = ($ext | ForEach-Object { $_.Filename } | Sort-Object -Unique) -join ', '
    Write-Output ("  used({0,2})  ApiEndpoints.{1,-30} [{2}]" -f $ext.Count, $n, $files)
  }
}