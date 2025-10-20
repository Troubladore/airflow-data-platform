#!/bin/bash
# Test Docker Compose File Validation
# =====================================
# Validates docker-compose files can be parsed without errors
# Prevents shipping invalid YAML that fails at runtime
#
# This catches:
# - YAML syntax errors
# - Invalid environment variable types (must be strings, not arrays)
# - Missing service dependencies
# - Invalid configuration values

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
echo -e "${BOLD}     DOCKER COMPOSE VALIDATION TEST        ${NC}"
echo -e "${BOLD}============================================${NC}"
echo ""
echo "This test validates docker-compose files can be parsed correctly"
echo "without starting any actual services."
echo ""

# Track results
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
FAILED_ITEMS=()

# Check if docker compose is available
if ! command -v docker >/dev/null 2>&1; then
    echo -e "${YELLOW}⚠ Docker not available - skipping validation${NC}"
    echo ""
    echo "Note: This test requires Docker to validate compose files."
    echo "Install Docker to run this test locally."
    exit 0
fi

# Helper function to validate a compose file
validate_compose_file() {
    local compose_file="$1"
    local description="$2"

    TOTAL_TESTS=$((TOTAL_TESTS + 1))

    echo -n "Validating $compose_file: $description... "

    # Use docker compose config to validate (doesn't start services)
    if docker compose -f "$compose_file" config >/dev/null 2>&1; then
        echo -e "${GREEN}PASS${NC}"
        PASSED_TESTS=$((PASSED_TESTS + 1))
        return 0
    else
        echo -e "${RED}FAIL${NC}"
        FAILED_TESTS=$((FAILED_TESTS + 1))
        FAILED_ITEMS+=("$compose_file: $description")
        # Show the error
        echo "  Error output:"
        docker compose -f "$compose_file" config 2>&1 | head -10 | sed 's/^/    /'
        return 1
    fi
}

# Helper function to validate multi-file compose setup
validate_compose_multi() {
    local description="$1"
    shift
    local files=("$@")

    TOTAL_TESTS=$((TOTAL_TESTS + 1))

    echo -n "Validating multi-file: $description... "

    # Build docker compose command with multiple -f flags
    local compose_cmd="docker compose"
    for file in "${files[@]}"; do
        compose_cmd="$compose_cmd -f $file"
    done

    # Use config to validate (doesn't start services)
    if eval "$compose_cmd config" >/dev/null 2>&1; then
        echo -e "${GREEN}PASS${NC}"
        PASSED_TESTS=$((PASSED_TESTS + 1))
        return 0
    else
        echo -e "${RED}FAIL${NC}"
        FAILED_TESTS=$((FAILED_TESTS + 1))
        FAILED_ITEMS+=("Multi-file: $description")
        # Show the error
        echo "  Error output:"
        eval "$compose_cmd config" 2>&1 | head -10 | sed 's/^/    /'
        return 1
    fi
}

print_header "INDIVIDUAL COMPOSE FILES"
echo ""

# Test each compose file individually
if [ -f "docker-compose.yml" ]; then
    validate_compose_file "docker-compose.yml" "Base Kerberos services"
fi

if [ -f "docker-compose.openmetadata.yml" ]; then
    validate_compose_file "docker-compose.openmetadata.yml" "OpenMetadata (no-Kerberos mode)"
fi

if [ -f "docker-compose.mock-services.yml" ]; then
    validate_compose_file "docker-compose.mock-services.yml" "Mock services"
fi

echo ""
print_header "MULTI-FILE COMPOSE CONFIGURATIONS"
echo ""

# Test multi-file setups (how they're actually used)
if [ -f "docker-compose.yml" ] && [ -f "docker-compose.openmetadata.yml" ]; then
    validate_compose_multi "Full platform (Kerberos + OpenMetadata)" \
        "docker-compose.yml" \
        "docker-compose.openmetadata.yml"
fi

echo ""
print_header "PROFILE-BASED CONFIGURATIONS"
echo ""

# Test different profile combinations (how users actually run it via .env)
echo "Testing OpenMetadata only (ENABLE_KERBEROS=false, ENABLE_OPENMETADATA=true)..."
TOTAL_TESTS=$((TOTAL_TESTS + 1))
if COMPOSE_PROFILES=openmetadata docker compose -f docker-compose.yml -f docker-compose.openmetadata.yml config >/dev/null 2>&1; then
    print_check "PASS" "OpenMetadata profile works standalone"
    PASSED_TESTS=$((PASSED_TESTS + 1))
else
    print_check "FAIL" "OpenMetadata profile fails"
    FAILED_TESTS=$((FAILED_TESTS + 1))
    FAILED_ITEMS+=("OpenMetadata profile configuration")
fi

# Note: Kerberos-only mode not tested - it's not a valid standalone configuration
# Kerberos is a supporting service that requires OpenMetadata or Airflow to be useful

echo "Testing Both (ENABLE_KERBEROS=true, ENABLE_OPENMETADATA=true)..."
TOTAL_TESTS=$((TOTAL_TESTS + 1))
if COMPOSE_PROFILES=kerberos,openmetadata docker compose -f docker-compose.yml -f docker-compose.openmetadata.yml config >/dev/null 2>&1; then
    print_check "PASS" "Both profiles work together"
    PASSED_TESTS=$((PASSED_TESTS + 1))
else
    print_check "FAIL" "Both profiles fail"
    FAILED_TESTS=$((FAILED_TESTS + 1))
    FAILED_ITEMS+=("Kerberos + OpenMetadata profile configuration")
fi

echo ""
print_header "ENVIRONMENT VARIABLE TYPE VALIDATION"
echo ""

# Check for common YAML type errors in environment sections
echo "Checking for array values in environment variables..."
TOTAL_TESTS=$((TOTAL_TESTS + 1))

# Look for patterns like "SOME_VAR: []" which should be "SOME_VAR: \"[]\""
ARRAY_VARS=$(grep -n "^\s*[A-Z_]\+:\s*\[\]" docker-compose*.yml 2>/dev/null || true)

if [ -z "$ARRAY_VARS" ]; then
    print_check "PASS" "No unquoted array values in environment variables"
    PASSED_TESTS=$((PASSED_TESTS + 1))
else
    print_check "FAIL" "Found unquoted array values (must be strings)"
    echo "$ARRAY_VARS" | sed 's/^/    /'
    FAILED_TESTS=$((FAILED_TESTS + 1))
    FAILED_ITEMS+=("Unquoted arrays in environment variables")
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
    echo -e "${RED}❌ DOCKER COMPOSE VALIDATION FAILED${NC}"
    echo ""
    echo "Failed items:"
    for failure in "${FAILED_ITEMS[@]}"; do
        echo "  - $failure"
    done
    echo ""
    echo -e "${YELLOW}These compose files will fail at runtime!${NC}"
    echo "Fix the YAML syntax and configuration before creating a PR."
    exit 1
else
    echo ""
    echo -e "${GREEN}✅ ALL DOCKER COMPOSE FILES VALID${NC}"
    echo ""
    echo "All compose files can be parsed and will work at runtime."
    exit 0
fi
