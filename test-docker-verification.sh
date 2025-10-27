#!/bin/bash
# Docker Container/Image Creation Verification Script
# Tests three scenarios:
# 1. Postgres only
# 2. Postgres + Kerberos
# 3. Custom image (postgres:16)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLATFORM_INFRA_DIR="$SCRIPT_DIR/platform-infrastructure"
KERBEROS_DIR="$SCRIPT_DIR/kerberos"
PLATFORM_BOOTSTRAP_DIR="$SCRIPT_DIR/platform-bootstrap"
TEST_RESULTS_FILE="$SCRIPT_DIR/docker-verification-results.txt"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test results
declare -A TEST_RESULTS

log() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$TEST_RESULTS_FILE"
}

log_success() {
    echo -e "${GREEN}[PASS]${NC} $1" | tee -a "$TEST_RESULTS_FILE"
    TEST_RESULTS["$2"]="PASS"
}

log_fail() {
    echo -e "${RED}[FAIL]${NC} $1" | tee -a "$TEST_RESULTS_FILE"
    TEST_RESULTS["$2"]="FAIL"
}

log_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1" | tee -a "$TEST_RESULTS_FILE"
}

print_separator() {
    echo "========================================" | tee -a "$TEST_RESULTS_FILE"
}

clean_docker() {
    log "Cleaning Docker environment..."

    # Stop and remove platform containers
    docker stop platform-postgres kerberos-sidecar 2>/dev/null || true
    docker rm platform-postgres kerberos-sidecar 2>/dev/null || true

    # Remove volumes
    docker volume rm platform_postgres_data platform_kerberos_cache 2>/dev/null || true

    # Remove platform network
    docker network rm platform_network 2>/dev/null || true

    log "Docker environment cleaned"
}

wait_for_healthy() {
    local container_name="$1"
    local max_wait=60
    local elapsed=0

    log "Waiting for $container_name to become healthy (max ${max_wait}s)..."

    while [ $elapsed -lt $max_wait ]; do
        if docker ps --filter "name=$container_name" --format '{{.Status}}' | grep -q "healthy"; then
            log_success "$container_name is healthy" "health_$container_name"
            return 0
        fi
        sleep 2
        elapsed=$((elapsed + 2))
        echo -n "." | tee -a "$TEST_RESULTS_FILE"
    done

    echo "" | tee -a "$TEST_RESULTS_FILE"
    log_fail "$container_name did not become healthy within ${max_wait}s" "health_$container_name"
    docker ps -a --filter "name=$container_name" | tee -a "$TEST_RESULTS_FILE"
    docker logs "$container_name" 2>&1 | tail -20 | tee -a "$TEST_RESULTS_FILE"
    return 1
}

test_postgres_connection() {
    local container_name="$1"
    local user="${2:-platform_admin}"
    local max_retries=10
    local retry=0

    log "Testing PostgreSQL connection in $container_name with user $user..."

    while [ $retry -lt $max_retries ]; do
        if docker exec "$container_name" psql -U "$user" -d postgres -c "SELECT 1;" >/dev/null 2>&1; then
            log_success "PostgreSQL connection successful" "postgres_connection"
            return 0
        fi
        retry=$((retry + 1))
        sleep 2
    done

    log_fail "PostgreSQL connection failed after $max_retries attempts" "postgres_connection"
    docker logs "$container_name" 2>&1 | tail -20 | tee -a "$TEST_RESULTS_FILE"
    return 1
}

verify_docker_objects() {
    local scenario_name="$1"
    shift
    local expected_containers=("$@")

    print_separator
    log "Verifying Docker objects for: $scenario_name"
    print_separator

    # Check containers
    log "Checking containers..."
    docker ps -a --format "table {{.Names}}\t{{.Image}}\t{{.Status}}" | tee -a "$TEST_RESULTS_FILE"

    for container in "${expected_containers[@]}"; do
        if docker ps -a --filter "name=$container" --format '{{.Names}}' | grep -q "$container"; then
            log_success "Container $container exists" "container_$container"

            # Check if running
            if docker ps --filter "name=$container" --format '{{.Names}}' | grep -q "$container"; then
                log_success "Container $container is running" "running_$container"
            else
                log_fail "Container $container is not running" "running_$container"
            fi
        else
            log_fail "Container $container does not exist" "container_$container"
        fi
    done

    # Check images
    log ""
    log "Checking images..."
    docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}" | tee -a "$TEST_RESULTS_FILE"

    # Check network
    log ""
    log "Checking networks..."
    if docker network ls | grep -q "platform-network"; then
        log_success "Network platform-network exists" "network"
    else
        log_fail "Network platform-network does not exist" "network"
    fi
}

# ==========================================
# SCENARIO 1: Postgres Only
# ==========================================
test_scenario_1() {
    print_separator
    echo "SCENARIO 1: PostgreSQL Only" | tee -a "$TEST_RESULTS_FILE"
    print_separator

    clean_docker

    log "Setting up Postgres-only configuration..."

    # Create minimal .env file for platform-infrastructure
    cat > "$PLATFORM_INFRA_DIR/.env" <<EOF
PLATFORM_DB_USER=platform_admin
PLATFORM_DB_PASSWORD=testpass123
IMAGE_POSTGRES=postgres:17.5-alpine
EOF

    # Also update platform-bootstrap .env
    cat > "$PLATFORM_BOOTSTRAP_DIR/.env" <<EOF
PLATFORM_DB_USER=platform_admin
PLATFORM_DB_PASSWORD=testpass123
EOF

    # Run docker compose
    log "Starting PostgreSQL container..."
    cd "$PLATFORM_INFRA_DIR"
    docker compose up -d 2>&1 | tee -a "$TEST_RESULTS_FILE"

    sleep 5

    # Verify
    verify_docker_objects "Postgres Only" "platform-postgres"

    # Wait for healthy
    wait_for_healthy "platform-postgres"

    # Test connection
    test_postgres_connection "platform-postgres" "platform_admin"

    log_success "Scenario 1 completed" "scenario_1"
}

# ==========================================
# SCENARIO 2: Postgres + Kerberos
# ==========================================
test_scenario_2() {
    print_separator
    echo "SCENARIO 2: PostgreSQL + Kerberos Sidecar" | tee -a "$TEST_RESULTS_FILE"
    print_separator

    clean_docker

    log "Setting up Postgres + Kerberos configuration..."

    # First, check if kerberos-sidecar image exists
    log "Checking for kerberos-sidecar image..."
    if ! docker images platform/kerberos-sidecar:latest --format '{{.Repository}}:{{.Tag}}' | grep -q "platform/kerberos-sidecar:latest"; then
        log_warning "Kerberos sidecar image not found. Building it..."
        cd "$KERBEROS_DIR"
        make build 2>&1 | tee -a "$TEST_RESULTS_FILE" || {
            log_fail "Failed to build kerberos-sidecar image" "kerberos_image_build"
            log "Skipping Scenario 2"
            return 1
        }
    else
        log_success "Kerberos sidecar image exists" "kerberos_image_exists"
    fi

    # Create .env files
    cat > "$PLATFORM_INFRA_DIR/.env" <<EOF
PLATFORM_DB_USER=platform_admin
PLATFORM_DB_PASSWORD=testpass123
IMAGE_POSTGRES=postgres:17.5-alpine
EOF

    cat > "$PLATFORM_BOOTSTRAP_DIR/.env" <<EOF
PLATFORM_DB_USER=platform_admin
PLATFORM_DB_PASSWORD=testpass123
EOF

    # Create kerberos .env
    cat > "$KERBEROS_DIR/.env" <<EOF
TICKET_MODE=copy
USER=testuser
COMPANY_DOMAIN=EXAMPLE.COM
COPY_INTERVAL=300
KRB5_CONF_PATH=/etc/krb5.conf
KERBEROS_TICKET_DIR=${HOME}/.krb5-cache
EOF

    # Create secrets directory and password file
    mkdir -p "$KERBEROS_DIR/.secrets"
    echo "testpass" > "$KERBEROS_DIR/.secrets/krb_password.txt"

    # Start postgres first
    log "Starting PostgreSQL container..."
    cd "$PLATFORM_INFRA_DIR"
    docker compose up -d 2>&1 | tee -a "$TEST_RESULTS_FILE"

    sleep 5

    # Then start kerberos (which joins the existing network)
    log "Starting Kerberos sidecar..."
    cd "$KERBEROS_DIR"
    docker compose up -d 2>&1 | tee -a "$TEST_RESULTS_FILE"

    sleep 5

    # Verify
    verify_docker_objects "Postgres + Kerberos" "platform-postgres" "kerberos-sidecar"

    # Wait for healthy
    wait_for_healthy "platform-postgres"

    # Kerberos sidecar health check might fail in copy mode without tickets, so just check if running
    if docker ps --filter "name=kerberos-sidecar" --format '{{.Names}}' | grep -q "kerberos-sidecar"; then
        log_success "Kerberos sidecar is running" "kerberos_running"
    else
        log_fail "Kerberos sidecar is not running" "kerberos_running"
    fi

    # Test connection
    test_postgres_connection "platform-postgres" "platform_admin"

    log_success "Scenario 2 completed" "scenario_2"
}

# ==========================================
# SCENARIO 3: Custom Image (postgres:16)
# ==========================================
test_scenario_3() {
    print_separator
    echo "SCENARIO 3: Custom Image (postgres:16)" | tee -a "$TEST_RESULTS_FILE"
    print_separator

    clean_docker

    log "Setting up custom image configuration..."

    # Remove postgres:16 if it exists to test pulling
    log "Removing postgres:16 image if exists..."
    docker rmi postgres:16 2>/dev/null || true

    # Create .env file with custom image
    cat > "$PLATFORM_INFRA_DIR/.env" <<EOF
PLATFORM_DB_USER=platform_admin
PLATFORM_DB_PASSWORD=testpass123
IMAGE_POSTGRES=postgres:16
EOF

    cat > "$PLATFORM_BOOTSTRAP_DIR/.env" <<EOF
PLATFORM_DB_USER=platform_admin
PLATFORM_DB_PASSWORD=testpass123
EOF

    # Run docker compose
    log "Starting PostgreSQL with custom image..."
    cd "$PLATFORM_INFRA_DIR"
    docker compose up -d 2>&1 | tee -a "$TEST_RESULTS_FILE"

    sleep 5

    # Verify image was pulled
    log "Checking if postgres:16 image exists..."
    if docker images postgres:16 --format '{{.Repository}}:{{.Tag}}' | grep -q "postgres:16"; then
        log_success "Custom image postgres:16 was pulled" "custom_image"
    else
        log_fail "Custom image postgres:16 was not pulled" "custom_image"
    fi

    # Verify
    verify_docker_objects "Custom Image" "platform-postgres"

    # Check what image the container is using
    log "Checking container image..."
    CONTAINER_IMAGE=$(docker inspect platform-postgres --format='{{.Config.Image}}' 2>/dev/null || echo "NOT_FOUND")
    log "Container is using image: $CONTAINER_IMAGE"

    if [[ "$CONTAINER_IMAGE" == "postgres:16" ]]; then
        log_success "Container is using custom image postgres:16" "container_custom_image"
    else
        log_warning "Container is using image: $CONTAINER_IMAGE (expected postgres:16)"
        TEST_RESULTS["container_custom_image"]="FAIL"
    fi

    # Wait for healthy - postgres:16 doesn't have healthcheck, just check if running
    if docker ps --filter "name=platform-postgres" --format '{{.Names}}' | grep -q "platform-postgres"; then
        log_success "Container platform-postgres is running" "container_running"
        sleep 10  # Give it time to start up
    else
        log_fail "Container platform-postgres is not running" "container_running"
    fi

    # Test connection
    test_postgres_connection "platform-postgres" "platform_admin"

    log_success "Scenario 3 completed" "scenario_3"
}

# ==========================================
# Main Execution
# ==========================================
main() {
    # Initialize results file
    echo "Docker Container/Image Verification Test Results" > "$TEST_RESULTS_FILE"
    echo "Date: $(date)" >> "$TEST_RESULTS_FILE"
    echo "" >> "$TEST_RESULTS_FILE"

    log "Starting Docker verification tests..."
    log "Platform Infrastructure directory: $PLATFORM_INFRA_DIR"
    log "Kerberos directory: $KERBEROS_DIR"
    log "Platform Bootstrap directory: $PLATFORM_BOOTSTRAP_DIR"

    # Check if docker is available
    if ! command -v docker &> /dev/null; then
        log_fail "Docker is not installed or not in PATH" "docker_available"
        exit 1
    fi
    log_success "Docker is available" "docker_available"

    # Check if docker compose is available
    if ! docker compose version &> /dev/null; then
        log_fail "Docker Compose is not available" "docker_compose_available"
        exit 1
    fi
    log_success "Docker Compose is available" "docker_compose_available"

    # Run scenarios
    test_scenario_1
    echo "" | tee -a "$TEST_RESULTS_FILE"

    test_scenario_2
    echo "" | tee -a "$TEST_RESULTS_FILE"

    test_scenario_3
    echo "" | tee -a "$TEST_RESULTS_FILE"

    # Print summary
    print_separator
    echo "TEST SUMMARY" | tee -a "$TEST_RESULTS_FILE"
    print_separator

    local pass_count=0
    local fail_count=0

    for key in "${!TEST_RESULTS[@]}"; do
        result="${TEST_RESULTS[$key]}"
        if [[ "$result" == "PASS" ]]; then
            echo -e "${GREEN}✓${NC} $key: PASS" | tee -a "$TEST_RESULTS_FILE"
            pass_count=$((pass_count + 1))
        else
            echo -e "${RED}✗${NC} $key: FAIL" | tee -a "$TEST_RESULTS_FILE"
            fail_count=$((fail_count + 1))
        fi
    done

    echo "" | tee -a "$TEST_RESULTS_FILE"
    echo "Total: $pass_count passed, $fail_count failed" | tee -a "$TEST_RESULTS_FILE"

    log "Results saved to: $TEST_RESULTS_FILE"

    # Clean up
    print_separator
    if ask_cleanup; then
        log "Cleaning up Docker environment..."
        clean_docker
        log "Cleanup completed"
    else
        log "Skipping cleanup - containers left running for inspection"
    fi

    if [ $fail_count -eq 0 ]; then
        log_success "All tests passed!" "overall"
        exit 0
    else
        log_fail "Some tests failed - see details above" "overall"
        exit 1
    fi
}

ask_cleanup() {
    read -p "Clean up Docker containers? [y/N]: " answer
    case "$answer" in
        [Yy]* ) return 0;;
        * ) return 1;;
    esac
}

# Run main
main "$@"
