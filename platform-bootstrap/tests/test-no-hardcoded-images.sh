#!/bin/bash
# Test that no scripts have hardcoded Docker images (bypassing .env config)

set -e

# Source formatting library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/formatting.sh"

FAILED=0

print_header "Hardcoded Image Detection Tests"

# Check for hardcoded alpine
print_section "Test 1: Checking for hardcoded 'alpine' in docker run"
HARDCODED=$(grep -r "docker run.*alpine" ../platform-bootstrap/*.sh 2>/dev/null | grep -v "IMAGE_ALPINE\|\${.*ALPINE\|.env" || true)
if [ -n "$HARDCODED" ]; then
    print_check "FAIL" "Found hardcoded alpine images"
    echo "$HARDCODED"
    FAILED=1
else
    print_check "PASS" "No hardcoded alpine images"
fi
echo ""

# Check for hardcoded python
print_section "Test 2: Checking for hardcoded 'python:' in docker run"
HARDCODED=$(grep -r "docker run.*python:" ../platform-bootstrap/*.sh 2>/dev/null | grep -v "IMAGE_PYTHON\|\${.*PYTHON\|.env" || true)
if [ -n "$HARDCODED" ]; then
    print_check "FAIL" "Found hardcoded python images"
    echo "$HARDCODED"
    FAILED=1
else
    print_check "PASS" "No hardcoded python images"
fi
echo ""

# Check for hardcoded mockserver
print_section "Test 3: Checking for hardcoded mockserver"
HARDCODED=$(grep -r "mockserver/mockserver" ../platform-bootstrap/*.yml 2>/dev/null | grep -v "IMAGE_MOCKSERVER\|\${.*MOCKSERVER\|#" || true)
if [ -n "$HARDCODED" ]; then
    print_check "FAIL" "Found hardcoded mockserver"
    echo "$HARDCODED"
    FAILED=1
else
    print_check "PASS" "No hardcoded mockserver"
fi
echo ""

print_divider
if [ $FAILED -eq 0 ]; then
    print_success "All images use variables from .env"
    exit 0
else
    print_error "Hardcoded images found - must use \${IMAGE_*} variables"
    exit 1
fi
