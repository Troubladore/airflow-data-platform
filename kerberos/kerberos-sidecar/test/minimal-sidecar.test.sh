#!/bin/bash
# Test: Minimal sidecar contains ONLY required packages
# Expected: FAIL (current image has bloated packages)

set -e

IMAGE="${IMAGE_NAME:-platform/kerberos-sidecar}:minimal"
FAILED=0

echo "========================================"
echo "TEST: Minimal Sidecar Package Requirements"
echo "========================================"
echo ""

# Test 1: Image must NOT contain build tools
echo "Test 1: Checking for prohibited build tools..."
PROHIBITED_BUILD_TOOLS=(
    "gcc"
    "g++"
    "musl-dev"
    "libffi-dev"
    "openssl-dev"
    "krb5-dev"
)

for pkg in "${PROHIBITED_BUILD_TOOLS[@]}"; do
    if docker run --rm "$IMAGE" sh -c "apk info | grep -q '^${pkg}$'" 2>/dev/null; then
        echo "  ✗ FAIL: Build tool found: $pkg"
        FAILED=1
    else
        echo "  ✓ PASS: Build tool not present: $pkg"
    fi
done

echo ""

# Test 2: Image must NOT contain ODBC/SQL tools
echo "Test 2: Checking for prohibited ODBC/SQL tools..."
PROHIBITED_SQL_TOOLS=(
    "msodbcsql18"
    "mssql-tools18"
    "unixodbc"
    "unixodbc-dev"
    "freetds"
    "freetds-dev"
)

for pkg in "${PROHIBITED_SQL_TOOLS[@]}"; do
    if docker run --rm "$IMAGE" sh -c "apk info | grep -q '^${pkg}$'" 2>/dev/null; then
        echo "  ✗ FAIL: SQL tool found: $pkg"
        FAILED=1
    else
        echo "  ✓ PASS: SQL tool not present: $pkg"
    fi
done

echo ""

# Test 3: Image must NOT contain Python
echo "Test 3: Checking for prohibited Python packages..."
PROHIBITED_PYTHON=(
    "python3"
    "py3-pip"
    "py3-setuptools"
)

for pkg in "${PROHIBITED_PYTHON[@]}"; do
    if docker run --rm "$IMAGE" sh -c "apk info | grep -q '^${pkg}$'" 2>/dev/null; then
        echo "  ✗ FAIL: Python package found: $pkg"
        FAILED=1
    else
        echo "  ✓ PASS: Python package not present: $pkg"
    fi
done

echo ""

# Test 4: Image MUST contain required Kerberos packages
echo "Test 4: Checking for required Kerberos packages..."
REQUIRED_PACKAGES=(
    "krb5"
    "krb5-libs"
    "bash"
    "curl"
    "ca-certificates"
)

for pkg in "${REQUIRED_PACKAGES[@]}"; do
    if docker run --rm "$IMAGE" sh -c "apk info | grep -q '^${pkg}$'" 2>/dev/null; then
        echo "  ✓ PASS: Required package present: $pkg"
    else
        echo "  ✗ FAIL: Required package missing: $pkg"
        FAILED=1
    fi
done

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
