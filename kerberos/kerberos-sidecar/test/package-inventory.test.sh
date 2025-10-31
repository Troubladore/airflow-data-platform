#!/bin/bash
# Test: Package inventory meets minimal requirements
# Expected: FAIL (current image has 120+ packages)

set -e

IMAGE="${IMAGE_NAME:-platform/kerberos-sidecar}:minimal"
FAILED=0

echo "========================================"
echo "TEST: Minimal Sidecar Package Inventory"
echo "========================================"
echo ""

# Check if image exists
if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
    echo "✗ FAIL: Image not found: $IMAGE"
    exit 1
fi

# Get package count
PACKAGE_COUNT=$(docker run --rm "$IMAGE" sh -c "apk info | wc -l")
echo "Total packages: $PACKAGE_COUNT"
echo ""

# Test 1: Package count must be < 40 (Alpine base has ~15, we add ~20)
MAX_PACKAGES=40
echo "Test 1: Package count < $MAX_PACKAGES"
if [ "$PACKAGE_COUNT" -gt "$MAX_PACKAGES" ]; then
    echo "  ✗ FAIL: Too many packages ($PACKAGE_COUNT > $MAX_PACKAGES)"
    FAILED=1
else
    echo "  ✓ PASS: Package count acceptable ($PACKAGE_COUNT < $MAX_PACKAGES)"
fi
echo ""

# Test 2: Required packages present
echo "Test 2: Required packages present"
REQUIRED_PACKAGES=(
    "krb5"
    "krb5-libs"
    "bash"
    "curl"
    "ca-certificates"
)

for pkg in "${REQUIRED_PACKAGES[@]}"; do
    if docker run --rm "$IMAGE" sh -c "apk info | grep -q '^${pkg}$'" 2>/dev/null; then
        echo "  ✓ $pkg"
    else
        echo "  ✗ MISSING: $pkg"
        FAILED=1
    fi
done
echo ""

# Test 3: Prohibited packages NOT present
echo "Test 3: Prohibited packages NOT present"
PROHIBITED_PACKAGES=(
    "gcc"
    "g++"
    "musl-dev"
    "python3"
    "py3-pip"
    "msodbcsql18"
    "mssql-tools18"
    "unixodbc"
    "freetds"
    "krb5-dev"
    "openssl-dev"
    "libffi-dev"
)

for pkg in "${PROHIBITED_PACKAGES[@]}"; do
    if docker run --rm "$IMAGE" sh -c "apk info | grep -q '^${pkg}$'" 2>/dev/null; then
        echo "  ✗ FOUND (should not exist): $pkg"
        FAILED=1
    else
        echo "  ✓ Not present: $pkg"
    fi
done
echo ""

# Test 4: Generate package manifest for documentation
echo "Test 4: Package manifest"
echo "Full package list:"
docker run --rm "$IMAGE" sh -c "apk info | sort" | sed 's/^/  /'
echo ""

echo "========================================"
if [ $FAILED -eq 1 ]; then
    echo "RESULT: TEST FAILED ❌"
    echo "========================================"
    exit 1
else
    echo "RESULT: TEST PASSED ✅"
    echo "========================================"
    exit 0
fi
