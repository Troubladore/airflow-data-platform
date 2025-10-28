#!/bin/bash
# PostgreSQL Startup Diagnostic Script
# =====================================
# Use this when PostgreSQL fails to start with corporate images

set -e

# Find repo root and source formatting library
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${REPO_ROOT}/platform-bootstrap/lib/formatting.sh"

print_header "PostgreSQL Startup Diagnostics"
echo ""

# 1. Check Docker status
print_section "1. Docker Environment"
docker version --format 'Docker Version: {{.Server.Version}}' 2>/dev/null || print_error "Docker not running!"
echo ""

# 2. Check configured image
print_section "2. Configuration"
if [ -f platform-config.yaml ]; then
    echo "platform-config.yaml:"
    grep -A 5 "postgres:" platform-config.yaml | sed 's/^/  /'
else
    print_error "platform-config.yaml not found"
fi
echo ""

if [ -f platform-bootstrap/.env ]; then
    echo "platform-bootstrap/.env (PostgreSQL settings):"
    grep -E "POSTGRES|PLATFORM_DB|IMAGE_POSTGRES" platform-bootstrap/.env | sed 's/^/  /' || echo "  No PostgreSQL settings found"

    # Check for no-password mode
    if grep -q "PLATFORM_DB_PASSWORD=$" platform-bootstrap/.env || grep -q "PLATFORM_DB_PASSWORD=\"\"" platform-bootstrap/.env; then
        print_info "No-password mode detected (trust authentication)"
    fi
else
    print_error "platform-bootstrap/.env not found"
fi
echo ""

# 3. Check if image exists
print_section "3. Docker Image Status"
IMAGE_POSTGRES=$(grep -E "IMAGE_POSTGRES=" platform-bootstrap/.env 2>/dev/null | cut -d= -f2 || echo "postgres:17.5-alpine")
if [ -z "$IMAGE_POSTGRES" ]; then
    IMAGE_POSTGRES="postgres:17.5-alpine"
fi
print_info "Image configured: $IMAGE_POSTGRES"

if docker image inspect "$IMAGE_POSTGRES" >/dev/null 2>&1; then
    print_check "PASS" "Image exists locally"
    echo "Image details:"
    docker image inspect "$IMAGE_POSTGRES" --format '  Size: {{.Size}} bytes' 2>/dev/null
    docker image inspect "$IMAGE_POSTGRES" --format '  Created: {{.Created}}' 2>/dev/null
    docker image inspect "$IMAGE_POSTGRES" --format '  ID: {{.Id}}' 2>/dev/null | cut -c1-20
else
    print_check "FAIL" "Image NOT found locally"
    echo "  Will need to pull from registry"
fi
echo ""

# 4. Check existing containers
print_section "4. Container Status"
if docker ps -a --format '{{.Names}}' | grep -q "^platform-postgres$"; then
    echo "platform-postgres container found:"
    docker ps -a --format "table {{.Names}}\t{{.Status}}\t{{.State}}" | grep platform-postgres || true

    # Check logs if container exists
    echo ""
    echo "Last 10 lines of container logs:"
    docker logs platform-postgres --tail 10 2>&1 | sed 's/^/  /' || echo "  Could not get logs"
else
    print_warning "No platform-postgres container exists"
    echo "  Container was never created - likely docker-compose issue"
fi
echo ""

# 5. Check Docker volumes
print_section "5. Docker Volumes"
if docker volume ls | grep -q platform_postgres_data; then
    print_check "PASS" "platform_postgres_data volume exists"
    docker volume inspect platform_postgres_data --format '  Driver: {{.Driver}}' 2>/dev/null || true
else
    print_info "platform_postgres_data volume not found (will be created on first start)"
fi
echo ""

# 6. Check network
print_section "6. Docker Network"
if docker network ls | grep -q platform_network; then
    print_check "PASS" "platform_network exists"
else
    print_warning "platform_network not found (will be created)"
fi
echo ""

# 7. Validate docker-compose.yml
print_section "7. Docker Compose Validation"
cd platform-infrastructure 2>/dev/null || { print_error "platform-infrastructure directory not found"; exit 1; }

echo "Validating docker-compose.yml syntax..."
if docker compose config --quiet 2>&1; then
    print_check "PASS" "docker-compose.yml is valid"
else
    print_check "FAIL" "docker-compose.yml has errors"
    echo "Validation output:"
    docker compose config 2>&1 | head -20 | sed 's/^/  /'
fi
echo ""

# 8. Try a dry-run
print_section "8. Docker Compose Dry Run"
echo "Testing what would happen (without starting)..."
docker compose config 2>&1 | grep -A 5 "platform-postgres:" | sed 's/^/  /'
echo ""

# 9. Try to start with verbose output
print_section "9. Attempting Verbose Start"
print_info "Running: docker compose up -d"
echo ""

# Capture both stdout and stderr
docker compose up -d 2>&1 | tee /tmp/postgres-start.log

if [ ${PIPESTATUS[0]} -eq 0 ]; then
    echo ""
    print_success "PostgreSQL started successfully!"

    # Wait a moment for container to initialize
    sleep 2

    # Check if container is actually running
    if docker ps | grep -q platform-postgres; then
        print_check "PASS" "Container is running"
    else
        print_check "FAIL" "Container exited immediately after start"
        echo "Container logs:"
        docker logs platform-postgres --tail 20 2>&1 | sed 's/^/  /'
    fi
else
    echo ""
    print_error "PostgreSQL failed to start"
    echo ""
    echo "Full log saved to: /tmp/postgres-start.log"

    # Parse specific errors
    print_section "Error Analysis"

    if grep -q "pull access denied" /tmp/postgres-start.log; then
        print_bullet "Pull access denied - Image requires authentication"
        print_info "  Solution: docker login <registry>"
    fi

    if grep -q "manifest unknown" /tmp/postgres-start.log; then
        print_bullet "Image not found in registry"
        print_info "  Verify image name and tag are correct"
        print_info "  Image: $IMAGE_POSTGRES"
    fi

    if grep -q "toomanyrequests" /tmp/postgres-start.log; then
        print_bullet "Docker Hub rate limit exceeded"
        print_info "  Solution: Wait or use docker login for higher limits"
    fi

    if grep -q "address already in use" /tmp/postgres-start.log; then
        print_bullet "Port 5432 already in use"
        print_info "  Check: lsof -i :5432 or ss -tulpn | grep 5432"
    fi

    if grep -q "permission denied" /tmp/postgres-start.log; then
        print_bullet "Permission issue with volumes or files"
        print_info "  Check Docker daemon permissions"
        print_info "  Check volume ownership"
    fi

    if grep -q "no space left" /tmp/postgres-start.log; then
        print_bullet "Disk space issue"
        print_info "  Check: df -h"
        print_info "  Clean Docker: docker system prune"
    fi

    # Check for corporate registry issues
    if echo "$IMAGE_POSTGRES" | grep -q '/'; then
        print_section "Corporate Registry Checks"
        print_info "Using corporate image: $IMAGE_POSTGRES"

        # Extract registry from image
        REGISTRY=$(echo "$IMAGE_POSTGRES" | cut -d'/' -f1)
        print_info "Registry: $REGISTRY"

        # Test connectivity
        if command -v nc >/dev/null 2>&1; then
            if echo "$REGISTRY" | grep -q ':'; then
                HOST=$(echo "$REGISTRY" | cut -d':' -f1)
                PORT=$(echo "$REGISTRY" | cut -d':' -f2)
            else
                HOST=$REGISTRY
                PORT=443
            fi

            if nc -zv -w2 "$HOST" "$PORT" 2>&1 | grep -q succeeded; then
                print_check "PASS" "Registry is reachable"
            else
                print_check "FAIL" "Cannot reach registry $HOST:$PORT"
                print_info "  Check network/firewall settings"
            fi
        fi
    fi
fi

echo ""
print_divider
echo "Diagnostic Complete"
print_divider
echo ""
echo "If PostgreSQL still fails to start, please share:"
print_bullet "This diagnostic output"
print_bullet "The file: /tmp/postgres-start.log"
print_bullet "Your platform-config.yaml"
print_bullet "Your platform-bootstrap/.env (remove passwords first)"
echo ""
print_info "For manual debugging:"
print_info "  cd platform-infrastructure"
print_info "  docker compose up (without -d to see real-time output)"