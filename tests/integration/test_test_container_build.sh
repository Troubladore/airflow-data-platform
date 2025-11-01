#!/bin/bash
# =============================================================================
# Test Container Build Integration Tests
# =============================================================================
#
# PURPOSE:
#   Comprehensive integration testing for postgres-test and sqlcmd-test
#   container build processes, covering both build-from-base and prebuilt modes.
#
# TESTS:
#   1. Build postgres-test from alpine:latest
#      - Verify psql command is available
#      - Verify klist command is available (Kerberos client)
#      - Verify unixODBC is installed (odbcinst)
#      - Verify non-root user (testuser, uid 10001)
#      - Verify Alpine-based and small (<50MB)
#
#   2. Build sqlcmd-test from alpine:latest
#      - Verify tsql command is available (FreeTDS)
#      - Verify odbcinst command is available (ODBC)
#      - Verify non-root user (testuser, uid 10001)
#      - Verify Alpine-based and small (<50MB)
#
#   3. Test prebuilt mode (postgres-test)
#      - Tag an existing image as prebuilt
#      - Set POSTGRES_TEST_PREBUILT=true in .env
#      - Verify it uses the tagged image (no rebuild)
#
#   4. Test prebuilt mode (sqlcmd-test)
#      - Tag an existing image as prebuilt
#      - Set SQLCMD_TEST_PREBUILT=true in .env
#      - Verify it uses the tagged image (no rebuild)
#
# EXIT CODES:
#   0 - All tests passed
#   1 - One or more tests failed
#
# USAGE:
#   ./tests/integration/test_test_container_build.sh
#
# REQUIREMENTS:
#   - Docker installed and running
#   - Access to Alpine base images
#   - Write access to platform-bootstrap/.env
#
# =============================================================================

set -e

# Find repo root and source formatting library
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"
source "${REPO_ROOT}/platform-bootstrap/lib/formatting.sh"

# Test tracking
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Cleanup tracking
CLEANUP_IMAGES=()
CLEANUP_ENV_BACKUP=""

# =============================================================================
# Helper Functions
# =============================================================================

run_test() {
    local test_name="$1"
    TESTS_RUN=$((TESTS_RUN + 1))
    print_section "Test ${TESTS_RUN}: ${test_name}"
}

pass_test() {
    local message="$1"
    TESTS_PASSED=$((TESTS_PASSED + 1))
    print_check "PASS" "${message}"
    echo ""
}

fail_test() {
    local message="$1"
    local detail="$2"
    TESTS_FAILED=$((TESTS_FAILED + 1))
    print_check "FAIL" "${message}" "${detail}"
    echo ""
}

cleanup() {
    print_section "Cleanup"

    # Remove test images
    for image in "${CLEANUP_IMAGES[@]}"; do
        if docker image inspect "$image" &>/dev/null; then
            print_info "Removing test image: $image"
            docker rmi -f "$image" 2>/dev/null || true
        fi
    done

    # Restore .env backup if it exists
    if [ -n "$CLEANUP_ENV_BACKUP" ] && [ -f "$CLEANUP_ENV_BACKUP" ]; then
        print_info "Restoring .env backup"
        mv "$CLEANUP_ENV_BACKUP" platform-bootstrap/.env
    elif [ -n "$CLEANUP_ENV_BACKUP" ]; then
        # If we created a backup placeholder but no original existed, remove the .env we created
        print_info "Removing temporary .env"
        rm -f platform-bootstrap/.env
    fi

    echo ""
}

trap cleanup EXIT

# =============================================================================
# Test Setup
# =============================================================================

print_header "Test Container Build Integration Tests"

# Backup existing .env if it exists
if [ -f platform-bootstrap/.env ]; then
    CLEANUP_ENV_BACKUP="platform-bootstrap/.env.backup.$$"
    cp platform-bootstrap/.env "$CLEANUP_ENV_BACKUP"
    print_info "Backed up existing .env to $CLEANUP_ENV_BACKUP"
else
    # Create a marker that we need to remove .env in cleanup
    CLEANUP_ENV_BACKUP="REMOVE"
    print_info "No existing .env found"
fi

# Create a clean .env for testing
cat > platform-bootstrap/.env <<EOF
# Test environment for test container builds
IMAGE_POSTGRES_TEST=alpine:latest
IMAGE_SQLCMD_TEST=alpine:latest
POSTGRES_TEST_PREBUILT=false
SQLCMD_TEST_PREBUILT=false
EOF

echo ""

# =============================================================================
# Test 1: Build postgres-test from alpine:latest
# =============================================================================

run_test "Build postgres-test from alpine:latest"

print_info "Building postgres-test container..."
cd platform-infrastructure
if make build-postgres-test > /tmp/postgres-test-build.log 2>&1; then
    pass_test "postgres-test built successfully"
else
    fail_test "postgres-test build failed" "See /tmp/postgres-test-build.log for details"
    cat /tmp/postgres-test-build.log
fi
cd "$REPO_ROOT"

CLEANUP_IMAGES+=("platform/postgres-test:latest")

# Verify psql is available
print_info "Verifying psql command..."
if docker run --rm platform/postgres-test:latest psql --version > /tmp/psql-version.log 2>&1; then
    version=$(cat /tmp/psql-version.log)
    pass_test "psql is available: $version"
else
    fail_test "psql command not found" "Expected PostgreSQL client to be installed"
fi

# Verify klist is available (Kerberos client)
print_info "Verifying klist command (Kerberos)..."
if docker run --rm platform/postgres-test:latest klist -V > /tmp/klist-version.log 2>&1; then
    version=$(cat /tmp/klist-version.log)
    pass_test "klist is available: $version"
else
    fail_test "klist command not found" "Expected Kerberos client to be installed"
fi

# Verify odbcinst is available (unixODBC)
print_info "Verifying odbcinst command (ODBC)..."
if docker run --rm platform/postgres-test:latest odbcinst --version > /tmp/odbcinst-version.log 2>&1; then
    version=$(cat /tmp/odbcinst-version.log | head -n1)
    pass_test "odbcinst is available: $version"
else
    fail_test "odbcinst command not found" "Expected unixODBC to be installed"
fi

# Verify non-root user (testuser, uid 10001)
print_info "Verifying non-root user configuration..."
actual_user=$(docker run --rm platform/postgres-test:latest whoami)
actual_uid=$(docker run --rm platform/postgres-test:latest id -u)

if [ "$actual_user" = "testuser" ] && [ "$actual_uid" = "10001" ]; then
    pass_test "Non-root user verified: $actual_user (uid $actual_uid)"
else
    fail_test "User configuration incorrect" "Expected testuser (uid 10001), got $actual_user (uid $actual_uid)"
fi

# Verify image is Alpine-based and small (<50MB)
print_info "Verifying image size and base..."
image_size=$(docker image inspect platform/postgres-test:latest --format='{{.Size}}')
image_size_mb=$((image_size / 1024 / 1024))

# Check for Alpine indicators
if docker run --rm platform/postgres-test:latest cat /etc/os-release 2>/dev/null | grep -q "Alpine"; then
    pass_test "Image is Alpine-based"
else
    fail_test "Image does not appear to be Alpine-based"
fi

if [ "$image_size_mb" -lt 50 ]; then
    pass_test "Image size is acceptable: ${image_size_mb}MB (< 50MB)"
else
    fail_test "Image size is too large: ${image_size_mb}MB" "Expected < 50MB for minimal Alpine image"
fi

# =============================================================================
# Test 2: Build sqlcmd-test from alpine:latest
# =============================================================================

run_test "Build sqlcmd-test from alpine:latest"

print_info "Building sqlcmd-test container..."
cd platform-infrastructure
if make build-sqlcmd-test > /tmp/sqlcmd-test-build.log 2>&1; then
    pass_test "sqlcmd-test built successfully"
else
    fail_test "sqlcmd-test build failed" "See /tmp/sqlcmd-test-build.log for details"
    cat /tmp/sqlcmd-test-build.log
fi
cd "$REPO_ROOT"

CLEANUP_IMAGES+=("platform/sqlcmd-test:latest")

# Verify tsql is available (FreeTDS)
print_info "Verifying tsql command (FreeTDS)..."
if docker run --rm platform/sqlcmd-test:latest tsql -C > /tmp/tsql-version.log 2>&1; then
    version=$(cat /tmp/tsql-version.log | head -n1)
    pass_test "tsql is available: $version"
else
    fail_test "tsql command not found" "Expected FreeTDS to be installed"
fi

# Verify odbcinst is available
print_info "Verifying odbcinst command (ODBC)..."
if docker run --rm platform/sqlcmd-test:latest odbcinst --version > /tmp/sqlcmd-odbcinst-version.log 2>&1; then
    version=$(cat /tmp/sqlcmd-odbcinst-version.log | head -n1)
    pass_test "odbcinst is available: $version"
else
    fail_test "odbcinst command not found" "Expected unixODBC to be installed"
fi

# Verify non-root user (testuser, uid 10001)
print_info "Verifying non-root user configuration..."
actual_user=$(docker run --rm platform/sqlcmd-test:latest whoami)
actual_uid=$(docker run --rm platform/sqlcmd-test:latest id -u)

if [ "$actual_user" = "testuser" ] && [ "$actual_uid" = "10001" ]; then
    pass_test "Non-root user verified: $actual_user (uid $actual_uid)"
else
    fail_test "User configuration incorrect" "Expected testuser (uid 10001), got $actual_user (uid $actual_uid)"
fi

# Verify image is Alpine-based and small (<50MB)
print_info "Verifying image size and base..."
image_size=$(docker image inspect platform/sqlcmd-test:latest --format='{{.Size}}')
image_size_mb=$((image_size / 1024 / 1024))

# Check for Alpine indicators
if docker run --rm platform/sqlcmd-test:latest cat /etc/os-release 2>/dev/null | grep -q "Alpine"; then
    pass_test "Image is Alpine-based"
else
    fail_test "Image does not appear to be Alpine-based"
fi

if [ "$image_size_mb" -lt 50 ]; then
    pass_test "Image size is acceptable: ${image_size_mb}MB (< 50MB)"
else
    fail_test "Image size is too large: ${image_size_mb}MB" "Expected < 50MB for minimal Alpine image"
fi

# =============================================================================
# Test 3: Test prebuilt mode (postgres-test)
# =============================================================================

run_test "Prebuilt mode for postgres-test"

# Tag the current image as a prebuilt image
PREBUILT_TAG="test-registry.example.com/postgres-test:prebuilt-v1"
print_info "Tagging current image as prebuilt: $PREBUILT_TAG"
docker tag platform/postgres-test:latest "$PREBUILT_TAG"
CLEANUP_IMAGES+=("$PREBUILT_TAG")

# Update .env to use prebuilt mode
cat > platform-bootstrap/.env <<EOF
# Test environment - prebuilt mode
IMAGE_POSTGRES_TEST=$PREBUILT_TAG
POSTGRES_TEST_PREBUILT=true
IMAGE_SQLCMD_TEST=alpine:latest
SQLCMD_TEST_PREBUILT=false
EOF

# Remove the existing built image to ensure we're pulling/tagging
docker rmi platform/postgres-test:latest 2>/dev/null || true

# Build should now pull and tag the prebuilt image
print_info "Running build-postgres-test in prebuilt mode..."
cd platform-infrastructure
if make build-postgres-test > /tmp/postgres-test-prebuilt.log 2>&1; then
    pass_test "Prebuilt mode executed successfully"
else
    fail_test "Prebuilt mode failed" "See /tmp/postgres-test-prebuilt.log for details"
    cat /tmp/postgres-test-prebuilt.log
fi
cd "$REPO_ROOT"

# Verify the image was pulled/tagged, not rebuilt
if grep -q "Pulling prebuilt postgres-test image" /tmp/postgres-test-prebuilt.log; then
    pass_test "Prebuilt mode used pull path (not build from base)"
else
    fail_test "Prebuilt mode did not use pull path" "Expected 'Pulling prebuilt' message in logs"
fi

# Verify the resulting image works
if docker run --rm platform/postgres-test:latest psql --version > /dev/null 2>&1; then
    pass_test "Prebuilt postgres-test image is functional"
else
    fail_test "Prebuilt postgres-test image not functional"
fi

# =============================================================================
# Test 4: Test prebuilt mode (sqlcmd-test)
# =============================================================================

run_test "Prebuilt mode for sqlcmd-test"

# Tag the current image as a prebuilt image
PREBUILT_TAG_SQL="test-registry.example.com/sqlcmd-test:prebuilt-v1"
print_info "Tagging current image as prebuilt: $PREBUILT_TAG_SQL"
docker tag platform/sqlcmd-test:latest "$PREBUILT_TAG_SQL"
CLEANUP_IMAGES+=("$PREBUILT_TAG_SQL")

# Update .env to use prebuilt mode
cat > platform-bootstrap/.env <<EOF
# Test environment - prebuilt mode
IMAGE_POSTGRES_TEST=alpine:latest
POSTGRES_TEST_PREBUILT=false
IMAGE_SQLCMD_TEST=$PREBUILT_TAG_SQL
SQLCMD_TEST_PREBUILT=true
EOF

# Remove the existing built image to ensure we're pulling/tagging
docker rmi platform/sqlcmd-test:latest 2>/dev/null || true

# Build should now pull and tag the prebuilt image
print_info "Running build-sqlcmd-test in prebuilt mode..."
cd platform-infrastructure
if make build-sqlcmd-test > /tmp/sqlcmd-test-prebuilt.log 2>&1; then
    pass_test "Prebuilt mode executed successfully"
else
    fail_test "Prebuilt mode failed" "See /tmp/sqlcmd-test-prebuilt.log for details"
    cat /tmp/sqlcmd-test-prebuilt.log
fi
cd "$REPO_ROOT"

# Verify the image was pulled/tagged, not rebuilt
if grep -q "Pulling prebuilt sqlcmd-test image" /tmp/sqlcmd-test-prebuilt.log; then
    pass_test "Prebuilt mode used pull path (not build from base)"
else
    fail_test "Prebuilt mode did not use pull path" "Expected 'Pulling prebuilt' message in logs"
fi

# Verify the resulting image works
if docker run --rm platform/sqlcmd-test:latest tsql -C > /dev/null 2>&1; then
    pass_test "Prebuilt sqlcmd-test image is functional"
else
    fail_test "Prebuilt sqlcmd-test image not functional"
fi

# =============================================================================
# Test Summary
# =============================================================================

print_header "Test Summary"

echo ""
print_info "Tests run:    $TESTS_RUN"
if [ $TESTS_PASSED -gt 0 ]; then
    print_check "PASS" "Tests passed: $TESTS_PASSED"
fi
if [ $TESTS_FAILED -gt 0 ]; then
    print_check "FAIL" "Tests failed: $TESTS_FAILED"
fi
echo ""

if [ $TESTS_FAILED -eq 0 ]; then
    print_success "All integration tests passed!"
    echo ""
    exit 0
else
    print_error "Some integration tests failed"
    echo ""
    exit 1
fi
