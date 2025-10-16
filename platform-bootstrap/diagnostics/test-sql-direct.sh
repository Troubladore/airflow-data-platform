#!/bin/bash
# Direct SQL Server test from host (no Docker, no sidecar)
# Tests SQL connectivity first - if it works, that's SUCCESS regardless of Kerberos details
# Only runs detailed diagnostics if SQL test fails

set -e

# Find script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLATFORM_DIR="$(dirname "$SCRIPT_DIR")"

# Source the shared formatting library
if [ -f "$PLATFORM_DIR/lib/formatting.sh" ]; then
    source "$PLATFORM_DIR/lib/formatting.sh"
else
    # Fallback if library not found - basic formatting
    echo "Warning: formatting library not found, using basic output" >&2
    print_check() { echo "[$1] $2"; }
    print_header() { echo "=== $1 ==="; }
    print_msg() { echo "$@"; }
    print_divider() { echo "========================================"; }
    print_success() { echo "[SUCCESS] $1"; }
    print_error() { echo "[ERROR] $1"; }
    print_warning() { echo "[WARNING] $1"; }
    print_info() { echo "[INFO] $1"; }
    CHECK_MARK="[OK]"
    CROSS_MARK="[FAIL]"
    WARNING_SIGN="[WARN]"
    GREEN=''
    RED=''
    YELLOW=''
    CYAN=''
    NC=''
fi

# Get SQL Server details
SQL_SERVER="${1:-}"
SQL_DATABASE="${2:-}"

if [ -z "$SQL_SERVER" ] || [ -z "$SQL_DATABASE" ]; then
    echo "Usage: $0 <sql-server> <database> [options]"
    echo ""
    echo "Example:"
    echo "  $0 sqlserver01.company.com TestDB"
    echo "  $0 sqlserver01.company.com TestDB -v    # Verbose mode"
    echo ""
    echo "This tests direct SQL Server connection from the host."
    exit 1
fi

print_header "Direct SQL Server Test (Host → SQL)"
echo ""
echo "Testing DIRECT connection from your host machine."
echo "No Docker containers, no sidecar - just pure Kerberos auth."
echo ""
print_msg "Target: ${CYAN}${SQL_SERVER}${NC} / ${CYAN}${SQL_DATABASE}${NC}"
echo ""

# Shift the first two arguments to pass remaining to diagnostic tool
shift 2

# First, check if we have a Kerberos ticket at all
echo "Checking for Kerberos ticket..."
if ! klist -s 2>/dev/null; then
    print_check "FAIL" "No Kerberos ticket found!"
    echo ""
    echo "You need to authenticate first:"
    echo "  kinit YOUR_USERNAME@DOMAIN.COM"
    exit 1
fi

print_check "PASS" "Kerberos ticket found"
PRINCIPAL=$(klist 2>/dev/null | grep "Default principal:" | sed 's/Default principal: //')
echo "  Principal: $PRINCIPAL"
echo ""

# Check if sqlcmd is available
echo "Checking for Microsoft SQL tools..."

# Try different possible locations for sqlcmd
SQLCMD=""
if command -v sqlcmd >/dev/null 2>&1; then
    SQLCMD="sqlcmd"
    print_check "PASS" "Found sqlcmd in PATH"
elif [ -x "/opt/mssql-tools18/bin/sqlcmd" ]; then
    SQLCMD="/opt/mssql-tools18/bin/sqlcmd"
    print_check "PASS" "Found sqlcmd at /opt/mssql-tools18/bin/sqlcmd"
elif [ -x "/opt/mssql-tools/bin/sqlcmd" ]; then
    SQLCMD="/opt/mssql-tools/bin/sqlcmd"
    print_check "PASS" "Found sqlcmd at /opt/mssql-tools/bin/sqlcmd"
else
    print_check "FAIL" "sqlcmd not found!"
    echo ""
    echo "Microsoft SQL Server tools are not installed on the host."
    echo ""
    echo "To install on Ubuntu/Debian/WSL:"
    echo "  curl https://packages.microsoft.com/keys/microsoft.asc | sudo apt-key add -"
    echo "  curl https://packages.microsoft.com/config/ubuntu/20.04/prod.list | sudo tee /etc/apt/sources.list.d/msprod.list"
    echo "  sudo apt-get update"
    echo "  sudo apt-get install mssql-tools18 unixodbc-dev"
    echo "  echo 'export PATH=\"\$PATH:/opt/mssql-tools18/bin\"' >> ~/.bashrc"
    echo ""
    echo "Alternative: Use the container test (test-sql-container.sh) which doesn't require host tools"
    exit 1
fi

# CRITICAL: Test SQL Server connection FIRST
echo ""
echo "Testing SQL Server connection..."
echo "Command: $SQLCMD -S $SQL_SERVER -d $SQL_DATABASE -E -C"
echo ""

# Run the SQL test and capture both output and exit code
SQL_OUTPUT=$("$SQLCMD" -S "$SQL_SERVER" -d "$SQL_DATABASE" -E -C \
    -Q "SELECT 'Connection successful!' as Result; SELECT auth_scheme FROM sys.dm_exec_connections WHERE session_id = @@SPID" \
    -W -h -1 2>&1)
SQL_RESULT=$?

if [ $SQL_RESULT -eq 0 ]; then
    # SQL CONNECTION SUCCESSFUL - This is the main success criteria!
    echo "$SQL_OUTPUT"
    echo ""

    # Extract authentication method cleanly
    AUTH_METHOD=$(echo "$SQL_OUTPUT" | grep -v "Connection successful" | grep -v "^$" | head -1 | tr -d '[:space:]')

    if [ -n "$AUTH_METHOD" ]; then
        if [ "$AUTH_METHOD" = "KERBEROS" ]; then
            print_divider
            print_success "SUCCESS! Direct Kerberos authentication works!"
            print_divider
            echo ""
            print_check "PASS" "Authentication method: KERBEROS"
            print_check "PASS" "Connection: Host → SQL Server (direct)"
            print_check "PASS" "No Docker containers involved"
        else
            print_divider
            print_success "SQL Connection works (using $AUTH_METHOD)"
            print_divider
            echo ""
            print_check "PASS" "SQL Server connection successful"
            print_check "WARN" "Authentication method: $AUTH_METHOD (not Kerberos)"
            echo ""
            echo "This might indicate:"
            echo "  - SQL Server fallback to NTLM"
            echo "  - SPN configuration may need attention"
            echo "  - But connection is working, which is the main goal"
        fi
    else
        print_divider
        print_success "SQL Server connection successful!"
        print_divider
        echo ""
        print_check "PASS" "Connected to SQL Server successfully"
    fi

    echo ""
    echo "This confirms:"
    echo "  ✓ Network connectivity is working"
    echo "  ✓ SQL Server accepts your credentials"
    echo "  ✓ Database access is configured"
    echo ""
    echo "Next: Test via sidecar (Step 11) to verify container setup"

    # SUCCESS - Exit with code 0
    exit 0
else
    # SQL CONNECTION FAILED - Now we need diagnostics
    echo "$SQL_OUTPUT"
    echo ""
    print_divider
    print_error "SQL Server connection FAILED"
    print_divider
    echo ""

    # Quick network check before detailed diagnostics
    echo "Quick network check..."
    if command -v nc >/dev/null 2>&1; then
        if ! timeout 3 nc -zv "$SQL_SERVER" 1433 >/dev/null 2>&1; then
            print_check "FAIL" "Cannot reach SQL Server on port 1433"
            echo ""
            echo "This is a network connectivity issue:"
            echo "  1. Check VPN connection if working remotely"
            echo "  2. Verify server name: $SQL_SERVER"
            echo "  3. Check firewall rules"
            echo ""
            echo "Fix network connectivity first, then retry."
            exit 2
        else
            print_check "PASS" "Port 1433 is reachable"
        fi
    fi

    echo ""
    # Analyze the specific error
    if echo "$SQL_OUTPUT" | grep -q "Login timeout expired"; then
        echo "Error type: TIMEOUT"
        echo "  - Cannot reach SQL Server"
        echo "  - Check VPN and network connectivity"
    elif echo "$SQL_OUTPUT" | grep -q "Cannot authenticate using Kerberos"; then
        echo "Error type: KERBEROS AUTHENTICATION FAILED"
        echo "  - Network is OK but Kerberos rejected"
        echo "  - Likely an SPN configuration issue"
        echo ""
        echo "Run detailed diagnostics for more info:"
        echo "  ./krb5-auth-test.sh -s $SQL_SERVER -d $SQL_DATABASE -v"
    elif echo "$SQL_OUTPUT" | grep -q "Login failed for user"; then
        echo "Error type: ACCESS DENIED"
        echo "  - Authentication worked but no database access"
        echo "  - Contact DBA to grant permissions"
    elif echo "$SQL_OUTPUT" | grep -q "not found or not accessible"; then
        echo "Error type: DATABASE NOT FOUND"
        echo "  - Can connect to server but database doesn't exist"
        echo "  - Verify database name: $SQL_DATABASE"
    else
        echo "Error type: UNKNOWN"
        echo ""
        echo "Run verbose diagnostics for details:"
        echo "  ./krb5-auth-test.sh -s $SQL_SERVER -d $SQL_DATABASE -v"
    fi

    # Only run detailed Kerberos diagnostics if requested or if it's a Kerberos-specific error
    if [ "$1" = "-v" ] || echo "$SQL_OUTPUT" | grep -q "Kerberos"; then
        echo ""
        echo "Running detailed Kerberos diagnostics..."
        echo ""

        if [ -f "$SCRIPT_DIR/krb5-auth-test.sh" ]; then
            # Run diagnostic but don't let it override our SQL test result
            "$SCRIPT_DIR/krb5-auth-test.sh" -v -s "$SQL_SERVER" -d "$SQL_DATABASE" || true
        fi
    fi

    # Exit with failure since SQL test failed
    exit 2
fi