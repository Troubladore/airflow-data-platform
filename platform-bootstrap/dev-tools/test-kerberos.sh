#!/bin/bash
# Convenience script to test Kerberos authentication with SQL Server
# Usage: ./test-kerberos.sh [server] [database]

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
    YELLOW='\033[1;33m'
    RED='\033[0;31m'
    NC='\033[0m'
fi

# Load .env for configuration
if [ -f "$SCRIPT_DIR/.env" ]; then
    source "$SCRIPT_DIR/.env" 2>/dev/null || true
fi

# Use pre-built test image if available, otherwise fall back to runtime install
# The pre-built image has pyodbc installed (avoids corporate PyPI blocks)
if docker image inspect platform/kerberos-test:latest >/dev/null 2>&1; then
    TEST_IMAGE="platform/kerberos-test:latest"
    USE_PREBUILT=true
    print_check "PASS" "Using pre-built test image (pyodbc already installed)"
else
    TEST_IMAGE="${IMAGE_PYTHON:-python:3.11-alpine}"
    USE_PREBUILT=false
    print_check "WARN" "Using runtime image (will install pyodbc via pip)"
    echo "  For corporate environments, build test image first:"
    echo "  cd kerberos-sidecar && make build-test-image"
    echo ""
fi

print_title "Kerberos SQL Server Connection Tester" "🔍"
print_header "Kerberos SQL Server Connection Tester"

# Check if we're in the right directory
if [ ! -f "test_kerberos.py" ]; then
    print_error "Run this from the platform-bootstrap directory"
    echo "   cd airflow-data-platform/platform-bootstrap"
    exit 1
fi

# Try to get configuration from running Kerberos service
DETECTED_DOMAIN=""
if docker exec kerberos-platform-service klist 2>/dev/null | grep -q "Default principal"; then
    print_check "PASS" "Found running Kerberos service with active ticket"
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
echo ""
print_step "1" "Testing ticket sharing..."
echo "  Using image: $TEST_IMAGE"
docker run --rm \
  --network platform_network \
  -v platform_kerberos_cache:/krb5/cache:ro \
  -v $(pwd)/test_kerberos_simple.py:/app/test.py \
  -e KRB5CCNAME=/krb5/cache/krb5cc \
  "$TEST_IMAGE" \
  sh -c "apk add --no-cache krb5 >/dev/null 2>&1 && python /app/test.py" | grep -q "SUCCESS" && \
  print_check "PASS" "Ticket sharing is working!" || \
  (print_check "FAIL" "Ticket sharing failed. Run 'make platform-start' first." && exit 1)

# Step 2: Get SQL Server details
if [ -n "$1" ] && [ -n "$2" ]; then
    SQL_SERVER="$1"
    SQL_DATABASE="$2"
    echo ""
    print_success "Using provided values:"
else
    echo ""
    print_step "2" "Enter SQL Server details"
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
        echo ""
        print_error "Both server and database are required"
        echo "Please run the script again with valid values."
        exit 1
    fi
fi

echo ""
echo "Testing with:"
echo "  Server: $SQL_SERVER"
echo "  Database: $SQL_DATABASE"

# Step 3: Show the exact command
echo ""
print_step "3" "Running SQL Server connection test..."
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
echo "  $TEST_IMAGE \\"
echo "  sh -c \"apk add --no-cache krb5 gcc musl-dev unixodbc-dev && \\"
echo "         pip install --no-cache-dir pyodbc && \\"
echo "         python /app/test_kerberos.py\""
echo "----------------------------------------"
echo ""
echo "Using image from .env: $TEST_IMAGE"
echo "You can copy and reuse this command with your own SQL servers!"
echo ""
echo "(This may take a minute to download dependencies...)"
echo ""

# Run the actual test
if [ "$USE_PREBUILT" = true ]; then
    # Pre-built image already has everything
    TEST_OUTPUT=$(docker run --rm \
      --network platform_network \
      -v platform_kerberos_cache:/krb5/cache:ro \
      -v $(pwd)/test_kerberos.py:/app/test_kerberos.py \
      -e KRB5CCNAME=/krb5/cache/krb5cc \
      -e SQL_SERVER="$SQL_SERVER" \
      -e SQL_DATABASE="$SQL_DATABASE" \
      "$TEST_IMAGE" \
      python /app/test_kerberos.py 2>&1)
else
    # Runtime image - install dependencies first
    TEST_OUTPUT=$(docker run --rm \
      --network platform_network \
      -v platform_kerberos_cache:/krb5/cache:ro \
      -v $(pwd)/test_kerberos.py:/app/test_kerberos.py \
      -e KRB5CCNAME=/krb5/cache/krb5cc \
      -e SQL_SERVER="$SQL_SERVER" \
      -e SQL_DATABASE="$SQL_DATABASE" \
      "$TEST_IMAGE" \
      sh -c "apk add --no-cache krb5 gcc musl-dev unixodbc-dev >/dev/null 2>&1 && \
             pip install --no-cache-dir pyodbc >/dev/null 2>&1 && \
             python /app/test_kerberos.py" 2>&1)
fi

TEST_EXIT_CODE=$?

# Display the output
echo "$TEST_OUTPUT"

# Parse the output and provide specific next steps
if [ $TEST_EXIT_CODE -eq 0 ]; then
    echo ""
    print_divider
    print_success "SUCCESS! Your Kerberos authentication is working!"
    print_divider
else
    echo ""
    print_divider
    print_error "Test Failed - Parsing Error for Specific Guidance"
    print_divider
    echo ""

    # Parse error type from output
    if echo "$TEST_OUTPUT" | grep -qi "SPN (Service Principal Name)"; then
        print_warning "QUICK ACTION:"
        echo ""
        echo "This is an SPN issue that requires DBA help."
        echo ""
        echo "Run this command to generate a message for your DBA:"
        print_msg "  ${GREEN}./diagnostics/check-sql-spn.sh $SQL_SERVER${NC}"
        echo ""
        echo "This will create a ready-to-send email with exact commands."

    elif echo "$TEST_OUTPUT" | grep -qi "Network Connectivity"; then
        print_warning "QUICK ACTION:"
        echo ""
        echo "Test network connectivity:"
        print_msg "  ${GREEN}nc -zv $SQL_SERVER 1433${NC}"
        echo ""
        echo "If connection fails:"
        echo "  1. Check you're on corporate VPN (if remote)"
        echo "  2. Verify server name is correct: $SQL_SERVER"
        echo "  3. Ask DBA: 'Is $SQL_SERVER reachable from my network?'"

    elif echo "$TEST_OUTPUT" | grep -qi "ODBC Driver"; then
        print_warning "QUICK ACTION:"
        echo ""
        echo "The ODBC driver issue is in the test container."
        echo "This should not happen with the standard test setup."
        echo ""
        echo "Try rebuilding the test environment or contact platform support."

    elif echo "$TEST_OUTPUT" | grep -qi "Kerberos Ticket Issue"; then
        print_warning "QUICK ACTION:"
        echo ""
        echo "Your Kerberos ticket needs attention."
        echo ""
        echo "Run the diagnostic tool:"
        print_msg "  ${GREEN}./diagnostics/diagnose-kerberos.sh${NC}"
        echo ""
        echo "This will check your ticket and provide specific fixes."

    elif echo "$TEST_OUTPUT" | grep -qi "Database Access Issue"; then
        print_warning "QUICK ACTION:"
        echo ""
        echo "Connected to server but cannot access the database."
        echo ""
        echo "Tell your DBA:"
        echo "  'I need read access (db_datareader) to database: $SQL_DATABASE'"
        echo "  'On server: $SQL_SERVER'"
        echo ""
        echo "Or try a different database you know you have access to."

    else
        print_warning "GENERAL TROUBLESHOOTING:"
        echo ""
        echo "1. Check Kerberos setup:"
        print_msg "   ${GREEN}./diagnostics/diagnose-kerberos.sh${NC}"
        echo ""
        echo "2. Check for SPN issues:"
        print_msg "   ${GREEN}./diagnostics/check-sql-spn.sh $SQL_SERVER${NC}"
        echo ""
        echo "3. Test network connectivity:"
        print_msg "   ${GREEN}nc -zv $SQL_SERVER 1433${NC}"
        echo ""
        echo "4. Review the error message above for specific details"
    fi
fi

echo ""

# Provide helpful next steps based on detected configuration and test result
if [ $TEST_EXIT_CODE -eq 0 ]; then
    if [ -n "$DETECTED_DOMAIN" ]; then
        echo ""
        echo "Your Kerberos configuration:"
        echo "  Domain: $DETECTED_DOMAIN"
        echo "  Server tested: $SQL_SERVER"
        echo "  Database: $SQL_DATABASE"
        echo ""
    fi
    echo "To test with other SQL Servers, run:"
    echo "  ./test-kerberos.sh <server> <database>"
    echo ""
    echo "You're ready to use SQL Server with Astronomer!"
fi
