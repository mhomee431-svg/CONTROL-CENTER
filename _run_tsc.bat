@echo off
cd /d c:\Users\aryan\Documents\CONTROL-CENTER
call node_modules\.bin\tsc.cmd --noEmit > tsc_out.txt 2>&1
echo TSC_EXIT=%errorlevel% >> tsc_out.txt
