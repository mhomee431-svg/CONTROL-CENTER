@echo off
echo === Frontend Analysis ===
cd /d "%~dp0Frontend"
flutter analyze lib/
echo === ShopkeeperApp Analysis ===
cd /d "%~dp0ShopkeeperApp"
flutter analyze lib/
echo ANALYZE_DONE
