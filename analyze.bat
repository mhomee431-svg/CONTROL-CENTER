@echo off
echo === Customer App Analysis ===
cd /d "%~dp0apps\customer_app"
flutter analyze lib/
echo === Shopkeeper App Analysis ===
cd /d "%~dp0apps\shopkeeper_app"
flutter analyze lib/
echo ANALYZE_DONE
