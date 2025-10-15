#!/bin/bash
# Kerberos Diagnostics Library
# Modular, testable functions for Kerberos authentication diagnostics
# Following principles from docs/kerberos/kerberos-diagnostics-design.md

# Version and metadata
readonly KERBEROS_DIAG_VERSION="1.0.0"
readonly KERBEROS_DIAG_LIB_PATH="$(dirname "${BASH_SOURCE[0]}")"

# Color codes (can be disabled with NO_COLOR environment variable)
setup_colors() {
    if [[ -t 1 && -z "${NO_COLOR}" ]]; then
        export COLOR_GREEN='\033[0;32m'
        export COLOR_RED='\033[0;31m'
        export COLOR_YELLOW='\033[1;33m'
        export COLOR_CYAN='\033[0;36m'
        export COLOR_BLUE='\033[0;34m'
        export COLOR_MAGENTA='\033[0;35m'
        export COLOR_BOLD='\033[1m'
        export COLOR_RESET='\033[0m'
    else
        export COLOR_GREEN=''
        export COLOR_RED=''
        export COLOR_YELLOW=''
        export COLOR_CYAN=''
        export COLOR_BLUE=''
        export COLOR_MAGENTA=''
        export COLOR_BOLD=''
        export COLOR_RESET=''
    fi
}

# Initialize colors on library load
setup_colors

# Logging functions with structured output
log_info() {
    echo -e "${COLOR_CYAN}ℹ${COLOR_RESET}  $*" >&2
}

log_success() {
    echo -e "${COLOR_GREEN}✓${COLOR_RESET} $*" >&2
}

log_error() {
    echo -e "${COLOR_RED}✗${COLOR_RESET} $*" >&2
}

log_warning() {
    echo -e "${COLOR_YELLOW}⚠${COLOR_RESET}  $*" >&2
}

log_debug() {
    [[ -n "${DEBUG}" ]] && echo -e "${COLOR_BLUE}[DEBUG]${COLOR_RESET} $*" >&2
}

# Diagnostic result structure
# Returns: 0 (success), 1 (warning), 2 (error)
declare -A DIAG_RESULTS
declare -A DIAG_METADATA

reset_diagnostics() {
    DIAG_RESULTS=()
    DIAG_METADATA=()
    DIAG_METADATA[timestamp]=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    DIAG_METADATA[version]="${KERBEROS_DIAG_VERSION}"
}

# Check if running in container
detect_environment() {
    local env_type="unknown"
    local platform="unknown"

    if [[ -f /.dockerenv ]]; then
        env_type="container"
    elif [[ -n "${KUBERNETES_SERVICE_HOST}" ]]; then
        env_type="kubernetes"
    else
        env_type="host"
    fi

    # Detect platform
    if grep -q Microsoft /proc/version 2>/dev/null; then
        platform="wsl"
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        platform="linux"
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        platform="macos"
    fi

    DIAG_RESULTS[environment]="${env_type}"
    DIAG_RESULTS[platform]="${platform}"

    log_debug "Environment: ${env_type}, Platform: ${platform}"
    echo "${env_type}:${platform}"
}

# Check for Kerberos ticket
check_ticket_exists() {
    local cache_location="${1:-${KRB5CCNAME}}"

    # If no cache specified, try to find default
    if [[ -z "${cache_location}" ]]; then
        if [[ -f "/tmp/krb5cc_$(id -u)" ]]; then
            cache_location="FILE:/tmp/krb5cc_$(id -u)"
        elif [[ -f "${HOME}/.krb5/cache/krb5cc" ]]; then
            cache_location="FILE:${HOME}/.krb5/cache/krb5cc"
        elif [[ -f "/krb5/cache/krb5cc" ]]; then
            cache_location="FILE:/krb5/cache/krb5cc"
        else
            log_debug "No ticket cache found"
            return 1
        fi
    fi

    # Export for klist to use
    export KRB5CCNAME="${cache_location}"

    if command -v klist >/dev/null 2>&1; then
        if klist -s 2>/dev/null; then
            DIAG_RESULTS[ticket_valid]="true"
            DIAG_RESULTS[ticket_cache]="${cache_location}"
            log_debug "Valid ticket found at ${cache_location}"
            return 0
        else
            DIAG_RESULTS[ticket_valid]="false"
            log_debug "No valid ticket at ${cache_location}"
            return 1
        fi
    else
        log_warning "klist not available"
        return 2
    fi
}

# Get ticket principal
get_ticket_principal() {
    if [[ "${DIAG_RESULTS[ticket_valid]}" != "true" ]]; then
        return 1
    fi

    local principal
    principal=$(klist 2>/dev/null | grep 'Default principal:' | cut -d: -f2- | xargs)

    if [[ -n "${principal}" ]]; then
        DIAG_RESULTS[principal]="${principal}"
        echo "${principal}"
        return 0
    fi

    return 1
}

# Check ticket expiration
check_ticket_expiration() {
    if [[ "${DIAG_RESULTS[ticket_valid]}" != "true" ]]; then
        return 1
    fi

    local expires
    expires=$(klist 2>/dev/null | grep -A1 "Default principal" | tail -1 | awk '{print $3, $4, $5}')

    if [[ -n "${expires}" ]]; then
        DIAG_RESULTS[ticket_expires]="${expires}"

        # Check if near expiration (within 1 hour)
        if command -v date >/dev/null 2>&1; then
            local now exp_time diff
            now=$(date +%s)
            exp_time=$(date -d "${expires}" +%s 2>/dev/null || date +%s)
            diff=$((exp_time - now))

            if [[ ${diff} -lt 3600 && ${diff} -gt 0 ]]; then
                DIAG_RESULTS[ticket_expiring_soon]="true"
                log_warning "Ticket expires in less than 1 hour"
                return 1
            elif [[ ${diff} -le 0 ]]; then
                DIAG_RESULTS[ticket_expired]="true"
                log_error "Ticket has expired"
                return 2
            fi
        fi

        return 0
    fi

    return 1
}

# Check krb5.conf configuration
check_krb5_config() {
    local config_file="${1:-${KRB5_CONFIG:-/etc/krb5.conf}}"

    if [[ ! -f "${config_file}" ]]; then
        DIAG_RESULTS[krb5_config]="missing"
        log_error "krb5.conf not found at ${config_file}"
        return 1
    fi

    if [[ ! -r "${config_file}" ]]; then
        DIAG_RESULTS[krb5_config]="unreadable"
        log_error "Cannot read ${config_file}"
        return 1
    fi

    DIAG_RESULTS[krb5_config]="${config_file}"

    # Extract key settings
    local default_realm
    default_realm=$(grep -E '^\s*default_realm' "${config_file}" 2>/dev/null | awk '{print $3}')

    if [[ -n "${default_realm}" ]]; then
        DIAG_RESULTS[default_realm]="${default_realm}"
        log_debug "Default realm: ${default_realm}"
    fi

    # Check DNS lookup settings
    if grep -q 'dns_lookup_kdc = true' "${config_file}" 2>/dev/null; then
        DIAG_RESULTS[dns_lookup_kdc]="true"
    else
        DIAG_RESULTS[dns_lookup_kdc]="false"
    fi

    return 0
}

# Check time synchronization
check_time_sync() {
    local max_skew="${1:-300}"  # Default 5 minutes

    # Try different methods to check time sync
    if command -v timedatectl >/dev/null 2>&1; then
        local ntp_status
        ntp_status=$(timedatectl status 2>/dev/null | grep "NTP" | head -1)

        if echo "${ntp_status}" | grep -q "synchronized: yes\|active: yes"; then
            DIAG_RESULTS[time_sync]="synchronized"
            log_debug "Time synchronized via NTP"
            return 0
        else
            DIAG_RESULTS[time_sync]="not_synchronized"
            log_warning "Time not synchronized"
            return 1
        fi
    elif command -v ntpstat >/dev/null 2>&1; then
        if ntpstat >/dev/null 2>&1; then
            DIAG_RESULTS[time_sync]="synchronized"
            return 0
        else
            DIAG_RESULTS[time_sync]="not_synchronized"
            return 1
        fi
    else
        DIAG_RESULTS[time_sync]="unknown"
        log_debug "Cannot determine time sync status"
        return 2
    fi
}

# Test network connectivity
test_network_connectivity() {
    local host="${1}"
    local port="${2:-88}"  # Default to Kerberos port
    local timeout="${3:-3}"

    if [[ -z "${host}" ]]; then
        log_error "Host not specified"
        return 2
    fi

    # Try different methods
    if command -v nc >/dev/null 2>&1; then
        if timeout "${timeout}" nc -zv "${host}" "${port}" >/dev/null 2>&1; then
            log_debug "Port ${port} on ${host} is reachable"
            return 0
        else
            log_debug "Port ${port} on ${host} is not reachable"
            return 1
        fi
    elif command -v telnet >/dev/null 2>&1; then
        if timeout "${timeout}" bash -c "echo quit | telnet ${host} ${port}" >/dev/null 2>&1; then
            return 0
        else
            return 1
        fi
    else
        log_warning "No network testing tools available (nc, telnet)"
        return 2
    fi
}

# Check DNS resolution
check_dns_resolution() {
    local hostname="${1}"

    if [[ -z "${hostname}" ]]; then
        return 2
    fi

    if command -v nslookup >/dev/null 2>&1; then
        if nslookup "${hostname}" >/dev/null 2>&1; then
            local ip
            ip=$(nslookup "${hostname}" 2>/dev/null | grep -A1 "Name:" | grep "Address:" | head -1 | awk '{print $2}')
            DIAG_RESULTS[dns_resolution_${hostname}]="${ip}"
            log_debug "DNS resolved ${hostname} to ${ip}"
            return 0
        fi
    elif command -v dig >/dev/null 2>&1; then
        if dig +short "${hostname}" | grep -q .; then
            return 0
        fi
    elif command -v host >/dev/null 2>&1; then
        if host "${hostname}" >/dev/null 2>&1; then
            return 0
        fi
    else
        log_warning "No DNS tools available"
        return 2
    fi

    log_debug "Failed to resolve ${hostname}"
    return 1
}

# Check for SQL Server SPNs
check_sql_spn() {
    local sql_server="${1}"
    local port="${2:-1433}"

    if [[ -z "${sql_server}" ]]; then
        return 2
    fi

    local spn="MSSQLSvc/${sql_server}:${port}"

    # Try to get service ticket
    if command -v kvno >/dev/null 2>&1; then
        if kvno "${spn}" >/dev/null 2>&1; then
            DIAG_RESULTS[sql_spn_valid]="true"
            log_debug "Successfully obtained service ticket for ${spn}"
            return 0
        else
            DIAG_RESULTS[sql_spn_valid]="false"
            log_debug "Failed to obtain service ticket for ${spn}"
            return 1
        fi
    else
        log_warning "kvno not available"
        return 2
    fi
}

# Enable Kerberos tracing
enable_krb5_trace() {
    local trace_output="${1:-/dev/stderr}"

    export KRB5_TRACE="${trace_output}"
    DIAG_RESULTS[krb5_trace_enabled]="true"
    DIAG_RESULTS[krb5_trace_output]="${trace_output}"

    log_info "Kerberos tracing enabled to ${trace_output}"
    return 0
}

# Run diagnostic with trace
run_with_trace() {
    local command="$*"

    if [[ -z "${command}" ]]; then
        return 2
    fi

    local original_trace="${KRB5_TRACE}"
    export KRB5_TRACE="/dev/stderr"

    log_debug "Running with trace: ${command}"
    eval "${command}"
    local result=$?

    if [[ -n "${original_trace}" ]]; then
        export KRB5_TRACE="${original_trace}"
    else
        unset KRB5_TRACE
    fi

    return ${result}
}

# Test SQL Server connectivity (requires sqlcmd)
test_sql_server() {
    local server="${1}"
    local database="${2}"
    local auth_type="${3:-kerberos}"  # kerberos or sql
    local username="${4}"
    local password="${5}"

    # Find sqlcmd
    local sqlcmd=""
    if command -v sqlcmd >/dev/null 2>&1; then
        sqlcmd="sqlcmd"
    elif [[ -x "/opt/mssql-tools18/bin/sqlcmd" ]]; then
        sqlcmd="/opt/mssql-tools18/bin/sqlcmd"
    elif [[ -x "/opt/mssql-tools/bin/sqlcmd" ]]; then
        sqlcmd="/opt/mssql-tools/bin/sqlcmd"
    else
        DIAG_RESULTS[sql_tools]="not_found"
        log_error "sqlcmd not found"
        return 2
    fi

    DIAG_RESULTS[sql_tools]="${sqlcmd}"

    local query="SELECT auth_scheme FROM sys.dm_exec_connections WHERE session_id = @@SPID"
    local output result

    if [[ "${auth_type}" == "kerberos" ]]; then
        output=$("${sqlcmd}" -S "${server}" -d "${database}" -E -C -Q "${query}" -W -h -1 2>&1)
        result=$?
    else
        output=$("${sqlcmd}" -S "${server}" -d "${database}" -U "${username}" -P "${password}" -C -Q "${query}" -W -h -1 2>&1)
        result=$?
    fi

    if [[ ${result} -eq 0 ]]; then
        DIAG_RESULTS[sql_connection]="success"

        if echo "${output}" | grep -q "KERBEROS"; then
            DIAG_RESULTS[sql_auth_method]="KERBEROS"
            log_success "SQL Server connected with KERBEROS"
        elif echo "${output}" | grep -q "NTLM"; then
            DIAG_RESULTS[sql_auth_method]="NTLM"
            log_warning "SQL Server connected with NTLM (not Kerberos)"
        else
            DIAG_RESULTS[sql_auth_method]="${output}"
        fi

        return 0
    else
        DIAG_RESULTS[sql_connection]="failed"
        DIAG_RESULTS[sql_error]="${output}"

        # Analyze error
        if echo "${output}" | grep -q "Login timeout"; then
            DIAG_RESULTS[sql_error_type]="timeout"
        elif echo "${output}" | grep -q "Login failed"; then
            DIAG_RESULTS[sql_error_type]="auth_failed"
        elif echo "${output}" | grep -q "Cannot authenticate using Kerberos"; then
            DIAG_RESULTS[sql_error_type]="kerberos_failed"
        else
            DIAG_RESULTS[sql_error_type]="unknown"
        fi

        log_error "SQL Server connection failed: ${DIAG_RESULTS[sql_error_type]}"
        return 1
    fi
}

# Generate diagnostic report
generate_report() {
    local format="${1:-text}"  # text or json

    if [[ "${format}" == "json" ]]; then
        # Generate JSON output
        echo "{"
        local first=true
        for key in "${!DIAG_RESULTS[@]}"; do
            if [[ "${first}" == true ]]; then
                first=false
            else
                echo ","
            fi
            echo -n "  \"${key}\": \"${DIAG_RESULTS[${key}]}\""
        done
        echo ""
        echo "}"
    else
        # Generate text report
        echo "=== Kerberos Diagnostic Report ==="
        echo "Timestamp: ${DIAG_METADATA[timestamp]}"
        echo "Version: ${DIAG_METADATA[version]}"
        echo ""

        for key in "${!DIAG_RESULTS[@]}"; do
            echo "${key}: ${DIAG_RESULTS[${key}]}"
        done
    fi
}

# Run comprehensive diagnostics
run_full_diagnostics() {
    local sql_server="${1}"
    local sql_database="${2}"

    reset_diagnostics

    log_info "Running comprehensive Kerberos diagnostics..."

    # Basic environment
    detect_environment

    # Kerberos configuration
    check_krb5_config

    # Ticket checks
    if check_ticket_exists; then
        get_ticket_principal
        check_ticket_expiration
    fi

    # Time sync
    check_time_sync

    # SQL Server specific
    if [[ -n "${sql_server}" ]]; then
        check_dns_resolution "${sql_server}"
        test_network_connectivity "${sql_server}" 1433

        if [[ "${DIAG_RESULTS[ticket_valid]}" == "true" ]]; then
            check_sql_spn "${sql_server}"

            if [[ -n "${sql_database}" ]]; then
                test_sql_server "${sql_server}" "${sql_database}"
            fi
        fi
    fi

    # Determine overall status
    local status="SUCCESS"

    if [[ "${DIAG_RESULTS[ticket_valid]}" != "true" ]]; then
        status="FAILURE"
    elif [[ -n "${sql_server}" && "${DIAG_RESULTS[sql_connection]}" == "failed" ]]; then
        status="FAILURE"
    elif [[ "${DIAG_RESULTS[time_sync]}" == "not_synchronized" ]]; then
        status="WARNING"
    fi

    DIAG_RESULTS[overall_status]="${status}"

    return 0
}

# Export all functions for use by other scripts
export -f setup_colors
export -f log_info log_success log_error log_warning log_debug
export -f reset_diagnostics detect_environment
export -f check_ticket_exists get_ticket_principal check_ticket_expiration
export -f check_krb5_config check_time_sync
export -f test_network_connectivity check_dns_resolution
export -f check_sql_spn enable_krb5_trace run_with_trace
export -f test_sql_server generate_report run_full_diagnostics
