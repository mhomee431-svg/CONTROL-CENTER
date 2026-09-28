$ErrorActionPreference = 'Stop'
# Guards against the file-corruption class of bug: a mis-placed edit can
# duplicate a class, truncate a build() body, or leave a stray BOM. Those
# corruptions are invisible to `git diff --stat` and produce hundreds of
# cascading analyzer errors that bury the one real mistake.
#
# Run:  powershell -ExecutionPolicy Bypass -File scripts\check_dart_integrity.ps1
$root = Split-Path -Parent $PSScriptRoot
$app = Join-Path $root 'apps\customer_app'
$files = Get-ChildItem -Path "$app\lib","$app\test" -Recurse -Filter *.dart

$failures = @()
$bom = [char]0xFEFF

foreach ($f in $files) {
  # Generated code is not hand-edited, so its (legal) repeated private class
  # names and style are none of this check's business.
  if ($f.Name -like '*.g.dart' -or $f.Name -like '*.freezed.dart') { continue }

  $text = [System.Text.Encoding]::UTF8.GetString([System.IO.File]::ReadAllBytes($f.FullName))
  $rel = $f.FullName.Replace("$app\", '')

  if ($text.IndexOf($bom) -gt 0) {
    $failures += "$rel : byte-order mark inside the file (re-encoded mid-edit)"
  }
  if ($text -match 'extends void') {
    $failures += "$rel : 'extends void' corruption"
  }
  # `index` is a built-in enum member; re-declaring it never compiles.
  if ($text -match 'final int index;') {
    $failures += "$rel : enum declares a field named 'index'"
  }
  # `unawaited` needs a Future; ref.read on a notifier provider is not one.
  if ($text -match 'unawaited\(ref\.read\(\w*ControllerProvider\)\)') {
    $failures += "$rel : unawaited() around ref.read of a notifier provider"
  }
  if ($text.Contains([char]0xFFFD)) {
    $failures += "$rel : replacement character (encoding damage)"
  }

  # Duplicate top-level private class names in one file are always a
  # mis-placed insert.
  $classes = [regex]::Matches($text, '(?m)^class (\w+)') | ForEach-Object { $_.Groups[1].Value }
  foreach ($dup in ($classes | Group-Object | Where-Object { $_.Count -gt 1 })) {
    $failures += "$rel : class '$($dup.Name)' declared $($dup.Count) times"
  }
}

if ($failures.Count -gt 0) {
  $failures | ForEach-Object { Write-Output "ERROR: $_" }
  Write-Output "check_dart_integrity: $($failures.Count) problem(s) found."
  exit 1
}
Write-Output "check_dart_integrity: clean ($($files.Count) files)."
