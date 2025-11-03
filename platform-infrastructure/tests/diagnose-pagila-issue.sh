#!/bin/bash
# Pagila Connectivity Diagnostic Script
# Purpose: Diagnose connectivity issues between test containers and Pagila database

set -e

# Find repo root and source formatting library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
source "$REPO_ROOT/platform-bootstrap/lib/formatting.sh"

print_header "Pagila Connectivity Diagnostics"

# Load configuration
PAGILA_DIR="$REPO_ROOT/../pagila"
ENV_FILE="$PAGILA_DIR/.env"

# Get configured settings
if [ -f "$ENV_FILE" ]; then
    POSTGRES_PASSWORD=$(grep '^POSTGRES_PASSWORD=' "$ENV_FILE" | cut -d'=' -f2- | tr -d '"' | tr -d "'")
    IMAGE_POSTGRES=$(grep '^IMAGE_POSTGRES=' "$ENV_FILE" | cut -d'=' -f2- | tr -d '"' | tr -d "'")
fi

# Get test container image from platform-bootstrap
PLATFORM_ENV="$REPO_ROOT/platform-bootstrap/.env"
if [ -f "$PLATFORM_ENV" ]; then
    IMAGE_POSTGRES_TEST=$(grep '^IMAGE_POSTGRES_TEST=' "$PLATFORM_ENV" | cut -d'=' -f2- | tr -d '"' | tr -d "'")
fi

# Defaults
IMAGE_POSTGRES="${IMAGE_POSTGRES:-postgres:17}"
IMAGE_POSTGRES_TEST="${IMAGE_POSTGRES_TEST:-platform/postgres-test:latest}"

print_section "Configuration"
print_info "Pagila directory: ${PAGILA_DIR}"
print_info "Pagila PostgreSQL image: $IMAGE_POSTGRES"
print_info "Test container image: $IMAGE_POSTGRES_TEST"
print_info "Password configured: $([ -n "$POSTGRES_PASSWORD" ] && echo "Yes" || echo "No (trust auth)")"

print_section "Container Status"

# Check if containers exist and are running
for container in postgres-test pagila-postgres; do
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
            print_info "  Pagila database may still be restoring data"
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

print_section "Pagila Database Status"

# Check if Pagila database exists
if docker ps --filter "name=pagila-postgres" --format '{{.Names}}' | grep -q '^pagila-postgres$'; then
    print_info "Checking Pagila database..."

    # Check if database exists
    if docker exec pagila-postgres psql -U postgres -lqt 2>/dev/null | cut -d \| -f 1 | grep -qw pagila; then
        print_check "PASS" "Pagila database exists"

        # Check table count
        TABLE_COUNT=$(docker exec pagila-postgres psql -U postgres -d pagila -t -c "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='public'" 2>/dev/null || echo "0")
        print_info "  Tables in database: $TABLE_COUNT"

        # Check if restoration is complete (should have 23 tables)
        if [ "$TABLE_COUNT" -eq "23" ]; then
            print_check "PASS" "Database fully restored (23 tables)"
        elif [ "$TABLE_COUNT" -gt "0" ]; then
            print_warning "  Database partially restored ($TABLE_COUNT/23 tables)"
            print_info "  Restoration may still be in progress"
        else
            print_error "  No tables found - restoration may have failed"
        fi
    else
        print_check "FAIL" "Pagila database does not exist"
        print_info "  Database may still be creating/restoring"
    fi
fi

print_section "Network Configuration"

# Check if platform_network exists
if docker network ls --format '{{.Name}}' | grep -q '^platform_network$'; then
    print_check "PASS" "platform_network exists"

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

# Only run tests if both containers are running
if docker ps --filter "name=postgres-test" --format '{{.Names}}' | grep -q '^postgres-test$' && \
   docker ps --filter "name=pagila-postgres" --format '{{.Names}}' | grep -q '^pagila-postgres$'; then

    print_info "Testing connectivity from postgres-test to pagila-postgres..."

    # Test 1: DNS Resolution
    if docker exec postgres-test nslookup pagila-postgres 2>&1 | grep -q "can't resolve"; then
        print_check "FAIL" "Cannot resolve pagila-postgres"
    else
        IP=$(docker exec postgres-test nslookup pagila-postgres 2>&1 | grep "Address" | tail -1 | awk '{print $2}')
        print_check "PASS" "Can resolve pagila-postgres to $IP"
    fi

    # Test 2: PostgreSQL connectivity
    print_info "Testing PostgreSQL connectivity..."

    # Export password for psql
    export PGPASSWORD="$POSTGRES_PASSWORD"

    if docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" postgres-test \
        psql -h pagila-postgres -U postgres -d postgres -c 'SELECT 1' >/dev/null 2>&1; then
        print_check "PASS" "Can connect to PostgreSQL"

        # Check if pagila database exists
        if docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" postgres-test \
            psql -h pagila-postgres -U postgres -d pagila -c 'SELECT 1' >/dev/null 2>&1; then
            print_check "PASS" "Can connect to Pagila database"
        else
            print_check "FAIL" "Cannot connect to Pagila database"
            ERROR=$(docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" postgres-test \
                psql -h pagila-postgres -U postgres -d pagila -c 'SELECT 1' 2>&1 | head -3)
            print_error "  Error: $ERROR"
        fi
    else
        print_check "FAIL" "Cannot connect to PostgreSQL"
        ERROR=$(docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" postgres-test \
            psql -h pagila-postgres -U postgres -d postgres -c 'SELECT 1' 2>&1 | head -3)
        print_error "  Error: $ERROR"
    fi

else
    print_warning "Cannot run connectivity tests - containers not running"
fi

print_section "Recommendations"

print_info "Based on the diagnostics above:"
echo ""

# Give specific recommendations based on what we found
if ! docker ps --filter "name=postgres-test" --format '{{.Names}}' | grep -q '^postgres-test$'; then
    print_error "1. postgres-test container is not running"
    print_info "   Fix: Run './platform setup' to create test containers"
fi

if ! docker ps --filter "name=pagila-postgres" --format '{{.Names}}' | grep -q '^pagila-postgres$'; then
    print_error "2. pagila-postgres container is not running"
    print_info "   Fix: Run 'make -C platform-bootstrap setup-pagila'"
fi

# Check if Pagila is still restoring
if docker ps --filter "name=pagila-postgres" --format '{{.Names}}' | grep -q '^pagila-postgres$'; then
    HEALTH_STATUS=$(docker inspect pagila-postgres --format '{{.State.Health.Status}}' 2>/dev/null || echo "unknown")
    if [ "$HEALTH_STATUS" = "starting" ]; then
        print_warning "3. Pagila is still initializing"
        print_info "   The database restore process can take 30-60 seconds"
        print_info "   Wait a moment and retry the test"
    fi
fi

if ! docker network ls --format '{{.Name}}' | grep -q '^platform_network$'; then
    print_error "4. platform_network does not exist"
    print_info "   Fix: Create it with: docker network create platform_network"
fi

print_divider
echo ""
print_success "Diagnostics complete!"