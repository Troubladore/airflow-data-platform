#!/bin/bash
# Test runner for Kerberos diagnostic tools
# Runs syntax checks, unit tests, and integration tests

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "==================================="
echo "Kerberos Diagnostics Test Suite"
echo "==================================="
echo ""

# Track overall status
ALL_PASSED=true

# Function to run a test section
run_test_section() {
    local name="$1"
    local command="$2"

    echo -n "Running $name... "

    if eval "$command" >/dev/null 2>&1; then
        echo -e "${GREEN}✓ PASSED${NC}"
        return 0
    else
        echo -e "${RED}✗ FAILED${NC}"
        ALL_PASSED=false
        return 1
    fi
}

# 1. Syntax checks
echo "1. SYNTAX VALIDATION"
echo "--------------------"

# Check all shell scripts for syntax errors
for script in "$PROJECT_ROOT"/*.sh "$PROJECT_ROOT"/lib/*.sh "$PROJECT_ROOT"/tests/*.sh; do
    if [[ -f "$script" ]]; then
        name=$(basename "$script")
        run_test_section "  $name" "bash -n '$script'"
    fi
done

echo ""

# 2. ShellCheck static analysis (if available)
echo "2. STATIC ANALYSIS"
echo "------------------"

if command -v shellcheck >/dev/null 2>&1; then
    for script in "$PROJECT_ROOT"/{test-sql-direct.sh,krb5-auth-test.sh,test-sql-container.sh} "$PROJECT_ROOT"/lib/*.sh; do
        if [[ -f "$script" ]]; then
            name=$(basename "$script")
            # Exclude some checks that are too strict
            # SC2034: Variable appears unused
            # SC2155: Declare and assign separately
            run_test_section "  $name" "shellcheck -e SC2034,SC2155 '$script'"
        fi
    done
else
    echo -e "${YELLOW}  ⚠ shellcheck not installed - skipping${NC}"
    echo "  Install with: apt-get install shellcheck"
fi

echo ""

# 3. Unit tests with BATS
echo "3. UNIT TESTS"
echo "-------------"

if command -v bats >/dev/null 2>&1; then
    # Run BATS tests
    run_test_section "  kerberos-diagnostics library" "bats '$PROJECT_ROOT/tests/test-kerberos-diagnostics.bats'"
else
    echo -e "${YELLOW}  ⚠ BATS not installed - skipping unit tests${NC}"
    echo "  Install BATS:"
    echo "    git clone https://github.com/bats-core/bats-core.git"
    echo "    cd bats-core && ./install.sh /usr/local"
fi

echo ""

# 4. Library loading test
echo "4. INTEGRATION TESTS"
echo "-------------------"

# Test that library can be sourced
TEMP_TEST=$(mktemp)
cat > "$TEMP_TEST" <<'EOF'
#!/bin/bash
source "$(dirname "$0")/../lib/kerberos-diagnostics.sh"
reset_diagnostics
detect_environment >/dev/null
[[ -n "${DIAG_RESULTS[environment]}" ]] || exit 1
EOF

chmod +x "$TEMP_TEST"
run_test_section "  Library loading" "$TEMP_TEST"
rm -f "$TEMP_TEST"

# Test that test-sql-direct.sh has valid syntax after fix
run_test_section "  test-sql-direct.sh syntax" "bash -n '$PROJECT_ROOT/test-sql-direct.sh'"

echo ""

# 5. Documentation tests
echo "5. DOCUMENTATION"
echo "----------------"

# Check that key files have documentation
check_file_has_content() {
    local file="$1"
    local pattern="$2"
    grep -q "$pattern" "$file"
}

if check_file_has_content "$PROJECT_ROOT/lib/kerberos-diagnostics.sh" "^# Kerberos Diagnostics Library"; then
    echo -e "  Library documentation ${GREEN}✓${NC}"
else
    echo -e "  Library documentation ${RED}✗${NC}"
    ALL_PASSED=false
fi

echo ""

# Summary
echo "==================================="
if [[ "$ALL_PASSED" == true ]]; then
    echo -e "${GREEN}ALL TESTS PASSED${NC}"
    exit 0
else
    echo -e "${RED}SOME TESTS FAILED${NC}"
    echo ""
    echo "To debug failures, run individual test commands:"
    echo "  bash -n <script>                    # Syntax check"
    echo "  shellcheck <script>                 # Static analysis"
    echo "  bats tests/test-kerberos-diagnostics.bats  # Unit tests"
    exit 1
fi
