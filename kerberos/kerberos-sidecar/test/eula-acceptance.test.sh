#!/usr/bin/env bash
# Test: EULA Acceptance in Test Containers
# ==========================================
# Verifies that test containers using Microsoft tools have ACCEPT_EULA=Y set
# to comply with Microsoft EULA requirements for ODBC drivers and SQL tools.
#
# This is Phase 5, Task 2 of the TDD refactor plan.
#
# Expected: Test containers with Microsoft tools have ENV ACCEPT_EULA=Y

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

echo "=========================================="
echo "Test: EULA Acceptance in Test Containers"
echo "=========================================="
echo ""

# Test result tracking
FAILED=0

# Test 1: Dockerfile.sqlcmd-test has ACCEPT_EULA=Y
echo "Test 1: Dockerfile.sqlcmd-test has ACCEPT_EULA=Y"
echo "---"
DOCKERFILE="${PROJECT_DIR}/Dockerfile.sqlcmd-test"
if [ ! -f "$DOCKERFILE" ]; then
    echo "✗ FAIL: Dockerfile.sqlcmd-test not found"
    FAILED=$((FAILED + 1))
else
    if grep -q "^ENV ACCEPT_EULA=Y" "$DOCKERFILE"; then
        echo "✓ PASS: Found ENV ACCEPT_EULA=Y in Dockerfile.sqlcmd-test"
    else
        echo "✗ FAIL: ENV ACCEPT_EULA=Y not found in Dockerfile.sqlcmd-test"
        echo "  This Dockerfile uses Microsoft ODBC drivers (msodbcsql18, mssql-tools18)"
        echo "  and requires ACCEPT_EULA=Y to comply with Microsoft EULA requirements"
        FAILED=$((FAILED + 1))
    fi
fi
echo ""

# Test 2: Dockerfile.test-image does NOT need ACCEPT_EULA (uses unixodbc-dev, not Microsoft drivers)
echo "Test 2: Dockerfile.test-image does NOT require ACCEPT_EULA"
echo "---"
DOCKERFILE="${PROJECT_DIR}/Dockerfile.test-image"
if [ ! -f "$DOCKERFILE" ]; then
    echo "✓ PASS: Dockerfile.test-image not found (skipped)"
else
    # Check if it uses Microsoft ODBC drivers
    if grep -qE "(msodbcsql|mssql-tools)" "$DOCKERFILE"; then
        echo "  Info: Dockerfile.test-image uses Microsoft tools"
        if grep -q "^ENV ACCEPT_EULA=Y" "$DOCKERFILE"; then
            echo "✓ PASS: Found ENV ACCEPT_EULA=Y in Dockerfile.test-image"
        else
            echo "✗ FAIL: ENV ACCEPT_EULA=Y not found in Dockerfile.test-image"
            echo "  This Dockerfile uses Microsoft tools and requires ACCEPT_EULA=Y"
            FAILED=$((FAILED + 1))
        fi
    else
        echo "✓ PASS: Dockerfile.test-image does not use Microsoft tools (ACCEPT_EULA not required)"
    fi
fi
echo ""

# Test 3: Dockerfile.postgres-test does NOT need ACCEPT_EULA (only uses PostgreSQL client)
echo "Test 3: Dockerfile.postgres-test does NOT require ACCEPT_EULA"
echo "---"
DOCKERFILE="${PROJECT_DIR}/Dockerfile.postgres-test"
if [ ! -f "$DOCKERFILE" ]; then
    echo "✓ PASS: Dockerfile.postgres-test not found (skipped)"
else
    # Check if it uses Microsoft ODBC drivers
    if grep -qE "(msodbcsql|mssql-tools)" "$DOCKERFILE"; then
        echo "  Info: Dockerfile.postgres-test uses Microsoft tools"
        if grep -q "^ENV ACCEPT_EULA=Y" "$DOCKERFILE"; then
            echo "✓ PASS: Found ENV ACCEPT_EULA=Y in Dockerfile.postgres-test"
        else
            echo "✗ FAIL: ENV ACCEPT_EULA=Y not found in Dockerfile.postgres-test"
            echo "  This Dockerfile uses Microsoft tools and requires ACCEPT_EULA=Y"
            FAILED=$((FAILED + 1))
        fi
    else
        echo "✓ PASS: Dockerfile.postgres-test does not use Microsoft tools (ACCEPT_EULA not required)"
    fi
fi
echo ""

# Summary
echo "=========================================="
if [ $FAILED -eq 0 ]; then
    echo "✓ ALL TESTS PASSED"
    echo "=========================================="
    exit 0
else
    echo "✗ $FAILED TEST(S) FAILED"
    echo "=========================================="
    exit 1
fi
