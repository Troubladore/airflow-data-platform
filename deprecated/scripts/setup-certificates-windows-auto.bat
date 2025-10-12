@echo off
REM Windows Certificate Setup with Automated mkcert Installation - Wrapper Script
REM Copies PowerShell script to Windows temp and runs it to avoid WSL2 path issues

echo Windows Certificate Setup (Automated)
echo =========================================
echo.
echo This script will:
echo - Install mkcert automatically (via Scoop or direct download)
echo - Install the mkcert CA to Windows certificate store
echo - Generate development certificates with proper SANs
echo.

REM Create temp directory
if not exist "%TEMP%\airflow-platform" mkdir "%TEMP%\airflow-platform"

REM Copy PowerShell script to Windows temp location
echo Copying PowerShell script to Windows temp directory...
copy "%~dp0setup-certificates-windows-auto.ps1" "%TEMP%\airflow-platform\setup-certificates-auto.ps1" >nul

if %errorlevel% neq 0 (
    echo ERROR: Could not copy PowerShell script
    echo Make sure the script exists: %~dp0setup-certificates-windows-auto.ps1
    pause
    exit /b 1
)

REM Run PowerShell script from Windows location
echo Running automated certificate setup...
echo.

PowerShell -ExecutionPolicy Bypass -File "%TEMP%\airflow-platform\setup-certificates-auto.ps1" %*

REM Clean up temp file
del "%TEMP%\airflow-platform\setup-certificates-auto.ps1" >nul 2>&1

echo.
echo Automated certificate setup wrapper complete.
pause
