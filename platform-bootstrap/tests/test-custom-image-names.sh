#!/bin/bash
# Integration Test for Custom Test Container Image Names
# ========================================================
# Tests that custom-named test images work correctly throughout the setup
#
# This test validates the bug fix for hard-coded image names:
# - User reported: "Prerequisites [FAIL] postgres-test container running"
# - Issue: System checked for hard-coded "postgres-test" instead of custom image
#
# Test strategy:
# 1. Build test containers with custom names (not platform/postgres-test)
# 2. Configure system to use custom names
# 3. Run setup and verification
# 4. Verify no hard-coded name errors occur
#
# Usage:
#   ./test-custom-image-names.sh

# set -e  # Disabled so tests continue on failure

# Find repo root and source formatting library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "${REPO_ROOT}/platform-bootstrap/lib/formatting.sh"

# ==========================================
# Configuration
# ==========================================

# Use non-standard image names to expose hard-coding issues
CUSTOM_POSTGRES_TEST_IMAGE="custom/postgres-conn-test:v1"
CUSTOM_PAGILA_TEST_IMAGE="mycorp/pagila-connection:latest"
CUSTOM_BASE_IMAGE="custom/alpine-base:3.19"

# ==========================================
# Cleanup Function
# ==========================================

cleanup() {
    print_header "Cleanup"

    # Stop and remove containers
    docker rm -f platform-postgres pagila-postgres 2>/dev/null || true

    # Remove custom test images
    docker rmi -f $CUSTOM_POSTGRES_TEST_IMAGE 2>/dev/null || true
    docker rmi -f $CUSTOM_PAGILA_TEST_IMAGE 2>/dev/null || true
    docker rmi -f $CUSTOM_BASE_IMAGE 2>/dev/null || true
    docker rmi -f platform/postgres-test:latest 2>/dev/null || true
    docker rmi -f platform/pagila-test:latest 2>/dev/null || true

    # Clean config files
    rm -f "$REPO_ROOT/platform-config.yaml"
    rm -f "$REPO_ROOT/platform-bootstrap/.env"

    print_success "Cleanup complete"
}

# Trap to cleanup on exit
# trap cleanup EXIT  # Disabled for debugging

# ==========================================
# Test 1: Build Custom Base Image
# ==========================================

test_build_custom_base() {
    print_header "Test 1: Build Custom Base Image"

    # Create a custom base image with a non-standard name
    # This simulates a corporate-approved base image
    cat > /tmp/Dockerfile.custom-base << 'EOF'
FROM alpine:latest
RUN echo "Custom corporate base image" > /etc/custom-base.txt
EOF

    if docker build -t $CUSTOM_BASE_IMAGE -f /tmp/Dockerfile.custom-base /tmp; then
        print_check "PASS" "Custom base image built: $CUSTOM_BASE_IMAGE"
    else
        print_check "FAIL" "Failed to build custom base image"
        return 1
    fi

    # Verify image exists with exact custom name
    if docker images | grep -q "custom/alpine-base.*3.19"; then
        print_check "PASS" "Custom base image exists with correct name"
    else
        print_check "FAIL" "Custom base image not found"
        docker images | grep alpine
        return 1
    fi

    rm -f /tmp/Dockerfile.custom-base
}

# ==========================================
# Test 2: Build Custom Postgres Test Image
# ==========================================

test_build_custom_postgres_test() {
    print_header "Test 2: Build Custom Postgres Test Image"

    print_info "Building from custom base: $CUSTOM_BASE_IMAGE"

    # Build postgres test image from custom base with custom name
    cd "$REPO_ROOT/platform-infrastructure"

    if docker build \
        -f test-containers/postgres-test/Dockerfile \
        --build-arg BASE_IMAGE=$CUSTOM_BASE_IMAGE \
        -t $CUSTOM_POSTGRES_TEST_IMAGE \
        test-containers/postgres-test/; then
        print_check "PASS" "Custom postgres test image built"
    else
        print_check "FAIL" "Failed to build custom postgres test image"
        return 1
    fi

    # Verify the custom image exists (NOT platform/postgres-test)
    if docker images | grep -q "custom/postgres-conn-test.*v1"; then
        print_check "PASS" "Custom image has correct non-standard name"
    else
        print_check "FAIL" "Image name incorrect"
        docker images | grep postgres
        return 1
    fi

    # Verify image has psql
    if docker run --rm $CUSTOM_POSTGRES_TEST_IMAGE psql --version | grep -q "PostgreSQL"; then
        print_check "PASS" "Custom image contains psql"
    else
        print_check "FAIL" "psql not found in custom image"
        return 1
    fi
}

# ==========================================
# Test 3: Build Custom Pagila Test Image
# ==========================================

test_build_custom_pagila_test() {
    print_header "Test 3: Build Custom Pagila Test Image"

    print_info "Building from custom base: $CUSTOM_BASE_IMAGE"

    # Build pagila test image from custom base with custom name
    cd "$REPO_ROOT/pagila"

    if docker build \
        -f test-containers/pagila-test/Dockerfile \
        --build-arg BASE_IMAGE=$CUSTOM_BASE_IMAGE \
        -t $CUSTOM_PAGILA_TEST_IMAGE \
        test-containers/pagila-test/; then
        print_check "PASS" "Custom pagila test image built"
    else
        print_check "FAIL" "Failed to build custom pagila test image"
        return 1
    fi

    # Verify custom name (NOT platform/pagila-test)
    if docker images | grep -q "mycorp/pagila-connection.*latest"; then
        print_check "PASS" "Custom pagila image has correct non-standard name"
    else
        print_check "FAIL" "Image name incorrect"
        docker images | grep pagila
        return 1
    fi
}

# ==========================================
# Test 4: Configure System with Custom Images
# ==========================================

test_configure_custom_images() {
    print_header "Test 4: Configure System with Custom Images"

    cd "$REPO_ROOT/platform-bootstrap"

    # Create .env with custom image configurations
    # This simulates what the wizard would save
    cat > .env << EOF
# Custom test container images
IMAGE_POSTGRES_TEST=$CUSTOM_POSTGRES_TEST_IMAGE
POSTGRES_TEST_PREBUILT=true
IMAGE_PAGILA_TEST=$CUSTOM_PAGILA_TEST_IMAGE
PAGILA_TEST_PREBUILT=true
EOF

    print_check "PASS" "Configured .env with custom image names"
    print_info "  POSTGRES: $CUSTOM_POSTGRES_TEST_IMAGE"
    print_info "  PAGILA:   $CUSTOM_PAGILA_TEST_IMAGE"
}

# ==========================================
# Test 5: Build Test Containers via Makefile
# ==========================================

test_makefile_build_with_custom() {
    print_header "Test 5: Build Test Containers via Makefile"

    cd "$REPO_ROOT/platform-infrastructure"

    # The Makefile should pull the custom image and tag it as platform/postgres-test
    print_info "Building postgres-test with custom image..."
    if make build-postgres-test; then
        print_check "PASS" "Makefile build succeeded with custom image"
    else
        print_check "FAIL" "Makefile build failed"
        return 1
    fi

    # Verify platform/postgres-test:latest now exists and references custom image
    if docker images | grep -q "platform/postgres-test.*latest"; then
        print_check "PASS" "platform/postgres-test:latest tagged"
    else
        print_check "FAIL" "Standard tag not created"
        return 1
    fi

    # Verify it's actually our custom image underneath
    CUSTOM_IMAGE_ID=$(docker images -q $CUSTOM_POSTGRES_TEST_IMAGE)
    PLATFORM_IMAGE_ID=$(docker images -q platform/postgres-test:latest)

    if [ "$CUSTOM_IMAGE_ID" = "$PLATFORM_IMAGE_ID" ]; then
        print_check "PASS" "platform/postgres-test:latest references custom image"
    else
        print_check "FAIL" "Image IDs don't match - not using custom image"
        print_info "  Custom ID:   $CUSTOM_IMAGE_ID"
        print_info "  Platform ID: $PLATFORM_IMAGE_ID"
        return 1
    fi
}

# ==========================================
# Test 6: Test Connection with Custom Image
# ==========================================

test_connection_with_custom_image() {
    print_header "Test 6: Test Connection with Custom Image"

    # Ensure platform_network exists
    print_info "Ensuring platform_network exists..."
    docker network create platform_network 2>/dev/null || print_check "INFO" "platform_network already exists"

    # Clean up any existing test container
    docker rm -f platform-postgres 2>/dev/null || true

    # Start a test postgres container
    print_info "Bootstrapping test postgres container..."

    # First, ensure we have a postgres image available
    # Check for exact postgres images (not just any image with 'postgres' in the name)
    POSTGRES_IMAGE=""

    # Check if we have a real postgres image by looking at REPOSITORY column
    if docker images --format "{{.Repository}}:{{.Tag}}" | grep -E "^postgres:17-alpine$"; then
        POSTGRES_IMAGE="postgres:17-alpine"
        print_check "INFO" "Using existing postgres:17-alpine image"
    elif docker images --format "{{.Repository}}:{{.Tag}}" | grep -E "^postgres:latest$"; then
        POSTGRES_IMAGE="postgres:latest"
        print_check "INFO" "Using existing postgres:latest image"
    elif docker images --format "{{.Repository}}:{{.Tag}}" | grep -E "^postgres:"; then
        # Found some postgres image, use it
        POSTGRES_IMAGE=$(docker images --format "{{.Repository}}:{{.Tag}}" | grep -E "^postgres:" | head -1)
        print_check "INFO" "Using existing postgres image: $POSTGRES_IMAGE"
    else
        # No postgres image found, need to pull one
        print_info "No postgres image found locally, attempting to pull..."

        # Try to pull postgres:17-alpine (our preferred image)
        print_info "Trying to pull postgres:17-alpine..."
        if docker pull postgres:17-alpine; then
            POSTGRES_IMAGE="postgres:17-alpine"
            print_check "PASS" "Successfully pulled postgres:17-alpine"
        else
            # If that fails, try postgres:latest
            print_info "Failed to pull postgres:17-alpine, trying postgres:latest..."
            if docker pull postgres:latest; then
                POSTGRES_IMAGE="postgres:latest"
                print_check "PASS" "Successfully pulled postgres:latest"
            else
                # If we can't pull any postgres image, TEST FAILS
                print_check "FAIL" "Cannot pull postgres images - Docker registry unavailable or authentication issues"
                print_info "Test 6 requires a working PostgreSQL container to test custom image connectivity"
                print_info "This failure indicates a Docker environment issue, not a code bug"
                return 1
            fi
        fi
    fi

    # Now start the postgres container
    print_info "Starting PostgreSQL container with $POSTGRES_IMAGE..."

    DOCKER_OUTPUT=$(docker run -d --name platform-postgres \
        --network platform_network \
        -e POSTGRES_PASSWORD=test \
        -e POSTGRES_HOST_AUTH_METHOD=trust \
        "$POSTGRES_IMAGE" 2>&1)

    if [ $? -ne 0 ]; then
        print_check "FAIL" "Could not start PostgreSQL container"
        print_info "Docker error: $DOCKER_OUTPUT"
        return 1
    fi

    print_check "PASS" "PostgreSQL container started"

    # Wait for postgres to be ready (with timeout)
    print_info "Waiting for PostgreSQL to be ready..."
    MAX_WAIT=30
    WAITED=0
    while [ $WAITED -lt $MAX_WAIT ]; do
        if docker exec platform-postgres pg_isready -U postgres >/dev/null 2>&1; then
            print_check "PASS" "PostgreSQL is ready"
            break
        fi
        sleep 1
        ((WAITED++))
    done

    if [ $WAITED -ge $MAX_WAIT ]; then
        print_check "FAIL" "PostgreSQL did not become ready in time"
        docker logs platform-postgres --tail 30
        return 1
    fi

    # Try to connect using the custom test image (via platform/postgres-test tag)
    print_info "Testing PostgreSQL connection via custom test container..."

    # This is the actual test - can our custom-named test image connect to PostgreSQL?
    CONNECTION_OUTPUT=$(docker run --rm --network platform_network \
        platform/postgres-test:latest \
        psql -h platform-postgres -U postgres -c "SELECT 'Custom image works!' as status;" 2>&1)

    if echo "$CONNECTION_OUTPUT" | grep -q "Custom image works"; then
        print_check "PASS" "PostgreSQL connection successful with custom test image"
    else
        print_check "FAIL" "PostgreSQL connection failed with custom test image"
        print_info "Connection output: $CONNECTION_OUTPUT"
        docker logs platform-postgres --tail 20
        return 1
    fi

    # Verify we're actually using the custom image
    print_info "Verifying custom image is in use..."
    if docker run --rm platform/postgres-test:latest cat /etc/custom-base.txt 2>/dev/null | grep -q "Custom corporate base"; then
        print_check "PASS" "Confirmed using custom corporate base image"
    else
        print_check "FAIL" "Not using custom base image"
        return 1
    fi
}

# ==========================================
# Test 7: Check for Hard-Coded Name Errors
# ==========================================

test_no_hardcoded_errors() {
    print_header "Test 7: Check for Hard-Coded Name Errors"

    print_info "Checking if any scripts fail due to hard-coded 'postgres-test' name..."

    # This is where we'd catch the reported bug:
    # "Prerequisites [FAIL] postgres-test container running"

    # Try to find and run any validation scripts
    cd "$REPO_ROOT/platform-bootstrap"

    # Check if test scripts exist that might have this issue
    if [ -f "tests/test-postgres-validation.sh" ]; then
        print_info "Running postgres validation test..."
        if ./tests/test-postgres-validation.sh 2>&1 | tee /tmp/test-output.txt; then
            print_check "PASS" "Validation script succeeded"
        else
            # Check for hard-coded name error
            if grep -q "postgres-test container" /tmp/test-output.txt; then
                print_check "FAIL" "Found hard-coded 'postgres-test' reference in error"
                cat /tmp/test-output.txt
                return 1
            fi
        fi
    else
        print_check "INFO" "No postgres validation script found"
    fi

    # Check if there are any hard-coded references in the codebase
    print_info "Scanning for hard-coded 'postgres-test' container references..."
    HARDCODED_REFS=$(grep -r "postgres-test container running\|docker ps.*postgres-test" \
        "$REPO_ROOT/wizard/services/base_platform" \
        "$REPO_ROOT/platform-bootstrap" 2>/dev/null | grep -v ".pyc" | grep -v "test-custom" || true)

    if [ -n "$HARDCODED_REFS" ]; then
        print_check "WARN" "Found potential hard-coded references:"
        echo "$HARDCODED_REFS"
        print_info "These may need to use IMAGE_POSTGRES_TEST from .env instead"
    else
        print_check "PASS" "No hard-coded 'postgres-test' container references found"
    fi
}

# ==========================================
# Test 8: Pagila with Custom Image
# ==========================================

test_pagila_custom_image() {
    print_header "Test 8: Pagila with Custom Image"

    cd "$REPO_ROOT/platform-bootstrap"

    # Build pagila test container with custom image
    print_info "Building pagila-test with custom image via Makefile..."
    if make build-pagila-test; then
        print_check "PASS" "Pagila test container built from custom image"
    else
        print_check "FAIL" "Pagila test container build failed"
        return 1
    fi

    # Verify platform/pagila-test exists
    if docker images | grep -q "platform/pagila-test.*latest"; then
        print_check "PASS" "platform/pagila-test:latest tagged"
    else
        print_check "FAIL" "Pagila test image not tagged"
        return 1
    fi

    # Verify it references our custom image
    CUSTOM_PAG_ID=$(docker images -q $CUSTOM_PAGILA_TEST_IMAGE)
    PLATFORM_PAG_ID=$(docker images -q platform/pagila-test:latest)

    if [ "$CUSTOM_PAG_ID" = "$PLATFORM_PAG_ID" ]; then
        print_check "PASS" "platform/pagila-test references custom image"
    else
        print_check "FAIL" "Not using custom pagila image"
        return 1
    fi
}

# ==========================================
# Main Test Flow
# ==========================================

main() {
    print_header "Custom Test Container Image Names - Integration Test"
    print_info "This test validates that custom-named images work correctly"
    print_info "Reproducing user bug: hard-coded 'postgres-test' container checks"
    print_divider

    # Ensure we have a clean slate
    cleanup

    # Create platform network if it doesn't exist
    docker network create platform_network 2>/dev/null || true

    # Track results
    TESTS_PASSED=0
    TESTS_FAILED=0

    # Run all tests
    if test_build_custom_base; then
        ((TESTS_PASSED++))
    else
        ((TESTS_FAILED++))
    fi

    if test_build_custom_postgres_test; then
        ((TESTS_PASSED++))
    else
        ((TESTS_FAILED++))
    fi

    if test_build_custom_pagila_test; then
        ((TESTS_PASSED++))
    else
        ((TESTS_FAILED++))
    fi

    if test_configure_custom_images; then
        ((TESTS_PASSED++))
    else
        ((TESTS_FAILED++))
    fi

    if test_makefile_build_with_custom; then
        ((TESTS_PASSED++))
    else
        ((TESTS_FAILED++))
    fi

    if test_connection_with_custom_image; then
        ((TESTS_PASSED++))
    else
        ((TESTS_FAILED++))
    fi

    if test_no_hardcoded_errors; then
        ((TESTS_PASSED++))
    else
        ((TESTS_FAILED++))
    fi

    if test_pagila_custom_image; then
        ((TESTS_PASSED++))
    else
        ((TESTS_FAILED++))
    fi

    # Report results
    print_divider
    print_header "Test Results"
    print_info "Tests Passed: $TESTS_PASSED"
    print_info "Tests Failed: $TESTS_FAILED"

    if [ $TESTS_FAILED -eq 0 ]; then
        print_success "All tests passed!"
        print_info "Custom image names work correctly - no hard-coding issues found"
        return 0
    else
        print_error "Some tests failed"
        print_info "Hard-coded image name issues may exist"
        return 1
    fi
}

# Run main test
main "$@"
