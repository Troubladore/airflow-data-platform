#!/bin/bash
# Network Connectivity Diagnostic Script
# Purpose: Diagnose connectivity issues between test containers and platform services

set -e

# Find repo root and source formatting library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
source "$REPO_ROOT/platform-bootstrap/lib/formatting.sh"

print_header "Network Connectivity Diagnostics"

# Load configuration from .env and platform-config.yaml
ENV_FILE="$REPO_ROOT/platform-bootstrap/.env"
CONFIG_FILE="$REPO_ROOT/platform-config.yaml"

# Get configured image names
if [ -f "$ENV_FILE" ]; then
    IMAGE_POSTGRES_TEST=$(grep '^IMAGE_POSTGRES_TEST=' "$ENV_FILE" | cut -d'=' -f2- | tr -d '"' | tr -d "'")
    IMAGE_SQLCMD_TEST=$(grep '^IMAGE_SQLCMD_TEST=' "$ENV_FILE" | cut -d'=' -f2- | tr -d '"' | tr -d "'")
    POSTGRES_TEST_PREBUILT=$(grep '^POSTGRES_TEST_PREBUILT=' "$ENV_FILE" | cut -d'=' -f2- | tr -d '"' | tr -d "'")
    SQLCMD_TEST_PREBUILT=$(grep '^SQLCMD_TEST_PREBUILT=' "$ENV_FILE" | cut -d'=' -f2- | tr -d '"' | tr -d "'")
fi

# Get postgres image from platform-config.yaml if available
if [ -f "$CONFIG_FILE" ]; then
    IMAGE_POSTGRES=$(grep -A2 "^  postgres:" "$CONFIG_FILE" | grep "image:" | sed 's/.*image: //' | tr -d '"' | tr -d "'")
fi

# Fallback to defaults if not configured
IMAGE_POSTGRES_TEST="${IMAGE_POSTGRES_TEST:-platform/postgres-test:latest}"
IMAGE_SQLCMD_TEST="${IMAGE_SQLCMD_TEST:-platform/sqlcmd-test:latest}"
IMAGE_POSTGRES="${IMAGE_POSTGRES:-postgres:17.5-alpine}"

print_section "Configuration"
print_info "Test Container Images:"
print_bullet "postgres-test: $IMAGE_POSTGRES_TEST (prebuilt: ${POSTGRES_TEST_PREBUILT:-false})"
print_bullet "sqlcmd-test: $IMAGE_SQLCMD_TEST (prebuilt: ${SQLCMD_TEST_PREBUILT:-false})"
print_bullet "platform-postgres: $IMAGE_POSTGRES"

print_section "Container Status"

# Check if containers exist and are running
for container in postgres-test sqlcmd-test platform-postgres; do
    if docker ps --filter "name=$container" --format '{{.Names}}' | grep -q "^$container$"; then
        print_check "PASS" "$container is running"
        # Get container details
        IMAGE=$(docker inspect $container --format '{{.Config.Image}}')
        NETWORK=$(docker inspect $container --format '{{range .NetworkSettings.Networks}}{{.NetworkID}}{{end}}' | cut -c1-12)
        IP=$(docker inspect $container --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}')
        HEALTH_STATUS=$(docker inspect $container --format '{{.State.Health.Status}}' 2>/dev/null || echo "N/A")
        print_info "  Image: $IMAGE"
        print_info "  Network ID: $NETWORK"
        print_info "  IP Address: $IP"
        print_info "  Health Status: $HEALTH_STATUS"

        # If unhealthy or starting, show additional info
        if [ "$HEALTH_STATUS" = "starting" ]; then
            print_warning "  Container is still initializing - this may cause connection failures"
        elif [ "$HEALTH_STATUS" = "unhealthy" ]; then
            print_error "  Container health check is failing"
            HEALTH_LOG=$(docker inspect $container --format '{{range .State.Health.Log}}{{.Output}}{{end}}' 2>/dev/null | head -1)
            if [ -n "$HEALTH_LOG" ]; then
                print_info "  Last health check output: $HEALTH_LOG"
            fi
        fi
    else
        print_check "FAIL" "$container is not running"
        # Check if it exists but stopped
        if docker ps -a --filter "name=$container" --format '{{.Names}}' | grep -q "^$container$"; then
            STATUS=$(docker inspect $container --format '{{.State.Status}}')
            print_warning "  Container exists but status is: $STATUS"
            # Check exit code if exited
            if [ "$STATUS" = "exited" ]; then
                EXIT_CODE=$(docker inspect $container --format '{{.State.ExitCode}}')
                print_error "  Exit code: $EXIT_CODE"
                print_info "  Last 10 logs:"
                docker logs --tail 10 $container 2>&1 | sed 's/^/    /'
            fi
        else
            print_error "  Container does not exist"
        fi
    fi
done

print_section "Network Configuration"

# Check if platform_network exists
if docker network ls --format '{{.Name}}' | grep -q '^platform_network$'; then
    print_check "PASS" "platform_network exists"

    # Get network details
    DRIVER=$(docker network inspect platform_network --format '{{.Driver}}')
    SUBNET=$(docker network inspect platform_network --format '{{range .IPAM.Config}}{{.Subnet}}{{end}}')
    print_info "  Driver: $DRIVER"
    print_info "  Subnet: $SUBNET"

    # Check which containers are connected
    print_info "  Connected containers:"
    docker network inspect platform_network --format '{{range $k, $v := .Containers}}{{$v.Name}} {{end}}' | tr ' ' '\n' | grep -v '^$' | while read container; do
        if [ -n "$container" ]; then
            print_bullet "$container"
        fi
    done
else
    print_check "FAIL" "platform_network does not exist"
    print_error "Create it with: docker network create platform_network"
fi

print_section "Connectivity Tests"

# Only run tests if postgres-test is running
if docker ps --filter "name=postgres-test" --format '{{.Names}}' | grep -q '^postgres-test$'; then

    # Test 1: DNS Resolution
    print_info "Testing DNS resolution from postgres-test..."
    for target in platform-postgres sqlcmd-test; do
        if docker exec postgres-test nslookup $target 2>&1 | grep -q "can't resolve"; then
            print_check "FAIL" "Cannot resolve $target"
        else
            IP=$(docker exec postgres-test nslookup $target 2>&1 | grep "Address" | tail -1 | awk '{print $2}')
            print_check "PASS" "Can resolve $target to $IP"
        fi
    done

    # Test 2: Network Connectivity (using nc or telnet if available)
    print_info "Testing network connectivity..."

    # Check what tools are available
    HAS_NC=$(docker exec postgres-test which nc 2>/dev/null && echo "yes" || echo "no")
    HAS_TELNET=$(docker exec postgres-test which telnet 2>/dev/null && echo "yes" || echo "no")
    HAS_PING=$(docker exec postgres-test which ping 2>/dev/null && echo "yes" || echo "no")

    print_info "Available tools: nc=$HAS_NC, telnet=$HAS_TELNET, ping=$HAS_PING"

    if [ "$HAS_NC" = "yes" ]; then
        # Use nc to test port connectivity
        if docker exec postgres-test nc -zv platform-postgres 5432 2>&1 | grep -q "succeeded\|open"; then
            print_check "PASS" "Port 5432 on platform-postgres is reachable"
        else
            print_check "FAIL" "Port 5432 on platform-postgres is not reachable"
        fi
    elif [ "$HAS_PING" = "yes" ]; then
        # Fall back to ping
        if docker exec postgres-test ping -c 1 -W 2 platform-postgres >/dev/null 2>&1; then
            print_check "PASS" "Can ping platform-postgres (but can't test port)"
        else
            print_check "FAIL" "Cannot ping platform-postgres"
        fi
    else
        print_warning "No network testing tools available in container"
    fi

    # Test 3: PostgreSQL connectivity
    print_info "Testing PostgreSQL connectivity..."

    # Get password from .env
    ENV_FILE="$REPO_ROOT/platform-bootstrap/.env"
    if [ -f "$ENV_FILE" ]; then
        POSTGRES_PASSWORD=$(grep '^POSTGRES_PASSWORD=' "$ENV_FILE" | cut -d'=' -f2- | tr -d '"' | tr -d "'")
    else
        POSTGRES_PASSWORD=""
    fi

    # Try with both users
    for USER in platform_admin postgres; do
        if docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" postgres-test \
            psql -h platform-postgres -U $USER -d postgres -c 'SELECT 1' >/dev/null 2>&1; then
            print_check "PASS" "Can connect to PostgreSQL as $USER"
            break
        else
            print_check "FAIL" "Cannot connect to PostgreSQL as $USER"
            # Get detailed error
            ERROR=$(docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" postgres-test \
                psql -h platform-postgres -U $USER -d postgres -c 'SELECT 1' 2>&1 | head -3)
            print_error "  Error: $ERROR"
        fi
    done

else
    print_warning "postgres-test container not running, skipping connectivity tests"
fi

print_section "Docker Network Debugging"

# Additional docker network debugging
print_info "Checking for network isolation or firewall issues..."

# Check if containers can see each other
if docker ps --filter "name=postgres-test" --format '{{.Names}}' | grep -q '^postgres-test$' && \
   docker ps --filter "name=platform-postgres" --format '{{.Names}}' | grep -q '^platform-postgres$'; then

    # Get container IPs
    POSTGRES_TEST_IP=$(docker inspect postgres-test --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}')
    PLATFORM_POSTGRES_IP=$(docker inspect platform-postgres --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}')

    print_info "Container IPs:"
    print_bullet "postgres-test: $POSTGRES_TEST_IP"
    print_bullet "platform-postgres: $PLATFORM_POSTGRES_IP"

    # Check if they're on the same network
    POSTGRES_TEST_NETWORKS=$(docker inspect postgres-test --format '{{range $k, $v := .NetworkSettings.Networks}}{{$k}} {{end}}')
    PLATFORM_POSTGRES_NETWORKS=$(docker inspect platform-postgres --format '{{range $k, $v := .NetworkSettings.Networks}}{{$k}} {{end}}')

    print_info "Networks:"
    print_bullet "postgres-test networks: $POSTGRES_TEST_NETWORKS"
    print_bullet "platform-postgres networks: $PLATFORM_POSTGRES_NETWORKS"

    # Check for common network
    for net in $POSTGRES_TEST_NETWORKS; do
        if echo "$PLATFORM_POSTGRES_NETWORKS" | grep -q "$net"; then
            print_check "PASS" "Both containers share network: $net"
        fi
    done
fi

print_section "Recommendations"

print_info "Based on the diagnostics above:"
echo ""

# Give specific recommendations based on what we found
if ! docker ps --filter "name=postgres-test" --format '{{.Names}}' | grep -q '^postgres-test$'; then
    print_error "1. postgres-test container is not running"
    print_info "   Fix: Ensure the custom image exists and can run 'sleep infinity'"
    print_info "   Test: docker run --rm custom/postgres-conn-test:v1 sleep 10"
fi

if ! docker ps --filter "name=platform-postgres" --format '{{.Names}}' | grep -q '^platform-postgres$'; then
    print_error "2. platform-postgres container is not running"
    print_info "   Fix: Start it with: make -C platform-infrastructure start"
fi

if ! docker network ls --format '{{.Name}}' | grep -q '^platform_network$'; then
    print_error "3. platform_network does not exist"
    print_info "   Fix: Create it with: docker network create platform_network"
fi

print_divider
echo ""
print_success "Diagnostics complete!"