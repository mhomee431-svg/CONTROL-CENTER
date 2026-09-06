@echo off
REM ============================================================
REM Hyperlocal Customer App - Production Build Script
REM ============================================================
REM
REM Usage:
REM   scripts\build_customer_app.bat [dev|staging|production]
REM
REM Examples:
REM   scripts\build_customer_app.bat production
REM   scripts\build_customer_app.bat staging
REM   scripts\build_customer_app.bat dev
REM ============================================================

setlocal enabledelayedexpansion

set APP_NAME=Hyperlocal Customer App
set FLUTTER_PROJECT=Frontend
set DEFAULT_ENV=production

REM Parse environment argument
set ENV=%~1
if "%ENV%"=="" set ENV=%DEFAULT_ENV%

echo.
echo ============================================================
echo Building %APP_NAME%
echo Environment: %ENV%
echo ============================================================
echo.

REM Validate environment
if not "%ENV%"=="dev" if not "%ENV%"=="staging" if not "%ENV%"=="production" (
    echo ERROR: Invalid environment: %ENV%
    echo Valid environments: dev, staging, production
    exit /1
)

REM Set environment-specific variables
if "%ENV%"=="production" (
    set API_BASE_URL=https://api.hyperlocal.in
    set APP_ENV=production
    set BUILD_MODE=release
) else if "%ENV%"=="staging" (
    set API_BASE_URL=https://staging-api.hyperlocal.in
    set APP_ENV=staging
    set BUILD_MODE=release
) else (
    set API_BASE_URL=http://localhost:8000
    set APP_ENV=development
    set BUILD_MODE=debug
)

REM Check if Flutter is installed
where flutter >nul 2>nul
if %ERRORLEVEL% neq 0 (
    echo ERROR: Flutter not found in PATH
    echo Please install Flutter: https://flutter.dev/docs/get-started/install
    exit /1
)

REM Navigate to Flutter project
cd /d "%~dp0..\%FLUTTER_PROJECT%"

echo Step 1: Cleaning previous build...
flutter clean

echo.
echo Step 2: Getting dependencies...
flutter pub get

echo.
echo Step 3: Running code analysis...
flutter analyze
if %ERRORLEVEL% neq 0 (
    echo ERROR: Code analysis failed. Fix issues before building.
    exit /1
)

echo.
echo Step 4: Building %BUILD_MODE% APK...
flutter build apk --%BUILD_MODE% ^
    --dart-define=API_BASE_URL=%API_BASE_URL% ^
    --dart-define=APP_ENV=%APP_ENV% ^
    --dart-define=MAPS_API_KEY=%MAPS_API_KEY%

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