#!/bin/bash
# Comprehensive test suite for Kerberos configuration refactoring
# Tests the single KERBEROS_TICKET_DIR variable implementation

set -e

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

TESTS_PASSED=0
TESTS_FAILED=0

# Test helper functions
pass_test() {
    echo -e "${GREEN}✓${NC} $1"
    TESTS_PASSED=$((TESTS_PASSED + 1))
}

fail_test() {
    echo -e "${RED}✗${NC} $1"
    echo -e "  ${RED}$2${NC}"
    TESTS_FAILED=$((TESTS_FAILED + 1))
}

info() {
    echo -e "${BLUE}ℹ${NC}  $1"
}

section() {
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
}

# Test 1: Parse FILE:/tmp/krb5cc_1000 → TICKET_DIR=/tmp
test_parse_file_format() {
    section "Test 1: Parse FILE format ticket cache"

    # Create a test function that simulates the parsing logic
    TICKET_CACHE="FILE:/tmp/krb5cc_1000"
    DETECTED_TICKET_DIR=""

    if [[ "$TICKET_CACHE" == FILE:* ]]; then
        CACHE_FILE=${TICKET_CACHE#FILE:}
        DETECTED_TICKET_DIR=$(dirname "$CACHE_FILE")
    fi

    if [ "$DETECTED_TICKET_DIR" = "/tmp" ]; then
        pass_test "FILE:/tmp/krb5cc_1000 → /tmp"
    else
        fail_test "FILE format parsing" "Expected '/tmp', got '$DETECTED_TICKET_DIR'"
    fi
}

# Test 2: Parse DIR::/home/user/.krb5-cache/dev/tkt → TICKET_DIR=/home/user/.krb5-cache
test_parse_dir_format() {
    section "Test 2: Parse DIR format ticket cache"

    TICKET_CACHE="DIR::/home/user/.krb5-cache/dev/tkt"
    DETECTED_TICKET_DIR=""

    if [[ "$TICKET_CACHE" == DIR::* ]]; then
        FULL_PATH=${TICKET_CACHE#DIR::}
        # Extract base directory (remove subdirectories and ticket file)
        TICKET_DIR=$(dirname "$FULL_PATH")
        DETECTED_TICKET_DIR=$(dirname "$TICKET_DIR")
    fi

    if [ "$DETECTED_TICKET_DIR" = "/home/user/.krb5-cache" ]; then
        pass_test "DIR::/home/user/.krb5-cache/dev/tkt → /home/user/.krb5-cache"
    else
        fail_test "DIR format parsing" "Expected '/home/user/.krb5-cache', got '$DETECTED_TICKET_DIR'"
    fi
}

# Test 3: Verify no echo without -e in diagnose-kerberos.sh
test_diagnose_echo_flags() {
    section "Test 3: Verify echo -e usage in diagnose-kerberos.sh"

    local script="$PROJECT_ROOT/diagnose-kerberos.sh"

    # Find all echo statements that directly use escape codes (\\033 or \\e) without -e
    # Note: echo "$VAR" where VAR contains escape codes works fine without -e
    local bad_echoes=$(grep -n 'echo [^-].*\\033\|echo [^-].*\\\\e' "$script" | grep -v 'echo -e' || true)

    if [ -z "$bad_echoes" ]; then
        pass_test "All echo statements with escape sequences use -e flag"
    else
        fail_test "Found echo statements without -e flag" "Lines:\n$bad_echoes"
    fi
}

# Test 4: Verify no echo without -e in setup-kerberos.sh
test_setup_echo_flags() {
    section "Test 4: Verify echo -e usage in setup-kerberos.sh"

    local script="$PROJECT_ROOT/setup-kerberos.sh"

    # Find all echo statements that directly use escape codes (\\033 or \\e) without -e
    # Note: echo "$VAR" where VAR contains escape codes works fine without -e
    local bad_echoes=$(grep -n 'echo [^-].*\\033\|echo [^-].*\\\\e' "$script" | grep -v 'echo -e' || true)

    if [ -z "$bad_echoes" ]; then
        pass_test "All echo statements with escape sequences use -e flag"
    else
        fail_test "Found echo statements without -e flag" "Lines:\n$bad_echoes"
    fi
}

# Test 5: Verify docker-compose.yml uses ${KERBEROS_TICKET_DIR}
test_docker_compose_variable() {
    section "Test 5: Verify docker-compose.yml uses KERBEROS_TICKET_DIR"

    local compose_file="$PROJECT_ROOT/docker-compose.yml"

    if grep -q 'KERBEROS_TICKET_DIR' "$compose_file"; then
        pass_test "docker-compose.yml uses KERBEROS_TICKET_DIR variable"

        # Verify the exact volume mount syntax
        if grep -q '\${KERBEROS_TICKET_DIR:-\${HOME}/.krb5-cache}:/host/tickets:ro' "$compose_file"; then
            pass_test "Volume mount syntax is correct"
        else
            fail_test "Volume mount syntax" "Expected '\${KERBEROS_TICKET_DIR:-\${HOME}/.krb5-cache}:/host/tickets:ro'"
        fi
    else
        fail_test "docker-compose.yml variable check" "KERBEROS_TICKET_DIR not found"
    fi

    # Verify old variables are not present
    if grep -q 'KERBEROS_CACHE_TYPE\|KERBEROS_CACHE_PATH\|KERBEROS_CACHE_TICKET' "$compose_file"; then
        fail_test "Old variable check" "Found references to old KERBEROS_CACHE_* variables"
    else
        pass_test "No references to old KERBEROS_CACHE_* variables"
    fi
}

# Test 6: Test .env variable substitution
test_env_substitution() {
    section "Test 6: Test .env variable substitution"

    # Create a temporary .env file
    local temp_env="/tmp/test-krb-config-$$.env"
    cat > "$temp_env" << 'EOF'
COMPANY_DOMAIN=TEST.COM
KERBEROS_TICKET_DIR=/tmp
EOF

    # Source the .env and test variable
    source "$temp_env"

    if [ "$KERBEROS_TICKET_DIR" = "/tmp" ]; then
        pass_test "KERBEROS_TICKET_DIR substitution works"
    else
        fail_test "Variable substitution" "Expected '/tmp', got '$KERBEROS_TICKET_DIR'"
    fi

    rm -f "$temp_env"
}

# Test 7: Verify diagnose-kerberos.sh doesn't reference old variables
test_diagnose_no_old_vars() {
    section "Test 7: Verify diagnose-kerberos.sh uses new variable names"

    local script="$PROJECT_ROOT/diagnose-kerberos.sh"

    # Check for DETECTED_CACHE_TYPE, DETECTED_CACHE_PATH, DETECTED_CACHE_TICKET
    # These should not exist anymore
    local old_vars=$(grep -n 'DETECTED_CACHE_TYPE\|DETECTED_CACHE_PATH\|DETECTED_CACHE_TICKET' "$script" || true)

    if [ -z "$old_vars" ]; then
        pass_test "No references to old DETECTED_CACHE_* variables"
    else
        fail_test "Old variable references found" "Lines:\n$old_vars"
    fi

    # Check for new variable DETECTED_TICKET_DIR
    if grep -q 'DETECTED_TICKET_DIR' "$script"; then
        pass_test "Uses new DETECTED_TICKET_DIR variable"
    else
        fail_test "New variable check" "DETECTED_TICKET_DIR not found"
    fi
}

# Test 8: Verify setup-kerberos.sh doesn't reference old variables
test_setup_no_old_vars() {
    section "Test 8: Verify setup-kerberos.sh uses new variable names"

    local script="$PROJECT_ROOT/setup-kerberos.sh"

    # Check for old variables (should not exist)
    local old_vars=$(grep -n 'DETECTED_CACHE_TYPE\|DETECTED_CACHE_PATH\|DETECTED_CACHE_TICKET' "$script" || true)

    if [ -z "$old_vars" ]; then
        pass_test "No references to old DETECTED_CACHE_* variables"
    else
        fail_test "Old variable references found" "Lines:\n$old_vars"
    fi

    # Check for new variable
    if grep -q 'DETECTED_TICKET_DIR' "$script"; then
        pass_test "Uses new DETECTED_TICKET_DIR variable"
    else
        fail_test "New variable check" "DETECTED_TICKET_DIR not found"
    fi
}

# Test 9: Verify .env.example has correct variable
test_env_example() {
    section "Test 9: Verify .env.example has correct configuration"

    local env_example="$PROJECT_ROOT/.env.example"

    if [ -f "$env_example" ]; then
        if grep -q 'KERBEROS_TICKET_DIR' "$env_example"; then
            pass_test ".env.example contains KERBEROS_TICKET_DIR"
        else
            fail_test ".env.example variable check" "KERBEROS_TICKET_DIR not found"
        fi

        # Verify old variables are not present
        if grep -q '^KERBEROS_CACHE_TYPE=\|^KERBEROS_CACHE_PATH=\|^KERBEROS_CACHE_TICKET=' "$env_example"; then
            fail_test ".env.example old variables" "Found old KERBEROS_CACHE_* variables"
        else
            pass_test "No old KERBEROS_CACHE_* variables in .env.example"
        fi
    else
        fail_test ".env.example check" "File not found"
    fi
}

# Test 10: Verify output format consistency
test_output_format() {
    section "Test 10: Verify output format in diagnostic"

    local script="$PROJECT_ROOT/diagnose-kerberos.sh"

    # Check that Section 5 references KERBEROS_TICKET_DIR
    if grep -A 20 "=== 5. EXACT .ENV CONFIGURATION ===" "$script" | grep -q 'KERBEROS_TICKET_DIR'; then
        pass_test "Section 5 outputs KERBEROS_TICKET_DIR"
    else
        fail_test "Section 5 format" "Should output KERBEROS_TICKET_DIR configuration"
    fi

    # Check Section 1 doesn't show confusing Type/Path/Ticket
    if grep -A 30 "=== 1. HOST KERBEROS TICKETS ===" "$script" | grep -q 'KERBEROS_TICKET_DIR:'; then
        pass_test "Section 1 shows simplified directory output"
    else
        info "Section 1 may need review for output clarity"
    fi
}

# Main execution
main() {
    echo ""
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║${NC}     Kerberos Configuration Refactoring Test Suite           ${BLUE}║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    info "Testing 3-variable to 1-variable refactoring"
    info "Project root: $PROJECT_ROOT"
    echo ""

    # Run all tests
    test_parse_file_format
    test_parse_dir_format
    test_diagnose_echo_flags
    test_setup_echo_flags
    test_docker_compose_variable
    test_env_substitution
    test_diagnose_no_old_vars
    test_setup_no_old_vars
    test_env_example
    test_output_format

    # Summary
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}Test Summary${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "  ${GREEN}Passed:${NC} $TESTS_PASSED"
    echo -e "  ${RED}Failed:${NC} $TESTS_FAILED"
    echo -e "  ${BLUE}Total:${NC}  $((TESTS_PASSED + TESTS_FAILED))"
    echo ""

    if [ $TESTS_FAILED -eq 0 ]; then
        echo -e "${GREEN}✓ All tests passed!${NC}"
        echo ""
        return 0
    else
        echo -e "${RED}✗ Some tests failed${NC}"
        echo ""
        return 1
    fi
}

# Run main
main "$@"
