#!/bin/bash
# SQL Server SPN Checker and DBA Communication Helper
# Purpose: Generate exact information needed for DBA to fix SPN issues

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "========================================================================="
echo "SQL Server SPN (Service Principal Name) Checker"
echo "========================================================================="
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
    echo -e "${RED}Error: SQL Server hostname is required${NC}"
    exit 1
fi

# Try to detect domain from current Kerberos ticket
DOMAIN=""
if command -v klist >/dev/null 2>&1; then
    if klist 2>/dev/null | grep -q "Default principal"; then
        PRINCIPAL=$(klist 2>/dev/null | grep "Default principal:" | sed 's/Default principal: //')
        DOMAIN=$(echo "$PRINCIPAL" | sed 's/.*@//')
        echo -e "${GREEN}✓ Detected domain from your Kerberos ticket: $DOMAIN${NC}"
    fi
fi

# If not detected, ask user
if [ -z "$DOMAIN" ]; then
    echo ""
    echo "Enter your Active Directory domain (e.g., COMPANY.COM):"
    read -p "Domain: " DOMAIN
fi

if [ -z "$DOMAIN" ]; then
    echo -e "${RED}Error: Domain is required${NC}"
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
echo -e "${YELLOW}EXPECTED SPNs (Service Principal Names):${NC}"
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
echo "========================================================================="
echo "YOUR CURRENT KERBEROS TICKET"
echo "========================================================================="
echo ""

if command -v klist >/dev/null 2>&1; then
    if klist -s 2>/dev/null; then
        echo -e "${GREEN}✓ You have a valid Kerberos ticket${NC}"
        echo ""
        klist 2>/dev/null | head -8
    else
        echo -e "${RED}✗ No valid Kerberos ticket found${NC}"
        echo ""
        echo "Get a ticket first:"
        echo "  kinit your_username@$DOMAIN"
    fi
else
    echo -e "${YELLOW}⚠ klist command not available${NC}"
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
echo -e "${BLUE}WHAT TO DO NEXT:${NC}"
echo ""
echo "1. Copy the message above (scroll up if needed)"
echo "2. Send it to your DBA or Domain Administrator"
echo "3. Include any specific error messages from your connection attempts"
echo "4. Wait for confirmation that SPNs are registered"
echo "5. Test again with: ./test-kerberos.sh $SQL_SERVER <database_name>"
echo ""
echo "========================================================================="
echo "ADVANCED: CHECKING SPNs YOURSELF (if you have domain access)"
echo "========================================================================="
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
echo -e "${GREEN}Tool complete!${NC}"
