#!/bin/bash
# Test Makefile Targets
# =====================
# Validates that all Makefile targets can execute without errors
# Prevents shipping broken make commands that fail embarrassingly
#
# This catches:
# - Wrong script paths (like we just fixed)
# - Missing scripts
# - Syntax errors in Makefile
# - Circular dependencies
# - Missing prerequisites

set -e

# Find script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLATFORM_DIR="$(dirname "$SCRIPT_DIR")"

# Source formatting library
if [ -f "$PLATFORM_DIR/lib/formatting.sh" ]; then
    source "$PLATFORM_DIR/lib/formatting.sh"
else
    # Fallback formatting
    GREEN='\033[0;32m'
    RED='\033[0;31m'
    YELLOW='\033[1;33m'
    CYAN='\033[0;36m'
    BOLD='\033[1m'
    NC='\033[0m'
    print_header() { echo -e "${BOLD}=== $1 ===${NC}"; }
    print_check() {
        local status=$1
        local message=$2
        case $status in
            PASS) echo -e "${GREEN}✓${NC} $message" ;;
            FAIL) echo -e "${RED}✗${NC} $message" ;;
            WARN) echo -e "${YELLOW}⚠${NC} $message" ;;
            INFO) echo -e "${CYAN}ℹ${NC} $message" ;;
        esac
    }
fi

cd "$PLATFORM_DIR"

echo -e "${BOLD}============================================${NC}"
echo -e "${BOLD}        MAKEFILE TARGET VALIDATION          ${NC}"
echo -e "${BOLD}============================================${NC}"
echo ""
echo "This test ensures all Makefile targets are properly configured"
echo "and reference correct script paths."
echo ""

# Track results
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
FAILED_TARGETS=()

# Helper function to test a make target
test_make_target() {
    local target="$1"
    local test_type="$2"  # "dry-run" or "help-only" or "check-script"
    local description="$3"

    TOTAL_TESTS=$((TOTAL_TESTS + 1))

    echo -n "Testing 'make $target': $description... "

    case "$test_type" in
        dry-run)
            # Use make -n to do a dry run (shows commands without executing)
            if make -n "$target" >/dev/null 2>&1; then
                echo -e "${GREEN}PASS${NC}"
                PASSED_TESTS=$((PASSED_TESTS + 1))
            else
                echo -e "${RED}FAIL${NC}"
                FAILED_TESTS=$((FAILED_TESTS + 1))
                FAILED_TARGETS+=("$target: $description")
                # Show the error
                echo "  Error output:"
                make -n "$target" 2>&1 | head -5 | sed 's/^/    /'
            fi
            ;;

        check-script)
            # Check if the script referenced by the target exists
            local script_path=$(make -n "$target" 2>/dev/null | grep -oE '\./[^ ]+\.sh' | head -1)
            if [ -n "$script_path" ]; then
                if [ -f "$script_path" ]; then
                    echo -e "${GREEN}PASS${NC} (script exists: $script_path)"
                    PASSED_TESTS=$((PASSED_TESTS + 1))
                else
                    echo -e "${RED}FAIL${NC} (script not found: $script_path)"
                    FAILED_TESTS=$((FAILED_TESTS + 1))
                    FAILED_TARGETS+=("$target: Missing script $script_path")
                fi
            else
                # No script path found, might be a docker command
                if make -n "$target" 2>&1 | grep -q "docker\|echo\|@\["; then
                    echo -e "${GREEN}PASS${NC} (docker/builtin command)"
                    PASSED_TESTS=$((PASSED_TESTS + 1))
                else
                    echo -e "${YELLOW}WARN${NC} (no script to check)"
                fi
            fi
            ;;

        help-only)
            # Just check if target exists in Makefile
            if make -n "$target" 2>&1 | grep -q "No rule to make target"; then
                echo -e "${RED}FAIL${NC} (target not found)"
                FAILED_TESTS=$((FAILED_TESTS + 1))
                FAILED_TARGETS+=("$target: Target not defined in Makefile")
            else
                echo -e "${GREEN}PASS${NC}"
                PASSED_TESTS=$((PASSED_TESTS + 1))
            fi
            ;;
    esac
}

print_header "CORE TARGETS"
echo ""

# Test essential targets that should always work
test_make_target "help" "help-only" "Show help message"
test_make_target "platform-status" "dry-run" "Check platform status"

echo ""
print_header "SETUP & CONFIGURATION TARGETS"
echo ""

test_make_target "kerberos-setup" "check-script" "Run setup wizard"
test_make_target "kerberos-diagnose" "dry-run" "Run diagnostics"

echo ""
print_header "SERVICE MANAGEMENT TARGETS"
echo ""

test_make_target "platform-start" "dry-run" "Start platform services"
test_make_target "platform-stop" "dry-run" "Stop platform services"
test_make_target "kerberos-start" "dry-run" "Start Kerberos service"
test_make_target "kerberos-stop" "dry-run" "Stop Kerberos service"
test_make_target "kerberos-test" "dry-run" "Test Kerberos ticket"
test_make_target "mock-start" "dry-run" "Start mock services"
test_make_target "mock-stop" "dry-run" "Stop mock services"

echo ""
print_header "TESTING TARGETS"
echo ""

test_make_target "test-kerberos-simple" "dry-run" "Simple Kerberos test"
test_make_target "test-kerberos-full" "check-script" "Full Kerberos test"
test_make_target "test-connection" "check-script" "Test SQL connection"

echo ""
print_header "CLEANUP TARGETS"
echo ""

test_make_target "clean" "check-script" "Clean platform (non-interactive)"
test_make_target "clean-slate" "check-script" "Clean platform (interactive)"
test_make_target "reset" "dry-run" "Reset everything"

echo ""
print_header "DEVELOPER WORKFLOW TARGETS"
echo ""

test_make_target "dev-start" "dry-run" "Developer startup"
test_make_target "dev-stop" "dry-run" "Developer shutdown"
test_make_target "debug-logs" "dry-run" "Show service logs"

echo ""
print_header "TROUBLESHOOTING TARGETS"
echo ""

test_make_target "doctor" "check-script" "Run diagnostics"
test_make_target "fix-permissions" "dry-run" "Fix permissions"
test_make_target "fix-network" "dry-run" "Fix Docker networks"

echo ""
print_header "SCRIPT PATH VALIDATION"
echo ""

# Extract all script references from Makefile and verify they exist
echo "Checking all script references in Makefile..."
# Extract script paths, handle both ./ (local) and ../ (external service) paths
# Also handle "cd dir && ./script.sh" patterns
SCRIPT_REFS=$(grep -v '^\s*#' "$PLATFORM_DIR/Makefile" | grep -oE '@?(\./|\.\./)[a-zA-Z0-9/_-]+\.sh' | sort -u | sed 's/@//')

REPO_ROOT="$(dirname "$PLATFORM_DIR")"

for script in $SCRIPT_REFS; do
    # Check relative to platform-bootstrap for ./ paths
    # Check relative to repo root for ../ paths
    if [[ "$script" == ../* ]]; then
        script_abs="$REPO_ROOT/${script#../}"
    else
        # For ./diagnostics/... patterns after "cd ../kerberos &&", check in kerberos
        # Extract the Makefile line containing this script to see if there's a cd command
        script_line=$(grep -F "$script" "$PLATFORM_DIR/Makefile" | head -1)
        if echo "$script_line" | grep -q "cd \.\./kerberos"; then
            # Script is relative to kerberos directory
            script_abs="$REPO_ROOT/kerberos/${script#./}"
        else
            # Script is relative to platform-bootstrap
            script_abs="$PLATFORM_DIR/$script"
        fi
    fi

    if [ -f "$script_abs" ]; then
        print_check "PASS" "$script exists"
    else
        print_check "FAIL" "$script NOT FOUND (expected: $script_abs)"
        FAILED_TESTS=$((FAILED_TESTS + 1))
        FAILED_TARGETS+=("Script not found: $script")
    fi
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
done

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
    echo -e "${RED}❌ MAKEFILE VALIDATION FAILED${NC}"
    echo ""
    echo "Failed targets:"
    for failure in "${FAILED_TARGETS[@]}"; do
        echo "  - $failure"
    done
    echo ""
    echo -e "${YELLOW}These make commands will fail if shipped!${NC}"
    echo "Fix the Makefile or missing scripts before creating a PR."
    exit 1
else
    echo ""
    echo -e "${GREEN}✅ ALL MAKEFILE TARGETS VALID${NC}"
    echo ""
    echo "All make commands reference correct scripts and can execute."
    exit 0
fi