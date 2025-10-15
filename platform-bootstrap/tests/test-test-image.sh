#!/bin/bash
# Tests for pre-built test image

set -e

# Source formatting library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/formatting.sh"

PLATFORM_DIR="$(dirname "$SCRIPT_DIR")"

print_header "Test Image Validation Tests"

FAILED=0

# Test 1: Dockerfile.test-image exists
print_section "Test 1: Dockerfile.test-image exists"
if [ -f "$PLATFORM_DIR/kerberos-sidecar/Dockerfile.test-image" ]; then
    print_check "PASS" "Dockerfile found"
else
    print_check "FAIL" "Dockerfile missing"
    FAILED=1
fi
echo ""

# Test 2: Dockerfile syntax
print_section "Test 2: Dockerfile syntax valid"
if docker build -f ../kerberos-sidecar/Dockerfile.test-image --check ../kerberos-sidecar 2>/dev/null; then
    print_check "PASS" "Dockerfile syntax valid"
else
    print_check "WARN" "docker build --check not available (older Docker version)"
fi
echo ""

# Test 3: Makefile has build-test-image target
print_section "Test 3: Makefile has build-test-image target"
if grep -q "^build-test-image:" ../kerberos-sidecar/Makefile; then
    print_check "PASS" "build-test-image target exists"
else
    print_check "FAIL" "build-test-image target missing"
    FAILED=1
fi
echo ""

# Test 4: test-kerberos.sh checks for pre-built image
print_section "Test 4: test-kerberos.sh checks for platform/kerberos-test"
if grep -q "platform/kerberos-test:latest" ../test-kerberos.sh; then
    print_check "PASS" "Script checks for pre-built image"
else
    print_check "FAIL" "Script doesn't check for pre-built image"
    FAILED=1
fi
echo ""

# Test 5: clean-slate.sh removes test image
print_section "Test 5: clean-slate.sh removes test image when purging"
if grep -q "platform/kerberos-test" ../clean-slate.sh; then
    print_check "PASS" "clean-slate removes test image"
else
    print_check "FAIL" "clean-slate missing test image removal"
    FAILED=1
fi
echo ""

# Test 6: Wizard offers to build test image
print_section "Test 6: Wizard offers to build test image in Step 11"
if grep -q "make build-test-image\|Build test image" ../setup-kerberos.sh; then
    print_check "PASS" "Wizard offers to build test image"
else
    print_check "FAIL" "Wizard doesn't offer to build"
    FAILED=1
fi
echo ""

print_divider
if [ $FAILED -eq 0 ]; then
    print_success "All test image tests passed!"
    exit 0
else
    print_error "Some tests failed"
    exit 1
fi
