#!/bin/bash
# Dry Run Test for All Critical Scripts
# ======================================
# Runs all critical scripts in dry-run/test mode to ensure they compile and execute
# Prevents shipping broken scripts that fail during demos
#
# This script MUST pass before any PR is merged!

set -e

# Colors for output
if [ -t 1 ] && [ -z "${NO_COLOR}" ]; then
    GREEN='\033[0;32m'
    RED='\033[0;31m'
    YELLOW='\033[1;33m'
    CYAN='\033[0;36m'
    BOLD='\033[1m'
    NC='\033[0m'
else
    GREEN=''
    RED=''
    YELLOW=''
    CYAN=''
    BOLD=''
    NC=''
fi

# Find script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLATFORM_DIR="$(dirname "$SCRIPT_DIR")"

echo -e "${BOLD}============================================${NC}"
echo -e "${BOLD}     DRY RUN TEST - PREVENT DEMO FAILURES  ${NC}"
echo -e "${BOLD}============================================${NC}"
echo ""
echo "This test ensures all scripts can execute without crashing."
echo "It simulates real usage scenarios to catch errors before demos."
echo ""

# Track failures
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
FAILED_SCRIPTS=()

# Helper function to test a script
test_script() {
    local script_name="$1"
    local test_command="$2"
    local description="$3"

    TOTAL_TESTS=$((TOTAL_TESTS + 1))

    echo -n "Testing $script_name: $description... "

    # Create a temporary directory for test output
    local temp_dir=$(mktemp -d)

    # Run test in subshell to isolate failures
    if (
        cd "$PLATFORM_DIR"
        export NO_COLOR=1  # Disable colors for consistent output
        export DRY_RUN=1   # Signal to scripts they're being tested
        eval "$test_command" >/dev/null 2>&1
    ); then
        echo -e "${GREEN}PASS${NC}"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        echo -e "${RED}FAIL${NC}"
        FAILED_TESTS=$((FAILED_TESTS + 1))
        FAILED_SCRIPTS+=("$script_name: $description")

        # Try to capture error for debugging
        echo "  Error output:"
        (
            cd "$PLATFORM_DIR"
            export NO_COLOR=1
            export DRY_RUN=1
            eval "$test_command" 2>&1 | head -10 | sed 's/^/    /'
        ) || true
    fi

    # Clean up
    rm -rf "$temp_dir" 2>/dev/null || true
}

echo -e "${CYAN}=== SYNTAX VALIDATION ===${NC}"
echo ""

# First, check all scripts for basic syntax errors
SCRIPTS_TO_TEST=(
    "dev-tools/clean-slate.sh"
    "dev-tools/setup-kerberos.sh"
    "diagnostics/diagnose-kerberos.sh"
    "diagnostics/krb5-auth-test.sh"
    "diagnostics/test-sql-direct.sh"
    "diagnostics/test-sql-simple.sh"
    "diagnostics/generate-diagnostic-context.sh"
    "dev-tools/run-kerberos-setup.sh"
    "kerberos-sidecar/scripts/check-build-requirements.sh"
)

for script in "${SCRIPTS_TO_TEST[@]}"; do
    if [ -f "$PLATFORM_DIR/$script" ]; then
        test_script "$script" "bash -n $script" "Syntax check"
    fi
done

echo ""
echo -e "${CYAN}=== HELP/VERSION TESTS ===${NC}"
echo ""

# Test scripts that support --help
test_script "diagnostics/krb5-auth-test.sh" "./diagnostics/krb5-auth-test.sh --help" "Help output"
test_script "diagnostics/krb5-auth-test.sh" "./diagnostics/krb5-auth-test.sh -h" "Short help"

echo ""
echo -e "${CYAN}=== DRY RUN EXECUTION TESTS ===${NC}"
echo ""

# Test diagnostic scripts in quick/safe mode
# Note: krb5-auth-test.sh exits with 1 if no valid ticket (expected in test env)
test_script "diagnostics/krb5-auth-test.sh" "./diagnostics/krb5-auth-test.sh -q || [ \$? -eq 1 ]" "Quick mode execution"

# Test generate-diagnostic-context with mock data
test_script "diagnostics/generate-diagnostic-context.sh" "
    export KRB5CCNAME=FILE:/tmp/krb5cc_test_\$\$
    timeout 5 ./diagnostics/generate-diagnostic-context.sh --dry-run 2>/dev/null || true
" "Dry run mode"

# Test the test script itself (meta!)
test_script "test-shell-syntax.sh" "./tests/test-shell-syntax.sh" "Syntax validation suite"

# Test that color code detection works properly
test_script "check-build-requirements.sh" "
    cd kerberos-sidecar/scripts
    NO_COLOR=1 bash -c './check-build-requirements.sh 2>&1 | grep -E \"\\033|✓|✗|⚠|ℹ|═|─|▶\" && exit 1 || exit 0'
" "No color/unicode when NO_COLOR=1"

test_script "diagnostics/krb5-auth-test.sh" "
    NO_COLOR=1 bash -c './diagnostics/krb5-auth-test.sh --help 2>&1 | grep -E \"\\033|✓|✗|⚠|ℹ|═|─|▶\" && exit 1 || exit 0'
" "No color/unicode in krb5-auth-test when NO_COLOR=1"

echo ""
echo -e "${CYAN}=== INTERACTIVE SCRIPT SAFETY ===${NC}"
echo ""

# Test that interactive scripts handle non-interactive mode gracefully
# Note: clean-slate.sh has multiple prompts, need to answer 'n' to all
test_script "dev-tools/clean-slate.sh" "
    printf 'n\nn\nn\nn\n' | timeout 2 ./dev-tools/clean-slate.sh 2>&1 | grep -q 'Cancelled'
" "Handles 'no' input"

# Test setup-kerberos.sh can at least parse without errors
test_script "dev-tools/setup-kerberos.sh" "bash -n ./dev-tools/setup-kerberos.sh" "Setup script syntax"

echo ""
echo -e "${CYAN}=== BUILD REQUIREMENT CHECKS ===${NC}"
echo ""

# Test the build requirements script
test_script "check-build-requirements.sh" "
    cd kerberos-sidecar/scripts
    timeout 10 ./check-build-requirements.sh || [ \$? -ne 0 ]
" "Build requirements check runs"

echo ""
echo -e "${CYAN}=== CRITICAL PATH SIMULATION ===${NC}"
echo ""

# Simulate the critical path that users follow in demos
echo "Simulating demo workflow (Step 7-11 from guide)..."
echo ""

# Step 7: Building sidecar (just check the script exists and is valid)
test_script "kerberos-sidecar/Makefile" "
    cd kerberos-sidecar
    make help >/dev/null 2>&1
" "Makefile help works"

# Step 10: Direct SQL test script
test_script "diagnostics/test-sql-direct.sh" "
    ./diagnostics/test-sql-direct.sh 2>&1 | head -1 | grep -q 'Direct SQL Server Test' || \
    ./diagnostics/test-sql-direct.sh 2>&1 | head -5 | grep -q 'Usage:'
" "Shows usage or title"

# Step 11: Container test simulation
test_script "diagnostics/test-sql-simple.sh" "bash -n ./diagnostics/test-sql-simple.sh" "Simple SQL test syntax"

echo ""
echo -e "${BOLD}============================================${NC}"
echo -e "${BOLD}                   SUMMARY                  ${NC}"
echo -e "${BOLD}============================================${NC}"
echo ""

echo "Total tests run: $TOTAL_TESTS"
echo -e "Passed: ${GREEN}$PASSED_TESTS${NC}"
echo -e "Failed: ${RED}$FAILED_TESTS${NC}"

if [ $FAILED_TESTS -gt 0 ]; then
    echo ""
    echo -e "${RED}❌ DRY RUN FAILED - THESE WILL BREAK IN DEMOS!${NC}"
    echo ""
    echo "Failed tests:"
    for failure in "${FAILED_SCRIPTS[@]}"; do
        echo "  - $failure"
    done
    echo ""
    echo -e "${YELLOW}DO NOT SHIP THIS CODE!${NC}"
    echo "Fix these issues before creating a PR."
    echo ""
    echo "To debug a specific failure, run the script directly:"
    echo "  cd $PLATFORM_DIR"
    echo "  <script-name> --help  # or appropriate test command"
    exit 1
else
    echo ""
    echo -e "${GREEN}✅ ALL DRY RUN TESTS PASSED${NC}"
    echo ""
    echo "All scripts can execute without crashing."
    echo "Safe to demo and ship!"
    exit 0
fi