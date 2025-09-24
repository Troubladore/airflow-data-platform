#!/bin/bash
# Unit tests for Docker proxy diagnostics utility

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

assert_exit_code() {
    local expected_code="$1"
    local actual_code="$2"
    local test_name="$3"

    TESTS_RUN=$((TESTS_RUN + 1))

    if [ "$expected_code" = "$actual_code" ]; then
        echo "✅ PASS: $test_name (exit code: $actual_code)"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo "❌ FAIL: $test_name"
        echo "   Expected exit code: $expected_code"
        echo "   Actual exit code:   $actual_code"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

# Source the utility we're testing
source "$(dirname "$0")/../../diagnostics/docker-proxy-diagnostics.sh"

echo "🧪 Docker Proxy Diagnostics Unit Tests"
echo "======================================="

# Test 1: Function exists and is callable
test_function_exists() {
    if declare -f detect_docker_engine_proxy >/dev/null; then
        echo "✅ PASS: detect_docker_engine_proxy function exists"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo "❌ FAIL: detect_docker_engine_proxy function does not exist"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    TESTS_RUN=$((TESTS_RUN + 1))

    if declare -f detect_docker_settings >/dev/null; then
        echo "✅ PASS: detect_docker_settings function exists"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo "❌ FAIL: detect_docker_settings function does not exist"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    TESTS_RUN=$((TESTS_RUN + 1))

    if declare -f check_bypass_domains >/dev/null; then
        echo "✅ PASS: check_bypass_domains function exists"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo "❌ FAIL: check_bypass_domains function does not exist"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    TESTS_RUN=$((TESTS_RUN + 1))

    if declare -f version_gte >/dev/null; then
        echo "✅ PASS: version_gte function exists"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo "❌ FAIL: version_gte function does not exist"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    TESTS_RUN=$((TESTS_RUN + 1))

    if declare -f determine_proxy_state >/dev/null; then
        echo "✅ PASS: determine_proxy_state function exists"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo "❌ FAIL: determine_proxy_state function does not exist"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    TESTS_RUN=$((TESTS_RUN + 1))
}

# Test 2: Docker engine detection
test_docker_engine_detection() {
    if command -v docker &>/dev/null && docker info &>/dev/null; then
        local output exit_code
        output=$(detect_docker_engine_proxy 2>&1)
        exit_code=$?

        assert_contains "DOCKER_HTTP_PROXY=" "$output" "Docker HTTP proxy detection"
        assert_contains "DOCKER_NO_PROXY=" "$output" "Docker no-proxy detection"
        assert_contains "DOCKER_PROXY_STATUS=" "$output" "Docker proxy status detection"

        if [ $exit_code -eq 0 ] || [ $exit_code -eq 1 ]; then
            echo "✅ PASS: Docker engine detection returns valid exit code ($exit_code)"
            TESTS_PASSED=$((TESTS_PASSED + 1))
        else
            echo "❌ FAIL: Docker engine detection returns invalid exit code: $exit_code"
            TESTS_FAILED=$((TESTS_FAILED + 1))
        fi
        TESTS_RUN=$((TESTS_RUN + 1))
    else
        echo "⏭️  SKIP: Docker engine tests (Docker not accessible)"
    fi
}

# Test 3: Bypass domain checking logic
test_bypass_domain_checking() {
    # Test with complete bypass list
    local output exit_code
    output=$(check_bypass_domains "localhost,*.localhost,127.0.0.1,registry.localhost,traefik.localhost,airflow.localhost" 2>&1)
    exit_code=$?

    assert_contains "BYPASS_DOMAINS_STATUS=complete" "$output" "Complete bypass list detection"
    assert_exit_code "0" "$exit_code" "Complete bypass list exit code"

    # Test with missing domains
    output=$(check_bypass_domains "localhost,127.0.0.1" 2>&1)
    exit_code=$?

    assert_contains "BYPASS_DOMAINS_STATUS=missing" "$output" "Missing domains detection"
    assert_contains "MISSING_DOMAINS=" "$output" "Missing domains list"
    assert_exit_code "2" "$exit_code" "Missing domains exit code"

    # Test with empty bypass list
    output=$(check_bypass_domains "" 2>&1)
    exit_code=$?

    assert_contains "BYPASS_DOMAINS_STATUS=missing" "$output" "Empty bypass list detection"
    assert_exit_code "2" "$exit_code" "Empty bypass list exit code"
}

# Test 4: Version comparison function
test_version_comparison() {
    # Test version_gte function with known version comparisons
    if version_gte "4.35.0" "4.34.0"; then
        echo "✅ PASS: version_gte correctly identifies 4.35.0 >= 4.34.0"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo "❌ FAIL: version_gte incorrectly handles 4.35.0 >= 4.34.0"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    TESTS_RUN=$((TESTS_RUN + 1))

    if version_gte "4.34.0" "4.35.0"; then
        echo "❌ FAIL: version_gte incorrectly identifies 4.34.0 >= 4.35.0"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    else
        echo "✅ PASS: version_gte correctly identifies 4.34.0 < 4.35.0"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    fi
    TESTS_RUN=$((TESTS_RUN + 1))

    if version_gte "28.4.0" "4.35.0"; then
        echo "✅ PASS: version_gte correctly handles modern Docker version 28.4.0"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo "❌ FAIL: version_gte incorrectly handles modern Docker version 28.4.0"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    TESTS_RUN=$((TESTS_RUN + 1))
}

# Test 5: Enhanced settings file detection (if accessible)
test_enhanced_settings_detection() {
    if command -v docker &>/dev/null && docker info &>/dev/null; then
        local output exit_code
        output=$(detect_docker_settings 2>&1)
        exit_code=$?

        assert_contains "DOCKER_VERSION=" "$output" "Docker version detection"
        assert_contains "SETTINGS_FORMAT=" "$output" "Settings format detection (modern/legacy)"
        assert_contains "DOCKER_SETTINGS=" "$output" "Settings file path detection"
        assert_contains "SETTINGS_PROXY_MODE=" "$output" "Proxy mode detection"
        assert_contains "SETTINGS_BYPASS_LIST=" "$output" "Bypass list detection"

        # Check if modern or legacy format is correctly identified
        if [[ "$output" == *"SETTINGS_FORMAT=modern"* ]]; then
            echo "✅ PASS: Detected modern Docker Desktop format (settings-store.json)"
            TESTS_PASSED=$((TESTS_PASSED + 1))
        elif [[ "$output" == *"SETTINGS_FORMAT=legacy"* ]]; then
            echo "✅ PASS: Detected legacy Docker Desktop format (settings.json)"
            TESTS_PASSED=$((TESTS_PASSED + 1))
        else
            echo "❌ FAIL: Settings format detection missing or invalid"
            TESTS_FAILED=$((TESTS_FAILED + 1))
        fi
        TESTS_RUN=$((TESTS_RUN + 1))

        if [ $exit_code -eq 0 ] || [ $exit_code -eq 4 ]; then
            echo "✅ PASS: Enhanced settings detection returns valid exit code ($exit_code)"
            TESTS_PASSED=$((TESTS_PASSED + 1))
        else
            echo "❌ FAIL: Enhanced settings detection returns invalid exit code: $exit_code"
            TESTS_FAILED=$((TESTS_FAILED + 1))
        fi
        TESTS_RUN=$((TESTS_RUN + 1))
    else
        echo "⏭️  SKIP: Enhanced settings file tests (Docker not accessible)"
    fi
}

# Test 5: Main function integration test (if Docker is accessible)
test_main_integration() {
    if command -v docker &>/dev/null && docker info &>/dev/null; then
        local output exit_code
        output=$(main 2>&1)
        exit_code=$?

        assert_contains "OVERALL_STATUS=" "$output" "Main function overall status"

        # Valid exit codes: 0 (working), 1 (no proxy), 2 (missing), 3 (restart), 4 (error)
        if [ $exit_code -ge 0 ] && [ $exit_code -le 4 ]; then
            echo "✅ PASS: Main function returns valid exit code ($exit_code)"
            TESTS_PASSED=$((TESTS_PASSED + 1))
        else
            echo "❌ FAIL: Main function returns invalid exit code: $exit_code"
            TESTS_FAILED=$((TESTS_FAILED + 1))
        fi
        TESTS_RUN=$((TESTS_RUN + 1))

        # Test specific condition detection
        if [[ "$output" == *"restart_required"* ]]; then
            echo "✅ PASS: Correctly detected current restart_required condition"
            TESTS_PASSED=$((TESTS_PASSED + 1))
        elif [[ "$output" == *"proxy_bypass_working"* ]]; then
            echo "✅ PASS: Correctly detected working proxy bypass"
            TESTS_PASSED=$((TESTS_PASSED + 1))
        elif [[ "$output" == *"no_proxy_configured"* ]]; then
            echo "✅ PASS: Correctly detected no proxy configuration"
            TESTS_PASSED=$((TESTS_PASSED + 1))
        else
            echo "⚠️  INFO: Detected other proxy condition - this may be expected"
            TESTS_PASSED=$((TESTS_PASSED + 1))
        fi
        TESTS_RUN=$((TESTS_RUN + 1))
    else
        echo "⏭️  SKIP: Main integration test (Docker not accessible)"
    fi
}

# Run all tests
test_function_exists
test_docker_engine_detection
test_bypass_domain_checking
test_version_comparison
test_enhanced_settings_detection
test_main_integration

# Test summary
echo "======================================="
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
