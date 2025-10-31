#!/bin/bash
# Test: Ticket manager script works in minimal container
# Expected: FAIL if script needs dependencies not in minimal image

set -e

IMAGE="${IMAGE_NAME:-platform/kerberos-sidecar}:minimal"

echo "========================================"
echo "TEST: Ticket Manager in Minimal Container"
echo "========================================"
echo ""

# Test 1: Script exists and is executable
echo "Test 1: Checking ticket manager script..."
if docker run --rm "$IMAGE" test -x /scripts/kerberos-ticket-manager.sh; then
    echo "  ✓ PASS: Ticket manager script exists and is executable"
else
    echo "  ✗ FAIL: Ticket manager script not found or not executable"
    exit 1
fi
echo ""

# Test 2: Script can start (no missing dependencies)
echo "Test 2: Testing script starts without errors..."
# Run for 2 seconds and check for errors
if timeout 2 docker run --rm \
    -e TICKET_MODE=copy \
    -e KRB_PRINCIPAL=test@TEST.COM \
    "$IMAGE" /scripts/kerberos-ticket-manager.sh 2>&1 | grep -q "Starting ticket copier"; then
    echo "  ✓ PASS: Script starts successfully"
else
    echo "  ✗ FAIL: Script failed to start or missing dependencies"
    echo ""
    echo "Common issues:"
    echo "  - Missing bash (but should be in minimal image)"
    echo "  - Missing klist command (from krb5 package)"
    echo "  - Missing find command (from busybox)"
    exit 1
fi
echo ""

# Test 3: Kerberos tools available
echo "Test 3: Checking Kerberos tools..."
TOOLS=("klist" "kinit" "kdestroy")
FAILED=0

for tool in "${TOOLS[@]}"; do
    if docker run --rm "$IMAGE" which "$tool" >/dev/null 2>&1; then
        echo "  ✓ $tool available"
    else
        echo "  ✗ $tool MISSING"
        FAILED=1
    fi
done

echo ""
if [ $FAILED -eq 1 ]; then
    echo "✗ FAIL: Missing Kerberos tools"
    exit 1
else
    echo "✓ PASS: All Kerberos tools available"
fi

echo ""
echo "========================================"
echo "RESULT: TEST PASSED ✅"
echo "========================================"
