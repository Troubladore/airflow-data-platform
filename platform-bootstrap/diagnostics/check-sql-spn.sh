#!/bin/bash
# SQL Server SPN Checker and DBA Communication Helper
# Purpose: Generate exact information needed for DBA to fix SPN issues

set -e

# Source the shared formatting library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLATFORM_DIR="$(dirname "$SCRIPT_DIR")"
if [ -f "$PLATFORM_DIR/lib/formatting.sh" ]; then
    source "$PLATFORM_DIR/lib/formatting.sh"
else
    # Fallback if library not found - basic formatting
    echo "Warning: formatting library not found, using basic output" >&2
    print_check() { echo "[$1] $2"; }
    print_header() { echo "=== $1 ==="; }
    print_divider() { echo "========================================"; }
    print_msg() { echo "$@"; }
    CHECK_MARK="[OK]"
    CROSS_MARK="[FAIL]"
    WARNING_SIGN="[WARN]"
    GREEN=''
    YELLOW=''
    RED=''
    BLUE=''
    NC=''
fi

print_divider
echo "SQL Server SPN (Service Principal Name) Checker"
print_divider
echo ""
echo "This tool helps you communicate with your DBA about Kerberos SPN issues."
echo ""

# Get SQL Server details
if [ -n "$1" ]; then
    SQL_SERVER="$1"
else
    echo "Enter SQL Server hostname (e.g., sqlserver01.company.com):"
    read -p "SQL Server: " SQL_SERVER
fi

if [ -z "$SQL_SERVER" ]; then
    print_error "SQL Server hostname is required"
    exit 1
fi

# Try to detect domain from current Kerberos ticket
DOMAIN=""
if command -v klist >/dev/null 2>&1; then
    if klist 2>/dev/null | grep -q "Default principal"; then
        PRINCIPAL=$(klist 2>/dev/null | grep "Default principal:" | sed 's/Default principal: //')
        DOMAIN=$(echo "$PRINCIPAL" | sed 's/.*@//')
        print_check "PASS" "Detected domain from your Kerberos ticket: $DOMAIN"
    fi
fi

# If not detected, ask user
if [ -z "$DOMAIN" ]; then
    echo ""
    echo "Enter your Active Directory domain (e.g., COMPANY.COM):"
    read -p "Domain: " DOMAIN
fi

if [ -z "$DOMAIN" ]; then
    print_error "Domain is required"
    exit 1
fi

# Convert domain to uppercase for consistency
DOMAIN=$(echo "$DOMAIN" | tr '[:lower:]' '[:upper:]')

# Extract hostname from FQDN if needed
HOSTNAME=$(echo "$SQL_SERVER" | cut -d'.' -f1)
FQDN="$SQL_SERVER"

echo ""
echo "========================================================================="
echo "ANALYSIS"
echo "========================================================================="
echo ""
echo "SQL Server: $SQL_SERVER"
echo "Domain: $DOMAIN"
echo ""

# Show expected SPNs
print_list_header "EXPECTED SPNs (Service Principal Names):"
echo ""
echo "The SQL Server should have these SPNs registered in Active Directory:"
echo ""
echo "  1. MSSQLSvc/$FQDN:1433"
echo "  2. MSSQLSvc/$FQDN"
echo ""
if [ "$HOSTNAME" != "$FQDN" ]; then
    echo "Alternate forms (sometimes needed):"
    echo "  3. MSSQLSvc/$HOSTNAME:1433"
    echo "  4. MSSQLSvc/$HOSTNAME"
    echo ""
fi

# Show current Kerberos ticket info
print_divider
echo "YOUR CURRENT KERBEROS TICKET"
print_divider
echo ""

if command -v klist >/dev/null 2>&1; then
    if klist -s 2>/dev/null; then
        print_check "PASS" "You have a valid Kerberos ticket"
        echo ""
        klist 2>/dev/null | head -8
    else
        print_check "FAIL" "No valid Kerberos ticket found"
        echo ""
        echo "Get a ticket first:"
        echo "  kinit your_username@$DOMAIN"
    fi
else
    print_check "WARN" "klist command not available"
    echo "Cannot verify your Kerberos ticket status"
fi

echo ""
echo "========================================================================="
echo "MESSAGE FOR YOUR DBA"
echo "========================================================================="
echo ""
echo "Copy the section below and send it to your DBA or Domain Administrator:"
echo ""
echo "-------------------------------------------------------------------------"
echo "Subject: SQL Server SPN Registration Required for Kerberos Auth"
echo "-------------------------------------------------------------------------"
echo ""
echo "Hi,"
echo ""
echo "I'm getting Kerberos authentication errors when connecting to SQL Server."
echo "The error message is: 'Cannot generate SSPI context' or 'Login failed'"
echo ""
echo "This typically indicates that the SQL Server's Service Principal Names"
echo "(SPNs) are not properly registered in Active Directory."
echo ""
echo "Server Information:"
echo "  - SQL Server: $SQL_SERVER"
echo "  - Domain: $DOMAIN"
echo "  - Port: 1433 (default)"
echo ""
echo "Required SPNs:"
echo "  1. MSSQLSvc/$FQDN:1433"
echo "  2. MSSQLSvc/$FQDN"
echo ""
echo "Please verify if these SPNs are registered, and if not, register them"
echo "using the commands below (requires Domain Admin privileges):"
echo ""
echo "Step 1: Find the SQL Server service account"
echo "  - Check SQL Server Configuration Manager"
echo "  - Look for account running 'SQL Server (MSSQLSERVER)' service"
echo "  - Format: DOMAIN\\ServiceAccount or serviceaccount@domain.com"
echo ""
echo "Step 2: Register the SPNs"
echo "  setspn -A MSSQLSvc/$FQDN:1433 <SQL_SERVICE_ACCOUNT>"
echo "  setspn -A MSSQLSvc/$FQDN <SQL_SERVICE_ACCOUNT>"
echo ""
echo "Step 3: Verify registration"
echo "  setspn -L <SQL_SERVICE_ACCOUNT>"
echo ""
echo "Step 4: Check for duplicates (can cause issues)"
echo "  setspn -X"
echo ""
echo "Additional Information:"
echo "  - I have a valid Kerberos ticket for domain $DOMAIN"
echo "  - I can reach the server (network connectivity is OK)"
echo "  - Using Trusted_Connection=yes in connection string"
echo "  - ODBC Driver: 'ODBC Driver 17 for SQL Server'"
echo ""
echo "References:"
echo "  - https://docs.microsoft.com/en-us/sql/database-engine/configure-windows/register-a-service-principal-name-for-kerberos-connections"
echo ""
echo "Please let me know once the SPNs are registered so I can test again."
echo ""
echo "Thank you!"
echo "-------------------------------------------------------------------------"
echo ""
print_section "WHAT TO DO NEXT"
echo ""
echo "1. Copy the message above (scroll up if needed)"
echo "2. Send it to your DBA or Domain Administrator"
echo "3. Include any specific error messages from your connection attempts"
echo "4. Wait for confirmation that SPNs are registered"
echo "5. Test again with: ./test-kerberos.sh $SQL_SERVER <database_name>"
echo ""
print_divider
echo "ADVANCED: CHECKING SPNs YOURSELF (if you have domain access)"
print_divider
echo ""
echo "If you have access to a Windows machine with domain admin rights,"
echo "you can check and register SPNs yourself:"
echo ""
echo "Check if SPNs exist for this server:"
echo "  setspn -Q MSSQLSvc/$FQDN"
echo ""
echo "List all SPNs for SQL service account (if you know it):"
echo "  setspn -L <SQL_SERVICE_ACCOUNT>"
echo ""
echo "Find duplicate SPNs (can cause authentication failures):"
echo "  setspn -X"
echo ""
echo "Register missing SPNs (as Domain Admin):"
echo "  setspn -A MSSQLSvc/$FQDN:1433 <SQL_SERVICE_ACCOUNT>"
echo "  setspn -A MSSQLSvc/$FQDN <SQL_SERVICE_ACCOUNT>"
echo ""
print_success "Tool complete!"
