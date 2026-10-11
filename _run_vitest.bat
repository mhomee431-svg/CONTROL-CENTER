@echo off
cd /d c:\Users\aryan\Documents\CONTROL-CENTER
call node_modules\.bin\vitest.cmd run --config vitest.config.mjs > vitest_out.txt 2>&1
echo VITEST_EXIT=%errorlevel% >> vitest_out.txt
