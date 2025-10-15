#!/bin/bash
# Tests for .env file persistence
# Verifies variables are actually written to .env

set -e

# Source formatting library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/formatting.sh"

TESTS_PASSED=0
TESTS_FAILED=0

test_result() {
    if [ "$1" = "pass" ]; then
        print_check "PASS" "$2"
        ((TESTS_PASSED++))
    else
        print_check "FAIL" "$2"
        echo "  $3"
        ((TESTS_FAILED++))
    fi
}

print_header ".env Persistence Tests"

# Create temp .env for testing
TEST_ENV=$(mktemp)
cat > "$TEST_ENV" <<'EOF'
# Test .env file
COMPANY_DOMAIN=TESTDOMAIN.COM
EOF

echo "Test 1: Update existing COMPANY_DOMAIN"
sed -i "s|^COMPANY_DOMAIN=.*|COMPANY_DOMAIN=NEWDOMAIN.COM|" "$TEST_ENV"
if grep -q "^COMPANY_DOMAIN=NEWDOMAIN.COM$" "$TEST_ENV"; then
    test_result "pass" "Update existing variable works"
else
    test_result "fail" "Update existing variable" "Expected: COMPANY_DOMAIN=NEWDOMAIN.COM"
fi
echo ""

echo "Test 2: Add new variable (doesn't exist)"
if grep -q "^KERBEROS_TICKET_DIR=" "$TEST_ENV"; then
    sed -i "s|^KERBEROS_TICKET_DIR=.*|KERBEROS_TICKET_DIR=/test/path|" "$TEST_ENV"
else
    echo "KERBEROS_TICKET_DIR=/test/path" >> "$TEST_ENV"
fi

if grep -q "^KERBEROS_TICKET_DIR=/test/path$" "$TEST_ENV"; then
    test_result "pass" "Add new variable works"
else
    test_result "fail" "Add new variable" "Variable not found in file"
fi
echo ""

echo "Test 3: Update newly added variable"
if grep -q "^KERBEROS_TICKET_DIR=" "$TEST_ENV"; then
    sed -i "s|^KERBEROS_TICKET_DIR=.*|KERBEROS_TICKET_DIR=/updated/path|" "$TEST_ENV"
else
    echo "KERBEROS_TICKET_DIR=/updated/path" >> "$TEST_ENV"
fi

if grep -q "^KERBEROS_TICKET_DIR=/updated/path$" "$TEST_ENV"; then
    test_result "pass" "Update added variable works"
else
    test_result "fail" "Update added variable" "Expected: KERBEROS_TICKET_DIR=/updated/path"
fi
echo ""

echo "Test 4: Verify .env.example has KERBEROS_TICKET_DIR"
if grep -q "^KERBEROS_TICKET_DIR=" ../platform-bootstrap/.env.example 2>/dev/null || \
   grep -q "^KERBEROS_TICKET_DIR=" ../.env.example 2>/dev/null; then
    test_result "pass" ".env.example contains KERBEROS_TICKET_DIR"
else
    test_result "fail" ".env.example contains KERBEROS_TICKET_DIR" "Template missing variable"
fi
echo ""

echo "Test 5: Verify TICKET_MODE in .env.example"
if grep -q "^TICKET_MODE=" ../platform-bootstrap/.env.example 2>/dev/null || \
   grep -q "^TICKET_MODE=" ../.env.example 2>/dev/null; then
    test_result "pass" ".env.example contains TICKET_MODE"
else
    test_result "fail" ".env.example contains TICKET_MODE" "Template missing variable"
fi

# Cleanup
rm "$TEST_ENV"

echo ""
print_section "Results"
print_msg "${GREEN}Passed: $TESTS_PASSED${NC}"
print_msg "${RED}Failed: $TESTS_FAILED${NC}"
echo ""

if [ $TESTS_FAILED -eq 0 ]; then
    print_success "All persistence tests passed!"
    exit 0
else
    print_error "Some tests failed"
    exit 1
fi
