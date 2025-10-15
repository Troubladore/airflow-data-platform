#!/bin/bash
# SQL Server test using Microsoft's official sqlcmd tool
# Tests NT Authentication via Kerberos using integrated security (-E flag)
# No Python, no pip, no PyPI - just Microsoft's official tools

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
    CHECK_MARK="[OK]"
    CROSS_MARK="[FAIL]"
    WARNING_SIGN="[WARN]"
    GREEN=''
    RED=''
    YELLOW=''
    NC=''
fi

# Load .env to get corporate image sources and ODBC URL
if [ -f .env ]; then
    source .env
fi

print_header "SQL Server Kerberos Authentication Test"

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
    print_check "FAIL" "Kerberos service not running"
    echo ""
    echo "Start it first:"
    echo "  make platform-start"
    exit 1
fi

print_check "PASS" "Kerberos service running"
echo ""

# Determine ODBC driver URL (Microsoft or corporate mirror)
echo "Package Source Configuration:"
echo "------------------------------"
if [ -n "$MSSQL_TOOLS_URL" ]; then
    print_check "PASS" "MSSQL_TOOLS_URL is set in .env"
    echo "  Using corporate mirror:"
    print_msg "  ${YELLOW}$MSSQL_TOOLS_URL${NC}"
    ODBC_BASE_URL="$MSSQL_TOOLS_URL"
    IS_CORPORATE="true"
else
    print_check "WARN" "MSSQL_TOOLS_URL not set in .env"
    echo "  Using Microsoft public downloads:"
    print_msg "  ${YELLOW}https://download.microsoft.com${NC}"
    ODBC_BASE_URL="https://download.microsoft.com/download/7/6/d/76de322a-d860-4894-9945-f0cc5d6a45f8"
    IS_CORPORATE="false"
fi

# Check if .netrc exists for corporate authentication
NETRC_MOUNT=""
if [ -f "${HOME}/.netrc" ]; then
    if [ "$IS_CORPORATE" = "true" ]; then
        print_check "PASS" "Found .netrc - will mount for Artifactory auth"
        NETRC_MOUNT="-v ${HOME}/.netrc:/root/.netrc:ro"
    else
        print_check "INFO" "Found .netrc (not needed for public downloads)"
    fi
else
    if [ "$IS_CORPORATE" = "true" ]; then
        print_check "FAIL" "No .netrc found - corporate download may fail!"
        echo "  Create .netrc with Artifactory credentials"
    else
        print_check "PASS" "No .netrc needed for public downloads"
    fi
fi
echo "------------------------------"
echo ""

echo "Running SQL Server connection test with Microsoft sqlcmd..."
echo "(Downloading and installing Microsoft ODBC driver and tools)"
echo ""

# Show the actual Docker image being used
DOCKER_IMAGE="${IMAGE_ALPINE:-alpine:latest}"
echo "Docker image configuration:"
print_msg "  Using: ${YELLOW}$DOCKER_IMAGE${NC}"
if [[ "$DOCKER_IMAGE" == *"artifactory"* ]] || [[ "$DOCKER_IMAGE" == *"company"* ]]; then
    echo "  Source: Corporate registry"
else
    echo "  Source: Docker Hub (public)"
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
    ${DOCKER_IMAGE} \
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
        # Capture output for error analysis
        OUTPUT=$(sqlcmd -S "$SQL_SERVER" -d "$SQL_DATABASE" -E -C -Q "SELECT @@VERSION" 2>&1)
        RESULT=$?

        if [ $RESULT -eq 0 ]; then
            echo "$OUTPUT"
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
            echo "$OUTPUT"
            echo ""
            echo "=========================================="
            echo "❌ Connection failed"
            echo "=========================================="
            echo ""

            # Analyze specific error
            if echo "$OUTPUT" | grep -q "Login timeout expired"; then
                echo "🔍 Error Analysis: LOGIN TIMEOUT"
                echo "---------------------------------"
                echo "Cannot establish network connection to SQL Server."
                echo ""
                echo "Likely causes:"
                echo "  1. Server name is incorrect or not resolvable"
                echo "  2. SQL Server is not reachable (firewall/network)"
                echo "  3. SQL Server not listening on port 1433"
                echo ""
                echo "Diagnostics to run:"
                echo "  1. Test direct connectivity (bypasses sidecar):"
                echo "     ./test-sql-direct.sh $SQL_SERVER $SQL_DATABASE"
                echo ""
                echo "  2. Check DNS resolution:"
                echo "     nslookup $SQL_SERVER"
                echo ""
                echo "  3. Test network connectivity:"
                echo "     telnet $SQL_SERVER 1433"

            elif echo "$OUTPUT" | grep -q "Error code 0x2AF9"; then
                echo "🔍 Error Analysis: NETWORK ERROR (0x2AF9)"
                echo "------------------------------------------"
                echo "TCP connection failed - server not found or not accessible."
                echo ""
                echo "This is a network-level issue, NOT a Kerberos problem."
                echo ""
                echo "Required fixes:"
                echo "  1. Verify server name is correct (must be FQDN)"
                echo "  2. Ensure you are on corporate network/VPN"
                echo "  3. Check if SQL Server uses non-standard port"
                echo ""
                echo "Next step:"
                echo "  Run direct test to isolate the issue:"
                echo "     ./test-sql-direct.sh $SQL_SERVER $SQL_DATABASE"

            elif echo "$OUTPUT" | grep -q "Cannot authenticate using Kerberos"; then
                echo "🔍 Error Analysis: KERBEROS AUTHENTICATION FAILED"
                echo "--------------------------------------------------"
                echo "Network connection OK, but Kerberos auth rejected."
                echo ""
                echo "Likely causes:"
                echo "  1. SQL Server SPN not registered in Active Directory"
                echo "  2. Kerberos ticket not valid for this server"
                echo "  3. Clock skew between client and server"
                echo ""
                echo "Ask your DBA to verify SPNs:"
                echo "  setspn -L <sql-service-account>"

            elif echo "$OUTPUT" | grep -q "Login failed for user"; then
                echo "🔍 Error Analysis: LOGIN FAILED"
                echo "--------------------------------"
                echo "Authentication worked but access denied."
                echo ""
                echo "Likely causes:"
                echo "  1. User not granted access to database"
                echo "  2. Database name is incorrect"
                echo ""
                echo "Ask your DBA to grant access:"
                echo "  GRANT CONNECT TO [$DETECTED_USERNAME]"

            else
                echo "🔍 Error Analysis: UNKNOWN ERROR"
                echo "---------------------------------"
                echo "Could not identify specific error pattern."
                echo ""
                echo "Next steps:"
                echo "  1. Run direct connectivity test:"
                echo "     ./test-sql-direct.sh $SQL_SERVER $SQL_DATABASE"
                echo ""
                echo "  2. Check sidecar logs:"
                echo "     docker logs kerberos-platform-service --tail 50"
            fi

            echo ""
            echo "For detailed diagnostics:"
            echo "  ./diagnose-kerberos.sh"
            exit 1
        fi
    '

echo ""
echo "Test complete."
