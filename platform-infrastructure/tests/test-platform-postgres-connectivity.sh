#!/bin/bash
# Test platform-postgres connectivity from postgres-test container
# Purpose: Verify core infrastructure database is accessible and functional

set -e

# Find repo root and source formatting library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
source "$REPO_ROOT/platform-bootstrap/lib/formatting.sh"

# Parse arguments
QUIET_MODE=false
if [[ "$1" == "--quiet" ]]; then
    QUIET_MODE=true
fi

print_header "Platform PostgreSQL Connectivity Test"

# Check prerequisites
print_section "Prerequisites"

TESTS_PASSED=0
TESTS_TOTAL=0

# Arrays to track test results
declare -a TEST_NAMES
declare -a TEST_STATUSES  # PASS, FAIL, or WARN
declare -a TEST_MESSAGES
TEST_INDEX=0

# Allow configurable timeout (default 60 seconds)
POSTGRES_WAIT_TIMEOUT=${POSTGRES_WAIT_TIMEOUT:-60}

# Function to record test results
record_test() {
    local name="$1"
    local status="$2"  # PASS, FAIL, or WARN
    local message="${3:-}"

    TEST_NAMES[$TEST_INDEX]="$name"
    TEST_STATUSES[$TEST_INDEX]="$status"
    TEST_MESSAGES[$TEST_INDEX]="$message"
    TEST_INDEX=$((TEST_INDEX + 1))

    TESTS_TOTAL=$((TESTS_TOTAL + 1))
    if [ "$status" = "PASS" ] || [ "$status" = "WARN" ]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
    fi
}

check_prerequisite() {
    local name="$1"
    local command="$2"

    if eval "$command" >/dev/null 2>&1; then
        print_check "PASS" "$name"
        record_test "$name" "PASS"
        return 0
    else
        print_check "FAIL" "$name"
        record_test "$name" "FAIL" "$name failed"
        return 1
    fi
}

# Test 1: Verify postgres-test container exists and is running
if ! check_prerequisite "Test 1: postgres-test container running" "docker ps --filter 'name=postgres-test' --filter 'status=running' --format '{{.Names}}' | grep -q '^postgres-test$'"; then
    print_error "Test 1 FAILED: postgres-test container not found or not running"
    print_info "Create test containers with: ./platform setup"
    exit 1
fi

# Test 2: Verify platform-postgres container exists and is running
if ! check_prerequisite "Test 2: platform-postgres container running" "docker ps --filter 'name=platform-postgres' --filter 'status=running' --format '{{.Names}}' | grep -q '^platform-postgres$'"; then
    print_error "Test 2 FAILED: platform-postgres container not found or not running"
    print_info "Start platform infrastructure with: make -C platform-infrastructure start"
    exit 1
fi

# Test 3: PostgreSQL readiness (with proper fallback for containers without health checks)
print_info "Test 3: Checking PostgreSQL readiness..."

# Check if container has health check defined
HEALTH_STATUS=$(docker inspect platform-postgres --format='{{if .State.Health}}{{.State.Health.Status}}{{else}}no-health-check{{end}}' 2>/dev/null || echo "error")

if [ "$HEALTH_STATUS" = "no-health-check" ]; then
    # No health check defined, use pg_isready directly
    if docker exec platform-postgres pg_isready >/dev/null 2>&1; then
        print_check "PASS" "Test 3: PostgreSQL is ready (pg_isready)"
        record_test "Test 3: PostgreSQL readiness" "PASS"
    else
        print_check "FAIL" "Test 3: PostgreSQL not ready"
        record_test "Test 3: PostgreSQL readiness" "FAIL" "PostgreSQL service not responding to pg_isready"
        print_error "PostgreSQL service not responding to pg_isready"
        exit 1
    fi
elif [ "$HEALTH_STATUS" = "healthy" ]; then
    print_check "PASS" "Test 3: PostgreSQL is healthy"
    record_test "Test 3: PostgreSQL readiness" "PASS"
elif [ "$HEALTH_STATUS" = "unhealthy" ]; then
    print_check "FAIL" "Test 3: PostgreSQL is unhealthy"
    record_test "Test 3: PostgreSQL readiness" "FAIL" "PostgreSQL container health check failed"
    print_error "Check logs: docker logs platform-postgres"
    exit 1
else
    # Starting or unknown state, wait for it
    print_info "Waiting for PostgreSQL to be ready (timeout: ${POSTGRES_WAIT_TIMEOUT}s)..."
    WAIT_SECONDS=0
    MAX_WAIT=$POSTGRES_WAIT_TIMEOUT
    while [ $WAIT_SECONDS -lt $MAX_WAIT ]; do
        HEALTH_STATUS=$(docker inspect platform-postgres --format='{{if .State.Health}}{{.State.Health.Status}}{{else}}no-health-check{{end}}' 2>/dev/null)

        if [ "$HEALTH_STATUS" = "healthy" ] || [ "$HEALTH_STATUS" = "no-health-check" ]; then
            if docker exec platform-postgres pg_isready >/dev/null 2>&1; then
                print_check "PASS" "Test 3: PostgreSQL is ready"
                record_test "Test 3: PostgreSQL readiness" "PASS"
                break
            fi
        elif [ "$HEALTH_STATUS" = "unhealthy" ]; then
            print_check "FAIL" "Test 3: PostgreSQL is unhealthy"
            record_test "Test 3: PostgreSQL readiness" "FAIL" "PostgreSQL container health check failed"
            print_error "Check logs: docker logs platform-postgres"
            exit 1
        fi

        if [ $((WAIT_SECONDS % 10)) -eq 0 ] && [ $WAIT_SECONDS -gt 0 ]; then
            REMAINING=$((MAX_WAIT - WAIT_SECONDS))
            print_info "Still waiting for PostgreSQL... (${REMAINING}s remaining)"
        fi

        sleep 1
        WAIT_SECONDS=$((WAIT_SECONDS + 1))
    done

    if [ $WAIT_SECONDS -ge $MAX_WAIT ]; then
        print_check "FAIL" "Test 3: PostgreSQL did not become ready in $MAX_WAIT seconds"
        record_test "Test 3: PostgreSQL readiness" "FAIL" "PostgreSQL did not become ready within timeout"
        print_info "Check logs: docker logs platform-postgres"
        exit 1
    fi
fi

# Test 4: Verify both containers on platform_network
if ! check_prerequisite "Test 4: Containers on platform_network" "docker network inspect platform_network -f '{{range .Containers}}{{.Name}} {{end}}' | grep -q 'postgres-test' && docker network inspect platform_network -f '{{range .Containers}}{{.Name}} {{end}}' | grep -q 'platform-postgres'"; then
    print_error "Test 4 FAILED: Containers not on same network"
    print_info "Connect with: docker network connect platform_network postgres-test"
    exit 1
fi

# Detect authentication configuration
print_section "Authentication Configuration"

ENV_FILE="$REPO_ROOT/platform-bootstrap/.env"
POSTGRES_PASSWORD=""

if [ -f "$ENV_FILE" ]; then
    # Read password from .env file
    POSTGRES_PASSWORD=$(grep '^POSTGRES_PASSWORD=' "$ENV_FILE" | cut -d'=' -f2- | tr -d '"' | tr -d "'")

    if [ -n "$POSTGRES_PASSWORD" ]; then
        print_info "Using password authentication (from platform-bootstrap/.env)"
    else
        print_warning "POSTGRES_PASSWORD empty in .env - using trust authentication"
    fi
else
    print_warning "No .env file found - using trust authentication"
fi

# Export for psql commands
export PGPASSWORD="$POSTGRES_PASSWORD"

# Run connectivity tests
print_section "Connectivity Tests"

run_test() {
    local test_name="$1"
    local test_command="$2"
    local success_pattern="${3:-}"

    TESTS_TOTAL=$((TESTS_TOTAL + 1))

    if [ "$QUIET_MODE" = false ]; then
        print_info "Running: $test_name"
    fi

    local output
    if output=$(eval "$test_command" 2>&1); then
        if [ -z "$success_pattern" ] || echo "$output" | grep -q "$success_pattern"; then
            print_check "PASS" "$test_name"
            TESTS_PASSED=$((TESTS_PASSED + 1))
            return 0
        fi
    fi

    print_check "FAIL" "$test_name"
    if [ "$QUIET_MODE" = false ]; then
        print_error "Error: $output"
    fi
    return 1
}

# Determine which user to use (try platform_admin first, fall back to postgres)
POSTGRES_USER="platform_admin"
if ! docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" postgres-test psql -h platform-postgres -U platform_admin -d postgres -c 'SELECT 1' -t -A >/dev/null 2>&1; then
    # platform_admin doesn't exist, try postgres user
    if docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" postgres-test psql -h platform-postgres -U postgres -d postgres -c 'SELECT 1' -t -A >/dev/null 2>&1; then
        POSTGRES_USER="postgres"
        print_info "Using 'postgres' user (platform_admin not found)"
    fi
else
    print_info "Using 'platform_admin' user"
fi

# Test 5: Database authentication (the actual goal)
if ! run_test "Test 5: Database authentication" "docker exec -e PGPASSWORD=\"$POSTGRES_PASSWORD\" postgres-test psql -h platform-postgres -U $POSTGRES_USER -d postgres -c 'SELECT 1' -t -A" "^1$"; then
    print_error "Test 5 FAILED: Authentication failed"

    # Only if the main test fails, run diagnostics
    print_section "Diagnostic Information"

    # Test network connectivity (may not work in all containers)
    if docker exec postgres-test which ping >/dev/null 2>&1; then
        if run_test "Network connectivity (ping)" "docker exec postgres-test ping -c 1 -W 2 platform-postgres" >/dev/null 2>&1; then
            print_check "PASS" "Network connectivity (ping)"
        else
            print_check "FAIL" "Network connectivity (ping)"
            print_error "Cannot reach platform-postgres from postgres-test"
        fi
    else
        print_info "Ping not available in container, skipping network test"
    fi

    # Test PostgreSQL service ready
    if ! run_test "PostgreSQL service ready" "docker exec postgres-test pg_isready -h platform-postgres -q"; then
        print_error "PostgreSQL service not accepting connections"
    fi

    # Try to get more diagnostic info
    print_info "Attempting to get PostgreSQL error details:"
    docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" postgres-test psql -h platform-postgres -U $POSTGRES_USER -d postgres -c 'SELECT 1' 2>&1 | head -5

    exit 1
fi

# Test 6: PostgreSQL service ready (quick check after successful auth)
if ! run_test "Test 6: PostgreSQL service ready" "docker exec postgres-test pg_isready -h platform-postgres -q"; then
    print_warning "Test 6: pg_isready check failed despite successful authentication"
fi

# Test 7: Query database list
DB_LIST=$(docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" postgres-test psql -h platform-postgres -U $POSTGRES_USER -d postgres -t -A -c "SELECT datname FROM pg_database WHERE datname IN ('airflow_db', 'openmetadata_db') ORDER BY datname")
# Only count non-empty lines
if [ -n "$DB_LIST" ]; then
    DB_COUNT=$(echo "$DB_LIST" | grep -c '^')
else
    DB_COUNT=0
fi

if [ "$DB_COUNT" -gt 0 ]; then
    print_check "PASS" "Test 7: Platform databases exist ($DB_COUNT found)"
    TESTS_PASSED=$((TESTS_PASSED + 1))
    if [ "$QUIET_MODE" = false ]; then
        echo "$DB_LIST" | while read -r db; do
            print_bullet "$db"
        done
    fi
else
    # This is a WARNING, not a failure - count it as passed
    print_check "WARN" "Test 7: No platform databases found yet"
    print_info "Databases will be created on first use by services"
    TESTS_PASSED=$((TESTS_PASSED + 1))  # Count warning as passed
fi
TESTS_TOTAL=$((TESTS_TOTAL + 1))

# Test 8: Query PostgreSQL version
PG_VERSION=$(docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" postgres-test psql -h platform-postgres -U $POSTGRES_USER -d postgres -t -A -c "SELECT version()" | head -n1 | cut -d' ' -f2)
print_check "PASS" "Test 8: PostgreSQL version: $PG_VERSION"
TESTS_PASSED=$((TESTS_PASSED + 1))
TESTS_TOTAL=$((TESTS_TOTAL + 1))

# Store test results for summary
declare -a TEST_RESULTS
declare -a TEST_NAMES
TEST_INDEX=0

# Add function to track test results
track_test() {
    local status="$1"
    local name="$2"
    TEST_NAMES[$TEST_INDEX]="$name"
    TEST_RESULTS[$TEST_INDEX]="$status"
    TEST_INDEX=$((TEST_INDEX + 1))
}

# Summary
print_divider
echo ""

if [ "$QUIET_MODE" = true ]; then
    # Brief output for wizard integration - now with enumerated test results
    if [ $TESTS_PASSED -eq $TESTS_TOTAL ]; then
        echo "✓ Platform postgres healthy - All $TESTS_TOTAL tests passed"
        echo "  Tests: 1.postgres-test ✓ 2.platform-postgres ✓ 3.pg-ready ✓ 4.network ✓ 5.auth ✓ 6.service ✓ 7.databases ✓ 8.version ✓"
        exit 0
    else
        # Build enumerated test summary showing which tests failed
        TEST_SUMMARY="  Tests:"
        TEST_DETAIL=""
        FAILED_TESTS=""

        # Test 1: postgres-test container
        TEST_SUMMARY="$TEST_SUMMARY 1.postgres-test"
        if docker ps --filter 'name=postgres-test' --filter 'status=running' --format '{{.Names}}' | grep -q '^postgres-test$'; then
            TEST_SUMMARY="$TEST_SUMMARY ✓"
        else
            TEST_SUMMARY="$TEST_SUMMARY ✗"
            FAILED_TESTS="$FAILED_TESTS\n  ✗ Test 1: postgres-test container not running"
        fi

        # Test 2: platform-postgres container
        TEST_SUMMARY="$TEST_SUMMARY 2.platform-postgres"
        if docker ps --filter 'name=platform-postgres' --filter 'status=running' --format '{{.Names}}' | grep -q '^platform-postgres$'; then
            TEST_SUMMARY="$TEST_SUMMARY ✓"
        else
            TEST_SUMMARY="$TEST_SUMMARY ✗"
            FAILED_TESTS="$FAILED_TESTS\n  ✗ Test 2: platform-postgres container not running"
        fi

        # Test 3: PostgreSQL readiness
        TEST_SUMMARY="$TEST_SUMMARY 3.pg-ready"
        if docker exec platform-postgres pg_isready >/dev/null 2>&1; then
            TEST_SUMMARY="$TEST_SUMMARY ✓"
        else
            TEST_SUMMARY="$TEST_SUMMARY ✗"
            FAILED_TESTS="$FAILED_TESTS\n  ✗ Test 3: PostgreSQL not ready"
        fi

        # Test 4: Network connectivity
        TEST_SUMMARY="$TEST_SUMMARY 4.network"
        if docker network inspect platform_network -f '{{range .Containers}}{{.Name}} {{end}}' 2>/dev/null | grep -q 'postgres-test' && docker network inspect platform_network -f '{{range .Containers}}{{.Name}} {{end}}' 2>/dev/null | grep -q 'platform-postgres'; then
            TEST_SUMMARY="$TEST_SUMMARY ✓"
        else
            TEST_SUMMARY="$TEST_SUMMARY ✗"
            FAILED_TESTS="$FAILED_TESTS\n  ✗ Test 4: Containers not on platform_network"
        fi

        # Test 5: Database authentication
        TEST_SUMMARY="$TEST_SUMMARY 5.auth"
        if docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" postgres-test psql -h platform-postgres -U $POSTGRES_USER -d postgres -c 'SELECT 1' -t -A >/dev/null 2>&1; then
            TEST_SUMMARY="$TEST_SUMMARY ✓"
        else
            TEST_SUMMARY="$TEST_SUMMARY ✗"
            FAILED_TESTS="$FAILED_TESTS\n  ✗ Test 5: Database authentication failed"
        fi

        # Test 6: PostgreSQL service test
        TEST_SUMMARY="$TEST_SUMMARY 6.service"
        if docker exec postgres-test pg_isready -h platform-postgres -q 2>/dev/null; then
            TEST_SUMMARY="$TEST_SUMMARY ✓"
        else
            TEST_SUMMARY="$TEST_SUMMARY ✗"
            FAILED_TESTS="$FAILED_TESTS\n  ✗ Test 6: PostgreSQL service not ready"
        fi

        # Test 7: Database existence
        TEST_SUMMARY="$TEST_SUMMARY 7.databases"
        if [ "$DB_COUNT" -gt 0 ]; then
            TEST_SUMMARY="$TEST_SUMMARY ✓"
        else
            TEST_SUMMARY="$TEST_SUMMARY ⚠"
            FAILED_TESTS="$FAILED_TESTS\n  ⚠ Test 7: No platform databases found (will be created on first use)"
        fi

        # Test 8: Version check (always passes if we get this far)
        TEST_SUMMARY="$TEST_SUMMARY 8.version ✓"

        echo "✗ Platform postgres unhealthy - $TESTS_PASSED/$TESTS_TOTAL tests passed"
        echo "$TEST_SUMMARY"
        if [ -n "$FAILED_TESTS" ]; then
            echo -e "$FAILED_TESTS"
        fi
        exit 1
    fi
else
    # Detailed output
    if [ $TESTS_PASSED -eq $TESTS_TOTAL ]; then
        print_success "All tests passed! ($TESTS_PASSED/$TESTS_TOTAL)"
        exit 0
    else
        print_error "Some tests failed! ($TESTS_PASSED/$TESTS_TOTAL passed)"
        exit 1
    fi
fi
