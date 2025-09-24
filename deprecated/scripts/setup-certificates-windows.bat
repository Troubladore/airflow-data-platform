@echo off
REM Windows Certificate Setup - Wrapper Script
REM Copies PowerShell script to Windows temp and runs it to avoid WSL2 path issues

echo Windows Certificate Setup Wrapper
echo ===================================
echo.

REM Create temp directory
if not exist "%TEMP%\airflow-platform" mkdir "%TEMP%\airflow-platform"

REM Copy PowerShell script to Windows temp location
echo Copying PowerShell script to Windows temp directory...
copy "%~dp0setup-certificates-windows-clean.ps1" "%TEMP%\airflow-platform\setup-certificates.ps1" >nul

if %errorlevel% neq 0 (
    echo ERROR: Could not copy PowerShell script
    echo Make sure the script exists: %~dp0setup-certificates-windows.ps1
    pause
    exit /b 1
)

REM Run PowerShell script from Windows location
echo Running certificate setup...
echo.

PowerShell -ExecutionPolicy Bypass -File "%TEMP%\airflow-platform\setup-certificates.ps1"

REM Clean up temp file
del "%TEMP%\airflow-platform\setup-certificates.ps1" >nul 2>&1

echo.
echo Certificate setup wrapper complete.
pause
