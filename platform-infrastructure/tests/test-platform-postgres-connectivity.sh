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

# Verify platform-postgres container exists and is running
if ! check_prerequisite "platform-postgres container running" "docker ps --filter 'name=platform-postgres' --filter 'status=running' --format '{{.Names}}' | grep -q '^platform-postgres$'"; then
    print_error "platform-postgres container not found or not running"
    print_info "Start platform infrastructure with: make -C platform-infrastructure start"
    exit 1
fi

# Wait for PostgreSQL to be healthy (not just container running)
print_info "Waiting for PostgreSQL to be ready..."
WAIT_SECONDS=0
MAX_WAIT=30
while [ $WAIT_SECONDS -lt $MAX_WAIT ]; do
    HEALTH_STATUS=$(docker inspect platform-postgres --format='{{.State.Health.Status}}' 2>/dev/null || echo "unknown")

    if [ "$HEALTH_STATUS" = "healthy" ]; then
        print_check "PASS" "PostgreSQL is healthy"
        break
    elif [ "$HEALTH_STATUS" = "unhealthy" ]; then
        print_check "FAIL" "PostgreSQL is unhealthy"
        print_error "Check logs: docker logs platform-postgres"
        exit 1
    elif [ "$HEALTH_STATUS" = "unknown" ] || [ -z "$HEALTH_STATUS" ]; then
        # No health check defined or old Docker version, fall back to pg_isready
        if docker exec platform-postgres pg_isready -q 2>/dev/null; then
            print_check "PASS" "PostgreSQL is ready (pg_isready)"
            break
        fi
    fi

    # Show progress
    if [ $((WAIT_SECONDS % 5)) -eq 0 ] && [ $WAIT_SECONDS -gt 0 ]; then
        print_info "Still waiting... ($WAIT_SECONDS/$MAX_WAIT seconds, status: $HEALTH_STATUS)"
    fi

    sleep 1
    WAIT_SECONDS=$((WAIT_SECONDS + 1))
done

if [ $WAIT_SECONDS -ge $MAX_WAIT ]; then
    print_check "FAIL" "PostgreSQL did not become ready in $MAX_WAIT seconds"
    print_info "Current status: $HEALTH_STATUS"
    print_info "Check logs: docker logs platform-postgres"
    exit 1
fi

# Verify both containers on platform_network
if ! check_prerequisite "Containers on platform_network" "docker network inspect platform_network -f '{{range .Containers}}{{.Name}} {{end}}' | grep -q 'postgres-test' && docker network inspect platform_network -f '{{range .Containers}}{{.Name}} {{end}}' | grep -q 'platform-postgres'"; then
    print_error "Containers not on same network"
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

# Test 1: Database authentication (the actual goal)
if ! run_test "Database authentication" "docker exec -e PGPASSWORD=\"$POSTGRES_PASSWORD\" postgres-test psql -h platform-postgres -U $POSTGRES_USER -d postgres -c 'SELECT 1' -t -A" "^1$"; then
    print_error "Authentication failed"

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

# Test 2: PostgreSQL service ready (quick check after successful auth)
if ! run_test "PostgreSQL service ready" "docker exec postgres-test pg_isready -h platform-postgres -q"; then
    print_warning "pg_isready check failed despite successful authentication"
fi

# Test 3: Query database list
DB_LIST=$(docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" postgres-test psql -h platform-postgres -U $POSTGRES_USER -d postgres -t -A -c "SELECT datname FROM pg_database WHERE datname IN ('airflow_db', 'openmetadata_db') ORDER BY datname")
# Only count non-empty lines
if [ -n "$DB_LIST" ]; then
    DB_COUNT=$(echo "$DB_LIST" | grep -c '^')
else
    DB_COUNT=0
fi

if [ "$DB_COUNT" -gt 0 ]; then
    print_check "PASS" "Platform databases exist ($DB_COUNT found)"
    TESTS_PASSED=$((TESTS_PASSED + 1))
    if [ "$QUIET_MODE" = false ]; then
        echo "$DB_LIST" | while read -r db; do
            print_bullet "$db"
        done
    fi
else
    print_check "WARN" "No platform databases found yet"
    print_info "Databases will be created on first use by services"
fi
TESTS_TOTAL=$((TESTS_TOTAL + 1))

# Test 4: Query PostgreSQL version
PG_VERSION=$(docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" postgres-test psql -h platform-postgres -U $POSTGRES_USER -d postgres -t -A -c "SELECT version()" | head -n1 | cut -d' ' -f2)
print_check "PASS" "PostgreSQL version: $PG_VERSION"
TESTS_PASSED=$((TESTS_PASSED + 1))
TESTS_TOTAL=$((TESTS_TOTAL + 1))

# Summary
print_divider
echo ""

if [ "$QUIET_MODE" = true ]; then
    # Brief output for wizard integration
    if [ $TESTS_PASSED -eq $TESTS_TOTAL ]; then
        echo "✓ Platform postgres healthy - $DB_COUNT databases, PostgreSQL $PG_VERSION"
        exit 0
    else
        echo "✗ Platform postgres unhealthy - $TESTS_PASSED/$TESTS_TOTAL tests passed"
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
