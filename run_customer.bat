@echo off
REM Customer app launcher.
REM Injects MAPS_API_KEY from android\local.properties (gitignored) into the
REM Dart runtime via --dart-define, exactly as the AndroidManifest placeholder
REM receives it from Gradle at build time. Without it the map tiles render but
REM the Google Geocoding / Directions REST calls fail their key check.
setlocal
set "APP_DIR=C:\Users\akash\OneDrive\Documents\hyperlocal_app\apps\customer_app"
set "KEY="
for /f "usebackq tokens=1,* delims==" %%A in ("%APP_DIR%\android\local.properties") do (
  if "%%A"=="MAPS_API_KEY" set "KEY=%%B"
)
if "%KEY%"=="" (
  echo MAPS_API_KEY not found in android\local.properties - Geocoding/Directions will fail.
)
cd /d "%APP_DIR%"
flutter run -d emulator-5554 --debug --dart-define=MAPS_API_KEY=%KEY%
endlocal