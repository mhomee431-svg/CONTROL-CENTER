@echo off
cd /d "%~dp0"
"C:\Users\aryan\AppData\Local\Programs\Python\Python312\python.exe" -m uvicorn app.main:app --host 0.0.0.0 --port 8000 > server.log 2>&1
