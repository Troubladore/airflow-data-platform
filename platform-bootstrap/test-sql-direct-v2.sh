#!/bin/bash
# Direct SQL Server test from host (no Docker, no sidecar)
# Version 2: Uses modular diagnostic library for reliability and testability
# This intermediate test isolates authentication issues from container complexity

set -e

# Find script directory and load library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source the diagnostic library
if [[ -f "$SCRIPT_DIR/lib/kerberos-diagnostics.sh" ]]; then
    source "$SCRIPT_DIR/lib/kerberos-diagnostics.sh"
else
    echo "ERROR: Cannot find diagnostic library at $SCRIPT_DIR/lib/kerberos-diagnostics.sh"
    echo "This script requires the Kerberos diagnostics library to function."
    exit 2
fi

# Script metadata
readonly VERSION="2.0.0"
readonly SCRIPT_NAME="$(basename "$0")"

# Parse command line arguments
show_usage() {
    cat <<EOF
Direct SQL Server Test v${VERSION}
Tests Kerberos authentication directly from host without containers

Usage: $SCRIPT_NAME <sql-server> <database> [options]

Arguments:
  sql-server    SQL Server hostname (FQDN recommended)
  database      Database name to connect to

Options:
  -v, --verbose     Enable verbose output with detailed diagnostics
  -j, --json        Output results in JSON format
  -t, --trace       Enable Kerberos trace logging
  -h, --help        Show this help message

Examples:
  $SCRIPT_NAME sqlserver01.company.com TestDB
  $SCRIPT_NAME sqlserver01.company.com TestDB -v    # Verbose mode
  $SCRIPT_NAME sqlserver01.company.com TestDB -j    # JSON output
  $SCRIPT_NAME sqlserver01.company.com TestDB -t    # With trace logging

Exit codes:
  0 - Success
  1 - Test failed
  2 - Invalid arguments or missing dependencies

For comprehensive diagnostics, use:
  ./krb5-auth-test.sh -s <sql-server> -d <database> -v
EOF
}

# Initialize variables
SQL_SERVER=""
SQL_DATABASE=""
VERBOSE=false
JSON_OUTPUT=false
TRACE_ENABLED=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_usage
            exit 0
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -j|--json)
            JSON_OUTPUT=true
            export NO_COLOR=1  # Disable colors for JSON output
            shift
            ;;
        -t|--trace)
            TRACE_ENABLED=true
            shift
            ;;
        -*)
            echo "Unknown option: $1"
            show_usage
            exit 2
            ;;
        *)
            if [[ -z "$SQL_SERVER" ]]; then
                SQL_SERVER="$1"
            elif [[ -z "$SQL_DATABASE" ]]; then
                SQL_DATABASE="$1"
            else
                echo "Too many arguments"
                show_usage
                exit 2
            fi
            shift
            ;;
    esac
done

# Validate required arguments
if [[ -z "$SQL_SERVER" ]] || [[ -z "$SQL_DATABASE" ]]; then
    echo "Error: Missing required arguments"
    echo ""
    show_usage
    exit 2
fi

# Main test function
run_direct_sql_test() {
    # Initialize diagnostics
    reset_diagnostics

    # Set metadata
    DIAG_METADATA[script]="$SCRIPT_NAME"
    DIAG_METADATA[script_version]="$VERSION"
    DIAG_METADATA[sql_server]="$SQL_SERVER"
    DIAG_METADATA[sql_database]="$SQL_DATABASE"

    if [[ "$JSON_OUTPUT" != true ]]; then
        echo "🔍 Direct SQL Server Test (Host → SQL)"
        echo "========================================"
        echo ""
        echo "Version: $VERSION"
        echo "Target: ${COLOR_CYAN}${SQL_SERVER}${COLOR_RESET} / ${COLOR_CYAN}${SQL_DATABASE}${COLOR_RESET}"
        echo "Mode: Direct from host (no containers)"
        echo ""
    fi

    # Enable trace if requested
    if [[ "$TRACE_ENABLED" == true ]]; then
        enable_krb5_trace "/dev/stderr"
        [[ "$JSON_OUTPUT" != true ]] && log_info "Kerberos tracing enabled"
    fi

    # Step 1: Environment detection
    if [[ "$VERBOSE" == true ]] && [[ "$JSON_OUTPUT" != true ]]; then
        echo "Step 1: Environment Detection"
        echo "------------------------------"
    fi

    local env_info
    env_info=$(detect_environment)
    [[ "$VERBOSE" == true ]] && [[ "$JSON_OUTPUT" != true ]] && log_info "Environment: $env_info"

    # Step 2: Check Kerberos configuration
    if [[ "$VERBOSE" == true ]] && [[ "$JSON_OUTPUT" != true ]]; then
        echo ""
        echo "Step 2: Kerberos Configuration"
        echo "-------------------------------"
    fi

    if check_krb5_config; then
        [[ "$JSON_OUTPUT" != true ]] && log_success "krb5.conf found at ${DIAG_RESULTS[krb5_config]}"
        if [[ -n "${DIAG_RESULTS[default_realm]}" ]]; then
            [[ "$VERBOSE" == true ]] && [[ "$JSON_OUTPUT" != true ]] && log_info "Default realm: ${DIAG_RESULTS[default_realm]}"
        fi
    else
        [[ "$JSON_OUTPUT" != true ]] && log_warning "krb5.conf not found or unreadable"
    fi

    # Step 3: Check for Kerberos ticket
    if [[ "$VERBOSE" == true ]] && [[ "$JSON_OUTPUT" != true ]]; then
        echo ""
        echo "Step 3: Kerberos Ticket Validation"
        echo "-----------------------------------"
    fi

    if ! check_ticket_exists; then
        [[ "$JSON_OUTPUT" != true ]] && log_error "No valid Kerberos ticket found!"
        [[ "$JSON_OUTPUT" != true ]] && echo ""
        [[ "$JSON_OUTPUT" != true ]] && echo "You need to authenticate first:"
        [[ "$JSON_OUTPUT" != true ]] && echo "  kinit YOUR_USERNAME@DOMAIN.COM"

        DIAG_RESULTS[test_result]="FAILED"
        DIAG_RESULTS[failure_reason]="no_ticket"

        if [[ "$JSON_OUTPUT" == true ]]; then
            generate_report "json"
        fi
        return 1
    fi

    [[ "$JSON_OUTPUT" != true ]] && log_success "Valid Kerberos ticket found"

    # Get ticket details
    local principal
    principal=$(get_ticket_principal)
    if [[ -n "$principal" ]]; then
        [[ "$VERBOSE" == true ]] && [[ "$JSON_OUTPUT" != true ]] && log_info "Principal: $principal"
    fi

    # Check expiration
    if ! check_ticket_expiration; then
        [[ "$JSON_OUTPUT" != true ]] && log_warning "Ticket expiration issue detected"
    fi

    # Step 4: Network connectivity
    if [[ "$VERBOSE" == true ]] && [[ "$JSON_OUTPUT" != true ]]; then
        echo ""
        echo "Step 4: Network Connectivity"
        echo "-----------------------------"
    fi

    # DNS resolution
    if check_dns_resolution "$SQL_SERVER"; then
        [[ "$JSON_OUTPUT" != true ]] && log_success "DNS resolution successful"
    else
        [[ "$JSON_OUTPUT" != true ]] && log_error "Cannot resolve $SQL_SERVER"
        DIAG_RESULTS[test_result]="FAILED"
        DIAG_RESULTS[failure_reason]="dns_resolution"

        if [[ "$JSON_OUTPUT" == true ]]; then
            generate_report "json"
        fi
        return 1
    fi

    # Port connectivity
    if test_network_connectivity "$SQL_SERVER" 1433; then
        [[ "$JSON_OUTPUT" != true ]] && log_success "Port 1433 is reachable"
    else
        [[ "$JSON_OUTPUT" != true ]] && log_error "Cannot reach SQL Server on port 1433"
        [[ "$JSON_OUTPUT" != true ]] && echo ""
        [[ "$JSON_OUTPUT" != true ]] && echo "Common causes:"
        [[ "$JSON_OUTPUT" != true ]] && echo "  - Not connected to VPN"
        [[ "$JSON_OUTPUT" != true ]] && echo "  - Firewall blocking connection"
        [[ "$JSON_OUTPUT" != true ]] && echo "  - SQL Server using non-standard port"

        DIAG_RESULTS[test_result]="FAILED"
        DIAG_RESULTS[failure_reason]="network_connectivity"

        if [[ "$JSON_OUTPUT" == true ]]; then
            generate_report "json"
        fi
        return 1
    fi

    # Step 5: Check time synchronization
    if [[ "$VERBOSE" == true ]] && [[ "$JSON_OUTPUT" != true ]]; then
        echo ""
        echo "Step 5: Time Synchronization"
        echo "-----------------------------"
    fi

    if check_time_sync; then
        [[ "$VERBOSE" == true ]] && [[ "$JSON_OUTPUT" != true ]] && log_success "Time synchronized"
    else
        [[ "$JSON_OUTPUT" != true ]] && log_warning "Time not synchronized (Kerberos requires <5min skew)"
    fi

    # Step 6: SQL Server SPN check
    if [[ "$VERBOSE" == true ]] && [[ "$JSON_OUTPUT" != true ]]; then
        echo ""
        echo "Step 6: SQL Server SPN Validation"
        echo "----------------------------------"
    fi

    if check_sql_spn "$SQL_SERVER"; then
        [[ "$JSON_OUTPUT" != true ]] && log_success "Successfully obtained service ticket for SQL SPN"
    else
        [[ "$JSON_OUTPUT" != true ]] && log_warning "Could not obtain service ticket for SQL SPN"
        [[ "$JSON_OUTPUT" != true ]] && echo "  This might indicate SPN configuration issues"
    fi

    # Step 7: SQL Server connection test
    if [[ "$JSON_OUTPUT" != true ]]; then
        echo ""
        echo "Step 7: SQL Server Authentication Test"
        echo "---------------------------------------"
    fi

    if test_sql_server "$SQL_SERVER" "$SQL_DATABASE"; then
        DIAG_RESULTS[test_result]="SUCCESS"

        if [[ "$JSON_OUTPUT" != true ]]; then
            echo ""
            echo "========================================="
            log_success "${COLOR_BOLD}SUCCESS! Direct Kerberos auth works!${COLOR_RESET}"
            echo "========================================="
            echo ""

            if [[ "${DIAG_RESULTS[sql_auth_method]}" == "KERBEROS" ]]; then
                log_success "Authentication method: KERBEROS"
            else
                log_warning "Authentication method: ${DIAG_RESULTS[sql_auth_method]}"
            fi

            echo ""
            echo "This confirms:"
            echo "  ✓ Your Kerberos ticket is valid"
            echo "  ✓ SQL Server SPNs are configured correctly"
            echo "  ✓ Network connectivity is working"
            echo "  ✓ SQL Server accepts your credentials"
            echo ""
            echo "Next: Test via sidecar (Step 11) to verify container setup"
        fi

        if [[ "$JSON_OUTPUT" == true ]]; then
            generate_report "json"
        fi

        return 0
    else
        DIAG_RESULTS[test_result]="FAILED"

        if [[ "$JSON_OUTPUT" != true ]]; then
            echo ""
            echo "========================================="
            log_error "${COLOR_BOLD}Direct connection FAILED${COLOR_RESET}"
            echo "========================================="
            echo ""

            # Provide specific guidance based on error type
            case "${DIAG_RESULTS[sql_error_type]}" in
                timeout)
                    echo "Error: Connection timeout"
                    echo "Check network connectivity and firewall rules"
                    ;;
                auth_failed)
                    echo "Error: Authentication failed"
                    echo "Your account may not have SQL Server access"
                    ;;
                kerberos_failed)
                    echo "Error: Kerberos authentication failed"
                    echo "Check SPN configuration with your DBA"
                    ;;
                *)
                    echo "Error: ${DIAG_RESULTS[sql_error_type]}"
                    if [[ "$VERBOSE" == true ]]; then
                        echo ""
                        echo "Error details:"
                        echo "${DIAG_RESULTS[sql_error]}"
                    fi
                    ;;
            esac

            echo ""
            echo "For detailed diagnostics, run:"
            echo "  $0 $SQL_SERVER $SQL_DATABASE -v"
            echo "  ./krb5-auth-test.sh -s $SQL_SERVER -d $SQL_DATABASE -v"
        fi

        if [[ "$JSON_OUTPUT" == true ]]; then
            generate_report "json"
        fi

        return 1
    fi
}

# Run the test
if run_direct_sql_test; then
    exit 0
else
    exit 1
fi
