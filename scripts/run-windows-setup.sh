#!/bin/bash
# WSL2 Helper: Run Windows Certificate Setup
# This script helps execute the Windows PowerShell script from WSL2

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

echo "🪟 WSL2 → Windows Certificate Setup Helper"
echo "=========================================="
echo

# Check if we're in WSL2
if ! grep -q microsoft /proc/version 2>/dev/null; then
    echo "❌ This script is designed to run from WSL2"
    echo "   If you're on native Linux, the Windows setup is not applicable."
    exit 1
fi

# Check if Windows automation script exists
WINDOWS_SCRIPT="$SCRIPT_DIR/setup-certificates-windows-auto.ps1"
if [[ ! -f "$WINDOWS_SCRIPT" ]]; then
    echo "❌ Windows automation script not found:"
    echo "   Expected: $WINDOWS_SCRIPT"
    exit 1
fi

echo "✅ Detected WSL2 environment"
echo "✅ Found Windows automation script"
echo

# Provide instructions
echo "AUTOMATED WINDOWS CERTIFICATE SETUP"
echo "===================================="
echo
echo "To complete Component 2 (Windows CA Trust), run this from Windows:"
echo
echo "Option 1 - PowerShell:"
echo "  cd \\\\wsl\$\\Ubuntu\\home\\$(whoami)\\repos\\airflow-data-platform"
echo "  .\\scripts\\setup-certificates-windows-auto.ps1"
echo
echo "Option 2 - Command Prompt:"
echo "  cd \\\\wsl\$\\Ubuntu\\home\\$(whoami)\\repos\\airflow-data-platform"
echo "  scripts\\setup-certificates-windows-auto.bat"
echo
echo "What the Windows script will do:"
echo "• Install mkcert if not present (via Scoop with fallbacks)"
echo "• Install mkcert CA to Windows certificate store"
echo "• Generate development certificates with proper SANs"
echo "• Handle all Windows-specific path and line ending issues"
echo
echo "After running the Windows script, continue with:"
echo "  ansible-playbook -i ansible/inventory/local-dev.ini ansible/orchestrators/setup-simple.yml"
echo
