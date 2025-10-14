#!/bin/bash
# Tests for .env file persistence
# Verifies variables are actually written to .env

set -e

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

TESTS_PASSED=0
TESTS_FAILED=0

test_result() {
    if [ "$1" = "pass" ]; then
        echo -e "${GREEN}✓${NC} $2"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗${NC} $2"
        echo "  $3"
        ((TESTS_FAILED++))
    fi
}

echo "=========================================="
echo ".env Persistence Tests"
echo "=========================================="
echo ""

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
echo "=========================================="
echo "Results"
echo "=========================================="
echo -e "${GREEN}Passed: $TESTS_PASSED${NC}"
echo -e "${RED}Failed: $TESTS_FAILED${NC}"
echo ""

if [ $TESTS_FAILED -eq 0 ]; then
    echo -e "${GREEN}✓ All persistence tests passed!${NC}"
    exit 0
else
    echo -e "${RED}✗ Some tests failed${NC}"
    exit 1
fi
