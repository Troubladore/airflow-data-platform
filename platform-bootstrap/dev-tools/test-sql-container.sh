#!/bin/bash
# Container-based SQL Server test with Kerberos diagnostics
# Runs diagnostic tool INSIDE a container to test ticket-based auth
# Can be used to debug production containers receiving tickets from sidecar

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
    RED='\033[0;31m'
    YELLOW='\033[1;33m'
    CYAN='\033[0;36m'
    NC='\033[0m'
fi

# Load .env for configuration
if [ -f .env ]; then
    source .env
fi

echo "🐳 Container-based SQL Server Test"
echo "===================================="
echo ""
echo "This test runs the Kerberos diagnostic INSIDE a container."
echo "Useful for debugging containers that receive tickets from the sidecar."
echo ""

# Parse arguments
SQL_SERVER="${1:-}"
SQL_DATABASE="${2:-}"
VERBOSE=""
NETWORK="platform_network"
DIAGNOSTIC_MODE="quick"

# Check for verbose flag
if [ "$3" = "-v" ] || [ "$3" = "--verbose" ]; then
    VERBOSE="-v"
    DIAGNOSTIC_MODE="verbose"
fi

if [ -z "$SQL_SERVER" ] || [ -z "$SQL_DATABASE" ]; then
    echo "Usage: $0 <sql-server> <database> [options]"
    echo ""
    echo "Options:"
    echo "  -v, --verbose     Detailed diagnostics"
    echo ""
    echo "Example:"
    echo "  $0 sqlserver01.company.com TestDB"
    echo "  $0 sqlserver01.company.com TestDB -v"
    echo ""
    echo "This test will:"
    echo "  1. Start a container with access to Kerberos tickets"
    echo "  2. Install diagnostic tools in the container"
    echo "  3. Run comprehensive Kerberos diagnostics"
    echo "  4. Test SQL Server authentication"
    exit 1
fi

echo -e "Target: ${CYAN}${SQL_SERVER}${NC} / ${CYAN}${SQL_DATABASE}${NC}"
echo -e "Mode: ${CYAN}${DIAGNOSTIC_MODE}${NC}"
echo ""

# Check if kerberos service is running
if ! docker ps | grep -q "kerberos-platform-service"; then
    echo -e "${YELLOW}⚠${NC}  Kerberos sidecar not running"
    echo ""
    echo "The sidecar provides tickets to containers."
    echo "Start it with: make platform-start"
    echo ""
    echo "Or run direct host test instead:"
    echo "  ./test-sql-direct.sh $SQL_SERVER $SQL_DATABASE"
    exit 1
fi

echo -e "${GREEN}✓${NC} Kerberos sidecar is running"

# Determine which diagnostic script to use
DIAG_SCRIPT="krb5-auth-test.sh"
if [ ! -f "$DIAG_SCRIPT" ]; then
    echo -e "${YELLOW}⚠${NC}  krb5-auth-test.sh not found locally"
    echo "  Will create basic diagnostic in container"
    DIAG_SCRIPT=""
fi

# Docker image to use
DOCKER_IMAGE="${IMAGE_ALPINE:-alpine:latest}"
echo ""
echo "Container configuration:"
echo -e "  Image: ${CYAN}$DOCKER_IMAGE${NC}"
echo -e "  Network: ${CYAN}$NETWORK${NC}"
echo ""

# Prepare the diagnostic script content if needed
if [ -n "$DIAG_SCRIPT" ]; then
    # Copy our diagnostic script
    MOUNT_DIAG="-v $(pwd)/$DIAG_SCRIPT:/tmp/krb5-auth-test.sh:ro"
else
    MOUNT_DIAG=""
fi

echo "Starting diagnostic container..."
echo ""

docker run --rm \
    --name "kerberos-diagnostic-$$" \
    --network "$NETWORK" \
    -v platform_kerberos_cache:/krb5/cache:ro \
    ${MOUNT_DIAG} \
    -e KRB5CCNAME=/krb5/cache/krb5cc \
    -e SQL_SERVER="$SQL_SERVER" \
    -e SQL_DATABASE="$SQL_DATABASE" \
    -e DIAGNOSTIC_MODE="$DIAGNOSTIC_MODE" \
    -e MSSQL_TOOLS_URL="${MSSQL_TOOLS_URL:-}" \
    ${DOCKER_IMAGE} \
    sh -c '
        echo "=== Container Environment ==="
        echo "Hostname: $(hostname)"
        echo "User: $(whoami)"
        echo "KRB5CCNAME: $KRB5CCNAME"
        echo ""

        # Install required tools
        echo "Installing diagnostic tools..."
        apk add --no-cache \
            krb5 \
            krb5-dev \
            curl \
            bind-tools \
            busybox-extras >/dev/null 2>&1 || {
                echo "Failed to install base packages"
                exit 1
            }

        # Check if we have the diagnostic script
        if [ -f /tmp/krb5-auth-test.sh ]; then
            echo ""
            echo "Running comprehensive Kerberos diagnostics..."
            echo "============================================"

            chmod +x /tmp/krb5-auth-test.sh

            # Run diagnostics with appropriate verbosity
            if [ "$DIAGNOSTIC_MODE" = "verbose" ]; then
                /tmp/krb5-auth-test.sh -v -s "$SQL_SERVER" -d "$SQL_DATABASE"
            else
                /tmp/krb5-auth-test.sh -q -s "$SQL_SERVER" -d "$SQL_DATABASE"
            fi

            RESULT=$?

            echo ""
            if [ $RESULT -eq 0 ]; then
                echo "✅ Container-based authentication SUCCESSFUL"
                echo ""
                echo "This confirms the sidecar is working correctly:"
                echo "  ✓ Tickets are being shared to containers"
                echo "  ✓ Container can authenticate to SQL Server"
                echo "  ✓ Kerberos delegation is functioning"
            else
                echo "❌ Container-based authentication FAILED"
                echo ""
                echo "Diagnostic exit code: $RESULT"

                if [ $RESULT -eq 1 ]; then
                    echo "Issue: No valid Kerberos ticket in container"
                    echo ""
                    echo "Check:"
                    echo "  1. Sidecar logs: docker logs kerberos-platform-service"
                    echo "  2. Volume mount: docker volume inspect platform_kerberos_cache"
                    echo "  3. Host ticket: klist on host system"
                elif [ $RESULT -eq 2 ]; then
                    echo "Issue: SQL Server connection failed from container"
                    echo ""
                    echo "This is likely a network or SPN issue."
                    echo "Try the direct host test to isolate:"
                    echo "  ./test-sql-direct.sh $SQL_SERVER $SQL_DATABASE"
                fi
            fi

            exit $RESULT
        else
            # Fallback to basic checks
            echo ""
            echo "Running basic Kerberos checks..."
            echo "================================="

            echo ""
            echo "1. Checking ticket cache..."
            if [ -f "$KRB5CCNAME" ] || [ -f "${KRB5CCNAME#FILE:}" ]; then
                echo "   ✓ Ticket cache file exists"

                if klist -s 2>/dev/null; then
                    echo "   ✓ Valid ticket found:"
                    klist 2>/dev/null | head -5 | sed "s/^/     /"
                else
                    echo "   ✗ No valid ticket in cache"
                    echo ""
                    echo "   The sidecar may not be sharing tickets properly."
                    echo "   Check: docker logs kerberos-platform-service"
                    exit 1
                fi
            else
                echo "   ✗ No ticket cache at: $KRB5CCNAME"
                echo ""
                echo "   The volume mount may be incorrect."
                echo "   Check: docker volume inspect platform_kerberos_cache"
                exit 1
            fi

            echo ""
            echo "2. Testing network connectivity..."
            if nc -zv "$SQL_SERVER" 1433 2>&1 | grep -q succeeded; then
                echo "   ✓ Can reach SQL Server on port 1433"
            else
                echo "   ✗ Cannot reach SQL Server"
                echo ""
                echo "   This is a network issue. Check:"
                echo "   - Container network configuration"
                echo "   - SQL Server name resolution"
                echo "   - Firewall rules"
                exit 2
            fi

            echo ""
            echo "3. Checking DNS resolution..."
            if nslookup "$SQL_SERVER" >/dev/null 2>&1; then
                echo "   ✓ DNS resolution working"
                nslookup "$SQL_SERVER" 2>/dev/null | grep -A2 "Name:" | sed "s/^/     /"
            else
                echo "   ✗ Cannot resolve $SQL_SERVER"
                exit 2
            fi

            # Try to test SQL if tools are available
            echo ""
            echo "4. SQL Server test..."

            # Check if we need to install SQL tools
            if ! command -v sqlcmd >/dev/null 2>&1; then
                echo "   Installing Microsoft SQL tools..."

                # Detect architecture
                case $(uname -m) in
                    x86_64) ARCH="amd64" ;;
                    aarch64|arm64) ARCH="arm64" ;;
                    *) echo "   ✗ Unsupported architecture: $(uname -m)"; exit 1 ;;
                esac

                # Download SQL tools
                if [ -n "$MSSQL_TOOLS_URL" ]; then
                    ODBC_URL="$MSSQL_TOOLS_URL"
                    echo "   Using corporate mirror"
                else
                    ODBC_URL="https://download.microsoft.com/download/7/6/d/76de322a-d860-4894-9945-f0cc5d6a45f8"
                    echo "   Using Microsoft public downloads"
                fi

                cd /tmp
                if curl -fsSL -o msodbcsql18.apk "${ODBC_URL}/msodbcsql18_18.4.1.1-1_${ARCH}.apk" 2>/dev/null && \
                   curl -fsSL -o mssql-tools18.apk "${ODBC_URL}/mssql-tools18_18.4.1.1-1_${ARCH}.apk" 2>/dev/null; then

                    apk add --allow-untrusted msodbcsql18.apk mssql-tools18.apk >/dev/null 2>&1 || {
                        echo "   ✗ Failed to install SQL tools"
                        exit 1
                    }
                    export PATH="/opt/mssql-tools18/bin:$PATH"
                    echo "   ✓ SQL tools installed"
                else
                    echo "   ✗ Failed to download SQL tools"
                    echo "   Cannot perform SQL test"
                    exit 0
                fi
            fi

            # Test SQL connection
            echo "   Testing SQL authentication..."
            OUTPUT=$(sqlcmd -S "$SQL_SERVER" -d "$SQL_DATABASE" -E -C \
                -Q "SELECT auth_scheme FROM sys.dm_exec_connections WHERE session_id = @@SPID" \
                -W -h -1 2>&1)

            if [ $? -eq 0 ]; then
                if echo "$OUTPUT" | grep -q "KERBEROS"; then
                    echo "   ✓ SQL Server: KERBEROS authentication working!"
                elif echo "$OUTPUT" | grep -q "NTLM"; then
                    echo "   ⚠ SQL Server: Using NTLM (not Kerberos)"
                else
                    echo "   ✓ SQL Server: Connected (auth: $OUTPUT)"
                fi
                echo ""
                echo "✅ Container-based SQL test PASSED"
                exit 0
            else
                echo "   ✗ SQL authentication failed"
                echo ""
                echo "$OUTPUT" | head -10 | sed "s/^/     /"
                echo ""
                echo "❌ Container-based SQL test FAILED"
                exit 2
            fi
        fi
    '

RESULT=$?

echo ""
echo "============================================"
if [ $RESULT -eq 0 ]; then
    echo -e "${GREEN}✅ Container diagnostic completed successfully${NC}"
    echo ""
    echo "The sidecar-based authentication is working correctly."
    echo "Containers can receive and use Kerberos tickets."
else
    echo -e "${RED}❌ Container diagnostic failed (exit code: $RESULT)${NC}"
    echo ""
    echo "Troubleshooting steps:"
    echo "  1. Check sidecar: docker logs kerberos-platform-service"
    echo "  2. Test from host: ./test-sql-direct.sh $SQL_SERVER $SQL_DATABASE"
    echo "  3. Run verbose diagnostics: $0 $SQL_SERVER $SQL_DATABASE -v"
fi

exit $RESULT
