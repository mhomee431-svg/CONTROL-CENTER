@echo off
cd /d "%~dp0"
echo Starting Hyperlocal Backend...
python -m uvicorn app.main:app --reload --port 8000 --host 0.0.0.0
