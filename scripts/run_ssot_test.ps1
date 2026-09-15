$ErrorActionPreference = 'Continue'
$root = 'c:\Users\akash\OneDrive\Documents\hyperlocal_customer_app\apps\shopkeeper_app'
Push-Location $root
$log = "$root\.ssot_run.log"
$psi = Start-Process powershell -ArgumentList @('-NoProfile','-Command',"flutter test test/state_ssot_test.dart --no-pub *> $log 2>&1; echo EXITCODE=$LASTEXITCODE >> $log") -WindowStyle Hidden -PassThru
Write-Output "launched, log=$log, pid=$($psi.Id)"
