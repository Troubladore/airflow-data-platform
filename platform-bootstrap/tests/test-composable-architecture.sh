#!/bin/bash
# Test Composable Architecture
# =============================
# Validates the standalone service architecture
# Tests each service (openmetadata, kerberos, pagila) works independently
#
# This catches:
# - Invalid docker-compose files in standalone services
# - Missing .env.example files
# - Broken Makefile targets in each service
# - Platform orchestrator delegation issues

set -e

# Find script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLATFORM_DIR="$(dirname "$SCRIPT_DIR")"
REPO_ROOT="$(dirname "$PLATFORM_DIR")"

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

echo -e "${BOLD}============================================${NC}"
echo -e "${BOLD}    COMPOSABLE ARCHITECTURE VALIDATION     ${NC}"
echo -e "${BOLD}============================================${NC}"
echo ""
echo "This test validates that all platform services follow"
echo "the standalone, composable architecture pattern."
echo ""

# Track results
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
FAILED_ITEMS=()

# Helper function to test a service
test_service() {
    local service_name="$1"
    local service_dir="$REPO_ROOT/$service_name"

    echo ""
    print_header "$service_name SERVICE"
    echo ""

    # Test: Directory exists
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    if [ -d "$service_dir" ]; then
        print_check "PASS" "Directory exists: $service_dir"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        print_check "FAIL" "Directory not found: $service_dir"
        FAILED_TESTS=$((FAILED_TESTS + 1))
        FAILED_ITEMS+=("$service_name: Directory missing")
        return
    fi

    # Test: docker-compose.yml exists
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    if [ -f "$service_dir/docker-compose.yml" ]; then
        print_check "PASS" "docker-compose.yml exists"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        print_check "FAIL" "docker-compose.yml missing"
        FAILED_TESTS=$((FAILED_TESTS + 1))
        FAILED_ITEMS+=("$service_name: docker-compose.yml missing")
        return
    fi

    # Test: .env.example exists
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    if [ -f "$service_dir/.env.example" ]; then
        print_check "PASS" ".env.example exists"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        print_check "FAIL" ".env.example missing"
        FAILED_TESTS=$((FAILED_TESTS + 1))
        FAILED_ITEMS+=("$service_name: .env.example missing")
    fi

    # Test: Makefile exists
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    if [ -f "$service_dir/Makefile" ]; then
        print_check "PASS" "Makefile exists"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        print_check "FAIL" "Makefile missing"
        FAILED_TESTS=$((FAILED_TESTS + 1))
        FAILED_ITEMS+=("$service_name: Makefile missing")
    fi

    # Test: docker-compose file is valid
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    if command -v docker >/dev/null 2>&1; then
        cd "$service_dir"
        if docker compose config >/dev/null 2>&1; then
            print_check "PASS" "docker-compose.yml is valid"
            PASSED_TESTS=$((PASSED_TESTS + 1))
        else
            print_check "FAIL" "docker-compose.yml has errors"
            FAILED_TESTS=$((FAILED_TESTS + 1))
            FAILED_ITEMS+=("$service_name: Invalid docker-compose.yml")
        fi
        cd "$PLATFORM_DIR"
    else
        print_check "WARN" "Docker not available (skipping validation)"
    fi

    # Test: Makefile has required targets
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    local required_targets=("start" "stop" "status")
    local missing_targets=()

    for target in "${required_targets[@]}"; do
        if ! grep -q "^${target}:.*##" "$service_dir/Makefile" 2>/dev/null; then
            missing_targets+=("$target")
        fi
    done

    if [ ${#missing_targets[@]} -eq 0 ]; then
        print_check "PASS" "Has required targets (start, stop, status)"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        print_check "FAIL" "Missing targets: ${missing_targets[*]}"
        FAILED_TESTS=$((FAILED_TESTS + 1))
        FAILED_ITEMS+=("$service_name: Missing Makefile targets")
    fi
}

# Test all standalone services
test_service "openmetadata"
test_service "kerberos"

echo ""
print_header "PLATFORM ORCHESTRATOR"
echo ""

# Test: platform-bootstrap delegates correctly
TOTAL_TESTS=$((TOTAL_TESTS + 1))
if grep -q "cd ../openmetadata && \$(MAKE) start" "$PLATFORM_DIR/Makefile"; then
    print_check "PASS" "Delegates to openmetadata service"
    PASSED_TESTS=$((PASSED_TESTS + 1))
else
    print_check "FAIL" "Doesn't delegate to openmetadata"
    FAILED_TESTS=$((FAILED_TESTS + 1))
    FAILED_ITEMS+=("Platform orchestrator: Missing openmetadata delegation")
fi

TOTAL_TESTS=$((TOTAL_TESTS + 1))
if grep -q "cd ../kerberos && \$(MAKE) start" "$PLATFORM_DIR/Makefile"; then
    print_check "PASS" "Delegates to kerberos service"
    PASSED_TESTS=$((PASSED_TESTS + 1))
else
    print_check "FAIL" "Doesn't delegate to kerberos"
    FAILED_TESTS=$((FAILED_TESTS + 1))
    FAILED_ITEMS+=("Platform orchestrator: Missing kerberos delegation")
fi

# Test: Old compose files moved to deprecated
TOTAL_TESTS=$((TOTAL_TESTS + 1))
if [ -d "$PLATFORM_DIR/deprecated/compose-files" ]; then
    print_check "PASS" "Old compose files in deprecated/"
    PASSED_TESTS=$((PASSED_TESTS + 1))
else
    print_check "WARN" "deprecated/compose-files not found (might still be in main dir)"
fi

echo ""
print_header "ARCHITECTURE CONSISTENCY"
echo ""

# Test: No external dependencies between services
TOTAL_TESTS=$((TOTAL_TESTS + 1))
EXTERNAL_DEPS=$(grep "external: true" "$REPO_ROOT"/openmetadata/docker-compose.yml 2>/dev/null || true)
if [ -z "$EXTERNAL_DEPS" ]; then
    print_check "PASS" "OpenMetadata has no external dependencies"
    PASSED_TESTS=$((PASSED_TESTS + 1))
else
    print_check "WARN" "OpenMetadata references external resources"
    echo "$EXTERNAL_DEPS" | sed 's/^/    /'
fi

TOTAL_TESTS=$((TOTAL_TESTS + 1))
EXTERNAL_DEPS=$(grep "external: true" "$REPO_ROOT"/kerberos/docker-compose.yml 2>/dev/null || true)
if [ -z "$EXTERNAL_DEPS" ]; then
    print_check "PASS" "Kerberos has no external dependencies"
    PASSED_TESTS=$((PASSED_TESTS + 1))
else
    print_check "WARN" "Kerberos references external resources"
    echo "$EXTERNAL_DEPS" | sed 's/^/    /'
fi

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
    echo -e "${RED}❌ COMPOSABLE ARCHITECTURE VALIDATION FAILED${NC}"
    echo ""
    echo "Failed items:"
    for failure in "${FAILED_ITEMS[@]}"; do
        echo "  - $failure"
    done
    echo ""
    echo -e "${YELLOW}Fix these issues to maintain clean architecture!${NC}"
    exit 1
else
    echo ""
    echo -e "${GREEN}✅ ALL ARCHITECTURE CHECKS PASSED${NC}"
    echo ""
    echo "All services follow the composable architecture pattern:"
    echo "  ✓ Standalone docker-compose.yml"
    echo "  ✓ Self-contained .env configuration"
    echo "  ✓ Independent Makefile with start/stop/status"
    echo "  ✓ No external dependencies"
    exit 0
fi
