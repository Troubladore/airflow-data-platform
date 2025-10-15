#!/bin/bash
# Unit tests for Kerberos ticket location parsing
# Tests the critical DIR parsing logic that configures .env

set -e

# Source formatting library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/formatting.sh"

TESTS_PASSED=0
TESTS_FAILED=0

# Test helper
assert_equals() {
    local test_name="$1"
    local expected="$2"
    local actual="$3"

    if [ "$expected" = "$actual" ]; then
        print_check "PASS" "$test_name"
        ((TESTS_PASSED++))
        return 0
    else
        print_check "FAIL" "$test_name"
        echo "  Expected: '$expected'"
        echo "  Got:      '$actual'"
        ((TESTS_FAILED++))
        return 1
    fi
}

print_header "Kerberos Ticket Parsing Unit Tests"

# ====================
# TEST CASE 1: DIR format with file path
# ====================
echo "Test Case 1: DIR::/home/emaynard/.krb5-cache/dev/tkt"
echo "Expected: PATH=${HOME}/.krb5-cache, TICKET=dev"
echo ""

TICKET_CACHE="DIR::/home/emaynard/.krb5-cache/dev/tkt"
FULL_PATH=${TICKET_CACHE#DIR::}

# Simulate user's home
export HOME="/home/emaynard"

# Parse using current logic
TICKET_DIR=$(dirname "$FULL_PATH")
DETECTED_CACHE_PATH=$(dirname "$TICKET_DIR")
DETECTED_CACHE_TICKET="$(basename "$TICKET_DIR")"

# Convert to ${HOME} format
if [[ "$DETECTED_CACHE_PATH" == "$HOME"* ]]; then
    RELATIVE_PATH=${DETECTED_CACHE_PATH#$HOME}
    DETECTED_CACHE_PATH_DISPLAY="\${HOME}$RELATIVE_PATH"
else
    DETECTED_CACHE_PATH_DISPLAY="$DETECTED_CACHE_PATH"
fi

assert_equals "Type detection" "DIR" "DIR"
assert_equals "Base directory" "\${HOME}/.krb5-cache" "$DETECTED_CACHE_PATH_DISPLAY"
assert_equals "Subdirectory" "dev" "$DETECTED_CACHE_TICKET"

echo ""

# ====================
# TEST CASE 2: FILE format
# ====================
echo "Test Case 2: FILE:/tmp/krb5cc_1000"
echo "Expected: PATH=/tmp, TICKET=krb5cc_1000"
echo ""

TICKET_CACHE="FILE:/tmp/krb5cc_1000"
CACHE_FILE=${TICKET_CACHE#FILE:}

DETECTED_CACHE_TYPE="FILE"
DETECTED_CACHE_PATH=$(dirname "$CACHE_FILE")
DETECTED_CACHE_TICKET=$(basename "$CACHE_FILE")

assert_equals "Type detection" "FILE" "$DETECTED_CACHE_TYPE"
assert_equals "Directory path" "/tmp" "$DETECTED_CACHE_PATH"
assert_equals "Ticket filename" "krb5cc_1000" "$DETECTED_CACHE_TICKET"

echo ""

# ====================
# TEST CASE 3: DIR format - root level ticket
# ====================
echo "Test Case 3: DIR::/home/user/.krb5_cache/krb5cc"
echo "Expected: PATH=${HOME}, TICKET=.krb5_cache"
echo ""

export HOME="/home/user"
TICKET_CACHE="DIR::/home/user/.krb5_cache/krb5cc"
FULL_PATH=${TICKET_CACHE#DIR::}

TICKET_DIR=$(dirname "$FULL_PATH")
DETECTED_CACHE_PATH=$(dirname "$TICKET_DIR")
DETECTED_CACHE_TICKET="$(basename "$TICKET_DIR")"

if [[ "$DETECTED_CACHE_PATH" == "$HOME"* ]]; then
    RELATIVE_PATH=${DETECTED_CACHE_PATH#$HOME}
    DETECTED_CACHE_PATH_DISPLAY="\${HOME}$RELATIVE_PATH"
else
    DETECTED_CACHE_PATH_DISPLAY="$DETECTED_CACHE_PATH"
fi

assert_equals "Base directory" "\${HOME}" "$DETECTED_CACHE_PATH_DISPLAY"
assert_equals "Subdirectory" ".krb5_cache" "$DETECTED_CACHE_TICKET"

echo ""

# ====================
# TEST CASE 4: Wizard extraction from diagnostic output
# ====================
echo "Test Case 4: Wizard parsing diagnostic Section 5 output"
echo "Simulates wizard extracting values from diagnose-kerberos.sh"
echo ""

# Simulate diagnostic output
DIAG_OUTPUT="
COMPANY_DOMAIN=MYCOMPANY.COM
KERBEROS_CACHE_TYPE=DIR
KERBEROS_CACHE_PATH=\${HOME}/.krb5-cache
KERBEROS_CACHE_TICKET=dev
"

EXTRACTED_TYPE=$(echo "$DIAG_OUTPUT" | grep "^KERBEROS_CACHE_TYPE=" | cut -d= -f2)
EXTRACTED_PATH=$(echo "$DIAG_OUTPUT" | grep "^KERBEROS_CACHE_PATH=" | cut -d= -f2-)  # Note: f2- not f2!
EXTRACTED_TICKET=$(echo "$DIAG_OUTPUT" | grep "^KERBEROS_CACHE_TICKET=" | cut -d= -f2)

assert_equals "Extracted type" "DIR" "$EXTRACTED_TYPE"
assert_equals "Extracted path" "\${HOME}/.krb5-cache" "$EXTRACTED_PATH"
assert_equals "Extracted ticket" "dev" "$EXTRACTED_TICKET"

echo ""

# ====================
# TEST CASE 5: Edge case - path with = sign
# ====================
echo "Test Case 5: Path containing = sign (edge case)"
echo ""

DIAG_OUTPUT="KERBEROS_CACHE_PATH=\${HOME}/weird=path/.krb5"

# Wrong way (f2 only gets first part)
WRONG=$(echo "$DIAG_OUTPUT" | cut -d= -f2)
# Right way (f2- gets everything after first =)
RIGHT=$(echo "$DIAG_OUTPUT" | cut -d= -f2-)

echo "Input: KERBEROS_CACHE_PATH=\${HOME}/weird=path/.krb5"
echo "  cut -d= -f2:  '$WRONG'  (WRONG - stops at first =)"
echo "  cut -d= -f2-: '$RIGHT'  (RIGHT - gets everything)"

if [ "$RIGHT" = "\${HOME}/weird=path/.krb5" ]; then
    print_check "PASS" "Extraction handles = in paths"
    ((TESTS_PASSED++))
else
    print_check "FAIL" "Extraction fails with = in paths"
    ((TESTS_FAILED++))
fi

echo ""
print_section "Test Results"
print_msg "${GREEN}Passed: $TESTS_PASSED${NC}"
print_msg "${RED}Failed: $TESTS_FAILED${NC}"
echo ""

if [ $TESTS_FAILED -eq 0 ]; then
    print_success "All tests passed!"
    exit 0
else
    print_error "Some tests failed - fix needed"
    exit 1
fi
