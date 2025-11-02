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

print_header "Pagila Database Connectivity Test"

# Check prerequisites
print_section "Prerequisites"

TESTS_PASSED=0
TESTS_TOTAL=0

check_prerequisite() {
    local name="$1"
    local command="$2"

    TESTS_TOTAL=$((TESTS_TOTAL + 1))

    if eval "$command" >/dev/null 2>&1; then
        print_check "PASS" "$name"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        print_check "FAIL" "$name"
        return 1
    fi
}

# Verify postgres-test container exists and is running
if ! check_prerequisite "postgres-test container running" "docker ps --filter 'name=postgres-test' --filter 'status=running' --format '{{.Names}}' | grep -q '^postgres-test$'"; then
    print_error "postgres-test container not found or not running"
    print_info "Create test containers with: ./platform setup"
    exit 1
fi

# Verify pagila-postgres container exists and is running
if ! check_prerequisite "pagila-postgres container running" "docker ps --filter 'name=pagila-postgres' --filter 'status=running' --format '{{.Names}}' | grep -q '^pagila-postgres$'"; then
    print_error "pagila-postgres container not found or not running"
    print_info "Install Pagila with: ./platform setup pagila"
    exit 1
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

# Test 1: Network connectivity
if ! run_test "Network connectivity" "docker exec postgres-test ping -c 1 -W 2 pagila-postgres"; then
    print_error "Cannot reach pagila-postgres from postgres-test"
    exit 1
fi

# Test 2: PostgreSQL service ready
if ! run_test "PostgreSQL service ready" "docker exec postgres-test pg_isready -h pagila-postgres -U postgres -q"; then
    print_error "PostgreSQL service not accepting connections"
    exit 1
fi

# Test 3: Database authentication
if ! run_test "Database authentication" "docker exec -e PGPASSWORD=\"$POSTGRES_PASSWORD\" postgres-test psql -h pagila-postgres -U postgres -d pagila -c 'SELECT 1' -t -A" "^1$"; then
    print_error "Authentication failed"
    exit 1
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
