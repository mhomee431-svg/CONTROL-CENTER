@echo off
set JAVA_HOME=C:\Program Files\Android\Android Studio\jbr
set ANDROID_HOME=%LOCALAPPDATA%\Android\sdk
set ANDROID_SDK_ROOT=%LOCALAPPDATA%\Android\sdk
"%LOCALAPPDATA%\Android\sdk\cmdline-tools\latest\bin\sdkmanager.bat" system-images;android-34;google_apis;x86_64
echo INSTALL_DONE