#!/bin/bash
# Test runner for all diagnostic components

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TESTS_DIR="$SCRIPT_DIR/tests"

echo "🧪 Platform Diagnostics Test Suite"
echo "==================================="
echo

# Track test results
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

run_test_suite() {
    local test_file="$1"
    local test_name="$2"

    echo "▶️  Running $test_name"
    echo "   Test file: $(basename "$test_file")"

    TOTAL_TESTS=$((TOTAL_TESTS + 1))

    if "$test_file"; then
        echo "✅ $test_name PASSED"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        echo "❌ $test_name FAILED"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
    echo
}

# Run unit tests
echo "🔬 Unit Tests"
echo "============="
if [ -d "$TESTS_DIR/unit" ]; then
    for test_file in "$TESTS_DIR/unit"/*.sh; do
        if [ -f "$test_file" ]; then
            test_name="Unit: $(basename "$test_file" .sh)"
            run_test_suite "$test_file" "$test_name"
        fi
    done
else
    echo "⚠️  No unit tests directory found"
fi

# Run integration tests
echo "🔗 Integration Tests"
echo "===================="
if [ -d "$TESTS_DIR/integration" ]; then
    for test_file in "$TESTS_DIR/integration"/*.sh; do
        if [ -f "$test_file" ]; then
            test_name="Integration: $(basename "$test_file" .sh)"
            run_test_suite "$test_file" "$test_name"
        fi
    done
else
    echo "⚠️  No integration tests directory found"
fi

# Summary
echo "🏁 Test Suite Complete"
echo "======================"
echo "Total test suites: $TOTAL_TESTS"
echo "Passed: $PASSED_TESTS"
echo "Failed: $FAILED_TESTS"

if [ $FAILED_TESTS -eq 0 ]; then
    echo "🎉 All test suites passed!"

    # Show current system state as detected by our diagnostics
    echo
    echo "📋 Current System State Summary"
    echo "==============================="
    "$SCRIPT_DIR/diagnostics/system-state.sh" | grep -E "(✅|❌|⚠️)" | head -10

    exit 0
else
    echo "💥 $FAILED_TESTS test suite(s) failed!"
    exit 1
fi
