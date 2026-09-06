@echo off
REM ============================================================
REM Hyperlocal Shopkeeper App - Production Build Script
REM ============================================================
REM
REM Usage:
REM   scripts\build_shopkeeper_app.bat [dev|staging|production]
REM ============================================================

setlocal enabledelayedexpansion

set APP_NAME=Hyperlocal Shopkeeper App
set FLUTTER_PROJECT=ShopkeeperApp
set DEFAULT_ENV=production

set ENV=%~1
if "%ENV%"=="" set ENV=%DEFAULT_ENV%

echo.
echo ============================================================
echo Building %APP_NAME%
echo Environment: %ENV%
echo ============================================================
echo.

if not "%ENV%"=="dev" if not "%ENV%"=="staging" if not "%ENV%"=="production" (
    echo ERROR: Invalid environment: %ENV%
    exit /1
)

if "%ENV%"=="production" (
    set API_BASE_URL=https://api.hyperlocal.in
    set APP_ENV=production
    set BUILD_MODE=release
) else if "%ENV%"=="staging" (
    set API_BASE_URL=https://staging-api.hyperlocal.in
    set APP_ENV=staging
    set BUILD_MODE=release
) else (
    set API_BASE_URL=http://10.0.2.2:8000
    set APP_ENV=development
    set BUILD_MODE=debug
)

where flutter >nul 2>nul
if %ERRORLEVEL% neq 0 (
    echo ERROR: Flutter not found in PATH
    exit /1
)

cd /d "%~dp0..\%FLUTTER_PROJECT%"

echo Step 1: Cleaning previous build...
flutter clean

echo.
echo Step 2: Getting dependencies...
flutter pub get

echo.
echo Step 3: Building %BUILD_MODE% APK...
flutter build apk --%BUILD_MODE% ^
    --dart-define=SHOPKEEPER_API_BASE_URL=%API_BASE_URL% ^
    --dart-define=APP_ENV=%APP_ENV%

if %ERRORLEVEL% neq 0 (
    echo ERROR: Build failed.
    exit /1
)

echo.
echo ============================================================
echo Build completed successfully!
echo.
echo Output: build\app\outputs\flutter-apk\app-%BUILD_MODE%.apk
echo API URL: %API_BASE_URL%
echo Environment: %APP_ENV%
echo ============================================================

endlocal