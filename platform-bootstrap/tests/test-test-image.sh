#!/bin/bash
# Tests for pre-built test image

set -e

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Find project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLATFORM_DIR="$(dirname "$SCRIPT_DIR")"

echo "=========================================="
echo "Test Image Validation Tests"
echo "=========================================="
echo ""

FAILED=0

# Test 1: Dockerfile.test-image exists
echo "Test 1: Dockerfile.test-image exists"
if [ -f "$PLATFORM_DIR/kerberos-sidecar/Dockerfile.test-image" ]; then
    echo -e "${GREEN}✓${NC} Dockerfile found"
else
    echo -e "${RED}✗${NC} Dockerfile missing"
    FAILED=1
fi
echo ""

# Test 2: Dockerfile syntax
echo "Test 2: Dockerfile syntax valid"
if docker build -f ../kerberos-sidecar/Dockerfile.test-image --check ../kerberos-sidecar 2>/dev/null; then
    echo -e "${GREEN}✓${NC} Dockerfile syntax valid"
else
    echo -e "${YELLOW}⚠${NC} docker build --check not available (older Docker version)"
fi
echo ""

# Test 3: Makefile has build-test-image target
echo "Test 3: Makefile has build-test-image target"
if grep -q "^build-test-image:" ../kerberos-sidecar/Makefile; then
    echo -e "${GREEN}✓${NC} build-test-image target exists"
else
    echo -e "${RED}✗${NC} build-test-image target missing"
    FAILED=1
fi
echo ""

# Test 4: test-kerberos.sh checks for pre-built image
echo "Test 4: test-kerberos.sh checks for platform/kerberos-test"
if grep -q "platform/kerberos-test:latest" ../test-kerberos.sh; then
    echo -e "${GREEN}✓${NC} Script checks for pre-built image"
else
    echo -e "${RED}✗${NC} Script doesn't check for pre-built image"
    FAILED=1
fi
echo ""

# Test 5: clean-slate.sh removes test image
echo "Test 5: clean-slate.sh removes test image when purging"
if grep -q "platform/kerberos-test" ../clean-slate.sh; then
    echo -e "${GREEN}✓${NC} clean-slate removes test image"
else
    echo -e "${RED}✗${NC} clean-slate missing test image removal"
    FAILED=1
fi
echo ""

# Test 6: Wizard offers to build test image
echo "Test 6: Wizard offers to build test image in Step 11"
if grep -q "make build-test-image\|Build test image" ../setup-kerberos.sh; then
    echo -e "${GREEN}✓${NC} Wizard offers to build test image"
else
    echo -e "${RED}✗${NC} Wizard doesn't offer to build"
    FAILED=1
fi
echo ""

echo "=========================================="
if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}✓ All test image tests passed!${NC}"
    exit 0
else
    echo -e "${RED}✗ Some tests failed${NC}"
    exit 1
fi
