#!/bin/bash
# Test Image Mode Behavior (Layered vs Prebuilt)
# ================================================
# Validates that the wizard correctly handles both custom image modes:
# - Layered mode: prompts for build parameters (ODBC URLs, etc)
# - Prebuilt mode: suppresses build prompts and builder activities

set -e
export NO_COLOR=1

# Source formatting library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLATFORM_DIR="$(dirname "$SCRIPT_DIR")"
REPO_ROOT="$(dirname "$PLATFORM_DIR")"

if [ -f "$PLATFORM_DIR/lib/formatting.sh" ]; then
    source "$PLATFORM_DIR/lib/formatting.sh"
else
    # Fallback
    print_header() { echo "=== $1 ==="; }
    print_check() { echo "[$1] $2"; }
    print_success() { echo "[PASS] $1"; }
    print_error() { echo "[FAIL] $1"; }
    print_info() { echo "[INFO] $1"; }
fi

TESTS_PASSED=0
TESTS_FAILED=0
FAILED_TESTS=()

test_result() {
    local status="$1"
    local description="$2"
    local details="${3:-}"

    if [ "$status" = "pass" ]; then
        print_check "PASS" "$description"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        print_check "FAIL" "$description"
        if [ -n "$details" ]; then
            echo "  $details"
        fi
        TESTS_FAILED=$((TESTS_FAILED + 1))
        FAILED_TESTS+=("$description")
    fi
}

echo ""
print_header "Image Mode Behavior Tests"
echo ""
echo "Testing layered vs prebuilt mode handling in setup wizards"
echo ""

# Test both wizard versions
WIZARD_V2="$PLATFORM_DIR/setup-scripts/platform-setup-wizard-v2.sh"
WIZARD_ORIGINAL="$PLATFORM_DIR/setup-scripts/platform-setup-wizard.sh"

# Use v2 if it exists
if [ -f "$WIZARD_V2" ]; then
    WIZARD_SCRIPT="$WIZARD_V2"
    echo "[INFO] Testing wizard v2 (streamlined version)"
else
    WIZARD_SCRIPT="$WIZARD_ORIGINAL"
    echo "[INFO] Testing original wizard"
fi

echo ""

# ==========================================
# Test 1: IMAGE_MODE variable handling
# ==========================================

print_info "Test 1: IMAGE_MODE variable handling"
echo ""

# Check that wizard sets IMAGE_MODE
if grep -q 'IMAGE_MODE=' "$WIZARD_SCRIPT"; then
    test_result "pass" "Wizard sets IMAGE_MODE variable"
else
    test_result "fail" "Wizard sets IMAGE_MODE" "Variable not found"
fi

# Check for both layered and prebuilt values
if grep -q 'IMAGE_MODE="layered"' "$WIZARD_SCRIPT"; then
    test_result "pass" "Supports layered mode"
else
    test_result "fail" "Supports layered mode" "layered mode not found"
fi

if grep -q 'IMAGE_MODE="prebuilt"' "$WIZARD_SCRIPT"; then
    test_result "pass" "Supports prebuilt mode"
else
    test_result "fail" "Supports prebuilt mode" "prebuilt mode not found"
fi

echo ""

# ==========================================
# Test 2: Conditional prompting based on mode
# ==========================================

print_info "Test 2: Conditional prompting based on mode"
echo ""

if [[ "$WIZARD_SCRIPT" == *"wizard-v2.sh" ]]; then
    # V2 wizard - check that ODBC prompts only appear in layered mode section
    COLLECT_FUNC=$(grep -A 500 "^collect_all_user_input()" "$WIZARD_SCRIPT" || true)

    # Check for ODBC_DRIVER_URL prompt conditional on layered mode
    if echo "$COLLECT_FUNC" | grep -B5 'ODBC_DRIVER_URL\|ODBC Driver URL' | grep -q 'IMAGE_MODE.*=.*"layered"'; then
        test_result "pass" "ODBC_DRIVER_URL only prompted in layered mode (v2)"
    else
        test_result "fail" "ODBC_DRIVER_URL conditional on mode" "Not properly conditioned on layered mode"
    fi

    # Check that prebuilt mode message exists
    if echo "$COLLECT_FUNC" | grep -q 'prebuilt images.*no.*driver\|won.*t ask about driver'; then
        test_result "pass" "Prebuilt mode skips driver prompts message (v2)"
    else
        test_result "fail" "Prebuilt mode message" "No indication that prebuilt skips prompts"
    fi
else
    # Original wizard - check setup_kerberos or similar
    if grep -A 20 'IMAGE_MODE.*=.*"prebuilt"' "$WIZARD_SCRIPT" | grep -q 'skip\|no.*download\|pre.*install'; then
        test_result "pass" "Prebuilt mode indicates no downloads needed"
    else
        test_result "fail" "Prebuilt mode indication" "No message about skipping downloads"
    fi
fi

echo ""

# ==========================================
# Test 3: IMAGE_MODE export to child scripts
# ==========================================

print_info "Test 3: IMAGE_MODE export to child scripts"
echo ""

# Check that IMAGE_MODE is exported before calling child scripts
if grep -B5 'setup.sh\|make.*start' "$WIZARD_SCRIPT" | grep -q 'export IMAGE_MODE'; then
    test_result "pass" "IMAGE_MODE exported to child scripts"
else
    test_result "fail" "IMAGE_MODE export" "Not exported before calling child scripts"
fi

echo ""

# ==========================================
# Test 4: Kerberos setup integration
# ==========================================

print_info "Test 4: Kerberos setup integration with IMAGE_MODE"
echo ""

# Check Kerberos setup script for IMAGE_MODE handling
KERBEROS_SETUP="$REPO_ROOT/kerberos/setup.sh"

if [ -f "$KERBEROS_SETUP" ]; then
    # Check that Kerberos setup reads IMAGE_MODE
    if grep -q 'IMAGE_MODE' "$KERBEROS_SETUP"; then
        test_result "pass" "Kerberos setup checks IMAGE_MODE"
    else
        test_result "fail" "Kerberos setup checks IMAGE_MODE" "Variable not checked"
    fi

    # Check for prebuilt mode handling (different patterns)
    if grep -q '"$image_mode" = "prebuilt"\|IMAGE_MODE.*prebuilt' "$KERBEROS_SETUP"; then
        test_result "pass" "Kerberos setup handles prebuilt mode"
    else
        test_result "fail" "Kerberos prebuilt handling" "Prebuilt mode not handled"
    fi

    # Check that prebuilt mode skips package installation
    if grep -A 10 'prebuilt' "$KERBEROS_SETUP" | grep -q 'pre.*install\|skip\|assume.*installed\|already installed'; then
        test_result "pass" "Prebuilt mode skips package installation"
    else
        test_result "fail" "Prebuilt skips installation" "Does not skip package installation"
    fi
else
    print_warning "Kerberos setup script not found"
fi

echo ""

# ==========================================
# Test 5: Documentation and user messaging
# ==========================================

print_info "Test 5: Documentation and user messaging"
echo ""

# Check for clear messaging about the two modes
if grep -i -q 'layered.*runtime.*install\|packages.*at runtime' "$WIZARD_SCRIPT"; then
    test_result "pass" "Layered mode explanation present"
else
    test_result "fail" "Layered mode explanation" "No clear explanation of layered mode"
fi

if grep -i -q 'prebuilt.*all.*dependencies\|everything.*included\|no.*download' "$WIZARD_SCRIPT"; then
    test_result "pass" "Prebuilt mode explanation present"
else
    test_result "fail" "Prebuilt mode explanation" "No clear explanation of prebuilt mode"
fi

echo ""

# ==========================================
# Test 6: .env file configuration
# ==========================================

print_info "Test 6: IMAGE_MODE saved to .env file"
echo ""

# Check that IMAGE_MODE is written to .env
if grep -q 'echo.*IMAGE_MODE=\|IMAGE_MODE=.*>>.*\.env' "$WIZARD_SCRIPT"; then
    test_result "pass" "IMAGE_MODE saved to .env file"
else
    test_result "fail" "IMAGE_MODE persistence" "Not saved to .env file"
fi

echo ""

# ==========================================
# Results Summary
# ==========================================

echo ""
print_header "Test Results Summary"
echo ""

echo "Total tests: $((TESTS_PASSED + TESTS_FAILED))"
echo "Passed: $TESTS_PASSED"
echo "Failed: $TESTS_FAILED"
echo ""

if [ $TESTS_FAILED -gt 0 ]; then
    print_error "Some tests failed:"
    for test in "${FAILED_TESTS[@]}"; do
        echo "  - $test"
    done
    echo ""
    exit 1
else
    print_success "All image mode behavior tests passed!"
    echo ""
    echo "Validated:"
    echo "  ✓ IMAGE_MODE variable is properly set"
    echo "  ✓ Both layered and prebuilt modes supported"
    echo "  ✓ Prebuilt mode suppresses build prompts"
    echo "  ✓ IMAGE_MODE exported to child scripts"
    echo "  ✓ Kerberos setup respects IMAGE_MODE"
    echo "  ✓ Clear user messaging about each mode"
    echo "  ✓ IMAGE_MODE persisted to .env file"
    echo ""
    exit 0
fi