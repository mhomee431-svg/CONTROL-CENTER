@echo off
REM ─────────────────────────────────────────────────────────────
REM  Run the Shopkeeper App on a PHYSICAL Android device over WiFi
REM  Auto-detects the PC's LAN IP so the app can reach the
REM  backend WITHOUT the ADB reverse tunnel (which is unstable).
REM
REM  Usage:
REM    run_on_phone.bat [DEVICE_ID]
REM
REM  Default DEVICE_ID: TKIBRWQO8P7P7LGQ
REM ─────────────────────────────────────────────────────────────
setlocal enabledelayedexpansion

set DEVICE_ID=%~1
if "%DEVICE_ID%"=="" set DEVICE_ID=TKIBRWQO8P7P7LGQ

REM ── 1. Find the PC's LAN (Wi-Fi/Ethernet) IPv4 address ────────
echo --- Detecting PC LAN IP for the backend ---
for /f "tokens=2 delims=:" %%a in (
  'ipconfig ^| findstr /i "IPv4"'
) do (
  set IP=%%a
  set IP=!IP: =!
  goto :found_ip
)
:found_ip
set LAN_IP=%IP%
echo LAN_IP = %LAN_IP%

REM ── 2. Verify backend is reachable at that IP ─────────────────
echo --- Verifying backend reachability at http://%LAN_IP%:8000 ---
curl -s -o nul -w "health check: HTTP %%{http_code}\n" http://%LAN_IP%:8000/health
if errorlevel 1 (
  echo.
  echo [WARNING] Backend NOT reachable at %LAN_IP%:8000
  echo           Make sure the backend is running on 0.0.0.0:8000
  echo           and this PC is on the same Wi-Fi network as the phone.
)

REM ── 3. Build & run the app with the correct Wi-Fi IP ──────────
echo --- flutter run -d %DEVICE_ID% --dart-define=SHOPKEEPER_API_BASE_URL=http://%LAN_IP%:8000 ---
flutter run -d %DEVICE_ID% --dart-define=SHOPKEEPER_API_BASE_URL=http://%LAN_IP%:8000

endlocal