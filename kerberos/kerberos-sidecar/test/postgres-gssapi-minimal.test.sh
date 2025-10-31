#!/bin/bash
# Test: PostgreSQL GSSAPI authentication with minimal sidecar
# Expected: FAIL if postgres client container not available or tickets invalid

set -e

SIDECAR_IMAGE="${IMAGE_NAME:-platform/kerberos-sidecar}:minimal"
POSTGRES_CLIENT_IMAGE="platform/postgres-client:test"

echo "========================================"
echo "TEST: PostgreSQL GSSAPI with Minimal Sidecar"
echo "========================================"
echo ""

# Check if user has real tickets to test with
if ! klist >/dev/null 2>&1; then
    echo "⚠ WARNING: No Kerberos tickets on host"
    echo "This test requires valid tickets. Run: kinit emaynard@ERUDITIS.LAB"
    echo "Skipping PostgreSQL GSSAPI test..."
    exit 1
fi

echo "Host Kerberos tickets:"
klist | head -3
echo ""

# Test 1: Start minimal sidecar
echo "Test 1: Starting minimal sidecar container..."
CONTAINER_NAME="minimal-sidecar-postgres-test-$$"
TICKET_DIR="${HOME}/.krb5-cache"
SHARED_TICKETS="/tmp/kerberos-tickets-postgres-test-$$"

# Clean up any previous test artifacts
rm -rf "$SHARED_TICKETS"
mkdir -p "$SHARED_TICKETS"

# Cleanup function
cleanup() {
    echo ""
    echo "Cleaning up..."
    docker stop "$CONTAINER_NAME" >/dev/null 2>&1 || true
    docker rm "$CONTAINER_NAME" >/dev/null 2>&1 || true
    rm -rf "$SHARED_TICKETS"
}
trap cleanup EXIT

# Create a volume for shared tickets
VOLUME_NAME="kerberos-tickets-postgres-test-$$"
docker volume create "$VOLUME_NAME" >/dev/null

# Update cleanup to remove volume
cleanup() {
    echo ""
    echo "Cleaning up..."
    docker stop "$CONTAINER_NAME" >/dev/null 2>&1 || true
    docker rm "$CONTAINER_NAME" >/dev/null 2>&1 || true
    docker volume rm "$VOLUME_NAME" >/dev/null 2>&1 || true
    rm -rf "$SHARED_TICKETS"
}
trap cleanup EXIT

# Start sidecar with ticket copying
docker run -d \
    --name "$CONTAINER_NAME" \
    -v "${TICKET_DIR}:/host/tickets:ro" \
    -v "${VOLUME_NAME}:/krb5/cache:rw" \
    -e TICKET_MODE=copy \
    -e COPY_INTERVAL=10 \
    "$SIDECAR_IMAGE" >/dev/null

# Give sidecar time to copy tickets
sleep 3

# Verify sidecar is healthy
if ! docker exec "$CONTAINER_NAME" klist >/dev/null 2>&1; then
    echo "  ✗ FAIL: Sidecar does not have valid tickets"
    docker logs "$CONTAINER_NAME"
    exit 1
fi

echo "  ✓ PASS: Minimal sidecar started with valid tickets"
echo ""

# Test 2: Check if postgres client image exists
echo "Test 2: Checking for PostgreSQL client container image..."
if ! docker image inspect "$POSTGRES_CLIENT_IMAGE" >/dev/null 2>&1; then
    echo "  ✗ FAIL: PostgreSQL client image not found: $POSTGRES_CLIENT_IMAGE"
    echo "  This is expected on first run (RED phase)"
    echo ""
    echo "  To fix, create a Dockerfile.postgres-test with:"
    echo "    - PostgreSQL client tools (psql)"
    echo "    - Kerberos client libraries"
    echo "    - Proper KRB5_CONFIG and KRB5CCNAME environment"
    exit 1
fi

echo "  ✓ PASS: PostgreSQL client image exists"
echo ""

# Test 3: Verify shared tickets are available in volume
echo "Test 3: Verifying shared ticket cache in volume..."
if ! docker run --rm \
    -v "${VOLUME_NAME}:/krb5/cache:ro" \
    "$SIDECAR_IMAGE" test -f /krb5/cache/krb5cc; then
    echo "  ✗ FAIL: Shared ticket cache not found in volume"
    docker logs "$CONTAINER_NAME"
    exit 1
fi

echo "  ✓ PASS: Shared ticket cache available in volume"
echo ""

# Test 4: Test PostgreSQL GSSAPI connection
echo "Test 4: Testing PostgreSQL GSSAPI connection to sqlpg.eruditis.lab..."
echo "Database: pagila"
echo "User: emaynard"
echo "Principal: emaynard@ERUDITIS.LAB"
echo ""

# Create krb5.conf for postgres client
KRB5_CONF_PATH="/tmp/krb5-postgres-test-$$.conf"
cat > "$KRB5_CONF_PATH" << 'EOF'
[libdefaults]
    default_realm = ERUDITIS.LAB
    dns_lookup_realm = false
    dns_lookup_kdc = true
    ticket_lifetime = 24h
    renew_lifetime = 7d
    forwardable = true
    rdns = false

[realms]
    ERUDITIS.LAB = {
        kdc = dc.eruditis.lab
        admin_server = dc.eruditis.lab
    }

[domain_realm]
    .eruditis.lab = ERUDITIS.LAB
    eruditis.lab = ERUDITIS.LAB
EOF

# Run psql with GSSAPI authentication
# Note: We need --add-host because sqlpg.eruditis.lab is in /etc/hosts on the host
if docker run --rm \
    --add-host "sqlpg.eruditis.lab:10.50.50.13" \
    -v "${VOLUME_NAME}:/krb5/cache:ro" \
    -v "${KRB5_CONF_PATH}:/etc/krb5.conf:ro" \
    -e KRB5CCNAME=/krb5/cache/krb5cc \
    -e PGHOST=sqlpg.eruditis.lab \
    -e PGPORT=5432 \
    -e PGDATABASE=pagila \
    -e PGUSER=emaynard \
    "$POSTGRES_CLIENT_IMAGE" \
    -c "psql -c 'SELECT version();'" 2>&1 | grep -q "PostgreSQL"; then
    echo "  ✓ PASS: PostgreSQL GSSAPI connection successful"
else
    echo "  ✗ FAIL: PostgreSQL GSSAPI connection failed"
    echo ""
    echo "Debug information:"
    docker run --rm \
        --add-host "sqlpg.eruditis.lab:10.50.50.13" \
        -v "${VOLUME_NAME}:/krb5/cache:ro" \
        -v "${KRB5_CONF_PATH}:/etc/krb5.conf:ro" \
        -e KRB5CCNAME=/krb5/cache/krb5cc \
        "$POSTGRES_CLIENT_IMAGE" \
        -c "klist" || true
    exit 1
fi

# Cleanup krb5.conf
rm -f "$KRB5_CONF_PATH"

echo ""
echo "========================================"
echo "RESULT: TEST PASSED ✅"
echo "========================================"
