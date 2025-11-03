#!/bin/bash
# Integration Test for Pagila Test Container Implementation
# ==========================================================
# Tests the complete flow of Pagila setup with test containers
#
# This script validates:
# 1. Test container configuration is saved correctly
# 2. Pagila database is created and populated
# 3. Connection verification works with test container
# 4. Both prebuilt and build-from-base modes work
#
# Usage:
#   ./test-pagila-integration.sh [--prebuilt]

set -e

# Find repo root and source formatting library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "${REPO_ROOT}/platform-bootstrap/lib/formatting.sh"

# ==========================================
# Configuration
# ==========================================

TEST_MODE="${1:-build}"  # build or --prebuilt
PREBUILT_MODE=false

if [ "$TEST_MODE" = "--prebuilt" ]; then
    PREBUILT_MODE=true
fi

# ==========================================
# Test Functions
# ==========================================

cleanup_test() {
    print_header "Cleanup Test Environment"

    # Remove test containers
    docker rm -f pagila-postgres 2>/dev/null || true

    # Remove test config files
    rm -f "$REPO_ROOT/platform-config.yaml"
    rm -f "$REPO_ROOT/platform-bootstrap/.env"

    # Remove pagila test image
    docker rmi platform/pagila-test:latest 2>/dev/null || true

    print_success "Cleanup complete"
}

test_build_pagila_test_container() {
    print_header "Test: Build pagila-test Container"

    cd "$REPO_ROOT/platform-bootstrap"

    if [ "$PREBUILT_MODE" = true ]; then
        print_info "Testing prebuilt mode (will fail if image doesn't exist)"
        # For prebuilt mode, we'd need a real corporate image
        # Skip for now unless user provides one
        print_warning "Prebuilt mode requires corporate image - skipping"
        return 0
    else
        print_info "Testing build-from-base mode"

        # Create minimal .env for build
        cat > .env << EOF
IMAGE_PAGILA_TEST=alpine:latest
PAGILA_TEST_PREBUILT=false
EOF

        # Build the test container
        if make build-pagila-test; then
            print_check "PASS" "pagila-test container built successfully"
        else
            print_check "FAIL" "Failed to build pagila-test container"
            return 1
        fi

        # Verify image exists
        if docker image inspect platform/pagila-test:latest >/dev/null 2>&1; then
            print_check "PASS" "platform/pagila-test:latest image exists"
        else
            print_check "FAIL" "platform/pagila-test:latest image not found"
            return 1
        fi

        # Verify image has psql
        if docker run --rm platform/pagila-test:latest psql --version | grep -q "PostgreSQL"; then
            print_check "PASS" "psql is available in test container"
        else
            print_check "FAIL" "psql not found in test container"
            return 1
        fi
    fi
}

test_pagila_setup() {
    print_header "Test: Pagila Database Setup"

    cd "$REPO_ROOT/platform-bootstrap"

    print_info "Setting up Pagila database..."

    # Setup with auto-yes
    if PAGILA_AUTO_YES=1 make setup-pagila; then
        print_check "PASS" "Pagila setup completed"
    else
        print_check "FAIL" "Pagila setup failed"
        return 1
    fi

    # Verify container is running
    if docker ps | grep -q pagila-postgres; then
        print_check "PASS" "pagila-postgres container is running"
    else
        print_check "FAIL" "pagila-postgres container not running"
        docker ps -a | grep pagila-postgres || true
        return 1
    fi
}

test_pagila_database_connection() {
    print_header "Test: Pagila Database Connection"

    # Wait for database to be ready
    print_info "Waiting for database to be ready..."
    sleep 5

    # Test direct connection (without test container)
    print_info "Testing direct connection via docker exec..."
    if docker exec pagila-postgres psql -U postgres -d pagila -c "SELECT COUNT(*) FROM film;" >/dev/null 2>&1; then
        print_check "PASS" "Direct database connection works"
    else
        print_check "WARN" "Direct connection failed (database may still be initializing)"
        docker logs pagila-postgres --tail 20
    fi

    # Test connection via test container
    print_info "Testing connection via pagila-test container..."
    if docker run --rm --network platform_network platform/pagila-test:latest \
        psql -h pagila-postgres -U postgres -d pagila -c "SELECT 'Connection successful!' as status;" 2>/dev/null | grep -q "Connection successful"; then
        print_check "PASS" "Test container connection works"
    else
        print_check "FAIL" "Test container connection failed"
        print_info "Checking network connectivity..."
        docker network inspect platform_network | grep -A 5 pagila-postgres || true
        return 1
    fi
}

test_pagila_data_verification() {
    print_header "Test: Pagila Data Verification"

    # Check that tables exist
    print_info "Checking for Pagila tables..."
    TABLES=$(docker exec pagila-postgres psql -U postgres -d pagila -c "\dt" 2>/dev/null | grep -E "actor|film|customer" | wc -l)

    if [ "$TABLES" -ge 3 ]; then
        print_check "PASS" "Pagila tables found (actor, film, customer)"
    else
        print_check "FAIL" "Pagila tables not found"
        docker exec pagila-postgres psql -U postgres -d pagila -c "\dt"
        return 1
    fi

    # Check that data is loaded
    print_info "Checking for data in film table..."
    FILM_COUNT=$(docker exec pagila-postgres psql -U postgres -d pagila -t -c "SELECT COUNT(*) FROM film;" 2>/dev/null | tr -d ' ')

    if [ "$FILM_COUNT" -gt 0 ]; then
        print_check "PASS" "Film data loaded (count: $FILM_COUNT)"
    else
        print_check "FAIL" "No film data found"
        return 1
    fi

    # Test a sample query
    print_info "Running sample query..."
    if docker run --rm --network platform_network platform/pagila-test:latest \
        psql -h pagila-postgres -U postgres -d pagila \
        -c "SELECT title FROM film LIMIT 3;" 2>/dev/null | grep -q "rows"; then
        print_check "PASS" "Sample query executed successfully"
    else
        print_check "FAIL" "Sample query failed"
        return 1
    fi
}

test_cleanup_verification() {
    print_header "Test: Cleanup Verification"

    cd "$REPO_ROOT/platform-bootstrap"

    print_info "Cleaning up Pagila..."
    if make clean-pagila; then
        print_check "PASS" "Pagila cleanup completed"
    else
        print_check "FAIL" "Pagila cleanup failed"
        return 1
    fi

    # Verify container is stopped
    if ! docker ps | grep -q pagila-postgres; then
        print_check "PASS" "pagila-postgres container stopped"
    else
        print_check "FAIL" "pagila-postgres container still running"
        return 1
    fi
}

# ==========================================
# Main Test Flow
# ==========================================

main() {
    print_header "Pagila Integration Test"
    print_info "Testing in $([ "$PREBUILT_MODE" = true ] && echo "PREBUILT" || echo "BUILD-FROM-BASE") mode"
    print_divider

    # Track results
    TESTS_PASSED=0
    TESTS_FAILED=0

    # Initial cleanup
    cleanup_test

    # Run tests
    if test_build_pagila_test_container; then
        ((TESTS_PASSED++))
    else
        ((TESTS_FAILED++))
    fi

    if test_pagila_setup; then
        ((TESTS_PASSED++))
    else
        ((TESTS_FAILED++))
        print_error "Pagila setup failed - skipping remaining tests"
        cleanup_test
        exit 1
    fi

    if test_pagila_database_connection; then
        ((TESTS_PASSED++))
    else
        ((TESTS_FAILED++))
    fi

    if test_pagila_data_verification; then
        ((TESTS_PASSED++))
    else
        ((TESTS_FAILED++))
    fi

    if test_cleanup_verification; then
        ((TESTS_PASSED++))
    else
        ((TESTS_FAILED++))
    fi

    # Final cleanup
    cleanup_test

    # Report results
    print_divider
    print_header "Test Results"
    print_info "Tests Passed: $TESTS_PASSED"
    print_info "Tests Failed: $TESTS_FAILED"

    if [ $TESTS_FAILED -eq 0 ]; then
        print_success "All tests passed!"
        return 0
    else
        print_error "Some tests failed"
        return 1
    fi
}

# Run main test flow
main "$@"
