#!/bin/bash
# Test: Dockerfile Naming Convention
# Purpose: Ensure Dockerfile.legacy and Dockerfile exist with correct naming
# Expected: Dockerfile.legacy (bloated), Dockerfile (minimal)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SIDECAR_DIR="$(dirname "$SCRIPT_DIR")"

echo "========================================"
echo "Test: Dockerfile Naming Convention"
echo "========================================"
echo ""

# Track test results
FAILED=0

# Test 1: Dockerfile.legacy exists (the current bloated one)
echo "Test 1: Checking Dockerfile.legacy exists..."
if [ -f "$SIDECAR_DIR/Dockerfile.legacy" ]; then
    echo "✓ Dockerfile.legacy exists"
else
    echo "✗ FAIL: Dockerfile.legacy not found"
    echo "  Expected: Bloated Dockerfile renamed to Dockerfile.legacy"
    FAILED=1
fi
echo ""

# Test 2: Dockerfile exists (the minimal one)
echo "Test 2: Checking Dockerfile exists..."
if [ -f "$SIDECAR_DIR/Dockerfile" ]; then
    echo "✓ Dockerfile exists"
else
    echo "✗ FAIL: Dockerfile not found"
    echo "  Expected: Minimal Dockerfile as default"
    FAILED=1
fi
echo ""

# Test 3: Dockerfile is the minimal one (not bloated)
echo "Test 3: Checking Dockerfile is minimal (not bloated)..."
if [ -f "$SIDECAR_DIR/Dockerfile" ]; then
    # Check for actual package installation, not just comments
    # Look for apk add or curl commands installing bloated packages
    if grep "apk add" "$SIDECAR_DIR/Dockerfile" | grep -q "msodbcsql18"; then
        echo "✗ FAIL: Dockerfile installs msodbcsql18 (bloated version)"
        echo "  Expected: Dockerfile should be minimal (no ODBC drivers)"
        FAILED=1
    elif grep "apk add" "$SIDECAR_DIR/Dockerfile" | grep -q "gcc"; then
        echo "✗ FAIL: Dockerfile installs gcc (bloated version)"
        echo "  Expected: Dockerfile should be minimal (no build tools)"
        FAILED=1
    elif grep "apk add" "$SIDECAR_DIR/Dockerfile" | grep -q "python3"; then
        echo "✗ FAIL: Dockerfile installs python3 (bloated version)"
        echo "  Expected: Dockerfile should be minimal (no Python)"
        FAILED=1
    elif grep -q "curl.*msodbcsql18" "$SIDECAR_DIR/Dockerfile"; then
        echo "✗ FAIL: Dockerfile downloads msodbcsql18 (bloated version)"
        echo "  Expected: Dockerfile should be minimal (no ODBC drivers)"
        FAILED=1
    else
        echo "✓ Dockerfile is minimal (no bloat detected)"
    fi
else
    echo "⊘ SKIP: Dockerfile not found"
fi
echo ""

# Test 4: Dockerfile.legacy is the bloated one
echo "Test 4: Checking Dockerfile.legacy is bloated (has ODBC/build tools)..."
if [ -f "$SIDECAR_DIR/Dockerfile.legacy" ]; then
    if grep -q "msodbcsql18" "$SIDECAR_DIR/Dockerfile.legacy" && \
       grep -q "gcc" "$SIDECAR_DIR/Dockerfile.legacy"; then
        echo "✓ Dockerfile.legacy contains expected bloat (ODBC + build tools)"
    else
        echo "✗ FAIL: Dockerfile.legacy missing expected bloat"
        echo "  Expected: Legacy version with msodbcsql18, gcc, etc."
        FAILED=1
    fi
else
    echo "⊘ SKIP: Dockerfile.legacy not found"
fi
echo ""

# Test 5: Makefile supports building both variants
echo "Test 5: Checking Makefile supports both Dockerfile variants..."
if grep -q "Dockerfile.legacy" "$SIDECAR_DIR/Makefile"; then
    echo "✓ Makefile references Dockerfile.legacy"
else
    echo "✗ FAIL: Makefile does not reference Dockerfile.legacy"
    echo "  Expected: Makefile should have build-legacy target"
    FAILED=1
fi
echo ""

# Test 6: Makefile default build uses Dockerfile (minimal)
echo "Test 6: Checking Makefile default build uses Dockerfile..."
if grep -q "^build:.*##.*Build.*minimal" "$SIDECAR_DIR/Makefile"; then
    # Extract the build target and check if it uses explicit Dockerfile
    BUILD_TARGET=$(sed -n '/^build:/,/^build-legacy:/p' "$SIDECAR_DIR/Makefile")
    if echo "$BUILD_TARGET" | grep -q "docker build.*-f Dockerfile.legacy"; then
        echo "✗ FAIL: Default build target uses Dockerfile.legacy"
        echo "  Expected: Default build should use Dockerfile (minimal)"
        FAILED=1
    else
        echo "✓ Makefile default build uses Dockerfile (minimal, no -f flag)"
    fi
else
    echo "⊘ SKIP: Could not find build target in Makefile"
fi
echo ""

# Test 7: Makefile has build-legacy target
echo "Test 7: Checking Makefile has build-legacy target..."
if grep -q "^build-legacy:" "$SIDECAR_DIR/Makefile"; then
    echo "✓ Makefile has build-legacy target"
else
    echo "✗ FAIL: Makefile missing build-legacy target"
    echo "  Expected: make build-legacy should build Dockerfile.legacy"
    FAILED=1
fi
echo ""

# Test 8: Both Dockerfiles have explanatory comments
echo "Test 8: Checking Dockerfiles have usage comments..."
DOCKERFILE_HAS_COMMENT=0
LEGACY_HAS_COMMENT=0

if [ -f "$SIDECAR_DIR/Dockerfile" ]; then
    if head -n 10 "$SIDECAR_DIR/Dockerfile" | grep -qi "minimal\|purpose"; then
        echo "✓ Dockerfile has explanatory comment"
        DOCKERFILE_HAS_COMMENT=1
    else
        echo "✗ FAIL: Dockerfile missing explanatory comment"
        FAILED=1
    fi
else
    echo "⊘ SKIP: Dockerfile not found"
fi

if [ -f "$SIDECAR_DIR/Dockerfile.legacy" ]; then
    if head -n 10 "$SIDECAR_DIR/Dockerfile.legacy" | grep -qi "legacy\|purpose\|bloated"; then
        echo "✓ Dockerfile.legacy has explanatory comment"
        LEGACY_HAS_COMMENT=1
    else
        echo "✗ FAIL: Dockerfile.legacy missing explanatory comment"
        FAILED=1
    fi
else
    echo "⊘ SKIP: Dockerfile.legacy not found"
fi
echo ""

# Test 9: Image tags are correct
echo "Test 9: Checking image tag configuration..."
if grep -q "IMAGE_NAME.*platform/kerberos-sidecar" "$SIDECAR_DIR/Makefile"; then
    echo "✓ IMAGE_NAME is platform/kerberos-sidecar"
else
    echo "✗ FAIL: IMAGE_NAME not set correctly"
    FAILED=1
fi

if grep -q "IMAGE_TAG.*latest" "$SIDECAR_DIR/Makefile"; then
    echo "✓ IMAGE_TAG defaults to latest"
else
    echo "⊘ WARNING: IMAGE_TAG may not default to latest"
fi
echo ""

# Summary
echo "========================================"
if [ $FAILED -eq 0 ]; then
    echo "✓ ALL TESTS PASSED"
    echo "========================================"
    exit 0
else
    echo "✗ TESTS FAILED"
    echo "========================================"
    echo ""
    echo "Expected file structure:"
    echo "  Dockerfile         → Minimal sidecar (default)"
    echo "  Dockerfile.legacy  → Bloated sidecar (backwards compatibility)"
    echo ""
    echo "Expected Makefile targets:"
    echo "  make build         → Builds Dockerfile (minimal)"
    echo "  make build-legacy  → Builds Dockerfile.legacy (bloated)"
    echo ""
    exit 1
fi
