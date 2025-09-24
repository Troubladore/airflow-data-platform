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
    read -p "SQL Server hostname (e.g., sqlserver01.company.com): " SQL_SERVER
    read -p "Database name (e.g., AdventureWorks): " SQL_DATABASE
fi

echo "  Server: $SQL_SERVER"
echo "  Database: $SQL_DATABASE"

# Step 3: Test SQL Server connection
echo -e "\n${YELLOW}Step 3: Testing SQL Server connection...${NC}"
echo "(This may take a minute to download dependencies)"

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
echo "If you see 'SUCCESS' above, you're ready to use SQL Server with Astronomer!"
