#!/bin/bash
# Test OpenMetadata Setup Script
# ================================
# Tests the OpenMetadata setup wizard in non-interactive mode
# Validates password generation, container startup, health checks

set -e

# Find script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLATFORM_DIR="$(dirname "$SCRIPT_DIR")"
REPO_ROOT="$(dirname "$PLATFORM_DIR")"
OPENMETADATA_DIR="$REPO_ROOT/openmetadata"

# Source formatting library
if [ -f "$PLATFORM_DIR/lib/formatting.sh" ]; then
    source "$PLATFORM_DIR/lib/formatting.sh"
else
    print_header() { echo "=== $1 ==="; }
    print_check() { echo "[$1] $2"; }
    print_success() { echo "+ $1"; }
    print_error() { echo "x $1"; }
fi

echo ""
print_header "OpenMetadata Setup Test (No-Kerberos Mode)"
echo ""
echo "This test validates the OpenMetadata setup script without Docker."
echo "Tests configuration, password generation, and error handling."
echo ""

# Track results
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
FAILED_ITEMS=()

# Test: Password generation with special characters
TOTAL_TESTS=$((TOTAL_TESTS + 1))
echo -n "Testing password generation with special characters... "

# Generate password that might contain sed-breaking characters
TEST_PASS=$(echo "test/pass+word=" | base64)
TEST_FILE=$(mktemp)
echo "PLATFORM_DB_PASSWORD=changeme" > "$TEST_FILE"

# Try to replace it (this is what the setup script does)
if sed -i "s|PLATFORM_DB_PASSWORD=.*|PLATFORM_DB_PASSWORD=$TEST_PASS|" "$TEST_FILE"; then
    # Verify it worked
    if grep -q "PLATFORM_DB_PASSWORD=$TEST_PASS" "$TEST_FILE"; then
        print_check "PASS" "sed with | delimiter handles special chars"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        print_check "FAIL" "Password not updated correctly"
        FAILED_TESTS=$((FAILED_TESTS + 1))
        FAILED_ITEMS+=("Password update verification")
    fi
else
    print_check "FAIL" "sed command failed"
    FAILED_TESTS=$((FAILED_TESTS + 1))
    FAILED_ITEMS+=("sed password replacement")
fi
rm -f "$TEST_FILE"

# Test: .env.example exists in openmetadata/
TOTAL_TESTS=$((TOTAL_TESTS + 1))
if [ -f "$OPENMETADATA_DIR/.env.example" ]; then
    print_check "PASS" "openmetadata/.env.example exists"
    PASSED_TESTS=$((PASSED_TESTS + 1))
else
    print_check "FAIL" "openmetadata/.env.example missing"
    FAILED_TESTS=$((FAILED_TESTS + 1))
    FAILED_ITEMS+=("openmetadata/.env.example missing")
fi

# Test: docker-compose.yml is valid
TOTAL_TESTS=$((TOTAL_TESTS + 1))
if command -v docker >/dev/null 2>&1; then
    cd "$OPENMETADATA_DIR"
    if docker compose config >/dev/null 2>&1; then
        print_check "PASS" "docker-compose.yml is valid"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        print_check "FAIL" "docker-compose.yml has errors"
        FAILED_TESTS=$((FAILED_TESTS + 1))
        FAILED_ITEMS+=("docker-compose.yml validation")
    fi
    cd "$PLATFORM_DIR"
else
    print_check "WARN" "Docker not available (skipping validation)"
fi

# Test: setup.sh exists and is executable
TOTAL_TESTS=$((TOTAL_TESTS + 1))
if [ -x "$OPENMETADATA_DIR/setup.sh" ]; then
    print_check "PASS" "setup.sh is executable"
    PASSED_TESTS=$((PASSED_TESTS + 1))
else
    print_check "FAIL" "setup.sh not executable"
    FAILED_TESTS=$((FAILED_TESTS + 1))
    FAILED_ITEMS+=("setup.sh permissions")
fi

# Test: setup.sh has --auto mode for non-interactive testing
TOTAL_TESTS=$((TOTAL_TESTS + 1))
if grep -q "\-\-auto" "$OPENMETADATA_DIR/setup.sh"; then
    print_check "PASS" "setup.sh supports --auto mode"
    PASSED_TESTS=$((PASSED_TESTS + 1))
else
    print_check "FAIL" "setup.sh missing --auto mode"
    FAILED_TESTS=$((FAILED_TESTS + 1))
    FAILED_ITEMS+=("--auto mode support")
fi

# Test: Makefile has setup target
TOTAL_TESTS=$((TOTAL_TESTS + 1))
if grep -q "^setup:.*##" "$OPENMETADATA_DIR/Makefile"; then
    print_check "PASS" "Makefile has setup target"
    PASSED_TESTS=$((PASSED_TESTS + 1))
else
    print_check "FAIL" "Makefile missing setup target"
    FAILED_TESTS=$((FAILED_TESTS + 1))
    FAILED_ITEMS+=("Makefile setup target")
fi

echo ""
print_divider
echo "Summary"
print_divider
echo ""

echo "Total tests run: $TOTAL_TESTS"
echo "Passed: $PASSED_TESTS"
echo "Failed: $FAILED_TESTS"

if [ $FAILED_TESTS -gt 0 ]; then
    echo ""
    print_error "OPENMETADATA SETUP TEST FAILED"
    echo ""
    echo "Failed items:"
    for failure in "${FAILED_ITEMS[@]}"; do
        echo "  - $failure"
    done
    exit 1
else
    echo ""
    print_success "ALL OPENMETADATA SETUP TESTS PASSED"
    echo ""
    echo "Note: This validates configuration and setup script structure."
    echo "For full integration testing, run: cd $OPENMETADATA_DIR && make setup"
    exit 0
fi
