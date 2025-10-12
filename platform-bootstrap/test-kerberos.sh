#!/bin/bash
# Convenience script to test Kerberos authentication with SQL Server
# Usage: ./test-kerberos.sh [server] [database]

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo "🔍 Kerberos SQL Server Connection Tester"
echo "========================================"

# Check if we're in the right directory
if [ ! -f "test_kerberos.py" ]; then
    echo -e "${RED}❌ Error: Run this from the platform-bootstrap directory${NC}"
    echo "   cd airflow-data-platform/platform-bootstrap"
    exit 1
fi

# Try to get configuration from running Kerberos service
DETECTED_DOMAIN=""
if docker exec kerberos-platform-service klist 2>/dev/null | grep -q "Default principal"; then
    echo -e "${GREEN}✓ Found running Kerberos service with active ticket${NC}"
    # Extract domain from the running service
    PRINCIPAL=$(docker exec kerberos-platform-service klist 2>/dev/null | grep "Default principal:" | sed 's/Default principal: //')
    if [ -n "$PRINCIPAL" ]; then
        DETECTED_DOMAIN=$(echo "$PRINCIPAL" | sed 's/.*@//' | tr -d '\r\n')
        echo "  Domain: $DETECTED_DOMAIN"
        USERNAME=$(echo "$PRINCIPAL" | sed 's/@.*//' | tr -d '\r\n')
        echo "  User: $USERNAME"
    fi
fi

# Step 1: Test basic ticket sharing
echo -e "\n${YELLOW}Step 1: Testing ticket sharing...${NC}"
docker run --rm \
  --network platform_network \
  -v platform_kerberos_cache:/krb5/cache:ro \
  -v $(pwd)/test_kerberos_simple.py:/app/test.py \
  -e KRB5CCNAME=/krb5/cache/krb5cc \
  python:3.11-alpine \
  sh -c "apk add --no-cache krb5 >/dev/null 2>&1 && python /app/test.py" | grep -q "SUCCESS" && \
  echo -e "${GREEN}✓ Ticket sharing is working!${NC}" || \
  (echo -e "${RED}✗ Ticket sharing failed. Run 'make platform-start' first.${NC}" && exit 1)

# Step 2: Get SQL Server details
if [ -n "$1" ] && [ -n "$2" ]; then
    SQL_SERVER="$1"
    SQL_DATABASE="$2"
    echo -e "\n${GREEN}Using provided values:${NC}"
else
    echo -e "\n${YELLOW}Step 2: Enter SQL Server details${NC}"
    echo ""
    echo "Where to find these values:"
    echo "  1. Ask your DBA: 'What SQL Server can I use for testing?'"
    echo "  2. Check your team's documentation or wiki"
    echo "  3. Look in existing ETL scripts or connection configs"
    echo "  4. Common patterns: analytics-sql-dev, datawarehouse-dev, etc."
    echo ""
    echo "Example values:"
    echo "  Server: sqlserver01.company.com"
    echo "  Database: TestDB or AdventureWorks"
    echo ""
    read -p "SQL Server hostname: " SQL_SERVER
    read -p "Database name: " SQL_DATABASE

    # Validate input
    if [ -z "$SQL_SERVER" ] || [ -z "$SQL_DATABASE" ]; then
        echo -e "\n${RED}❌ Both server and database are required${NC}"
        echo "Please run the script again with valid values."
        exit 1
    fi
fi

echo ""
echo "Testing with:"
echo "  Server: $SQL_SERVER"
echo "  Database: $SQL_DATABASE"

# Step 3: Show the exact command
echo -e "\n${YELLOW}Step 3: Running SQL Server connection test...${NC}"
echo ""
echo "The exact command being run:"
echo "----------------------------------------"
echo "docker run --rm \\"
echo "  --network platform_network \\"
echo "  -v platform_kerberos_cache:/krb5/cache:ro \\"
echo "  -v \$(pwd)/test_kerberos.py:/app/test_kerberos.py \\"
echo "  -e KRB5CCNAME=/krb5/cache/krb5cc \\"
echo "  -e SQL_SERVER=\"$SQL_SERVER\" \\"
echo "  -e SQL_DATABASE=\"$SQL_DATABASE\" \\"
echo "  python:3.11-alpine \\"
echo "  sh -c \"apk add --no-cache krb5 gcc musl-dev unixodbc-dev && \\"
echo "         pip install --no-cache-dir pyodbc && \\"
echo "         python /app/test_kerberos.py\""
echo "----------------------------------------"
echo ""
echo "You can copy and reuse this command with your own SQL servers!"
echo ""
echo "(This may take a minute to download dependencies...)"
echo ""

# Run the actual test
docker run --rm \
  --network platform_network \
  -v platform_kerberos_cache:/krb5/cache:ro \
  -v $(pwd)/test_kerberos.py:/app/test_kerberos.py \
  -e KRB5CCNAME=/krb5/cache/krb5cc \
  -e SQL_SERVER="$SQL_SERVER" \
  -e SQL_DATABASE="$SQL_DATABASE" \
  python:3.11-alpine \
  sh -c "apk add --no-cache krb5 gcc musl-dev unixodbc-dev >/dev/null 2>&1 && \
         pip install --no-cache-dir pyodbc >/dev/null 2>&1 && \
         python /app/test_kerberos.py"

echo -e "\n${GREEN}🎉 Test complete!${NC}"

# Provide helpful next steps based on detected configuration
if [ -n "$DETECTED_DOMAIN" ]; then
    echo ""
    echo "Your Kerberos configuration:"
    echo "  Domain: $DETECTED_DOMAIN"
    echo "  Server tested: $SQL_SERVER"
    echo "  Database: $SQL_DATABASE"
    echo ""
    echo "To test with other SQL Servers, run:"
    echo "  ./test-kerberos.sh <server> <database>"
fi

echo ""
echo "If you see 'SUCCESS' above, you're ready to use SQL Server with Astronomer!"
