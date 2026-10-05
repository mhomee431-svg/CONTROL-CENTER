@echo off
REM `hl` for Windows.
REM
REM Windows will not execute an extensionless `hl` without a PATHEXT change, so
REM this shim gives the same one-word command the docs promise:
REM
REM     hl check
REM     hl test
REM
REM It forwards every argument and, critically, preserves the EXIT CODE. A shim
REM that always returned 0 would make `hl check && git push` succeed on a failed
REM gate, which is worse than having no gate at all.
setlocal
python "%~dp0hl.py" %*
exit /b %ERRORLEVEL%
