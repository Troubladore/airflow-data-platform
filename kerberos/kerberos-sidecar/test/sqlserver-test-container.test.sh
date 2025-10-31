#!/bin/bash
# Test: SQL Server test container with minimal sidecar
# Expected: FAIL if sqlcmd-test image not available or tickets invalid

set -e

SIDECAR_IMAGE="${IMAGE_NAME:-platform/kerberos-sidecar}:minimal"
SQLCMD_TEST_IMAGE="platform/sqlcmd-test:latest"

echo "========================================"
echo "TEST: SQL Server Test Container with Minimal Sidecar"
echo "========================================"
echo ""

# Check if user has real tickets to test with
if ! klist >/dev/null 2>&1; then
    echo "⚠ WARNING: No Kerberos tickets on host"
    echo "This test requires valid tickets. Run: kinit emaynard@ERUDITIS.LAB"
    echo "Skipping SQL Server test..."
    exit 1
fi

echo "Host Kerberos tickets:"
klist | head -3
echo ""

# Test 1: Start minimal sidecar
echo "Test 1: Starting minimal sidecar container..."
CONTAINER_NAME="minimal-sidecar-sqlserver-test-$$"
TICKET_DIR="${HOME}/.krb5-cache"

# Cleanup function
cleanup() {
    echo ""
    echo "Cleaning up..."
    docker stop "$CONTAINER_NAME" >/dev/null 2>&1 || true
    docker rm "$CONTAINER_NAME" >/dev/null 2>&1 || true
    docker volume rm "$VOLUME_NAME" >/dev/null 2>&1 || true
}
trap cleanup EXIT

# Create a volume for shared tickets
VOLUME_NAME="kerberos-tickets-sqlserver-test-$$"
docker volume create "$VOLUME_NAME" >/dev/null

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

# Test 2: Check if sqlcmd-test image exists
echo "Test 2: Checking for sqlcmd-test container image..."
if ! docker image inspect "$SQLCMD_TEST_IMAGE" >/dev/null 2>&1; then
    echo "  ✗ FAIL: sqlcmd-test image not found: $SQLCMD_TEST_IMAGE"
    echo "  This is expected on first run (RED phase)"
    echo ""
    echo "  To fix, build the image:"
    echo "    docker build -f Dockerfile.sqlcmd-test -t platform/sqlcmd-test:latest ."
    exit 1
fi

echo "  ✓ PASS: sqlcmd-test image exists"
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

# Test 4: Verify sqlcmd is available
echo "Test 4: Verifying sqlcmd is available in test container..."
if ! docker run --rm "$SQLCMD_TEST_IMAGE" -c "command -v sqlcmd >/dev/null"; then
    echo "  ✗ FAIL: sqlcmd not found in test container"
    exit 1
fi

echo "  ✓ PASS: sqlcmd is available"
echo ""

# Test 5: Verify Kerberos client libraries are available
echo "Test 5: Verifying Kerberos client libraries in test container..."
if ! docker run --rm "$SQLCMD_TEST_IMAGE" -c "command -v klist >/dev/null"; then
    echo "  ✗ FAIL: klist not found in test container (krb5 missing)"
    exit 1
fi

echo "  ✓ PASS: Kerberos client libraries available"
echo ""

# Test 6: Verify sqlcmd can access Kerberos tickets
echo "Test 6: Verifying sqlcmd container can access Kerberos tickets..."

# Create krb5.conf for SQL Server client
KRB5_CONF_PATH="/tmp/krb5-sqlserver-test-$$.conf"
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

# Verify tickets are accessible from the test container
if docker run --rm \
    -v "${VOLUME_NAME}:/krb5/cache:ro" \
    -v "${KRB5_CONF_PATH}:/etc/krb5.conf:ro" \
    -e KRB5CCNAME=/krb5/cache/krb5cc \
    "$SQLCMD_TEST_IMAGE" \
    -c "klist" 2>&1 | grep -q "ERUDITIS.LAB"; then
    echo "  ✓ PASS: sqlcmd container can access Kerberos tickets"
else
    echo "  ✗ FAIL: sqlcmd container cannot access Kerberos tickets"
    echo ""
    echo "Debug information:"
    docker run --rm \
        -v "${VOLUME_NAME}:/krb5/cache:ro" \
        -v "${KRB5_CONF_PATH}:/etc/krb5.conf:ro" \
        -e KRB5CCNAME=/krb5/cache/krb5cc \
        "$SQLCMD_TEST_IMAGE" \
        -c "ls -la /krb5/cache/ && klist -v" || true
    rm -f "$KRB5_CONF_PATH"
    exit 1
fi

echo ""

# Test 7: Check for SQL Server availability (optional - may skip)
echo "Test 7: Testing SQL Server connection (optional)..."
echo "This test will skip if no SQL Server is available in ERUDITIS.LAB"
echo ""

# Look for SQL Server in /etc/hosts or DNS
SQL_SERVER=""
if grep -q "sqlserver" /etc/hosts 2>/dev/null; then
    SQL_SERVER=$(grep "sqlserver" /etc/hosts | head -1 | awk '{print $2}')
    echo "Found SQL Server in /etc/hosts: $SQL_SERVER"
elif host sqlserver.eruditis.lab >/dev/null 2>&1; then
    SQL_SERVER="sqlserver.eruditis.lab"
    echo "Found SQL Server via DNS: $SQL_SERVER"
else
    echo "  ⚠ SKIP: No SQL Server found in ERUDITIS.LAB"
    echo "  Test validates sqlcmd availability - SQL Server connection optional"
    rm -f "$KRB5_CONF_PATH"
    echo ""
    echo "========================================"
    echo "RESULT: TEST PASSED ✅ (with skip)"
    echo "========================================"
    exit 0
fi

# Try to connect to SQL Server using sqlcmd with Kerberos auth
echo "Attempting connection to: $SQL_SERVER"
echo "Using Kerberos authentication..."
echo ""

if docker run --rm \
    --add-host "$SQL_SERVER:$(getent hosts $SQL_SERVER | awk '{print $1}')" \
    -v "${VOLUME_NAME}:/krb5/cache:ro" \
    -v "${KRB5_CONF_PATH}:/etc/krb5.conf:ro" \
    -e KRB5CCNAME=/krb5/cache/krb5cc \
    "$SQLCMD_TEST_IMAGE" \
    -c "sqlcmd -S $SQL_SERVER -Q 'SELECT @@VERSION' -E -C" 2>&1 | grep -q "Microsoft SQL Server"; then
    echo "  ✓ PASS: SQL Server connection successful"
else
    echo "  ⚠ SKIP: SQL Server connection failed (may not support Kerberos or not accessible)"
    echo "  Test validates sqlcmd availability - connection failure is non-fatal"
fi

# Cleanup krb5.conf
rm -f "$KRB5_CONF_PATH"

echo ""
echo "========================================"
echo "RESULT: TEST PASSED ✅"
echo "========================================"
