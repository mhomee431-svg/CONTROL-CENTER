@echo off
REM Shopkeeper app launcher (physical Android phone over USB).
REM adb reverse tcp:8000 tcp:8000 tunnels the phone's localhost:8000 to this
REM computer's backend — works regardless of WiFi network / firewall.
set JAVA_HOME=C:\Program Files\Android\Android Studio\jbr
cd /d "C:\Users\akash\OneDrive\Documents\hyperlocal_customer_app\apps\shopkeeper_app"
flutter run -d TKIBRWQO8P7P7LGQ --debug --dart-define=SHOPKEEPER_API_BASE_URL=http://localhost:8000 > run_output.log 2>&1