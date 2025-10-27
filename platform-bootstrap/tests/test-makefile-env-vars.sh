#!/bin/bash
# Test: Verify Makefile passes environment variables to setup scripts
# This prevents regression where custom image paths aren't passed through

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLATFORM_DIR="$(dirname "$SCRIPT_DIR")"

echo "Testing Makefile environment variable passing..."
echo ""

# Test 1: Verify IMAGE_POSTGRES is passed to setup-pagila script
echo "Test 1: IMAGE_POSTGRES passed to setup-pagila"
echo "----------------------------------------------"

# Use make -n (dry run) to see what would be executed
MAKE_OUTPUT=$(cd "$PLATFORM_DIR" && make -n setup-pagila \
    IMAGE_POSTGRES="test.registry.com/custom-postgres:99.9" \
    PAGILA_REPO_URL="https://test.com/repo.git" \
    PAGILA_AUTO_YES=1)

echo "Make would execute:"
echo "$MAKE_OUTPUT"
echo ""

# Verify IMAGE_POSTGRES is in the command
if echo "$MAKE_OUTPUT" | grep -q 'IMAGE_POSTGRES="test.registry.com/custom-postgres:99.9"'; then
    echo "✓ PASS: IMAGE_POSTGRES is passed to script"
else
    echo "✗ FAIL: IMAGE_POSTGRES is NOT passed to script"
    echo "Expected to see: IMAGE_POSTGRES=\"test.registry.com/custom-postgres:99.9\""
    exit 1
fi

# Verify PAGILA_REPO_URL is in the command
if echo "$MAKE_OUTPUT" | grep -q 'PAGILA_REPO_URL="https://test.com/repo.git"'; then
    echo "✓ PASS: PAGILA_REPO_URL is passed to script"
else
    echo "✗ FAIL: PAGILA_REPO_URL is NOT passed to script"
    echo "Expected to see: PAGILA_REPO_URL=\"https://test.com/repo.git\""
    exit 1
fi

echo ""

# Test 2: Verify both interactive and non-interactive modes pass variables
echo "Test 2: Variables passed in both modes"
echo "---------------------------------------"

# Non-interactive mode (PAGILA_AUTO_YES=1)
MAKE_OUTPUT_AUTO=$(cd "$PLATFORM_DIR" && make -n setup-pagila \
    IMAGE_POSTGRES="custom:tag" \
    PAGILA_AUTO_YES=1)

if echo "$MAKE_OUTPUT_AUTO" | grep -q 'IMAGE_POSTGRES="custom:tag"'; then
    echo "✓ PASS: Variables passed in auto mode (--yes)"
else
    echo "✗ FAIL: Variables NOT passed in auto mode"
    exit 1
fi

# Interactive mode (PAGILA_AUTO_YES not set)
MAKE_OUTPUT_INTERACTIVE=$(cd "$PLATFORM_DIR" && make -n setup-pagila \
    IMAGE_POSTGRES="custom:tag")

if echo "$MAKE_OUTPUT_INTERACTIVE" | grep -q 'IMAGE_POSTGRES="custom:tag"'; then
    echo "✓ PASS: Variables passed in interactive mode"
else
    echo "✗ FAIL: Variables NOT passed in interactive mode"
    exit 1
fi

echo ""
echo "═══════════════════════════════════════════════"
echo "✓ ALL TESTS PASSED"
echo "═══════════════════════════════════════════════"
echo ""
echo "Makefile correctly passes environment variables to setup scripts."
echo "Custom image paths will work as expected."
