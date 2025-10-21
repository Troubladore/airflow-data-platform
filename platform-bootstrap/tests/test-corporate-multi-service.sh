#!/bin/bash
# Test Corporate Configuration for Multiple Services
# ====================================================
# Validates that corporate mode configures ALL services' Docker images
# Tests that missing properties trigger review of ALL settings

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
print_header "Corporate Multi-Service Configuration Tests"
echo ""

WIZARD_SCRIPT="$PLATFORM_DIR/setup-scripts/platform-setup-wizard.sh"

# ==========================================
# Test 1: Check all configuration functions exist
# ==========================================

print_info "Test 1: Configuration functions for all services"
echo ""

REQUIRED_FUNCTIONS=(
    "configure_infrastructure_env_interactive"
    "configure_infrastructure_env_prompts"
    "configure_openmetadata_env_interactive"
    "configure_openmetadata_env_prompts"
)

for func in "${REQUIRED_FUNCTIONS[@]}"; do
    if grep -q "^${func}()" "$WIZARD_SCRIPT"; then
        test_result "pass" "Function $func exists"
    else
        test_result "fail" "Function $func exists" "Missing function"
    fi
done

echo ""

# ==========================================
# Test 2: Infrastructure prompts for IMAGE_POSTGRES
# ==========================================

print_info "Test 2: Infrastructure image configuration"
echo ""

if grep -q "IMAGE_POSTGRES" "$WIZARD_SCRIPT"; then
    test_result "pass" "IMAGE_POSTGRES configured"
else
    test_result "fail" "IMAGE_POSTGRES configured" "Not found"
fi

echo ""

# ==========================================
# Test 3: OpenMetadata prompts for multiple images
# ==========================================

print_info "Test 3: OpenMetadata image configuration"
echo ""

OPENMETADATA_IMAGES=(
    "IMAGE_OPENMETADATA_SERVER"
    "IMAGE_ELASTICSEARCH"
)

for img in "${OPENMETADATA_IMAGES[@]}"; do
    if grep -q "$img" "$WIZARD_SCRIPT"; then
        test_result "pass" "$img configured"
    else
        test_result "fail" "$img configured" "Not found in wizard"
    fi
done

echo ""

# ==========================================
# Test 4: Corporate mode triggers configuration
# ==========================================

print_info "Test 4: Corporate mode integration"
echo ""

# Check setup_infrastructure calls configuration in corporate mode
if grep -A 15 "^setup_infrastructure()" "$WIZARD_SCRIPT" | grep -q "NEED_ARTIFACTORY.*true" && \
   grep -A 15 "^setup_infrastructure()" "$WIZARD_SCRIPT" | grep -q "configure_infrastructure_env_interactive"; then
    test_result "pass" "Infrastructure checks NEED_ARTIFACTORY"
else
    test_result "fail" "Infrastructure checks NEED_ARTIFACTORY" "Not found"
fi

# Check setup_openmetadata calls configuration in corporate mode
if grep -A 15 "^setup_openmetadata()" "$WIZARD_SCRIPT" | grep -q "NEED_ARTIFACTORY.*true" && \
   grep -A 15 "^setup_openmetadata()" "$WIZARD_SCRIPT" | grep -q "configure_openmetadata_env_interactive"; then
    test_result "pass" "OpenMetadata checks NEED_ARTIFACTORY"
else
    test_result "fail" "OpenMetadata checks NEED_ARTIFACTORY" "Not found"
fi

echo ""

# ==========================================
# Test 5: "Review ALL" behavior
# ==========================================

print_info "Test 5: Missing properties trigger full review"
echo ""

# Check that missing properties message mentions reviewing ALL
if grep -q "Since configuration is incomplete, let's review ALL settings" "$WIZARD_SCRIPT"; then
    test_result "pass" "Missing properties trigger ALL settings review"
else
    test_result "fail" "Missing properties trigger ALL settings review" "Message not found"
fi

# Check that prompt functions say "Configure ALL"
if grep -q "Configure ALL Docker image sources" "$WIZARD_SCRIPT"; then
    test_result "pass" "Prompts mention reviewing ALL properties"
else
    test_result "fail" "Prompts mention reviewing ALL properties" "Message not found"
fi

echo ""

# ==========================================
# Test 6: OpenMetadata docker-compose uses IMAGE variables
# ==========================================

print_info "Test 6: Docker Compose integration"
echo ""

OPENMETADATA_COMPOSE="$REPO_ROOT/openmetadata/docker-compose.yml"

if [ -f "$OPENMETADATA_COMPOSE" ]; then
    if grep -q '${IMAGE_OPENMETADATA_SERVER' "$OPENMETADATA_COMPOSE"; then
        test_result "pass" "OpenMetadata compose uses IMAGE_OPENMETADATA_SERVER"
    else
        test_result "fail" "OpenMetadata compose uses IMAGE_OPENMETADATA_SERVER" "Not found"
    fi

    if grep -q '${IMAGE_ELASTICSEARCH' "$OPENMETADATA_COMPOSE"; then
        test_result "pass" "OpenMetadata compose uses IMAGE_ELASTICSEARCH"
    else
        test_result "fail" "OpenMetadata compose uses IMAGE_ELASTICSEARCH" "Not found"
    fi
else
    test_result "fail" "OpenMetadata docker-compose.yml exists" "File not found"
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
    for failed in "${FAILED_TESTS[@]}"; do
        echo "  - $failed"
    done
    echo ""
    exit 1
else
    print_success "All corporate multi-service configuration tests passed!"
    echo ""
    echo "Validated:"
    echo "  ✓ Infrastructure and OpenMetadata configuration functions exist"
    echo "  ✓ IMAGE_POSTGRES configured for infrastructure"
    echo "  ✓ IMAGE_OPENMETADATA_SERVER and IMAGE_ELASTICSEARCH configured"
    echo "  ✓ Corporate mode triggers configuration for both services"
    echo "  ✓ Missing properties trigger review of ALL settings"
    echo "  ✓ Docker Compose files use IMAGE_ variables"
    echo ""
    exit 0
fi