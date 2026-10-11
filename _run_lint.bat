@echo off
cd /d c:\Users\aryan\Documents\CONTROL-CENTER
call node_modules\.bin\eslint.cmd src --ext .js,.jsx,.ts,.tsx > lint_out.txt 2>&1
echo LINT_EXIT=%errorlevel% >> lint_out.txt
