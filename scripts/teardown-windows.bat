@echo off
REM Windows Platform Teardown - Wrapper Script
REM Copies PowerShell script to Windows temp and runs it to avoid WSL2 path issues

echo Windows Platform Teardown Wrapper
echo ===================================
echo.
echo This will perform COMPLETE certificate cleanup for this machine.
echo It removes ALL mkcert certificates for ALL users (Windows + WSL2).
echo.

REM Check for admin privileges
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo WARNING: Not running as Administrator!
    echo Some cleanup operations may fail due to insufficient permissions.
    echo.
    echo For complete cleanup:
    echo 1. Right-click this file and select "Run as administrator"
    echo 2. Or run from an Administrator Command Prompt
    echo.
    set /p continue="Continue anyway? (y/N): "
    if /i not "%continue%"=="y" (
        echo Cancelled.
        pause
        exit /b 0
    )
) else (
    echo Running with Administrator privileges
)

echo.

REM Create temp directory
if not exist "%TEMP%\airflow-platform" mkdir "%TEMP%\airflow-platform"

REM Copy PowerShell script to Windows temp location
echo Copying PowerShell script to Windows temp directory...
copy "%~dp0teardown-windows.ps1" "%TEMP%\airflow-platform\teardown-windows.ps1" >nul

if %errorlevel% neq 0 (
    echo ERROR: Could not copy PowerShell script
    echo Make sure the script exists: %~dp0teardown-windows.ps1
    pause
    exit /b 1
)

REM Run PowerShell script from Windows location
echo Running platform teardown...
echo.

PowerShell -ExecutionPolicy Bypass -File "%TEMP%\airflow-platform\teardown-windows.ps1" -Force

REM Clean up temp file
del "%TEMP%\airflow-platform\teardown-windows.ps1" >nul 2>&1

echo.
echo Platform teardown wrapper complete.
echo.
echo Next steps:
echo 1. Return to WSL2 and run: ./scripts/teardown.sh
echo 2. Run fresh setup: ./scripts/setup-certificates-windows.ps1
echo 3. Deploy platform: ansible-playbook ansible/site.yml
echo.
pause
