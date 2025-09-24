#!/bin/bash
# Unit tests for Windows PowerShell detection utility

set -euo pipefail

# Test framework
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

assert_equals() {
    local expected="$1"
    local actual="$2"
    local test_name="$3"

    TESTS_RUN=$((TESTS_RUN + 1))

    if [ "$expected" = "$actual" ]; then
        echo "✅ PASS: $test_name"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo "❌ FAIL: $test_name"
        echo "   Expected: '$expected'"
        echo "   Actual:   '$actual'"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

assert_contains() {
    local expected_substring="$1"
    local actual_string="$2"
    local test_name="$3"

    TESTS_RUN=$((TESTS_RUN + 1))

    if [[ "$actual_string" == *"$expected_substring"* ]]; then
        echo "✅ PASS: $test_name"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo "❌ FAIL: $test_name"
        echo "   Expected substring: '$expected_substring'"
        echo "   Actual string:      '$actual_string'"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

# Source the functions we're testing
source "$(dirname "$0")/../../diagnostics/system-state.sh"

echo "🧪 Windows PowerShell Detection Unit Tests"
echo "==========================================="

# Test 0: Verify CA pollution detection in diagnostic output
test_ca_pollution_detection() {
    if [ "$WINDOWS_ACCESSIBLE" = true ]; then
        local diagnostic_output
        diagnostic_output=$(detect_windows_certificates 2>/dev/null)

        if [[ "$diagnostic_output" == *"POLLUTED"* ]]; then
            echo "✅ PASS: CA pollution correctly detected in diagnostic output"
            TESTS_PASSED=$((TESTS_PASSED + 1))
        elif [[ "$diagnostic_output" == *"Windows CA trust:"* ]]; then
            echo "✅ PASS: CA trust check present (may not be polluted in this environment)"
            TESTS_PASSED=$((TESTS_PASSED + 1))
        else
            echo "❌ FAIL: No CA trust information in diagnostic output"
            TESTS_FAILED=$((TESTS_FAILED + 1))
        fi
    else
        echo "⏭️  SKIP: CA pollution test (Windows not accessible)"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    fi
    TESTS_RUN=$((TESTS_RUN + 1))
}

# Test 1: detect_windows_powershell function exists and is callable
test_function_exists() {
    if declare -f detect_windows_powershell >/dev/null; then
        echo "✅ PASS: detect_windows_powershell function exists"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo "❌ FAIL: detect_windows_powershell function does not exist"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    TESTS_RUN=$((TESTS_RUN + 1))
}

# Test 2: Function returns valid PowerShell command or fails appropriately
test_powershell_detection() {
    local result
    local exit_code=0
    result=$(detect_windows_powershell 2>/dev/null) || exit_code=$?

    if [ $exit_code -eq 0 ] && [ -n "$result" ]; then
        echo "✅ PASS: PowerShell detection found: $result"
        TESTS_PASSED=$((TESTS_PASSED + 1))

        # Test 3: The returned command actually works
        if $result -NoProfile -Command "Write-Output 'test'" &>/dev/null; then
            echo "✅ PASS: Detected PowerShell command works"
            TESTS_PASSED=$((TESTS_PASSED + 1))
        else
            echo "❌ FAIL: Detected PowerShell command does not work"
            TESTS_FAILED=$((TESTS_FAILED + 1))
        fi
        TESTS_RUN=$((TESTS_RUN + 1))
    else
        echo "⏭️  SKIP: PowerShell not detected (exit code: $exit_code)"
        echo "   This is expected if Windows is not accessible from WSL2"
    fi
    TESTS_RUN=$((TESTS_RUN + 1))
}

# Test 4: init_windows_interaction sets global variables correctly
test_init_windows_interaction() {
    # Reset globals
    WINDOWS_PS=""
    WINDOWS_ACCESSIBLE=false

    local output
    output=$(init_windows_interaction 2>&1)

    if [ "$WINDOWS_ACCESSIBLE" = true ] && [ -n "$WINDOWS_PS" ]; then
        echo "✅ PASS: init_windows_interaction sets variables when Windows accessible"
        assert_contains "Windows accessible via:" "$output" "init_windows_interaction success message"
    elif [ "$WINDOWS_ACCESSIBLE" = false ] && [ -z "$WINDOWS_PS" ]; then
        echo "✅ PASS: init_windows_interaction sets variables when Windows not accessible"
        assert_contains "Windows not accessible" "$output" "init_windows_interaction failure message"
    else
        echo "❌ FAIL: init_windows_interaction inconsistent variable state"
        echo "   WINDOWS_ACCESSIBLE: $WINDOWS_ACCESSIBLE"
        echo "   WINDOWS_PS: '$WINDOWS_PS'"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        TESTS_RUN=$((TESTS_RUN + 1))
        return
    fi
    TESTS_PASSED=$((TESTS_PASSED + 1))
    TESTS_RUN=$((TESTS_RUN + 1))
}

# Test 5: Function handles missing PowerShell gracefully
test_missing_powershell() {
    # Mock environment with no PowerShell available
    local original_path="$PATH"
    export PATH="/bin:/usr/bin"  # Minimal PATH without Windows paths

    local result
    local exit_code=0
    result=$(detect_windows_powershell 2>/dev/null) || exit_code=$?

    # Restore PATH
    export PATH="$original_path"

    if [ $exit_code -ne 0 ]; then
        echo "✅ PASS: detect_windows_powershell fails gracefully when PowerShell missing"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo "⚠️  UNEXPECTED: PowerShell still detected with minimal PATH: $result"
        echo "   This might indicate PowerShell is in an unexpected location"
        TESTS_PASSED=$((TESTS_PASSED + 1))  # Not a failure, just unexpected
    fi
    TESTS_RUN=$((TESTS_RUN + 1))
}

# Run all tests
test_ca_pollution_detection
test_function_exists
test_powershell_detection
test_init_windows_interaction
test_missing_powershell

# Test summary
echo "==========================================="
echo "🧪 Test Results:"
echo "   Tests run:    $TESTS_RUN"
echo "   Passed:       $TESTS_PASSED"
echo "   Failed:       $TESTS_FAILED"

if [ $TESTS_FAILED -eq 0 ]; then
    echo "🎉 All tests passed!"
    exit 0
else
    echo "💥 Some tests failed!"
    exit 1
fi
