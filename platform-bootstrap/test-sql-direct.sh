#!/bin/bash
# Direct SQL Server test from host (no Docker, no sidecar)
# Lightweight wrapper around krb5-auth-test.sh for SQL Server testing
# This intermediate test isolates authentication issues from container complexity

set -e

# Find script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo "🔍 Direct SQL Server Test (Host → SQL)"
echo "========================================"
echo ""
echo "This test runs DIRECTLY from your host machine."
echo "No Docker containers, no sidecar - just pure Kerberos auth."
echo ""

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
    echo "For deep diagnostics, run:"
    echo "  ./krb5-auth-test.sh -s <sql-server> -d <database> -v"
    exit 1
fi

echo -e "Target: ${CYAN}${SQL_SERVER}${NC} / ${CYAN}${SQL_DATABASE}${NC}"
echo ""

# Shift the first two arguments to pass remaining to diagnostic tool
shift 2

# First, run a quick check using our universal diagnostic tool
if [ -f "$SCRIPT_DIR/krb5-auth-test.sh" ]; then
    echo "Running Kerberos authentication diagnostics..."
    echo ""

    # Run the diagnostic with SQL test
    if "$SCRIPT_DIR/krb5-auth-test.sh" -q -s "$SQL_SERVER" -d "$SQL_DATABASE" "$@"; then
        echo ""
        echo "========================================="
        echo -e "${GREEN}✅ SUCCESS! Direct Kerberos auth works!${NC}"
        echo "========================================="
        echo ""
        echo "This confirms:"
        echo "  ✓ Your Kerberos ticket is valid"
        echo "  ✓ SQL Server SPNs are configured"
        echo "  ✓ Network connectivity is working"
        echo "  ✓ SQL Server accepts your credentials"
        echo ""
        echo "Next: Test via sidecar (Step 11) to verify container setup"
        exit 0
    else
        EXIT_CODE=$?
        echo ""
        echo "========================================="
        echo -e "${RED}❌ Direct connection FAILED${NC}"
        echo "========================================="
        echo ""

        if [ $EXIT_CODE -eq 1 ]; then
            echo "Issue: Kerberos ticket problem"
            echo "Fix: Obtain valid ticket with: kinit"
        elif [ $EXIT_CODE -eq 2 ]; then
            echo "Issue: SQL Server connection failed"
            echo "Run with -v for detailed diagnostics:"
            echo "  $0 $SQL_SERVER $SQL_DATABASE -v"
        fi

        echo ""
        echo "For comprehensive diagnostics, run:"
        echo "  ./krb5-auth-test.sh -s $SQL_SERVER -d $SQL_DATABASE -v"
        exit $EXIT_CODE
    fi
else
    # Fallback to inline checks if diagnostic tool not available
    echo -e "${YELLOW}⚠${NC}  krb5-auth-test.sh not found - using basic checks"
    echo ""

    # Basic ticket check
    echo "Checking for Kerberos ticket..."
    if klist -s 2>/dev/null; then
        echo -e "${GREEN}✓${NC} Kerberos ticket found:"
        klist 2>/dev/null | head -5 | sed 's/^/  /'
    else
        echo -e "${RED}✗${NC} No Kerberos ticket found on host!"
        echo ""
        echo "You need to authenticate first:"
        echo "  kinit YOUR_USERNAME@DOMAIN.COM"
        exit 1
    fi

# Check if sqlcmd is available
echo ""
echo "Checking for Microsoft SQL tools..."

# Try different possible locations for sqlcmd
SQLCMD=""
if command -v sqlcmd >/dev/null 2>&1; then
    SQLCMD="sqlcmd"
    echo -e "${GREEN}✓${NC} Found sqlcmd in PATH"
elif [ -x "/opt/mssql-tools18/bin/sqlcmd" ]; then
    SQLCMD="/opt/mssql-tools18/bin/sqlcmd"
    echo -e "${GREEN}✓${NC} Found sqlcmd at /opt/mssql-tools18/bin/sqlcmd"
elif [ -x "/opt/mssql-tools/bin/sqlcmd" ]; then
    SQLCMD="/opt/mssql-tools/bin/sqlcmd"
    echo -e "${GREEN}✓${NC} Found sqlcmd at /opt/mssql-tools/bin/sqlcmd"
else
    echo -e "${RED}✗${NC} sqlcmd not found!"
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
    echo "Alternative: Skip this test and go directly to Step 11 (sidecar test)"
    exit 1
fi

# Test network connectivity first
echo ""
echo "Testing network connectivity to SQL Server..."
echo -n "  Checking port 1433... "

# Use timeout with nc for quick network check
if command -v nc >/dev/null 2>&1; then
    if timeout 3 nc -zv "$SQL_SERVER" 1433 >/dev/null 2>&1; then
        echo -e "${GREEN}✓ Port is open${NC}"
    else
        echo -e "${RED}✗ Port is not reachable${NC}"
        echo ""
        echo "Cannot reach SQL Server on port 1433."
        echo ""
        echo "Common causes:"
        echo "  1. Not connected to VPN"
        echo "  2. SQL Server name is incorrect"
        echo "  3. Firewall blocking connection"
        echo "  4. SQL Server using non-standard port"
        echo ""
        echo "Diagnostics:"
        echo "  - Check DNS: nslookup $SQL_SERVER"
        echo "  - Check VPN: Are you connected to corporate network?"
        echo "  - Try ping: ping -c 1 $SQL_SERVER"
        exit 1
    fi
else
    echo -e "${YELLOW}(nc not available, skipping port check)${NC}"
fi

# Test SQL Server connection with Kerberos
echo ""
echo "Attempting Kerberos authentication to SQL Server..."
echo "Using: $SQLCMD -E (integrated auth)"
echo ""

# Run the actual SQL test
# -S: Server
# -d: Database
# -E: Use integrated authentication (Kerberos)
# -C: Trust server certificate
# -Q: Query to execute
# -W: Remove trailing spaces
# -h: No headers for cleaner output

OUTPUT=$("$SQLCMD" -S "$SQL_SERVER" -d "$SQL_DATABASE" -E -C -Q "SELECT 'Connection successful!' as Result; SELECT auth_scheme FROM sys.dm_exec_connections WHERE session_id = @@SPID" -W -h -1 2>&1)
RESULT=$?

if [ $RESULT -eq 0 ]; then
    echo -e "${GREEN}$OUTPUT${NC}"
    echo ""

    # Check if we actually used Kerberos
    if echo "$OUTPUT" | grep -q "KERBEROS"; then
        echo "========================================="
        echo -e "${GREEN}✅ SUCCESS! Direct Kerberos auth works!${NC}"
        echo "========================================="
        echo ""
        echo -e "${GREEN}✓${NC} Authentication method: KERBEROS"
        echo -e "${GREEN}✓${NC} Connection: Host → SQL Server (direct)"
        echo -e "${GREEN}✓${NC} No Docker containers involved"
        echo ""
        echo "This confirms:"
        echo "  1. Your Kerberos ticket is valid"
        echo "  2. SQL Server SPNs are configured correctly"
        echo "  3. Network connectivity is working"
        echo "  4. SQL Server accepts your credentials"
        echo ""
        echo "Next: Test via sidecar (Step 11) to verify container setup"
    else
        echo "========================================="
        echo -e "${YELLOW}⚠ Connected but NOT using Kerberos${NC}"
        echo "========================================="
        echo ""
        echo "Authentication method: $(echo "$OUTPUT" | grep -v 'Connection successful')"
        echo ""
        echo "This might indicate:"
        echo "  - SQL Server fallback to NTLM"
        echo "  - SPN configuration issues"
        echo "  - Credential delegation problems"
    fi
    exit 0
else
    echo -e "${RED}$OUTPUT${NC}"
    echo ""
    echo "========================================="
    echo -e "${RED}❌ Direct connection FAILED${NC}"
    echo "========================================="
    echo ""

    # Analyze the error
    if echo "$OUTPUT" | grep -q "Login timeout expired"; then
        echo "Error: TIMEOUT"
        echo "Cannot reach SQL Server - network issue"
        echo ""
        echo "Check:"
        echo "  - VPN connection"
        echo "  - Server name spelling"
        echo "  - DNS resolution"

    elif echo "$OUTPUT" | grep -q "Cannot authenticate using Kerberos"; then
        echo "Error: KERBEROS AUTH FAILED"
        echo "Network OK, but Kerberos rejected"
        echo ""
        echo "Check:"
        echo "  - Run: klist -v"
        echo "  - Verify SPNs: ./check-sql-spn.sh $SQL_SERVER"
        echo "  - Clock sync: timedatectl status"

    elif echo "$OUTPUT" | grep -q "Login failed for user"; then
        echo "Error: ACCESS DENIED"
        echo "Authentication worked but no database access"
        echo ""
        echo "Your domain account needs SQL access."
        echo "Contact DBA to grant permissions."

    elif echo "$OUTPUT" | grep -q "not found or not accessible"; then
        echo "Error: DATABASE NOT FOUND"
        echo "Can connect to server but database doesn't exist"
        echo ""
        echo "Verify database name is correct."

    else
        echo "Error: UNKNOWN"
        echo "Could not identify specific issue"
    fi

    echo ""
    echo "For detailed diagnostics:"
    echo "  ./diagnose-kerberos.sh"
    exit 1
fi
fi  # This closes the main if statement that starts on line 47
