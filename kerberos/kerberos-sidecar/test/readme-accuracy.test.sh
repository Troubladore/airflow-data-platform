#!/bin/bash
set -euo pipefail

# Test: README Accuracy for Minimal Sidecar
# Purpose: Verify README.md documents minimal sidecar, test containers, and migration

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SIDECAR_DIR="$(dirname "$SCRIPT_DIR")"
README="$SIDECAR_DIR/README.md"

echo "=========================================="
echo "Testing README Accuracy"
echo "=========================================="

# RED: Assert README references Dockerfile.minimal
echo "Test 1: README references Dockerfile.minimal..."
if ! grep -qi "Dockerfile\.minimal" "$README"; then
    echo "FAIL: README does not reference Dockerfile.minimal"
    exit 1
fi
echo "PASS: README references Dockerfile.minimal"

# RED: Assert README shows minimal sidecar usage
echo ""
echo "Test 2: README shows minimal sidecar usage pattern..."
if ! grep -qi "platform/kerberos-sidecar:minimal" "$README"; then
    echo "FAIL: README does not show minimal sidecar image tag usage"
    exit 1
fi
echo "PASS: README shows minimal sidecar usage"

# RED: Assert README links to test containers
echo ""
echo "Test 3: README documents test container usage..."
if ! grep -qi "sqlcmd-test\|postgres-test" "$README" || \
   ! grep -qi "test.*container" "$README"; then
    echo "FAIL: README does not document test container usage"
    exit 1
fi
echo "PASS: README documents test containers"

# RED: Assert README documents separation of concerns
echo ""
echo "Test 4: README documents separation of concerns..."
if ! grep -qi "separation.*concern\|minimal.*legacy\|16.*MB\|15\.91.*MB" "$README"; then
    echo "FAIL: README does not document separation of concerns or image comparison"
    exit 1
fi
echo "PASS: README documents separation of concerns"

# Additional quality checks
echo ""
echo "Test 5: README links to MIGRATION-GUIDE.md..."
if ! grep -qi "MIGRATION-GUIDE\.md\|migration.*guide" "$README"; then
    echo "FAIL: README does not link to MIGRATION-GUIDE.md"
    exit 1
fi
echo "PASS: README links to migration guide"

echo ""
echo "Test 6: README documents image size stats..."
# Check for size comparison (minimal vs legacy)
if ! grep -qE "15\.91.*MB|16.*MB" "$README" || \
   ! grep -qE "35.*package|15-20.*package" "$README"; then
    echo "FAIL: README missing accurate size/package statistics"
    exit 1
fi
echo "PASS: README has accurate size statistics"

echo ""
echo "Test 7: README shows how to use test containers separately..."
# Check for docker run and test container names (separately, since they may be on different lines)
if ! grep -q "docker run" "$README" || \
   ! (grep -q "sqlcmd-test" "$README" && grep -q "postgres-test" "$README"); then
    echo "FAIL: README does not show how to run test containers"
    exit 1
fi
echo "PASS: README shows test container run commands"

echo ""
echo "Test 8: README documents legacy image for comparison..."
if ! grep -qE "312.*MB|legacy|bloated" "$README"; then
    echo "FAIL: README does not mention legacy/bloated image for comparison"
    exit 1
fi
echo "PASS: README documents legacy comparison"

echo ""
echo "=========================================="
echo "ALL TESTS PASSED"
echo "README accurately documents minimal sidecar!"
echo "=========================================="
