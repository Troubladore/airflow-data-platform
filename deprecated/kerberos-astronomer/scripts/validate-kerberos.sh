#!/bin/bash
# Validate Kerberos configuration and ticket status
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo "==================================="
echo " Kerberos Configuration Validator"
echo "==================================="
echo ""

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check function
check() {
    if [ $1 -eq 0 ]; then
        echo -e "${GREEN}✓${NC} $2"
        return 0
    else
        echo -e "${RED}✗${NC} $2"
        return 1
    fi
}

# Warning function
warn() {
    echo -e "${YELLOW}⚠${NC} $1"
}

echo "1. Checking environment configuration..."
echo "-----------------------------------------"

# Check for .env file
if [ -f "$PROJECT_ROOT/.env" ]; then
    check 0 ".env file exists"
    source "$PROJECT_ROOT/.env"
else
    check 1 ".env file not found (copy from .env.template)"
    exit 1
fi

# Check required environment variables
REQUIRED_VARS="KRB_PRINCIPAL KRB_REALM"
for var in $REQUIRED_VARS; do
    if [ -z "${!var}" ]; then
        check 1 "$var is not set"
        EXIT_CODE=1
    else
        check 0 "$var is set: ${!var}"
    fi
done

echo ""
echo "2. Checking Kerberos configuration files..."
echo "--------------------------------------------"

# Check krb5.conf
KRB5_CONF="${KRB5_CONF_HOST:-/etc/krb5.conf}"
if [ -f "$KRB5_CONF" ]; then
    check 0 "krb5.conf found at $KRB5_CONF"

    # Validate krb5.conf has required realm
    if grep -q "$KRB_REALM" "$KRB5_CONF"; then
        check 0 "Realm $KRB_REALM configured in krb5.conf"
    else
        warn "Realm $KRB_REALM not found in krb5.conf"
    fi
else
    check 1 "krb5.conf not found at $KRB5_CONF"
    echo "  Tip: Create krb5.conf or set KRB5_CONF_HOST in .env"
fi

# Check for keytab (production mode)
if [ "${USE_PASSWORD}" != "true" ]; then
    KEYTAB="${KRB_KEYTAB_HOST:-./config/airflow.keytab}"
    if [ -f "$KEYTAB" ]; then
        check 0 "Keytab found at $KEYTAB"

        # Verify keytab contents
        if command -v klist &> /dev/null; then
            if klist -k "$KEYTAB" 2>/dev/null | grep -q "$KRB_PRINCIPAL"; then
                check 0 "Principal $KRB_PRINCIPAL found in keytab"
            else
                warn "Principal $KRB_PRINCIPAL not found in keytab"
            fi
        fi
    else
        check 1 "Keytab not found at $KEYTAB"
        echo "  Tip: Generate keytab or switch to password mode for development"
    fi
fi

echo ""
echo "3. Checking Docker configuration..."
echo "------------------------------------"

# Check Docker daemon
if docker info &> /dev/null; then
    check 0 "Docker daemon is running"
else
    check 1 "Docker daemon is not running"
    exit 1
fi

# Check if sidecar image exists or can be built
IMAGE_NAME="kerberos-sidecar:latest"
if docker images | grep -q "kerberos-sidecar"; then
    check 0 "Kerberos sidecar image exists"
else
    warn "Kerberos sidecar image not found (will be built)"
fi

echo ""
echo "4. Checking current Kerberos tickets..."
echo "----------------------------------------"

# Check for existing tickets
if command -v klist &> /dev/null; then
    if klist -s 2>/dev/null; then
        check 0 "Valid Kerberos ticket found"
        echo ""
        echo "Current tickets:"
        klist | head -10
    else
        warn "No valid Kerberos ticket in current session"
        echo "  Tip: Tickets will be obtained by sidecar container"
    fi
else
    warn "klist command not found (install krb5-user)"
fi

echo ""
echo "5. Testing network connectivity..."
echo "-----------------------------------"

# Extract KDC from krb5.conf if possible
if [ -f "$KRB5_CONF" ]; then
    KDC_HOST=$(grep -A5 "\[$KRB_REALM\]" "$KRB5_CONF" | grep "kdc" | head -1 | awk '{print $3}' | cut -d: -f1)
    if [ -n "$KDC_HOST" ]; then
        if ping -c 1 -W 2 "$KDC_HOST" &> /dev/null; then
            check 0 "KDC server $KDC_HOST is reachable"
        else
            warn "KDC server $KDC_HOST is not reachable"
            echo "  This is OK if using test mode or VPN is not connected"
        fi
    fi
fi

# Check SQL Server connectivity (if configured)
if [ -n "$MSSQL_SERVER" ]; then
    if nc -z -w2 "$MSSQL_SERVER" "${MSSQL_PORT:-1433}" 2>/dev/null; then
        check 0 "SQL Server $MSSQL_SERVER:${MSSQL_PORT:-1433} is reachable"
    else
        warn "SQL Server $MSSQL_SERVER:${MSSQL_PORT:-1433} is not reachable"
        echo "  This is OK if using test mode or VPN is not connected"
    fi
fi

echo ""
echo "6. Validation Summary"
echo "---------------------"

if [ "${EXIT_CODE:-0}" -eq 0 ]; then
    echo -e "${GREEN}✓ All critical checks passed${NC}"
    echo ""
    echo "Next steps:"
    echo "1. Run: docker-compose up -d kerberos-sidecar"
    echo "2. Check logs: docker-compose logs -f kerberos-sidecar"
    echo "3. Verify ticket: docker exec kerberos-sidecar klist"
else
    echo -e "${RED}✗ Some checks failed${NC}"
    echo ""
    echo "Please review the errors above and:"
    echo "1. Ensure .env is properly configured"
    echo "2. Verify krb5.conf exists and is valid"
    echo "3. Generate keytab or enable password mode"
    exit 1
fi
