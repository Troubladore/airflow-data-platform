#!/bin/bash
set -euo pipefail

# Test: Migration Guide Completeness
# Purpose: Verify MIGRATION-GUIDE.md exists and contains all required sections

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SIDECAR_DIR="$(dirname "$SCRIPT_DIR")"
MIGRATION_GUIDE="$SIDECAR_DIR/MIGRATION-GUIDE.md"

echo "=========================================="
echo "Testing Migration Guide Completeness"
echo "=========================================="

# RED: Assert migration guide exists
echo "Test 1: Migration guide file exists..."
if [ ! -f "$MIGRATION_GUIDE" ]; then
    echo "FAIL: MIGRATION-GUIDE.md does not exist at $MIGRATION_GUIDE"
    exit 1
fi
echo "PASS: Migration guide exists"

# RED: Assert contains legacy → minimal migration steps
echo ""
echo "Test 2: Contains legacy to minimal migration steps..."
if ! grep -qi "migration.*steps" "$MIGRATION_GUIDE" || \
   ! grep -qi "legacy.*minimal" "$MIGRATION_GUIDE"; then
    echo "FAIL: Migration guide missing legacy to minimal migration steps"
    exit 1
fi
echo "PASS: Contains migration steps"

# RED: Assert documents test container usage
echo ""
echo "Test 3: Documents test container usage..."
if ! grep -qi "test.*container" "$MIGRATION_GUIDE" || \
   ! grep -qi "sqlcmd-test\|postgres" "$MIGRATION_GUIDE"; then
    echo "FAIL: Migration guide missing test container documentation"
    exit 1
fi
echo "PASS: Documents test containers"

# Additional assertions for quality
echo ""
echo "Test 4: Contains rationale (why migrate)..."
if ! grep -qi "why\|rationale\|benefit\|advantage" "$MIGRATION_GUIDE"; then
    echo "FAIL: Migration guide missing rationale for migration"
    exit 1
fi
echo "PASS: Contains migration rationale"

echo ""
echo "Test 5: Contains troubleshooting section..."
if ! grep -qi "troubleshoot\|common.*issue\|problem" "$MIGRATION_GUIDE"; then
    echo "FAIL: Migration guide missing troubleshooting section"
    exit 1
fi
echo "PASS: Contains troubleshooting section"

echo ""
echo "Test 6: Documents rollback plan..."
if ! grep -qi "rollback\|revert\|back.*to.*legacy" "$MIGRATION_GUIDE"; then
    echo "FAIL: Migration guide missing rollback plan"
    exit 1
fi
echo "PASS: Documents rollback plan"

echo ""
echo "Test 7: Documents image size comparison..."
if ! grep -qE "312|MB|16.*MB|size" "$MIGRATION_GUIDE"; then
    echo "FAIL: Migration guide missing image size comparison"
    exit 1
fi
echo "PASS: Documents image size comparison"

echo ""
echo "=========================================="
echo "ALL TESTS PASSED"
echo "Migration guide is complete!"
echo "=========================================="
