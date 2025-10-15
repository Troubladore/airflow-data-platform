#!/bin/bash
# SQL Server test using Microsoft's official sqlcmd tool
# Tests NT Authentication via Kerberos using integrated security (-E flag)
# No Python, no pip, no PyPI - just Microsoft's official tools

set -e

# Load .env to get corporate image sources and ODBC URL
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

# Determine ODBC driver URL (Microsoft or corporate mirror)
if [ -n "$MSSQL_TOOLS_URL" ]; then
    echo "Using corporate ODBC mirror: $MSSQL_TOOLS_URL"
    ODBC_BASE_URL="$MSSQL_TOOLS_URL"
else
    echo "Using Microsoft downloads (https://download.microsoft.com)"
    ODBC_BASE_URL="https://download.microsoft.com/download/7/6/d/76de322a-d860-4894-9945-f0cc5d6a45f8"
fi
echo ""

echo "Running SQL Server connection test with Microsoft sqlcmd..."
echo "(Downloading and installing Microsoft ODBC driver and tools)"

# Check if .netrc exists for corporate authentication
NETRC_MOUNT=""
if [ -f "${HOME}/.netrc" ]; then
    echo "Found .netrc - will use for corporate repository authentication"
    NETRC_MOUNT="-v ${HOME}/.netrc:/root/.netrc:ro"
fi
echo ""

docker run --rm \
    --network platform_network \
    -v platform_kerberos_cache:/krb5/cache:ro \
    ${NETRC_MOUNT} \
    -e KRB5CCNAME=/krb5/cache/krb5cc \
    -e SQL_SERVER="$SQL_SERVER" \
    -e SQL_DATABASE="$SQL_DATABASE" \
    -e ODBC_BASE_URL="$ODBC_BASE_URL" \
    ${IMAGE_ALPINE:-alpine:latest} \
    sh -c '
        # Install prerequisites
        echo "Installing prerequisites..."
        apk add --no-cache curl krb5 >/dev/null 2>&1 || exit 1

        # Detect architecture
        case $(uname -m) in
            x86_64) ARCH="amd64" ;;
            aarch64|arm64) ARCH="arm64" ;;
            *) echo "Unsupported architecture: $(uname -m)"; exit 1 ;;
        esac

        # Download Microsoft ODBC driver and tools
        echo "Downloading Microsoft ODBC driver and sqlcmd..."
        cd /tmp

        # Try to download with proper error handling
        if ! curl -fsSL -o msodbcsql18.apk "${ODBC_BASE_URL}/msodbcsql18_18.4.1.1-1_${ARCH}.apk" 2>/dev/null; then
            # Fallback to newer version URL structure if needed
            echo "Trying alternative download URL..."
            FALLBACK_URL="https://download.microsoft.com/download/7/6/d/76de322a-d860-4894-9945-f0cc5d6a45f8"
            curl -fsSL -o msodbcsql18.apk "${FALLBACK_URL}/msodbcsql18_18.4.1.1-1_${ARCH}.apk" || {
                echo "Failed to download ODBC driver"
                echo "Check MSSQL_TOOLS_URL in .env for corporate mirror"
                exit 1
            }
        fi

        if ! curl -fsSL -o mssql-tools18.apk "${ODBC_BASE_URL}/mssql-tools18_18.4.1.1-1_${ARCH}.apk" 2>/dev/null; then
            # Fallback for tools
            FALLBACK_URL="https://download.microsoft.com/download/7/6/d/76de322a-d860-4894-9945-f0cc5d6a45f8"
            curl -fsSL -o mssql-tools18.apk "${FALLBACK_URL}/mssql-tools18_18.4.1.1-1_${ARCH}.apk" || {
                echo "Failed to download SQL tools"
                exit 1
            }
        fi

        # Install Microsoft packages
        echo "Installing Microsoft ODBC driver and sqlcmd..."
        apk add --allow-untrusted msodbcsql18.apk mssql-tools18.apk >/dev/null 2>&1 || {
            echo "Failed to install Microsoft packages"
            echo "This may be due to missing dependencies"
            exit 1
        }

        # Add sqlcmd to PATH
        export PATH="/opt/mssql-tools18/bin:$PATH"

        # Verify sqlcmd is available
        if ! command -v sqlcmd >/dev/null 2>&1; then
            echo "✗ sqlcmd not found after installation"
            exit 1
        fi
        echo "✓ sqlcmd installed successfully"
        echo ""

        # Check if ticket exists
        if klist -s 2>/dev/null; then
            echo "✓ Kerberos ticket available:"
            klist | head -3
        else
            echo "✗ No Kerberos ticket found"
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
