#!/bin/bash
# Unit tests for Docker diagnostic components

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

# Source the component we're testing
source "$(dirname "$0")/../../diagnostics/docker-state.sh"

echo "🧪 Docker Diagnostics Unit Tests"
echo "================================="

# Test 1: Docker CLI detection when Docker is available
test_docker_cli_available() {
    if command -v docker &>/dev/null; then
        local output=$(detect_docker_cli)
        assert_contains "DOCKER_CLI=available" "$output" "Docker CLI detection when available"
    else
        echo "⏭️  SKIP: Docker CLI test (Docker not installed)"
    fi
}

# Test 2: Docker CLI detection when Docker is not available
test_docker_cli_missing() {
    # Mock the docker command to simulate it being missing
    local original_path="$PATH"
    export PATH="/nonexistent"

    local output=$(detect_docker_cli 2>&1 || true)
    assert_contains "DOCKER_CLI=missing" "$output" "Docker CLI detection when missing"

    # Restore PATH
    export PATH="$original_path"
}

# Test 3: Docker daemon detection when running
test_docker_daemon_running() {
    if docker info &>/dev/null; then
        local output=$(detect_docker_daemon)
        assert_contains "DOCKER_DAEMON=running" "$output" "Docker daemon detection when running"
    else
        echo "⏭️  SKIP: Docker daemon running test (Docker daemon not accessible)"
    fi
}

# Test 4: Docker proxy detection
test_docker_proxy_detection() {
    if docker info &>/dev/null; then
        local output=$(detect_docker_proxy)

        # Should contain either DOCKER_PROXY=none or DOCKER_PROXY=http://...
        if [[ "$output" == *"DOCKER_PROXY=none"* ]] || [[ "$output" == *"DOCKER_PROXY=http"* ]]; then
            echo "✅ PASS: Docker proxy detection returns valid proxy info"
            TESTS_PASSED=$((TESTS_PASSED + 1))
        else
            echo "❌ FAIL: Docker proxy detection returns invalid format"
            echo "   Output: '$output'"
            TESTS_FAILED=$((TESTS_FAILED + 1))
        fi
        TESTS_RUN=$((TESTS_RUN + 1))
    else
        echo "⏭️  SKIP: Docker proxy test (Docker daemon not accessible)"
    fi
}

# Test 5: Main function returns proper exit codes
test_main_function_exit_codes() {
    if command -v docker &>/dev/null && docker info &>/dev/null; then
        # Docker is working, should return 0 or 3 (proxy issue)
        local exit_code=0
        main &>/dev/null || exit_code=$?

        if [ $exit_code -eq 0 ] || [ $exit_code -eq 3 ]; then
            echo "✅ PASS: Main function returns appropriate exit code ($exit_code)"
            TESTS_PASSED=$((TESTS_PASSED + 1))
        else
            echo "❌ FAIL: Main function returns unexpected exit code: $exit_code"
            TESTS_FAILED=$((TESTS_FAILED + 1))
        fi
        TESTS_RUN=$((TESTS_RUN + 1))
    else
        echo "⏭️  SKIP: Main function exit code test (Docker not fully available)"
    fi
}

# Run all tests
test_docker_cli_available
test_docker_cli_missing
test_docker_daemon_running
test_docker_proxy_detection
test_main_function_exit_codes

# Test summary
echo "================================="
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
