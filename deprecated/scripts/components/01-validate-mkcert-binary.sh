#!/bin/bash
# Component 1: mkcert Binary Validation
# Simple pass/fail check if mkcert is available

set -e

echo "🔍 Validating mkcert binary availability..."

# Check WSL2 first
if command -v mkcert >/dev/null 2>&1; then
    MKCERT_VERSION=$(mkcert --version 2>/dev/null || echo "unknown")
    echo "✅ mkcert binary available in WSL2: $MKCERT_VERSION"
    exit 0
fi

# Check Windows via PowerShell
if command -v powershell.exe >/dev/null 2>&1; then
    if powershell.exe -Command "Get-Command mkcert -ErrorAction SilentlyContinue" >/dev/null 2>&1; then
        WINDOWS_MKCERT_VERSION=$(powershell.exe -Command "mkcert --version" 2>/dev/null | tr -d '\r\n' || echo "unknown")
        echo "✅ mkcert binary available in Windows: $WINDOWS_MKCERT_VERSION"
        exit 0
    fi
fi

echo "❌ mkcert binary not found in WSL2 or Windows"
echo "   This component needs to be installed"
exit 1
