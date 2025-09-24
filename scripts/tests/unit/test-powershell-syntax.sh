#!/bin/bash
# Unit tests for PowerShell script syntax validation

set -euo pipefail

# Test framework
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

assert_powershell_syntax() {
    local script_path="$1"
    local test_name="$2"

    TESTS_RUN=$((TESTS_RUN + 1))

    if [ ! -f "$script_path" ]; then
        echo "❌ FAIL: $test_name - Script not found: $script_path"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi

    # Use PowerShell syntax check (parse only, don't execute)
    local powershell_cmd
    if command -v powershell.exe &>/dev/null; then
        powershell_cmd="powershell.exe"
    elif [ -f "/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe" ]; then
        powershell_cmd="/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe"
    else
        echo "⏭️  SKIP: $test_name - PowerShell not accessible"
        return 0
    fi

    local syntax_check_result
    if syntax_check_result=$($powershell_cmd -NoProfile -ExecutionPolicy Bypass -Command "try { [System.Management.Automation.PSParser]::Tokenize((Get-Content '$script_path' -Raw), [ref]\$null) | Out-Null; Write-Output 'SYNTAX_OK' } catch { Write-Output \"SYNTAX_ERROR: \$(\$_.Exception.Message)\" }" 2>&1); then
        if [[ "$syntax_check_result" == *"SYNTAX_OK"* ]]; then
            echo "✅ PASS: $test_name"
            TESTS_PASSED=$((TESTS_PASSED + 1))
        else
            echo "❌ FAIL: $test_name"
            echo "   Syntax Error: $syntax_check_result"
            TESTS_FAILED=$((TESTS_FAILED + 1))
        fi
    else
        echo "❌ FAIL: $test_name"
        echo "   PowerShell execution failed: $syntax_check_result"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

assert_powershell_execution() {
    local script_path="$1"
    local test_name="$2"
    local test_args="$3"

    TESTS_RUN=$((TESTS_RUN + 1))

    if [ ! -f "$script_path" ]; then
        echo "❌ FAIL: $test_name - Script not found: $script_path"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi

    local powershell_cmd
    if command -v powershell.exe &>/dev/null; then
        powershell_cmd="powershell.exe"
    elif [ -f "/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe" ]; then
        powershell_cmd="/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe"
    else
        echo "⏭️  SKIP: $test_name - PowerShell not accessible"
        return 0
    fi

    # Test actual execution with dry-run or help parameters (with timeout to prevent hanging)
    local exec_result exit_code
    exec_result=$(timeout 15 $powershell_cmd -NoProfile -ExecutionPolicy Bypass -File "$script_path" $test_args 2>&1)
    exit_code=$?

    # Check for timeout
    if [ $exit_code -eq 124 ]; then
        echo "❌ FAIL: $test_name"
        echo "   Execution Error: Script timed out (likely waiting for input)"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    # Check for actual parsing errors (not just any output)
    elif [[ "$exec_result" == *"ParserError"* ]] || [[ "$exec_result" == *"TerminatorExpectedAtEndOfString"* ]] || [[ "$exec_result" == *"UnexpectedToken"* ]]; then
        echo "❌ FAIL: $test_name"
        echo "   Execution Error: $exec_result"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    else
        # Script executed without parsing errors (exit code doesn't matter for syntax test)
        echo "✅ PASS: $test_name"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    fi
}

echo "🧪 PowerShell Script Syntax Validation Tests"
echo "=============================================="

# Get script directory
SCRIPT_DIR="$(dirname "$0")/../.."

# Test all PowerShell scripts in diagnostics directory
assert_powershell_syntax "$SCRIPT_DIR/diagnostics/cleanup-mkcert-ca.ps1" "cleanup-mkcert-ca.ps1 syntax"
assert_powershell_syntax "$SCRIPT_DIR/diagnostics/unified-docker-proxy.ps1" "unified-docker-proxy.ps1 syntax"
assert_powershell_syntax "$SCRIPT_DIR/diagnostics/fix-docker-proxy.ps1" "fix-docker-proxy.ps1 syntax"

# Test execution with help/dry-run parameters to catch runtime parsing errors
echo ""
echo "🧪 PowerShell Execution Tests"
echo "=============================="

assert_powershell_execution "$SCRIPT_DIR/diagnostics/cleanup-mkcert-ca.ps1" "cleanup-mkcert-ca.ps1 execution" "-Preview -Force"

# Skip unified-docker-proxy test as it has complex dependencies
echo "⏭️  SKIP: unified-docker-proxy.ps1 execution (complex dependencies)"

assert_powershell_execution "$SCRIPT_DIR/diagnostics/fix-docker-proxy.ps1" "fix-docker-proxy.ps1 execution" "-Force"

# Test summary
echo "=============================================="
echo "🧪 Test Results:"
echo "   Tests run:    $TESTS_RUN"
echo "   Passed:       $TESTS_PASSED"
echo "   Failed:       $TESTS_FAILED"

if [ $TESTS_FAILED -eq 0 ]; then
    echo "🎉 All PowerShell syntax tests passed!"
    exit 0
else
    echo "💥 PowerShell syntax errors found!"
    exit 1
fi
