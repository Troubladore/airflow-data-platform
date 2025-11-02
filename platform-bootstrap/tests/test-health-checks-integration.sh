#!/bin/bash
# Integration test for health check functionality
# Tests the complete flow: setup → health check → verification

set -e

# Find repo root and source formatting library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLATFORM_DIR="$(dirname "$SCRIPT_DIR")"
REPO_ROOT="$(dirname "$PLATFORM_DIR")"

source "$PLATFORM_DIR/lib/formatting.sh"

print_header "Health Checks Integration Test"

TESTS_RUN=0
TESTS_PASSED=0

test_result() {
    local status=$1
    local test_name=$2

    TESTS_RUN=$((TESTS_RUN + 1))

    if [ "$status" = "pass" ]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        print_check "PASS" "$test_name"
    else
        print_check "FAIL" "$test_name"
    fi
}

# Test 1: Verify test scripts exist
print_section "Test 1: Script Files Exist"

if [ -f "$REPO_ROOT/platform-infrastructure/tests/test-platform-postgres-connectivity.sh" ]; then
    test_result "pass" "platform-postgres test script exists"
else
    test_result "fail" "platform-postgres test script exists"
fi

if [ -f "$REPO_ROOT/platform-infrastructure/tests/test-pagila-connectivity.sh" ]; then
    test_result "pass" "pagila test script exists"
else
    test_result "fail" "pagila test script exists"
fi

# Test 2: Verify scripts are executable
print_section "Test 2: Scripts Are Executable"

if [ -x "$REPO_ROOT/platform-infrastructure/tests/test-platform-postgres-connectivity.sh" ]; then
    test_result "pass" "platform-postgres script is executable"
else
    test_result "fail" "platform-postgres script is executable"
fi

if [ -x "$REPO_ROOT/platform-infrastructure/tests/test-pagila-connectivity.sh" ]; then
    test_result "pass" "pagila script is executable"
else
    test_result "fail" "pagila script is executable"
fi

# Test 3: Verify Makefile targets exist
print_section "Test 3: Makefile Targets"

if make -C "$REPO_ROOT/platform-infrastructure" -n test-platform-postgres-connectivity >/dev/null 2>&1; then
    test_result "pass" "test-platform-postgres-connectivity target exists"
else
    test_result "fail" "test-platform-postgres-connectivity target exists"
fi

if make -C "$REPO_ROOT/platform-infrastructure" -n test-pagila-connectivity >/dev/null 2>&1; then
    test_result "pass" "test-pagila-connectivity target exists"
else
    test_result "fail" "test-pagila-connectivity target exists"
fi

if make -C "$REPO_ROOT/platform-infrastructure" -n test-connectivity >/dev/null 2>&1; then
    test_result "pass" "test-connectivity target exists"
else
    test_result "fail" "test-connectivity target exists"
fi

# Test 4: Verify Python methods exist
print_section "Test 4: Python Integration"

if grep -q "def verify_postgres_health" "$REPO_ROOT/wizard/utils/diagnostics.py"; then
    test_result "pass" "verify_postgres_health method exists"
else
    test_result "fail" "verify_postgres_health method exists"
fi

if grep -q "def verify_pagila_health" "$REPO_ROOT/wizard/utils/diagnostics.py"; then
    test_result "pass" "verify_pagila_health method exists"
else
    test_result "fail" "verify_pagila_health method exists"
fi

# Test 5: Verify wizard integration
print_section "Test 5: Wizard Integration"

if grep -q "verify_postgres_health" "$REPO_ROOT/wizard/services/base_platform/actions.py"; then
    test_result "pass" "PostgreSQL action uses health check"
else
    test_result "fail" "PostgreSQL action uses health check"
fi

if grep -q "verify_pagila_health" "$REPO_ROOT/wizard/services/pagila/actions.py"; then
    test_result "pass" "Pagila action uses health check"
else
    test_result "fail" "Pagila action uses health check"
fi

# Test 6: Run actual health checks (if containers are running)
print_section "Test 6: Functional Tests (if containers available)"

if docker ps | grep -q postgres-test && docker ps | grep -q platform-postgres; then
    print_info "Containers detected, running functional tests..."

    if bash "$REPO_ROOT/platform-infrastructure/tests/test-platform-postgres-connectivity.sh" --quiet >/dev/null 2>&1; then
        test_result "pass" "platform-postgres connectivity test executes"
    else
        test_result "fail" "platform-postgres connectivity test executes"
    fi
else
    print_info "Containers not running, skipping functional tests"
    print_info "Start containers with: ./platform setup"
fi

if docker ps | grep -q postgres-test && docker ps | grep -q pagila-postgres; then
    if bash "$REPO_ROOT/platform-infrastructure/tests/test-pagila-connectivity.sh" --quiet >/dev/null 2>&1; then
        test_result "pass" "pagila connectivity test executes"
    else
        test_result "fail" "pagila connectivity test executes"
    fi
else
    print_info "Pagila not running, skipping pagila test"
fi

# Summary
print_divider
echo ""

if [ $TESTS_PASSED -eq $TESTS_RUN ]; then
    print_success "All tests passed! ($TESTS_PASSED/$TESTS_RUN)"
    exit 0
else
    print_error "Some tests failed! ($TESTS_PASSED/$TESTS_RUN passed)"
    exit 1
fi
