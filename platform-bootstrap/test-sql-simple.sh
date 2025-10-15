#!/bin/bash
# Simple SQL Server test using docker-compose (no custom image build)
# Tests NT Authentication via Kerberos

set -e

# Load .env to get corporate image sources
if [ -f .env ]; then
    source .env
fi

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "🔍 SQL Server Kerberos Authentication Test"
echo "=========================================="
echo ""

# Get SQL Server details
SQL_SERVER="${1:-}"
SQL_DATABASE="${2:-}"

if [ -z "$SQL_SERVER" ] || [ -z "$SQL_DATABASE" ]; then
    echo "Usage: $0 <sql-server> <database>"
    echo ""
    echo "Example:"
    echo "  $0 sqlserver01.company.com TestDB"
    exit 1
fi

echo "Testing connection to: $SQL_SERVER / $SQL_DATABASE"
echo ""

# Check if kerberos service is running
if ! docker ps | grep -q "kerberos-platform-service"; then
    echo -e "${RED}✗ Kerberos service not running${NC}"
    echo ""
    echo "Start it first:"
    echo "  make platform-start"
    exit 1
fi

echo -e "${GREEN}✓ Kerberos service running${NC}"
echo ""

# Simple test: Use Alpine with minimal setup
echo "Running SQL Server connection test..."
echo "(Installing dependencies in container - this may take a moment)"
echo ""

docker run --rm \
    --network platform_network \
    -v platform_kerberos_cache:/krb5/cache:ro \
    -e KRB5CCNAME=/krb5/cache/krb5cc \
    -e SQL_SERVER="$SQL_SERVER" \
    -e SQL_DATABASE="$SQL_DATABASE" \
    ${IMAGE_ALPINE:-alpine:latest} \
    sh -c '
        apk add --no-cache krb5 freetds >/dev/null 2>&1 || exit 1

        # Simple test using tsql (FreeTDS - no pyodbc complexity)
        echo "Testing with FreeTDS (simpler than ODBC)..."

        # Check if ticket exists
        if klist -s 2>/dev/null; then
            echo "✓ Kerberos ticket available"
            klist | head -3
        else
            echo "✗ No Kerberos ticket found"
            exit 1
        fi

        echo ""
        echo "Attempting SQL Server connection with Kerberos..."
        echo "Server: $SQL_SERVER"
        echo "Database: $SQL_DATABASE"
        echo ""

        # Test connection with tsql (Kerberos)
        # -K flag enables Kerberos authentication
        if echo "SELECT @@VERSION; GO" | timeout 10 tsql -S "$SQL_SERVER" -D "$SQL_DATABASE" -K 2>&1; then
            echo ""
            echo "=========================================="
            echo "✅ SUCCESS! Kerberos authentication works!"
            echo "=========================================="
            exit 0
        else
            echo ""
            echo "=========================================="
            echo "❌ Connection failed"
            echo "=========================================="
            echo ""
            echo "Common issues:"
            echo "1. SQL Server SPN not registered (ask DBA)"
            echo "2. Server name wrong or unreachable"
            echo "3. Database name wrong or no permissions"
            echo ""
            echo "Run diagnostic: ./diagnose-kerberos.sh"
            exit 1
        fi
    '

echo ""
echo "Test complete."
