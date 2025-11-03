#!/bin/bash
# Test pagila-postgres connectivity from postgres-test container
# Purpose: Verify Pagila sample database is accessible and contains expected data

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

# Only show header in verbose mode
if [ "$QUIET_MODE" = false ]; then
    print_header "Pagila Database Connectivity Test"
    print_section "Prerequisites"
fi

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
        [ "$QUIET_MODE" = false ] && print_check "PASS" "$name"
        record_test "$name" "PASS"
        return 0
    else
        # Always show failures
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

# Test 2: Verify pagila-postgres container exists and is running
if ! check_prerequisite "Test 2: pagila-postgres container running" "docker ps --filter 'name=pagila-postgres' --filter 'status=running' --format '{{.Names}}' | grep -q '^pagila-postgres$'"; then
    print_error "pagila-postgres container not found or not running"
    print_info "Install Pagila with: ./platform setup pagila"
    exit 1
fi

# Test 3: Wait for Pagila PostgreSQL to be healthy (not just container running)
[ "$QUIET_MODE" = false ] && print_info "Test 3: Checking Pagila PostgreSQL readiness..."
WAIT_SECONDS=0
MAX_WAIT=$POSTGRES_WAIT_TIMEOUT
# Check Docker health status if available
HEALTH_STATUS=$(docker inspect pagila-postgres --format='{{if .State.Health}}{{.State.Health.Status}}{{else}}no-health-check{{end}}' 2>/dev/null || echo "error")

if [ "$HEALTH_STATUS" = "no-health-check" ]; then
    # No health check defined, use pg_isready directly
    if docker exec pagila-postgres pg_isready >/dev/null 2>&1; then
        print_check "PASS" "Test 3: Pagila PostgreSQL is ready (pg_isready)"
        record_test "Test 3: Pagila PostgreSQL readiness" "PASS"
    else
        print_check "FAIL" "Test 3: Pagila PostgreSQL not ready"
        record_test "Test 3: Pagila PostgreSQL readiness" "FAIL" "PostgreSQL service not responding"
        print_error "PostgreSQL service not responding to pg_isready"
        exit 1
    fi
elif [ "$HEALTH_STATUS" = "healthy" ]; then
    print_check "PASS" "Test 3: Pagila PostgreSQL is healthy"
    record_test "Test 3: Pagila PostgreSQL readiness" "PASS"
elif [ "$HEALTH_STATUS" = "unhealthy" ]; then
    print_check "FAIL" "Test 3: Pagila PostgreSQL is unhealthy"
    record_test "Test 3: Pagila PostgreSQL readiness" "FAIL" "Container health check failed"
    print_error "Check logs: docker logs pagila-postgres"
    exit 1
else
    # Starting or unknown state, wait for it
    if [ "$QUIET_MODE" = true ]; then
        echo "Waiting for Pagila PostgreSQL (timeout: ${POSTGRES_WAIT_TIMEOUT}s)..."
    else
        print_info "Waiting for Pagila PostgreSQL to be ready (timeout: ${POSTGRES_WAIT_TIMEOUT}s)..."
    fi
    while [ $WAIT_SECONDS -lt $MAX_WAIT ]; do
        HEALTH_STATUS=$(docker inspect pagila-postgres --format='{{if .State.Health}}{{.State.Health.Status}}{{else}}no-health-check{{end}}' 2>/dev/null)

        if [ "$HEALTH_STATUS" = "healthy" ] || [ "$HEALTH_STATUS" = "no-health-check" ]; then
            if docker exec pagila-postgres pg_isready >/dev/null 2>&1; then
                print_check "PASS" "Test 3: Pagila PostgreSQL is ready"
                record_test "Test 3: Pagila PostgreSQL readiness" "PASS"
                break
            fi
        elif [ "$HEALTH_STATUS" = "unhealthy" ]; then
            print_check "FAIL" "Test 3: Pagila PostgreSQL is unhealthy"
            record_test "Test 3: Pagila PostgreSQL readiness" "FAIL" "Container health check failed"
            print_error "Check logs: docker logs pagila-postgres"
            exit 1
        fi

        # Show countdown
        if [ $((WAIT_SECONDS % 10)) -eq 0 ] && [ $WAIT_SECONDS -gt 0 ]; then
            REMAINING=$((MAX_WAIT - WAIT_SECONDS))
            if [ "$QUIET_MODE" = true ]; then
                echo "Waiting... (${REMAINING}s remaining)"
            else
                print_info "Still waiting for Pagila PostgreSQL... (${REMAINING}s remaining)"
            fi
        fi

        sleep 1
        WAIT_SECONDS=$((WAIT_SECONDS + 1))
    done

    if [ $WAIT_SECONDS -ge $MAX_WAIT ]; then
        print_check "FAIL" "Test 3: Pagila PostgreSQL did not become ready in $MAX_WAIT seconds"
        record_test "Test 3: Pagila PostgreSQL readiness" "FAIL" "Timeout waiting for PostgreSQL"
        print_info "Check logs: docker logs pagila-postgres"
        exit 1
    fi
fi

# Verify both containers on platform_network
if ! check_prerequisite "Containers on platform_network" "docker network inspect platform_network -f '{{range .Containers}}{{.Name}} {{end}}' | grep -q 'postgres-test' && docker network inspect platform_network -f '{{range .Containers}}{{.Name}} {{end}}' | grep -q 'pagila-postgres'"; then
    print_error "Containers not on same network"
    print_info "Connect with: docker network connect platform_network postgres-test"
    exit 1
fi

# Detect authentication configuration for Pagila
print_section "Authentication Configuration"

PAGILA_DIR="$REPO_ROOT/../pagila"
POSTGRES_PASSWORD=""

if [ -d "$PAGILA_DIR" ] && [ -f "$PAGILA_DIR/.env" ]; then
    # Read password from Pagila's .env file
    POSTGRES_PASSWORD=$(grep '^POSTGRES_PASSWORD=' "$PAGILA_DIR/.env" | cut -d'=' -f2- | tr -d '"' | tr -d "'")

    if [ -n "$POSTGRES_PASSWORD" ]; then
        print_info "Using password authentication (from ../pagila/.env)"
    else
        print_info "Using trust authentication (POSTGRES_PASSWORD empty in ../pagila/.env)"
    fi
else
    print_info "Using trust authentication (no ../pagila/.env file found)"
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

# Test 1: Database authentication (the actual goal)
if ! run_test "Database authentication" "docker exec -e PGPASSWORD=\"$POSTGRES_PASSWORD\" postgres-test psql -h pagila-postgres -U postgres -d pagila -c 'SELECT 1' -t -A" "^1$"; then
    print_error "Authentication failed"

    # Only if the main test fails, run diagnostics
    print_section "Diagnostic Information"

    # Test network connectivity (may not work in all containers)
    if docker exec postgres-test which ping >/dev/null 2>&1; then
        if run_test "Network connectivity (ping)" "docker exec postgres-test ping -c 1 -W 2 pagila-postgres" >/dev/null 2>&1; then
            print_check "PASS" "Network connectivity (ping)"
        else
            print_check "FAIL" "Network connectivity (ping)"
            print_error "Cannot reach pagila-postgres from postgres-test"
        fi
    else
        print_info "Ping not available in container, skipping network test"
    fi

    # Test PostgreSQL service ready
    if ! run_test "PostgreSQL service ready" "docker exec postgres-test pg_isready -h pagila-postgres -U postgres -q"; then
        print_error "PostgreSQL service not accepting connections"
    fi

    # Try to get more diagnostic info
    print_info "Attempting to get PostgreSQL error details:"
    docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" postgres-test psql -h pagila-postgres -U postgres -d pagila -c 'SELECT 1' 2>&1 | head -5

    exit 1
fi

# Test 2: PostgreSQL service ready (quick check after successful auth)
if ! run_test "PostgreSQL service ready" "docker exec postgres-test pg_isready -h pagila-postgres -U postgres -q"; then
    print_warning "pg_isready check failed despite successful authentication"
fi

# Data validation tests
print_section "Data Validation"

# Test 4: Actor table
ACTOR_COUNT=$(docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" postgres-test psql -h pagila-postgres -U postgres -d pagila -t -A -c "SELECT COUNT(*) FROM actor")
TESTS_TOTAL=$((TESTS_TOTAL + 1))

if [ "$ACTOR_COUNT" = "200" ]; then
    print_check "PASS" "Actor table: $ACTOR_COUNT rows (expected)"
    TESTS_PASSED=$((TESTS_PASSED + 1))
elif [ "$ACTOR_COUNT" -gt 0 ]; then
    print_check "WARN" "Actor table: $ACTOR_COUNT rows (expected 200)"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    print_check "FAIL" "Actor table: empty or missing"
fi

# Test 5: Film table
FILM_COUNT=$(docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" postgres-test psql -h pagila-postgres -U postgres -d pagila -t -A -c "SELECT COUNT(*) FROM film")
TESTS_TOTAL=$((TESTS_TOTAL + 1))

if [ "$FILM_COUNT" = "1000" ]; then
    print_check "PASS" "Film table: $FILM_COUNT rows (expected)"
    TESTS_PASSED=$((TESTS_PASSED + 1))
elif [ "$FILM_COUNT" -gt 0 ]; then
    print_check "WARN" "Film table: $FILM_COUNT rows (expected 1000)"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    print_check "FAIL" "Film table: empty or missing"
fi

# Test 6: Rental table
RENTAL_COUNT=$(docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" postgres-test psql -h pagila-postgres -U postgres -d pagila -t -A -c "SELECT COUNT(*) FROM rental")
TESTS_TOTAL=$((TESTS_TOTAL + 1))

if [ "$RENTAL_COUNT" -gt 0 ]; then
    print_check "PASS" "Rental table: $RENTAL_COUNT rows"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    print_check "FAIL" "Rental table: empty or missing"
fi

# Test 7: Schema check (list tables)
if [ "$QUIET_MODE" = false ]; then
    print_section "Database Schema"
    TABLE_LIST=$(docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" postgres-test psql -h pagila-postgres -U postgres -d pagila -t -A -c "SELECT tablename FROM pg_tables WHERE schemaname = 'public' ORDER BY tablename")
    TABLE_COUNT=$(echo "$TABLE_LIST" | grep -c '^')

    print_info "Found $TABLE_COUNT tables:"
    echo "$TABLE_LIST" | while read -r table; do
        print_bullet "$table"
    done
fi

# Summary
print_divider
echo ""

if [ "$QUIET_MODE" = true ]; then
    # Brief output for wizard integration
    if [ $TESTS_PASSED -eq $TESTS_TOTAL ]; then
        echo "✓ Pagila healthy - $ACTOR_COUNT actors, $FILM_COUNT films, $RENTAL_COUNT rentals"
        exit 0
    else
        echo "✗ Pagila unhealthy - $TESTS_PASSED/$TESTS_TOTAL tests passed"
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
