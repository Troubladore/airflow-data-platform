#!/bin/bash
# PostgreSQL Sandbox Test Runner
# Automatically bootstraps test database, runs tests, and ensures cleanup

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
COMPOSE_FILE="$REPO_ROOT/layer1-platform/docker/test-postgres.yml"
TEST_DB_CONTAINER="datakit-test-db"

# Logging functions
log_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
log_success() { echo -e "${GREEN}✅ $1${NC}"; }
log_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
log_error() { echo -e "${RED}❌ $1${NC}"; }

# Global variable to track if we need to cleanup the container
CLEANUP_CONTAINER=false

print_banner() {
    echo -e "${BLUE}"
    echo "🧪 =================================================="
    echo "   POSTGRESQL SANDBOX TEST RUNNER"
    echo "   Automated Test Lifecycle Management"
    echo "==================================================${NC}"
    echo
}

# Cleanup function - ALWAYS runs on exit
cleanup_sandbox() {
    local exit_code=$?

    echo
    log_info "Starting cleanup process..."

    if [ "$CLEANUP_CONTAINER" = true ]; then
        log_info "Stopping PostgreSQL test sandbox..."

        # Stop and remove container
        if command -v docker-compose &> /dev/null; then
            docker-compose -f "$COMPOSE_FILE" down --volumes 2>/dev/null || true
        elif docker compose version &> /dev/null 2>&1; then
            docker compose -f "$COMPOSE_FILE" down --volumes 2>/dev/null || true
        else
            # Fallback to direct docker commands
            docker stop "$TEST_DB_CONTAINER" 2>/dev/null || true
            docker rm -v "$TEST_DB_CONTAINER" 2>/dev/null || true
        fi

        log_success "Test sandbox cleaned up"
    else
        log_info "No test container to clean up"
    fi

    if [ $exit_code -eq 0 ]; then
        log_success "Test suite completed successfully"
    else
        log_error "Test suite failed with exit code $exit_code"
    fi

    exit $exit_code
}

# Set trap to ensure cleanup always runs
trap cleanup_sandbox EXIT INT TERM

# Check if container is already running
check_existing_container() {
    if docker ps --format "table {{.Names}}" | grep -q "^$TEST_DB_CONTAINER$"; then
        log_warning "Test database container already running - will reuse it"
        return 0
    else
        return 1
    fi
}

# Bootstrap PostgreSQL test sandbox
bootstrap_sandbox() {
    log_info "Bootstrapping PostgreSQL test sandbox..."

    # Check if already running - if so, we'll use it but ensure cleanup
    if check_existing_container; then
        log_info "Using existing test database container"
        CLEANUP_CONTAINER=true  # Always clean up test containers for resource conservation
        return 0
    fi

    # Check Docker availability
    if ! command -v docker &> /dev/null; then
        log_error "Docker not available - cannot start test sandbox"
        exit 1
    fi

    if ! docker info &> /dev/null; then
        log_error "Docker daemon not running - please start Docker Desktop"
        exit 1
    fi

    # Start the container
    log_info "Starting fresh test database container..."

    if command -v docker-compose &> /dev/null; then
        docker-compose -f "$COMPOSE_FILE" up -d
    elif docker compose version &> /dev/null 2>&1; then
        docker compose -f "$COMPOSE_FILE" up -d
    else
        log_error "Neither 'docker-compose' nor 'docker compose' available"
        exit 1
    fi

    CLEANUP_CONTAINER=true

    # Wait for database to be ready
    log_info "Waiting for database to be ready..."
    local max_attempts=30
    local attempt=1

    while [ $attempt -le $max_attempts ]; do
        if docker exec "$TEST_DB_CONTAINER" pg_isready -U test_user -d datakit_tests 2>/dev/null; then
            log_success "Database is ready!"
            break
        fi

        if [ $attempt -eq $max_attempts ]; then
            log_error "Database failed to start within $max_attempts attempts"
            exit 1
        fi

        echo -n "."
        sleep 1
        attempt=$((attempt + 1))
    done

    echo
    log_success "PostgreSQL test sandbox bootstrapped successfully"
    log_info "Connection: localhost:15444, database: datakit_tests, user: test_user"
}

# Run the actual tests
run_tests() {
    log_info "Running test suite with PostgreSQL sandbox..."

    cd "$REPO_ROOT/data-platform/sqlmodel-workspace/sqlmodel-framework"

    # Test 1: Framework Core
    log_info "Test 1: Framework core table mixins..."
    PYTHONPATH="./src:$PYTHONPATH" uv run -m pytest \
        tests/unit/test_table_mixins.py -v \
        --tb=short
    log_success "Framework core tests passed"

    # Test 2: Trigger Builder Tests
    log_info "Test 2: Trigger builder tests..."
    PYTHONPATH="./src:$PYTHONPATH" uv run -m pytest \
        tests/unit/test_trigger_builder.py -v \
        --tb=short
    log_success "Trigger builder tests passed"

    # Test 3: Example Datakit Deployment - TEMPORARILY DISABLED
    # The example datakit has missing language table references that need to be fixed
    # This is tracked in airflow-data-platform-examples issue #2
    log_info "Test 3: Example datakit deployment (skipped - missing language table)"
    log_warning "Example deployment test disabled until language table is added to pagila example"

    log_success "Platform framework tests passed! 🎉"
    log_info "Note: Example datakit deployment test skipped due to missing language table"
}

# Main execution
main() {
    print_banner

    bootstrap_sandbox
    echo
    run_tests
    echo

    # Cleanup happens automatically via trap
}

# Run main function
main "$@"
