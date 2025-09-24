#!/bin/bash
# Complete clean slate - removes everything for fresh install
# Non-interactive version that always does complete cleanup

set -e

echo "🧹 COMPLETE CLEAN SLATE - REMOVING ALL ARTIFACTS"
echo "================================================="
echo ""
echo "This will remove:"
echo "• All Docker containers, images, volumes, networks"
echo "• All WSL2 certificates and CA"
echo "• All Windows certificates and CA"
echo "• All configuration files"
echo "• All platform services"
echo ""

read -p "Continue with complete clean slate? (type 'YES' to confirm): " confirm
if [ "$confirm" != "YES" ]; then
    echo "Cancelled"
    exit 1
fi

# Run teardown script with complete cleanup (option 3)
# But first, we need to clean up certificates manually since the script is interactive

echo ""
echo "🔐 Cleaning WSL2 certificates..."

# Remove WSL2 certificates
if [ -d "$HOME/.local/share/certs" ]; then
    rm -rf "$HOME/.local/share/certs"
    echo "✅ Removed WSL2 certificates"
fi

# Remove mkcert CA
if [ -d "$HOME/.local/share/mkcert" ]; then
    rm -rf "$HOME/.local/share/mkcert"
    echo "✅ Removed mkcert CA"
fi

# Clean WSL2 system trust store
echo "🔐 Cleaning WSL2 system trust store..."
if [ -d "/usr/local/share/ca-certificates" ]; then
    sudo find /usr/local/share/ca-certificates -name "mkcert*.crt" -delete 2>/dev/null || true
    sudo update-ca-certificates --fresh >/dev/null 2>&1 || true
    echo "✅ Cleaned system trust store"
fi

# Clean Windows certificates
echo "🔐 Cleaning Windows certificates..."
./scripts/diagnostics/cleanup-mkcert-ca.ps1 -Force 2>/dev/null || echo "⚠️  Windows cleanup needs to be run from Windows"

echo ""
echo "🐳 Running Docker cleanup..."

# Run the teardown script in a way that skips certificate prompts
export CLEANUP_CHOICE="3"  # Complete teardown
echo "1" | ./scripts/teardown.sh || true  # Answer "keep certificates" but we already cleaned them

echo ""
echo "🎉 CLEAN SLATE COMPLETE"
echo ""
echo "Next steps for fresh install:"
echo "1. Run: ./scripts/setup-certificates-windows.ps1 (from Windows)"
echo "2. Run: ansible-playbook ansible/site.yml"
echo ""
