#!/bin/bash
# Test: End-to-End Ticket Management with Real ERUDITIS.LAB Tickets
# Expected: FAIL initially (integration not proven yet)

set -e

IMAGE="${IMAGE_NAME:-platform/kerberos-sidecar}:minimal"
CONTAINER_NAME="test-e2e-minimal-sidecar-$$"
COPY_INTERVAL=10  # Short interval for testing (10 seconds)
TEST_TIMEOUT=60   # Total test timeout (1 minute)

echo "========================================"
echo "TEST: E2E Minimal Sidecar with Real Tickets"
echo "========================================"
echo ""

# Cleanup function
cleanup() {
    echo ""
    echo "Cleaning up container and volume..."
    docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
    docker volume rm "test-krb5-cache-$$" >/dev/null 2>&1 || true
}
trap cleanup EXIT

# Test 1: Verify real ERUDITIS.LAB tickets exist on host
echo "Test 1: Verifying real ERUDITIS.LAB tickets on host..."
TICKET_DIR="${HOME}/.krb5-cache/dev"

if [ ! -d "$TICKET_DIR" ]; then
    echo "  ✗ FAIL: Ticket directory not found: $TICKET_DIR"
    echo "  This test requires real ERUDITIS.LAB tickets"
    echo "  Expected: $TICKET_DIR"
    exit 1
fi

# Find ticket file (not 'primary' or '.conf')
TICKET_FILE=$(find "$TICKET_DIR" -type f 2>/dev/null | grep -v "primary\|\.conf" | head -1)

if [ -z "$TICKET_FILE" ]; then
    echo "  ✗ FAIL: No ticket files found in $TICKET_DIR"
    echo "  Run: kinit emaynard@ERUDITIS.LAB"
    exit 1
fi

if ! klist -s "$TICKET_FILE" 2>/dev/null; then
    echo "  ✗ FAIL: Ticket file exists but is invalid or expired: $TICKET_FILE"
    echo "  Run: kinit emaynard@ERUDITIS.LAB"
    exit 1
fi

echo "  ✓ PASS: Valid ERUDITIS.LAB ticket found"
echo "  Ticket file: $TICKET_FILE"

# Get principal from ticket
PRINCIPAL=$(klist "$TICKET_FILE" 2>/dev/null | grep "Default principal:" | awk '{print $3}')
echo "  Principal: $PRINCIPAL"
echo ""

# Test 2: Start minimal sidecar with real tickets
echo "Test 2: Starting minimal sidecar with TICKET_MODE=copy..."

# Create a named volume for ticket sharing
VOLUME_NAME="test-krb5-cache-$$"
docker volume create "$VOLUME_NAME" >/dev/null 2>&1

# Start sidecar container
if ! docker run -d \
    --name "$CONTAINER_NAME" \
    -e TICKET_MODE=copy \
    -e COPY_INTERVAL="$COPY_INTERVAL" \
    -e KRB5CCNAME=/krb5/cache/krb5cc \
    -v "${TICKET_DIR}:/host/tickets:ro" \
    -v "${VOLUME_NAME}:/krb5/cache" \
    --health-cmd="test -f /krb5/cache/krb5cc && klist -s /krb5/cache/krb5cc" \
    --health-interval=5s \
    --health-timeout=3s \
    --health-retries=3 \
    "$IMAGE" \
    /bin/bash /scripts/kerberos-ticket-manager.sh >/dev/null 2>&1; then
    echo "  ✗ FAIL: Could not start sidecar container"
    exit 1
fi

echo "  ✓ PASS: Sidecar container started"
echo "  Container: $CONTAINER_NAME"
echo ""

# Test 3: Wait for sidecar to become healthy
echo "Test 3: Waiting for sidecar to become healthy..."
MAX_WAIT=30
WAITED=0

while [ $WAITED -lt $MAX_WAIT ]; do
    HEALTH_STATUS=$(docker inspect --format='{{.State.Health.Status}}' "$CONTAINER_NAME" 2>/dev/null || echo "none")

    if [ "$HEALTH_STATUS" = "healthy" ]; then
        echo "  ✓ PASS: Sidecar is healthy (took ${WAITED}s)"
        break
    fi

    if [ "$HEALTH_STATUS" = "unhealthy" ]; then
        echo "  ✗ FAIL: Sidecar became unhealthy"
        echo ""
        echo "Container logs:"
        docker logs "$CONTAINER_NAME" 2>&1 | tail -20
        exit 1
    fi

    sleep 2
    WAITED=$((WAITED + 2))
done

if [ $WAITED -ge $MAX_WAIT ]; then
    echo "  ✗ FAIL: Sidecar did not become healthy within ${MAX_WAIT}s"
    echo "  Current status: $HEALTH_STATUS"
    echo ""
    echo "Container logs:"
    docker logs "$CONTAINER_NAME" 2>&1 | tail -20
    exit 1
fi
echo ""

# Test 4: Verify shared volume has valid tickets
echo "Test 4: Verifying shared volume has valid tickets..."

if ! docker run --rm \
    -v "${VOLUME_NAME}:/krb5/cache:ro" \
    "$IMAGE" test -f /krb5/cache/krb5cc; then
    echo "  ✗ FAIL: Ticket file not found in shared volume"
    exit 1
fi

# Verify ticket is valid
if ! docker run --rm \
    -v "${VOLUME_NAME}:/krb5/cache:ro" \
    "$IMAGE" klist -s /krb5/cache/krb5cc; then
    echo "  ✗ FAIL: Ticket in shared volume is invalid"
    exit 1
fi

echo "  ✓ PASS: Valid ticket found in shared volume"

# Show ticket details
echo ""
echo "  Ticket details from shared volume:"
docker run --rm \
    -v "${VOLUME_NAME}:/krb5/cache:ro" \
    "$IMAGE" klist /krb5/cache/krb5cc 2>/dev/null | while read line; do
    echo "    $line"
done
echo ""

# Test 5: Verify tickets are refreshed periodically
echo "Test 5: Verifying tickets are refreshed every ${COPY_INTERVAL}s..."
echo "  Getting initial modification time..."

# Get initial mtime
INITIAL_MTIME=$(docker run --rm \
    -v "${VOLUME_NAME}:/krb5/cache:ro" \
    "$IMAGE" stat -c %Y /krb5/cache/krb5cc)

echo "  Initial mtime: $INITIAL_MTIME"
echo "  Waiting $((COPY_INTERVAL + 5)) seconds for refresh..."

# Wait for one refresh cycle plus buffer
sleep $((COPY_INTERVAL + 5))

# Get new mtime
NEW_MTIME=$(docker run --rm \
    -v "${VOLUME_NAME}:/krb5/cache:ro" \
    "$IMAGE" stat -c %Y /krb5/cache/krb5cc)

echo "  New mtime: $NEW_MTIME"

if [ "$NEW_MTIME" -le "$INITIAL_MTIME" ]; then
    echo "  ✗ FAIL: Ticket was not refreshed (mtime unchanged)"
    echo "  Expected mtime > $INITIAL_MTIME, got $NEW_MTIME"
    echo ""
    echo "Container logs:"
    docker logs "$CONTAINER_NAME" 2>&1 | tail -20
    exit 1
fi

echo "  ✓ PASS: Ticket was refreshed ($((NEW_MTIME - INITIAL_MTIME))s elapsed)"
echo ""

# Test 6: Verify container logs show successful copy operations
echo "Test 6: Verifying container logs show successful copy operations..."

LOGS=$(docker logs "$CONTAINER_NAME" 2>&1)

if ! echo "$LOGS" | grep -q "Starting ticket copier"; then
    echo "  ✗ FAIL: Container logs missing 'Starting ticket copier' message"
    exit 1
fi

if ! echo "$LOGS" | grep -q "Copied ticket from:"; then
    echo "  ✗ FAIL: Container logs missing 'Copied ticket from:' message"
    echo ""
    echo "Container logs:"
    echo "$LOGS" | tail -20
    exit 1
fi

echo "  ✓ PASS: Container logs show successful ticket copying"
echo ""
echo "  Recent log entries:"
echo "$LOGS" | tail -10 | while read line; do
    echo "    $line"
done
echo ""
echo ""
echo "========================================"
echo "RESULT: TEST PASSED ✅"
echo "========================================"
echo ""
echo "Summary:"
echo "  ✓ Real ERUDITIS.LAB tickets verified"
echo "  ✓ Minimal sidecar started successfully"
echo "  ✓ Sidecar health check passing"
echo "  ✓ Tickets copied to shared volume"
echo "  ✓ Tickets refreshed every ${COPY_INTERVAL}s"
echo "  ✓ Container logs show successful operations"
echo ""
echo "Image: $IMAGE"
echo "Principal: $PRINCIPAL"
echo "Ticket source: $TICKET_DIR"
