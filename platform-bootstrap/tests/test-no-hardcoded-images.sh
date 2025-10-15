#!/bin/bash
# Test that no scripts have hardcoded Docker images (bypassing .env config)

set -e

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

FAILED=0

echo "=========================================="
echo "Hardcoded Image Detection Tests"
echo "=========================================="
echo ""

# Check for hardcoded alpine
echo "Test 1: Checking for hardcoded 'alpine' in docker run..."
HARDCODED=$(grep -r "docker run.*alpine" ../platform-bootstrap/*.sh 2>/dev/null | grep -v "IMAGE_ALPINE\|\${.*ALPINE\|.env" || true)
if [ -n "$HARDCODED" ]; then
    echo -e "${RED}✗${NC} Found hardcoded alpine images:"
    echo "$HARDCODED"
    FAILED=1
else
    echo -e "${GREEN}✓${NC} No hardcoded alpine images"
fi
echo ""

# Check for hardcoded python
echo "Test 2: Checking for hardcoded 'python:' in docker run..."
HARDCODED=$(grep -r "docker run.*python:" ../platform-bootstrap/*.sh 2>/dev/null | grep -v "IMAGE_PYTHON\|\${.*PYTHON\|.env" || true)
if [ -n "$HARDCODED" ]; then
    echo -e "${RED}✗${NC} Found hardcoded python images:"
    echo "$HARDCODED"
    FAILED=1
else
    echo -e "${GREEN}✓${NC} No hardcoded python images"
fi
echo ""

# Check for hardcoded mockserver
echo "Test 3: Checking for hardcoded mockserver..."
HARDCODED=$(grep -r "mockserver/mockserver" ../platform-bootstrap/*.yml 2>/dev/null | grep -v "IMAGE_MOCKSERVER\|\${.*MOCKSERVER\|#" || true)
if [ -n "$HARDCODED" ]; then
    echo -e "${RED}✗${NC} Found hardcoded mockserver:"
    echo "$HARDCODED"
    FAILED=1
else
    echo -e "${GREEN}✓${NC} No hardcoded mockserver"
fi
echo ""

echo "=========================================="
if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}✓ All images use variables from .env${NC}"
    exit 0
else
    echo -e "${RED}✗ Hardcoded images found - must use \${IMAGE_*} variables${NC}"
    exit 1
fi
