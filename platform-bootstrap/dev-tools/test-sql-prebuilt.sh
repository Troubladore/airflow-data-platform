#!/bin/bash
# SQL Server test using pre-built image with Microsoft sqlcmd
# ============================================================
# This script uses a pre-built image that already has sqlcmd installed.
# No runtime downloads, no pip, no PyPI - just run the test!
#
# Prerequisites:
#   1. Build the test image once:
#      cd kerberos-sidecar && make build-sqlcmd-test
#   2. Start Kerberos service:
#      make platform-start
#   3. Run this test:
#      ./test-sql-prebuilt.sh sqlserver01.company.com TestDB

set -e

# Load formatting library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLATFORM_DIR="$(dirname "$SCRIPT_DIR")"
if [ -f "$PLATFORM_DIR/lib/formatting.sh" ]; then
    source "$PLATFORM_DIR/lib/formatting.sh"
else
    # Fallback if library not found
    echo "Warning: formatting library not found, using basic output" >&2
    GREEN='\033[0;32m'
    RED='\033[0;31m'
    YELLOW='\033[1;33m'
    NC='\033[0m'
fi

# Load .env to get configuration
if [ -f .env ]; then
    source .env
fi

print_title "SQL Server Kerberos Authentication Test (Pre-built Image)" "🔍"
print_header "SQL Server Kerberos Authentication Test"
echo ""

# Get SQL Server details
SQL_SERVER="${1:-}"
SQL_DATABASE="${2:-}"

if [ -z "$SQL_SERVER" ] || [ -z "$SQL_DATABASE" ]; then
    echo "Usage: $0 <sql-server> <database>"
    echo ""
    echo "Example:"
    echo "  $0 sqlserver01.company.com TestDB"
    echo ""
    echo "Prerequisites:"
    echo "  1. Build test image: cd kerberos-sidecar && make build-sqlcmd-test"
    echo "  2. Start Kerberos: make platform-start"
    exit 1
fi

echo "Testing connection to: $SQL_SERVER / $SQL_DATABASE"
echo ""

# Check if test image exists
if ! docker image inspect platform/sqlcmd-test:latest >/dev/null 2>&1; then
    print_check "FAIL" "Test image not found"
    echo ""
    echo "Build it first:"
    echo "  cd kerberos-sidecar"
    echo "  make build-sqlcmd-test"
    echo ""
    echo "This builds an image with Microsoft sqlcmd pre-installed."
    echo "You only need to build it once!"
    exit 1
fi

print_check "PASS" "Test image found"
echo ""

# Check if kerberos service is running
if ! docker ps | grep -q "kerberos-platform-service"; then
    print_check "FAIL" "Kerberos service not running"
    echo ""
    echo "Start it first:"
    echo "  make platform-start"
    exit 1
fi

print_check "PASS" "Kerberos service running"
echo ""

echo "Running SQL Server connection test..."
echo ""

docker run --rm \
    --network platform_network \
    -v platform_kerberos_cache:/krb5/cache:ro \
    -e KRB5CCNAME=/krb5/cache/krb5cc \
    -e SQL_SERVER="$SQL_SERVER" \
    -e SQL_DATABASE="$SQL_DATABASE" \
    platform/sqlcmd-test:latest \
    -c '
        # Check if ticket exists
        if klist -s 2>/dev/null; then
            echo "✓ Kerberos ticket available:"
            klist | head -3
        else
            echo "✗ No Kerberos ticket found"
            echo ""
            echo "The Kerberos sidecar should have copied your ticket."
            echo "Check sidecar logs: docker logs kerberos-platform-service"
            exit 1
        fi

        echo ""
        echo "Attempting SQL Server connection with Kerberos..."
        echo "Server: $SQL_SERVER"
        echo "Database: $SQL_DATABASE"
        echo "Using: sqlcmd with integrated authentication (-E flag)"
        echo ""

        # Test connection with sqlcmd using integrated authentication
        # -E flag uses Kerberos authentication
        # -C trusts the server certificate (for testing)
        if sqlcmd -S "$SQL_SERVER" -d "$SQL_DATABASE" -E -C -Q "SELECT @@VERSION" 2>&1; then
            echo ""
            echo "=========================================="
            echo "✅ SUCCESS! Kerberos authentication works!"
            echo "=========================================="

            # Verify we used Kerberos
            echo ""
            echo "Verifying authentication method..."
            sqlcmd -S "$SQL_SERVER" -d "$SQL_DATABASE" -E -C -Q "SELECT auth_scheme FROM sys.dm_exec_connections WHERE session_id = @@SPID" 2>&1 | grep -i kerberos && {
                echo "✓ Confirmed: Using KERBEROS authentication"
            }
            exit 0
        else
            echo ""
            echo "=========================================="
            echo "❌ Connection failed"
            echo "=========================================="
            echo ""
            echo "Common issues:"
            echo "1. SQL Server SPN not registered (ask DBA)"
            echo "2. Server name must be FQDN (not IP or short name)"
            echo "3. Database name wrong or no permissions"
            echo "4. Kerberos ticket not valid for SQL Server"
            echo ""
            echo "Debug with: ./diagnose-kerberos.sh"
            exit 1
        fi
    '

echo ""
echo "Test complete."
