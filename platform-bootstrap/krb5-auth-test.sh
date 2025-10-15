#!/bin/bash
# Universal Kerberos Authentication Diagnostic Tool
# Works on host systems AND inside containers
# Provides deep diagnostics for ticket-based authentication issues
# Following MIT Kerberos and Microsoft Active Directory best practices

set -e

# Script version
VERSION="1.0.0"

# Color codes (disabled if NO_COLOR is set or not in terminal)
if [ -t 1 ] && [ -z "${NO_COLOR}" ]; then
    GREEN='\033[0;32m'
    RED='\033[0;31m'
    YELLOW='\033[1;33m'
    CYAN='\033[0;36m'
    BLUE='\033[0;34m'
    MAGENTA='\033[0;35m'
    BOLD='\033[1m'
    NC='\033[0m'
else
    GREEN=''
    RED=''
    YELLOW=''
    CYAN=''
    BLUE=''
    MAGENTA=''
    BOLD=''
    NC=''
fi

# Diagnostic levels
QUICK_MODE=false
VERBOSE_MODE=false
JSON_OUTPUT=false
SQL_SERVER=""
SQL_DATABASE=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -q|--quick)
            QUICK_MODE=true
            shift
            ;;
        -v|--verbose)
            VERBOSE_MODE=true
            shift
            ;;
        -j|--json)
            JSON_OUTPUT=true
            shift
            ;;
        -s|--sql-server)
            SQL_SERVER="$2"
            shift 2
            ;;
        -d|--database)
            SQL_DATABASE="$2"
            shift 2
            ;;
        -h|--help)
            echo "Kerberos Authentication Diagnostic Tool v${VERSION}"
            echo ""
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  -q, --quick           Quick mode - essential checks only"
            echo "  -v, --verbose         Verbose mode - detailed diagnostics"
            echo "  -j, --json           JSON output for automation"
            echo "  -s, --sql-server      SQL Server to test (optional)"
            echo "  -d, --database        Database name (requires -s)"
            echo "  -h, --help           Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0                    # Run standard diagnostics"
            echo "  $0 -q                 # Quick check only"
            echo "  $0 -v                 # Detailed diagnostics"
            echo "  $0 -s sqlserver01 -d TestDB  # Include SQL test"
            echo ""
            echo "Environment variables:"
            echo "  KRB5CCNAME            Ticket cache location"
            echo "  KRB5_CONFIG           Kerberos config file"
            echo "  KRB5_TRACE            Enable trace logging (set to /dev/stderr)"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use -h for help"
            exit 1
            ;;
    esac
done

# JSON output structure
declare -A RESULTS
RESULTS["timestamp"]=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
RESULTS["version"]="$VERSION"

# Helper functions
print_header() {
    if [ "$JSON_OUTPUT" = false ]; then
        echo ""
        echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════════${NC}"
        echo -e "${BOLD}${CYAN}  $1${NC}"
        echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════════${NC}"
        echo ""
    fi
}

print_section() {
    if [ "$JSON_OUTPUT" = false ]; then
        echo ""
        echo -e "${BOLD}${BLUE}▶ $1${NC}"
        echo -e "${BLUE}$(printf '─%.0s' {1..50})${NC}"
    fi
}

print_check() {
    local status="$1"
    local message="$2"
    local detail="$3"

    if [ "$JSON_OUTPUT" = false ]; then
        case "$status" in
            "PASS")
                echo -e "  ${GREEN}✓${NC} ${message}"
                ;;
            "FAIL")
                echo -e "  ${RED}✗${NC} ${message}"
                ;;
            "WARN")
                echo -e "  ${YELLOW}⚠${NC} ${message}"
                ;;
            "INFO")
                echo -e "  ${CYAN}ℹ${NC} ${message}"
                ;;
        esac

        if [ -n "$detail" ] && [ "$VERBOSE_MODE" = true ]; then
            echo -e "    ${CYAN}${detail}${NC}"
        fi
    fi
}

# 1. ENVIRONMENT DETECTION
check_environment() {
    print_section "Environment Detection"

    # Check if in container
    if [ -f /.dockerenv ]; then
        RESULTS["environment"]="container"
        print_check "INFO" "Running inside Docker container"

        # Check for Kubernetes
        if [ -n "$KUBERNETES_SERVICE_HOST" ]; then
            RESULTS["orchestrator"]="kubernetes"
            print_check "INFO" "Kubernetes environment detected"
        fi
    else
        RESULTS["environment"]="host"
        print_check "INFO" "Running on host system"

        # Check for WSL
        if grep -q Microsoft /proc/version 2>/dev/null; then
            RESULTS["platform"]="wsl"
            print_check "INFO" "WSL environment detected"
        elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
            RESULTS["platform"]="linux"
            print_check "INFO" "Linux system detected"
        elif [[ "$OSTYPE" == "darwin"* ]]; then
            RESULTS["platform"]="macos"
            print_check "INFO" "macOS system detected"
        fi
    fi

    # Check architecture
    RESULTS["architecture"]=$(uname -m)
    print_check "INFO" "Architecture: $(uname -m)"
}

# 2. KERBEROS CONFIGURATION
check_krb5_config() {
    print_section "Kerberos Configuration"

    # Find krb5.conf
    local krb5_conf=""
    if [ -n "$KRB5_CONFIG" ]; then
        krb5_conf="$KRB5_CONFIG"
        print_check "INFO" "Using KRB5_CONFIG: $krb5_conf"
    elif [ -f /etc/krb5.conf ]; then
        krb5_conf="/etc/krb5.conf"
        print_check "INFO" "Using system krb5.conf: $krb5_conf"
    else
        print_check "WARN" "No krb5.conf found"
        RESULTS["krb5_config"]="missing"
        return 1
    fi

    if [ -f "$krb5_conf" ]; then
        RESULTS["krb5_config"]="$krb5_conf"

        # Extract key information
        local default_realm=$(grep -E '^\s*default_realm' "$krb5_conf" 2>/dev/null | awk '{print $3}')
        if [ -n "$default_realm" ]; then
            RESULTS["default_realm"]="$default_realm"
            print_check "PASS" "Default realm: $default_realm"
        else
            print_check "WARN" "No default realm configured"
        fi

        # Check DNS settings
        if grep -q 'dns_lookup_kdc = true' "$krb5_conf" 2>/dev/null; then
            print_check "PASS" "DNS lookup for KDC enabled"
            RESULTS["dns_lookup_kdc"]="true"
        else
            print_check "INFO" "DNS lookup for KDC disabled (using static config)"
            RESULTS["dns_lookup_kdc"]="false"
        fi

        # Check ticket lifetime
        local ticket_lifetime=$(grep -E '^\s*ticket_lifetime' "$krb5_conf" 2>/dev/null | awk '{print $3}')
        if [ -n "$ticket_lifetime" ]; then
            print_check "INFO" "Ticket lifetime: $ticket_lifetime"
            RESULTS["ticket_lifetime"]="$ticket_lifetime"
        fi

        if [ "$VERBOSE_MODE" = true ]; then
            echo ""
            echo "  Configuration details:"
            grep -E '(default_realm|dns_lookup|ticket_lifetime|renew_lifetime|forwardable)' "$krb5_conf" | sed 's/^/    /'
        fi
    else
        print_check "FAIL" "Cannot read $krb5_conf"
        RESULTS["krb5_config"]="unreadable"
        return 1
    fi
}

# 3. TICKET CACHE ANALYSIS
check_ticket_cache() {
    print_section "Kerberos Ticket Cache"

    # Find ticket cache
    local ccache=""
    if [ -n "$KRB5CCNAME" ]; then
        ccache="$KRB5CCNAME"
        print_check "INFO" "KRB5CCNAME: $ccache"
    else
        # Check default locations
        if [ -f "/tmp/krb5cc_$(id -u)" ]; then
            ccache="FILE:/tmp/krb5cc_$(id -u)"
        elif [ -f "$HOME/.krb5/cache/krb5cc" ]; then
            ccache="FILE:$HOME/.krb5/cache/krb5cc"
        elif [ -f "/krb5/cache/krb5cc" ]; then
            ccache="FILE:/krb5/cache/krb5cc"
        else
            print_check "FAIL" "No ticket cache found"
            print_check "INFO" "Set KRB5CCNAME or run: kinit"
            RESULTS["ticket_cache"]="missing"
            return 1
        fi
        print_check "INFO" "Found ticket cache: $ccache"
    fi

    RESULTS["ticket_cache"]="$ccache"

    # Check ticket validity
    if ! command -v klist >/dev/null 2>&1; then
        print_check "WARN" "klist not available - cannot check tickets"
        RESULTS["klist_available"]="false"
        return 1
    fi

    RESULTS["klist_available"]="true"

    # Set cache for klist
    export KRB5CCNAME="$ccache"

    if klist -s 2>/dev/null; then
        print_check "PASS" "Valid Kerberos ticket found"
        RESULTS["ticket_valid"]="true"

        # Get ticket details
        local principal=$(klist 2>/dev/null | grep 'Default principal:' | cut -d: -f2- | xargs)
        local expires=$(klist 2>/dev/null | grep -A1 "Default principal" | tail -1 | awk '{print $3, $4, $5}')

        if [ -n "$principal" ]; then
            RESULTS["principal"]="$principal"
            print_check "INFO" "Principal: $principal"
        fi

        if [ -n "$expires" ]; then
            print_check "INFO" "Expires: $expires"

            # Check if near expiration (within 1 hour)
            if command -v date >/dev/null 2>&1; then
                local now=$(date +%s)
                local exp_time=$(date -d "$expires" +%s 2>/dev/null || date +%s)
                local diff=$((exp_time - now))

                if [ $diff -lt 3600 ] && [ $diff -gt 0 ]; then
                    print_check "WARN" "Ticket expires in less than 1 hour!"
                elif [ $diff -le 0 ]; then
                    print_check "FAIL" "Ticket has expired!"
                    RESULTS["ticket_valid"]="expired"
                fi
            fi
        fi

        # Check ticket flags
        if [ "$VERBOSE_MODE" = true ]; then
            echo ""
            echo "  Ticket details:"
            klist -v 2>/dev/null | grep -E '(Flags:|Auth time:|Start time:|End time:|Renew till:)' | head -10 | sed 's/^/    /'

            # Check for forwardable flag
            if klist -f 2>/dev/null | grep -q 'F'; then
                print_check "PASS" "Ticket is forwardable"
                RESULTS["ticket_forwardable"]="true"
            else
                print_check "WARN" "Ticket is NOT forwardable (may cause delegation issues)"
                RESULTS["ticket_forwardable"]="false"
            fi
        fi
    else
        print_check "FAIL" "No valid Kerberos ticket"
        RESULTS["ticket_valid"]="false"

        # Try to provide helpful error
        local klist_error=$(klist 2>&1)
        if echo "$klist_error" | grep -q "No credentials cache found"; then
            print_check "INFO" "Run: kinit <username>@<REALM>"
        elif echo "$klist_error" | grep -q "Ticket expired"; then
            print_check "INFO" "Ticket expired - run: kinit"
        fi

        return 1
    fi
}

# 4. NETWORK AND DNS CHECKS
check_network_dns() {
    if [ "$QUICK_MODE" = true ]; then
        return 0
    fi

    print_section "Network and DNS Configuration"

    # Check DNS resolution for KDC
    if [ -n "${RESULTS[default_realm]}" ]; then
        local realm="${RESULTS[default_realm]}"

        # Check for KDC DNS records
        if command -v nslookup >/dev/null 2>&1; then
            print_check "INFO" "Checking DNS for realm: $realm"

            # Look for _kerberos._tcp SRV records
            local srv_record="_kerberos._tcp.$realm"
            if nslookup -type=SRV "$srv_record" >/dev/null 2>&1; then
                print_check "PASS" "KDC SRV records found for $realm"
                RESULTS["kdc_dns"]="true"
            else
                print_check "WARN" "No KDC SRV records found (may use static config)"
                RESULTS["kdc_dns"]="false"
            fi
        elif command -v dig >/dev/null 2>&1; then
            local srv_record="_kerberos._tcp.$realm"
            if dig +short SRV "$srv_record" | grep -q .; then
                print_check "PASS" "KDC SRV records found"
                RESULTS["kdc_dns"]="true"
            else
                print_check "WARN" "No KDC SRV records found"
                RESULTS["kdc_dns"]="false"
            fi
        else
            print_check "INFO" "DNS tools not available"
        fi
    fi

    # Check time synchronization (critical for Kerberos)
    print_check "INFO" "Checking time synchronization..."

    if command -v timedatectl >/dev/null 2>&1; then
        local ntp_status=$(timedatectl status 2>/dev/null | grep "NTP" | head -1)
        if echo "$ntp_status" | grep -q "synchronized: yes\|active: yes"; then
            print_check "PASS" "Time synchronized via NTP"
            RESULTS["time_sync"]="true"
        else
            print_check "WARN" "Time not synchronized (Kerberos requires <5min skew)"
            RESULTS["time_sync"]="false"
        fi

        if [ "$VERBOSE_MODE" = true ]; then
            timedatectl status | grep -E '(Local time|Universal time|synchronized|NTP)' | sed 's/^/    /'
        fi
    elif command -v ntpstat >/dev/null 2>&1; then
        if ntpstat >/dev/null 2>&1; then
            print_check "PASS" "Time synchronized via NTP"
            RESULTS["time_sync"]="true"
        else
            print_check "WARN" "Time not synchronized"
            RESULTS["time_sync"]="false"
        fi
    else
        # Basic time check
        print_check "INFO" "Current time: $(date)"
    fi
}

# 5. SQL SERVER SPECIFIC CHECKS
check_sql_server() {
    if [ -z "$SQL_SERVER" ]; then
        return 0
    fi

    print_section "SQL Server Authentication Test"

    print_check "INFO" "Target: $SQL_SERVER / $SQL_DATABASE"

    # Check for SQL tools
    local sqlcmd=""
    if command -v sqlcmd >/dev/null 2>&1; then
        sqlcmd="sqlcmd"
    elif [ -x "/opt/mssql-tools18/bin/sqlcmd" ]; then
        sqlcmd="/opt/mssql-tools18/bin/sqlcmd"
    elif [ -x "/opt/mssql-tools/bin/sqlcmd" ]; then
        sqlcmd="/opt/mssql-tools/bin/sqlcmd"
    fi

    if [ -z "$sqlcmd" ]; then
        print_check "WARN" "sqlcmd not found - skipping SQL test"
        print_check "INFO" "Install: apt-get install mssql-tools18"
        RESULTS["sql_tools"]="missing"
        return 1
    fi

    RESULTS["sql_tools"]="available"
    print_check "PASS" "Found sqlcmd: $sqlcmd"

    # Check network connectivity
    print_check "INFO" "Testing network connectivity..."
    if command -v nc >/dev/null 2>&1; then
        if timeout 3 nc -zv "$SQL_SERVER" 1433 >/dev/null 2>&1; then
            print_check "PASS" "Port 1433 is reachable"
            RESULTS["sql_network"]="true"
        else
            print_check "FAIL" "Cannot reach port 1433"
            RESULTS["sql_network"]="false"
            return 1
        fi
    fi

    # Check for SQL Server SPNs
    if command -v ldapsearch >/dev/null 2>&1 && [ -n "${RESULTS[principal]}" ]; then
        print_check "INFO" "Checking SQL Server SPNs..."

        local spn_check="MSSQLSvc/${SQL_SERVER}:1433"
        # This would need proper LDAP configuration
        print_check "INFO" "Expected SPN: $spn_check"
    fi

    # Test SQL connection
    print_check "INFO" "Testing SQL Server authentication..."

    local output
    output=$("$sqlcmd" -S "$SQL_SERVER" -d "$SQL_DATABASE" -E -C \
        -Q "SELECT auth_scheme, protocol_type, client_net_address FROM sys.dm_exec_connections WHERE session_id = @@SPID" \
        -W -h -1 2>&1)
    local result=$?

    if [ $result -eq 0 ]; then
        print_check "PASS" "SQL Server connection successful!"
        RESULTS["sql_auth"]="success"

        # Check authentication method
        if echo "$output" | grep -q "KERBEROS"; then
            print_check "PASS" "Using KERBEROS authentication"
            RESULTS["sql_auth_method"]="KERBEROS"
        elif echo "$output" | grep -q "NTLM"; then
            print_check "WARN" "Using NTLM authentication (not Kerberos)"
            RESULTS["sql_auth_method"]="NTLM"
        else
            print_check "INFO" "Authentication method: $(echo "$output" | awk '{print $1}')"
        fi

        if [ "$VERBOSE_MODE" = true ]; then
            echo ""
            echo "  Connection details:"
            echo "$output" | sed 's/^/    /'
        fi
    else
        print_check "FAIL" "SQL Server connection failed"
        RESULTS["sql_auth"]="failed"

        # Analyze error
        if echo "$output" | grep -q "Login timeout"; then
            print_check "INFO" "Timeout - check network/firewall"
            RESULTS["sql_error"]="timeout"
        elif echo "$output" | grep -q "Login failed"; then
            print_check "INFO" "Authentication failed - check permissions"
            RESULTS["sql_error"]="auth_failed"
        elif echo "$output" | grep -q "Cannot authenticate using Kerberos"; then
            print_check "INFO" "Kerberos auth failed - check SPNs"
            RESULTS["sql_error"]="kerberos_failed"
        else
            if [ "$VERBOSE_MODE" = true ]; then
                echo ""
                echo "  Error details:"
                echo "$output" | head -20 | sed 's/^/    /'
            fi
        fi
    fi
}

# 6. COMMON ISSUES AND RECOMMENDATIONS
check_common_issues() {
    if [ "$QUICK_MODE" = true ]; then
        return 0
    fi

    print_section "Common Issues Check"

    # Check keytab if exists
    if [ -n "$KRB5_KTNAME" ] || [ -f "/etc/krb5.keytab" ]; then
        local keytab="${KRB5_KTNAME:-/etc/krb5.keytab}"
        if [ -f "$keytab" ]; then
            print_check "INFO" "Keytab found: $keytab"

            if command -v klist >/dev/null 2>&1; then
                local keytab_entries=$(klist -k "$keytab" 2>/dev/null | grep -c '@' || echo "0")
                if [ "$keytab_entries" -gt 0 ]; then
                    print_check "PASS" "Keytab contains $keytab_entries entries"
                else
                    print_check "WARN" "Keytab appears empty"
                fi
            fi
        fi
    fi

    # Check for common environment variables
    local important_vars=(
        "KRB5CCNAME"
        "KRB5_CONFIG"
        "KRB5_KTNAME"
        "KRB5_TRACE"
    )

    echo ""
    echo "  Environment variables:"
    for var in "${important_vars[@]}"; do
        if [ -n "${!var}" ]; then
            echo -e "    ${GREEN}✓${NC} $var=${!var}"
        else
            echo -e "    ${CYAN}○${NC} $var (not set)"
        fi
    done

    # Check for delegation
    if [ "${RESULTS[ticket_forwardable]}" = "false" ]; then
        print_check "WARN" "Ticket not forwardable - may cause issues with delegation"
        print_check "INFO" "Fix: kinit -f <username>"
    fi

    # Check file permissions
    if [ -n "${RESULTS[ticket_cache]}" ]; then
        local cache_file="${RESULTS[ticket_cache]#FILE:}"
        if [ -f "$cache_file" ]; then
            local perms=$(stat -c %a "$cache_file" 2>/dev/null || stat -f %A "$cache_file" 2>/dev/null)
            if [ -n "$perms" ]; then
                if [ "$perms" != "600" ]; then
                    print_check "WARN" "Ticket cache permissions: $perms (should be 600)"
                fi
            fi
        fi
    fi
}

# 7. GENERATE SUMMARY REPORT
generate_summary() {
    if [ "$JSON_OUTPUT" = true ]; then
        # Output JSON
        echo "{"
        for key in "${!RESULTS[@]}"; do
            echo "  \"$key\": \"${RESULTS[$key]}\","
        done | sed '$ s/,$//'
        echo "}"
        return
    fi

    print_header "DIAGNOSTIC SUMMARY"

    # Overall status
    local has_errors=false

    if [ "${RESULTS[ticket_valid]}" != "true" ]; then
        has_errors=true
        echo -e "${RED}✗ No valid Kerberos ticket${NC}"
    else
        echo -e "${GREEN}✓ Valid Kerberos ticket${NC}"
    fi

    if [ -n "${RESULTS[sql_auth]}" ]; then
        if [ "${RESULTS[sql_auth]}" = "success" ]; then
            if [ "${RESULTS[sql_auth_method]}" = "KERBEROS" ]; then
                echo -e "${GREEN}✓ SQL Server Kerberos auth working${NC}"
            else
                echo -e "${YELLOW}⚠ SQL Server using ${RESULTS[sql_auth_method]} (not Kerberos)${NC}"
            fi
        else
            echo -e "${RED}✗ SQL Server authentication failed${NC}"
            has_errors=true
        fi
    fi

    echo ""
    if [ "$has_errors" = true ]; then
        echo -e "${BOLD}${RED}Status: ISSUES DETECTED${NC}"
        echo ""
        echo "Recommended actions:"

        if [ "${RESULTS[ticket_valid]}" != "true" ]; then
            echo "  1. Obtain Kerberos ticket: kinit <username>@<REALM>"
        fi

        if [ "${RESULTS[sql_error]}" = "kerberos_failed" ]; then
            echo "  2. Check SQL Server SPNs with DBA"
        elif [ "${RESULTS[sql_error]}" = "timeout" ]; then
            echo "  2. Check network connectivity and firewall"
        elif [ "${RESULTS[sql_error]}" = "auth_failed" ]; then
            echo "  2. Check SQL Server permissions"
        fi

        if [ "${RESULTS[time_sync]}" = "false" ]; then
            echo "  3. Synchronize system time (NTP)"
        fi
    else
        echo -e "${BOLD}${GREEN}Status: ALL CHECKS PASSED${NC}"
    fi

    echo ""
    echo "Run with -v for detailed diagnostics"
    echo "Run with -j for JSON output (automation-friendly)"
}

# Main execution
main() {
    if [ "$JSON_OUTPUT" = false ]; then
        print_header "KERBEROS AUTHENTICATION DIAGNOSTICS v${VERSION}"
    fi

    check_environment
    check_krb5_config
    check_ticket_cache
    check_network_dns
    check_sql_server
    check_common_issues
    generate_summary

    # Exit code based on results
    if [ "${RESULTS[ticket_valid]}" != "true" ]; then
        exit 1
    fi

    if [ -n "${RESULTS[sql_auth]}" ] && [ "${RESULTS[sql_auth]}" != "success" ]; then
        exit 2
    fi

    exit 0
}

# Run main
main
