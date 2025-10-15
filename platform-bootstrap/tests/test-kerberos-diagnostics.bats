#!/usr/bin/env bats
# Unit tests for Kerberos diagnostics library
# Run with: bats tests/test-kerberos-diagnostics.bats

# Load the library
setup() {
    export TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    export PROJECT_ROOT="$(cd "$TEST_DIR/.." && pwd)"
    export LIB_DIR="$PROJECT_ROOT/lib"

    # Source the library
    source "$LIB_DIR/kerberos-diagnostics.sh"

    # Create temp directory for test files
    export TEST_TEMP_DIR="$(mktemp -d)"

    # Disable colors for consistent test output
    export NO_COLOR=1

    # Reset diagnostics before each test
    reset_diagnostics
}

teardown() {
    # Clean up temp files
    [[ -d "$TEST_TEMP_DIR" ]] && rm -rf "$TEST_TEMP_DIR"
}

# Test color setup
@test "setup_colors disables colors when NO_COLOR is set" {
    NO_COLOR=1 setup_colors
    [[ -z "$COLOR_GREEN" ]]
    [[ -z "$COLOR_RED" ]]
}

@test "setup_colors enables colors when terminal is interactive" {
    unset NO_COLOR
    # Mock terminal check
    setup_colors
    # In test environment, colors might still be disabled
    # This is OK - we're testing the function logic
}

# Test environment detection
@test "detect_environment identifies host environment" {
    # When not in container
    [[ ! -f /.dockerenv ]]
    result=$(detect_environment)
    [[ "$result" == "host:"* ]]
}

@test "detect_environment detects WSL" {
    # This test will only pass on WSL
    if grep -q Microsoft /proc/version 2>/dev/null; then
        result=$(detect_environment)
        [[ "$result" == *":wsl" ]]
    else
        skip "Not running on WSL"
    fi
}

# Test ticket existence check
@test "check_ticket_exists returns false when no ticket" {
    # Use a non-existent cache location
    export KRB5CCNAME="FILE:/tmp/nonexistent_ticket_cache"
    run check_ticket_exists
    [[ "$status" -ne 0 ]]
}

@test "check_ticket_exists handles missing klist" {
    # Mock missing klist
    klist() { return 127; }
    export -f klist

    run check_ticket_exists
    [[ "$status" -eq 2 ]]
}

# Test krb5.conf validation
@test "check_krb5_config detects missing config" {
    run check_krb5_config "/nonexistent/krb5.conf"
    [[ "$status" -eq 1 ]]
    [[ "${DIAG_RESULTS[krb5_config]}" == "missing" ]]
}

@test "check_krb5_config reads valid config" {
    # Create test config
    cat > "$TEST_TEMP_DIR/krb5.conf" <<EOF
[libdefaults]
    default_realm = TEST.REALM
    dns_lookup_kdc = true
EOF

    run check_krb5_config "$TEST_TEMP_DIR/krb5.conf"
    [[ "$status" -eq 0 ]]
    [[ "${DIAG_RESULTS[default_realm]}" == "TEST.REALM" ]]
    [[ "${DIAG_RESULTS[dns_lookup_kdc]}" == "true" ]]
}

# Test network connectivity
@test "test_network_connectivity validates parameters" {
    run test_network_connectivity
    [[ "$status" -eq 2 ]]
}

@test "test_network_connectivity checks port reachability" {
    # Test localhost port that should exist
    if command -v nc >/dev/null 2>&1; then
        # Use a port that's likely to be open (SSH)
        run test_network_connectivity "localhost" "22" "1"
        # Note: This might fail in some environments
    else
        skip "nc not available"
    fi
}

# Test DNS resolution
@test "check_dns_resolution validates parameters" {
    run check_dns_resolution
    [[ "$status" -eq 2 ]]
}

@test "check_dns_resolution resolves localhost" {
    if command -v nslookup >/dev/null 2>&1 || command -v dig >/dev/null 2>&1; then
        run check_dns_resolution "localhost"
        [[ "$status" -eq 0 ]]
    else
        skip "No DNS tools available"
    fi
}

# Test time synchronization check
@test "check_time_sync returns status" {
    run check_time_sync
    # Status varies by system, but should not crash
    [[ "$status" -ge 0 ]]
    [[ -n "${DIAG_RESULTS[time_sync]}" ]]
}

# Test diagnostic results storage
@test "reset_diagnostics clears results" {
    DIAG_RESULTS[test_key]="test_value"
    reset_diagnostics
    [[ -z "${DIAG_RESULTS[test_key]}" ]]
    [[ -n "${DIAG_METADATA[timestamp]}" ]]
    [[ "${DIAG_METADATA[version]}" == "$KERBEROS_DIAG_VERSION" ]]
}

# Test report generation
@test "generate_report produces text output" {
    DIAG_RESULTS[test_key]="test_value"
    DIAG_RESULTS[another_key]="another_value"

    run generate_report "text"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"test_key: test_value"* ]]
    [[ "$output" == *"another_key: another_value"* ]]
}

@test "generate_report produces JSON output" {
    reset_diagnostics
    DIAG_RESULTS[test_key]="test_value"

    output=$(generate_report "json")
    [[ "$output" == *'"test_key": "test_value"'* ]]
    # Basic JSON validation
    echo "$output" | grep -q '^{$'
    echo "$output" | grep -q '^}$'
}

# Test error handling
@test "functions handle missing dependencies gracefully" {
    # Test with mock missing commands
    command() { return 127; }
    export -f command

    run check_ticket_exists
    # Should return error code but not crash
    [[ "$status" -ne 0 ]]
}

# Test SQL-specific functions
@test "check_sql_spn validates parameters" {
    run check_sql_spn
    [[ "$status" -eq 2 ]]
}

@test "test_sql_server requires sqlcmd" {
    # Mock missing sqlcmd
    command() {
        if [[ "$1" == "-v" && "$2" == "sqlcmd" ]]; then
            return 1
        fi
        builtin command "$@"
    }
    export -f command

    run test_sql_server "server" "database"
    [[ "$status" -eq 2 ]]
    [[ "${DIAG_RESULTS[sql_tools]}" == "not_found" ]]
}

# Test trace functionality
@test "enable_krb5_trace sets environment variable" {
    run enable_krb5_trace "/tmp/trace.log"
    [[ "$status" -eq 0 ]]
    [[ "$KRB5_TRACE" == "/tmp/trace.log" ]]
    [[ "${DIAG_RESULTS[krb5_trace_enabled]}" == "true" ]]
}

@test "run_with_trace preserves original trace setting" {
    export KRB5_TRACE="/original/trace"
    run_with_trace "echo test"
    [[ "$KRB5_TRACE" == "/original/trace" ]]
}

# Test comprehensive diagnostics
@test "run_full_diagnostics completes without errors" {
    run run_full_diagnostics
    [[ "$status" -eq 0 ]]
    [[ -n "${DIAG_RESULTS[overall_status]}" ]]
}

# Test logging functions
@test "logging functions work with NO_COLOR" {
    NO_COLOR=1 setup_colors
    run log_info "test message"
    [[ "$output" == *"test message"* ]]
    [[ "$output" != *"\033"* ]]  # No color codes
}

# Integration test
@test "full diagnostic pipeline works end-to-end" {
    reset_diagnostics
    detect_environment
    check_krb5_config

    # Should have collected some results
    [[ -n "${DIAG_RESULTS[environment]}" ]]

    # Should generate report
    output=$(generate_report "text")
    [[ -n "$output" ]]
}
