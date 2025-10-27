#!/bin/bash
# Test for volume removal during clean-slate
# This test verifies that platform_postgres_data volume is properly removed
# when user confirms volume removal during clean-slate operation

set -e

# Source formatting library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/formatting.sh"

print_info "=== Testing Volume Removal (RED phase) ==="

# Cleanup function
cleanup() {
    print_info "Cleaning up test environment..."
    docker container rm -f platform-postgres 2>/dev/null || true
    docker volume rm platform_postgres_data 2>/dev/null || true
}

# Setup cleanup trap
trap cleanup EXIT

# Step 1: Setup - Create postgres container with volume
print_info "Step 1: Setting up PostgreSQL with volume..."
docker volume create platform_postgres_data
docker run -d \
    --name platform-postgres \
    -e POSTGRES_PASSWORD=test \
    -v platform_postgres_data:/var/lib/postgresql/data \
    postgres:17.5-alpine

# Verify volume exists
if docker volume inspect platform_postgres_data &>/dev/null; then
    print_check "PASS" "Volume created successfully"
else
    print_check "FAIL" "Volume creation failed"
    exit 1
fi

# Step 2: Run clean-slate with remove_volumes=yes
print_info "Step 2: Running clean-slate wizard with remove_volumes=yes..."

cd "$SCRIPT_DIR/../.."

# Run the platform clean-slate command with yes to remove volumes
# This simulates user saying "yes" to removing volumes
echo "yes" | python3 -m wizard clean-slate --service postgres --remove-volumes 2>&1 || true

# Step 3: Verify volume should NOT exist (this should FAIL in RED phase)
print_info "Step 3: Verifying volume removal..."
if docker volume inspect platform_postgres_data &>/dev/null; then
    print_check "FAIL" "Volume still exists (BUG CONFIRMED - volume not removed)"
    print_info "Expected: Volume should be removed"
    print_info "Actual: Volume platform_postgres_data still exists"
    exit 1
else
    print_check "PASS" "Volume removed successfully"
    exit 0
fi
