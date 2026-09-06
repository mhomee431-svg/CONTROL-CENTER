@echo off
set JAVA_HOME=C:\Program Files\Android\Android Studio\jbr
set ANDROID_HOME=%LOCALAPPDATA%\Android\sdk
set ANDROID_SDK_ROOT=%LOCALAPPDATA%\Android\sdk
echo no | "%LOCALAPPDATA%\Android\sdk\cmdline-tools\latest\bin\avdmanager.bat" create avd --name "HyperlocalEmulator" --package "system-images;android-35;google_apis;x86_64" --force
echo AVD_CREATION_DONE