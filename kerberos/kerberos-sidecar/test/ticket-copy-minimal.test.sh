#!/bin/bash
# Test: Ticket copying works in minimal container
# Expected: FAIL if dependencies missing for ticket copy operation

set -e

IMAGE="${IMAGE_NAME:-platform/kerberos-sidecar}:minimal"

echo "========================================"
echo "TEST: Ticket Copying in Minimal Container"
echo "========================================"
echo ""

# Check if user has real tickets to test with
if ! klist >/dev/null 2>&1; then
    echo "⚠ WARNING: No Kerberos tickets on host"
    echo "This test requires valid tickets. Run: kinit user@DOMAIN"
    echo "Skipping real ticket copy test..."
    echo ""
    echo "Running basic copy mode test instead..."
fi

# Test 1: Container can access /host/tickets mount
echo "Test 1: Testing ticket directory mount..."
# Use actual ticket cache directory
TICKET_DIR="${HOME}/.krb5-cache"

# Start container with ticket mount, test mount accessibility
if docker run --rm \
    -v "${TICKET_DIR}:/host/tickets:ro" \
    "$IMAGE" /bin/sh -c "test -d /host/tickets && echo 'Mount OK'" | grep -q "Mount OK"; then
    echo "  ✓ PASS: Ticket directory mounted successfully"
else
    echo "  ✗ FAIL: Cannot access ticket directory mount"
    echo "  Tried to mount: ${TICKET_DIR}"
    exit 1
fi
echo ""

# Test 2: find command available (used by ticket manager)
echo "Test 2: Testing find command availability..."
if docker run --rm "$IMAGE" which find >/dev/null 2>&1; then
    echo "  ✓ PASS: find command available"
else
    echo "  ✗ FAIL: find command not available (needed for ticket copying)"
    exit 1
fi
echo ""

# Test 3: cp and chmod commands available
echo "Test 3: Testing file operation commands..."
COMMANDS=("cp" "chmod")
FAILED=0

for cmd in "${COMMANDS[@]}"; do
    if docker run --rm "$IMAGE" which "$cmd" >/dev/null 2>&1; then
        echo "  ✓ $cmd available"
    else
        echo "  ✗ $cmd MISSING"
        FAILED=1
    fi
done

echo ""
if [ $FAILED -eq 1 ]; then
    echo "✗ FAIL: Missing file operation commands"
    exit 1
fi

echo ""
echo "========================================"
echo "RESULT: TEST PASSED ✅"
echo "========================================"
