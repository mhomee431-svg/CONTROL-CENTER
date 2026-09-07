@echo off
set JAVA_HOME=C:\Program Files\Android\Android Studio\jbr
cd /d "C:\Users\akash\OneDrive\Documents\hyperlocal_customer_app\apps\shopkeeper_app"
flutter run -d emulator-5554 --debug > run_output.log 2>&1