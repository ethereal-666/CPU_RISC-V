@echo off
setlocal

where gcc >nul 2>nul
if errorlevel 1 (
    echo ERROR: gcc was not found in PATH.
    exit /b 1
)

gcc -std=c11 -O2 -DC_TEST runq_bm.c -o llama_windows.exe -lm
if errorlevel 1 exit /b 1

echo Built: %CD%\llama_windows.exe
