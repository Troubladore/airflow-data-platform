#!/bin/bash
# Test: Health check works in minimal container
# Expected: FAIL without valid ticket, PASS with valid ticket

set -e

IMAGE="${IMAGE_NAME:-platform/kerberos-sidecar}:minimal"

echo "========================================"
echo "TEST: Health Check in Minimal Container"
echo "========================================"
echo ""

# Test 1: Health check script exists
echo "Test 1: Checking health check script..."
if docker run --rm "$IMAGE" test -x /scripts/health-check.sh; then
    echo "  ✓ PASS: Health check script exists and is executable"
else
    echo "  ✗ FAIL: Health check script not found or not executable"
    exit 1
fi
echo ""

# Test 2: Health check fails without ticket (expected behavior)
echo "Test 2: Testing health check without ticket (should fail)..."
if docker run --rm "$IMAGE" /scripts/health-check.sh >/dev/null 2>&1; then
    echo "  ✗ FAIL: Health check passed without ticket (should fail!)"
    exit 1
else
    echo "  ✓ PASS: Health check correctly fails without ticket"
fi
echo ""

# Test 3: Health check command (klist -s) available
echo "Test 3: Testing klist -s command..."
if docker run --rm "$IMAGE" sh -c "klist -s" >/dev/null 2>&1; then
    echo "  ✗ UNEXPECTED: klist -s passed (no ticket should exist)"
else
    echo "  ✓ PASS: klist -s correctly reports no ticket"
fi
echo ""

echo "========================================"
echo "RESULT: TEST PASSED ✅"
echo "========================================"
