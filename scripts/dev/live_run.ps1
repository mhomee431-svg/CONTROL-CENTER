# live_run.ps1 — Persistent hot-reload host for `flutter run` on a real device.
# ------------------------------------------------------------------------------
# Usage:
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts\dev\live_run.ps1 `
#     -AppDir  C:\...\apps\shopkeeper_app `
#     -DeviceId TKIBRWQO8P7P7LGQ   # USB-connected device serial (flutter devices)
#     -Name shopkeeper
#
# The host launches `flutter run -d <DeviceId> --debug` in AppDir, keeps its
# stdin pipe OPEN (so the Flutter tool never sees EOF) and polls a tiny control
# file inside %TEMP% every 500 ms. Any other process (see live_reload.ps1) can
# drop a keystroke there:
#   r  -> hot reload          R  -> hot restart          q -> quit & stop app
# Flutter stdout/stderr are streamed to <AppDir>/live_run_out.log and
# live_run_err.log.
# ------------------------------------------------------------------------------

param(
    [Parameter(Mandatory = $true)][string]$AppDir,
    [Parameter(Mandatory = $true)][string]$DeviceId,
    [string]$Name = "app",
    [string]$ExtraArgs = ""
)

$flutterBat = "C:\flutter\bin\flutter.bat"
$outFile    = Join-Path $AppDir "live_run_out.log"
$errFile    = Join-Path $AppDir "live_run_err.log"
$cmdFile    = Join-Path $env:TEMP "hls_live_${Name}.cmd"
$pidFile    = Join-Path $AppDir "live_run.pid"

# Reset the control file so there is never stale input.
Set-Content -Path $cmdFile -Value "" -ErrorAction SilentlyContinue

# Heartbeat + host log (lets a human/agent see the host is alive).
$hbFile = Join-Path $AppDir "live_run_heartbeat.txt"
Set-Content -Path $hbFile -Value "started $(Get-Date -Format o)"

$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = "cmd.exe"
$psi.Arguments = "/d /c `"`"$flutterBat`" run -d $DeviceId --debug $ExtraArgs`""
$psi.WorkingDirectory = $AppDir
$psi.UseShellExecute = $false
$psi.RedirectStandardInput = $true
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$psi.CreateNoWindow = $true
$psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
$psi.StandardErrorEncoding = [System.Text.Encoding]::UTF8

$proc = $null
try {
    $proc = [System.Diagnostics.Process]::new()
    $proc.StartInfo = $psi
    [void]$proc.Start()
    Set-Content -Path $pidFile -Value $proc.Id

    # Stream flutter output to log files without blocking this loop.
    $fsOut = [System.IO.File]::Open($outFile, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write, [System.IO.FileShare]::Read)
    $fsErr = [System.IO.File]::Open($errFile, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write, [System.IO.FileShare]::Read)
    Add-Type -TypeDefinition 'using System; using System.IO; public static class _LiveOutPump { public static bool f(bool x){return x;} }' -ErrorAction SilentlyContinue
    $tOut = $proc.StandardOutput.BaseStream.CopyToAsync($fsOut)
    $tErr = $proc.StandardError.BaseStream.CopyToAsync($fsErr)

    $lastWrite = (Get-Item $cmdFile).LastWriteTime
    $stop = $false

    while (-not $stop -and -not $proc.HasExited) {
        Start-Sleep -Milliseconds 400
        try {
            # Heartbeat every iteration so you can confirm the host loop is alive.
            Set-Content -Path $hbFile -Value "$(Get-Date -Format o)" -ErrorAction SilentlyContinue

            $f = Get-Item $cmdFile -ErrorAction Stop
            if ($f.LastWriteTime -gt $lastWrite) {
                [string]$content = ((Get-Content $cmdFile -Raw) -join "").Trim()
                if ($content.Length -gt 0) {
                    # Reset BEFORE processing to avoid stale-input races.
                    Set-Content -Path $cmdFile -Value "" -ErrorAction SilentlyContinue
                    $lastWrite = (Get-Item $cmdFile).LastWriteTime
                    try {
                        if ($content -in @("q", "quit", "exit")) {
                            $proc.StandardInput.WriteLine("q")
                            $proc.StandardInput.Flush()
                            $proc.WaitForExit(30000) | Out-Null
                            $stop = $true
                        }
                        else {
                            $proc.StandardInput.WriteLine($content)
                            $proc.StandardInput.Flush()
                        }
                    }
                    catch {
                        Add-Content -Path (Join-Path $AppDir "live_run_err.log") -Value "HOST: failed to send '$content': $($_.Exception.Message)"
                    }
                }
            }
        }
        catch { }
    }

    if (-not $proc.HasExited) { try { $proc.Kill() } catch { } }
    $tOut.Wait(5000) | Out-Null
    $tErr.Wait(5000) | Out-Null
    $fsOut.Dispose(); $fsErr.Dispose()
}
finally {
    Set-Content -Path $hbFile -Value "stopped $(Get-Date -Format o)" -ErrorAction SilentlyContinue
}