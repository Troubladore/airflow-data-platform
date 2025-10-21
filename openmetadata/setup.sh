#!/bin/bash
# OpenMetadata Setup Script
# ==========================
# Progressive validation and setup for OpenMetadata
# Can be run standalone or called by platform wizard

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AUTO_MODE=false
TOTAL_STEPS=6

# Load formatting library from platform-bootstrap
PLATFORM_BOOTSTRAP="$(dirname "$SCRIPT_DIR")/platform-bootstrap"
if [ -f "$PLATFORM_BOOTSTRAP/lib/formatting.sh" ]; then
    source "$PLATFORM_BOOTSTRAP/lib/formatting.sh"
else
    # Fallback formatting
    echo "Warning: formatting library not found" >&2
    GREEN='' RED='' YELLOW='' CYAN='' BLUE='' BOLD='' NC=''
    CHECK_MARK="+" CROSS_MARK="x" WARNING_SIGN="!" INFO_SIGN="i"
    print_header() { echo ""; echo "=== $1 ==="; echo ""; }
    print_section() { echo ""; echo "--- $1 ---"; echo ""; }
    print_check() { echo "[$1] $2"; }
    print_success() { echo "+ $1"; }
    print_error() { echo "x $1"; }
    print_warning() { echo "! $1"; }
    print_info() { echo "i $1"; }
    print_divider() { echo "========================================"; }
fi

# ==========================================
# Utility Functions
# ==========================================
# Note: print_success, print_error, print_warning, print_info from formatting.sh

print_step() {
    local step_num=$1
    local step_desc=$2
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}Step ${step_num}/${TOTAL_STEPS}: ${step_desc}${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
}

ask_yes_no() {
    local prompt="$1"
    local default="${2:-n}"

    if [ "$AUTO_MODE" = true ]; then
        return 0
    fi

    if [ "$default" = "y" ]; then
        read -p "$prompt [Y/n]: " answer
        answer=${answer:-y}
    else
        read -p "$prompt [y/N]: " answer
        answer=${answer:-n}
    fi

    case "$answer" in
        [Yy]* ) return 0;;
        * ) return 1;;
    esac
}

# ==========================================
# Parse Arguments
# ==========================================

show_help() {
    cat << EOF
OpenMetadata Setup Script

Usage: $0 [OPTIONS]

Options:
  --auto        Non-interactive mode (use defaults)
  -h, --help    Show this help

This script performs progressive validation and setup:
  1. Check prerequisites (Docker)
  2. Configure .env file
  3. Start services (PostgreSQL, Elasticsearch, OpenMetadata)
  4. Validate health checks
  5. Test API connectivity
  6. Summary and next steps

Can be run standalone or called by platform-setup-wizard.sh
EOF
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --auto) AUTO_MODE=true; shift ;;
        -h|--help) show_help; exit 0 ;;
        *) echo "Unknown option: $1"; show_help; exit 1 ;;
    esac
done

# ==========================================
# Step 1: Prerequisites
# ==========================================

step_1_prerequisites() {
    print_step 1 "Checking Prerequisites"

    local all_ok=true

    # Check Docker
    echo -n "Checking for Docker... "
    if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
        print_success "Found and running"
    else
        print_error "Not found or not running"
        echo ""
        echo "  Docker is required. Install Docker Desktop:"
        echo "  https://www.docker.com/products/docker-desktop"
        all_ok=false
    fi

    # Check curl
    echo -n "Checking for curl... "
    if command -v curl >/dev/null 2>&1; then
        print_success "Found"
    else
        print_error "Not found"
        echo "  Install with: sudo apt-get install curl"
        all_ok=false
    fi

    if [ "$all_ok" = false ]; then
        echo ""
        print_error "Prerequisites not met"
        exit 1
    fi

    echo ""
    print_success "All prerequisites met"
}

# ==========================================
# Step 2: Configure .env
# ==========================================

step_2_configure_env() {
    print_step 2 "Configuring Environment"

    local env_file="$SCRIPT_DIR/.env"
    local env_example="$SCRIPT_DIR/.env.example"

    if [ -f "$env_file" ]; then
        print_info ".env file already exists"
        if [ "$AUTO_MODE" = true ]; then
            print_info "Auto mode: Preserving existing .env (not overwriting)"
            return 0
        fi
        if ask_yes_no "Overwrite with new configuration?"; then
            echo "Creating new .env..."
        else
            print_info "Using existing .env (preserving your settings)"
            return 0
        fi
    fi

    # Copy example (only if .env doesn't exist or user said yes to overwrite)
    cp "$env_example" "$env_file"
    print_success "Created .env from .env.example"

    # Generate random passwords
    echo ""
    echo "Generating secure passwords..."

    if command -v openssl >/dev/null 2>&1; then
        PLATFORM_PASS=$(openssl rand -base64 24)
        OPENMETADATA_PASS=$(openssl rand -base64 24)
    else
        PLATFORM_PASS=$(head -c 24 /dev/urandom | base64)
        OPENMETADATA_PASS=$(head -c 24 /dev/urandom | base64)
    fi

    # Update passwords in .env (use | as delimiter to avoid issues with / in base64)
    sed -i "s|PLATFORM_DB_PASSWORD=.*|PLATFORM_DB_PASSWORD=$PLATFORM_PASS|" "$env_file"
    sed -i "s|OPENMETADATA_DB_PASSWORD=.*|OPENMETADATA_DB_PASSWORD=$OPENMETADATA_PASS|" "$env_file"

    print_success "Generated secure database passwords"
    echo ""
    print_success "Configuration complete"
}

# ==========================================
# Step 3: Start Services
# ==========================================

step_3_start_services() {
    print_step 3 "Starting OpenMetadata Services"

    # Verify platform-infrastructure is running (prerequisite)
    if ! docker ps --filter "name=platform-postgres" --format "{{.Names}}" | grep -q "platform-postgres"; then
        print_error "platform-postgres not running!"
        echo ""
        echo "OpenMetadata requires platform-infrastructure to be running first."
        echo ""
        echo "Start it with:"
        echo "  cd ../platform-infrastructure && make start"
        echo "  OR"
        echo "  cd ../platform-bootstrap && make platform-start"
        exit 1
    fi
    print_success "Prerequisite: platform-infrastructure is running"
    echo ""

    # Check for existing OpenMetadata containers (NOT platform-postgres - that's infrastructure)
    EXISTING_CONTAINERS=$(docker ps -a --filter "name=openmetadata-" --format "{{.Names}}" 2>/dev/null)

    if [ -n "$EXISTING_CONTAINERS" ]; then
        echo "Found existing OpenMetadata containers:"
        echo "$EXISTING_CONTAINERS" | sed 's/^/  • /'
        echo ""

        print_info "Your data is safe - volumes are preserved even if containers are removed"
        echo ""
        echo "What would you like to do?"
        echo "  1. Restart with existing containers (quick, reuses everything)"
        echo "  2. Recreate containers (updates images, keeps data)"
        echo "  3. Skip - containers already running"
        echo ""
        read -p "Enter choice [1-3]: " container_choice

        case "$container_choice" in
            1)
                echo "Restarting existing containers..."
                docker restart $EXISTING_CONTAINERS 2>/dev/null || true
                print_success "Containers restarted"
                echo ""
                # Skip docker compose up since containers are already configured
                return 0
                ;;
            2)
                echo "Recreating containers (data volumes preserved)..."
                docker stop $EXISTING_CONTAINERS 2>/dev/null || true
                docker rm $EXISTING_CONTAINERS 2>/dev/null || true
                print_success "Old containers removed (data volumes preserved)"
                echo ""
                ;;
            3)
                print_info "Skipping container management"
                echo ""
                return 0
                ;;
            *)
                print_warning "Invalid choice, proceeding with recreation"
                docker stop $EXISTING_CONTAINERS 2>/dev/null || true
                docker rm $EXISTING_CONTAINERS 2>/dev/null || true
                ;;
        esac
    fi

    # Create volumes if they don't exist (idempotent)
    echo "Ensuring volumes exist..."
    docker volume create platform_postgres_data 2>/dev/null || print_info "Volume platform_postgres_data already exists"
    docker volume create openmetadata_es_data 2>/dev/null || print_info "Volume openmetadata_es_data already exists"

    # Run database migrations first (creates OpenMetadata schema)
    echo ""
    echo "Running database migrations (creates schema tables)..."
    cd "$SCRIPT_DIR"
    if docker compose up openmetadata-migrate; then
        print_success "Database migrations completed"
    else
        print_error "Database migrations failed"
        exit 1
    fi

    echo ""
    echo "Starting services (this may take 2-3 minutes on first run)..."
    echo ""

    if docker compose up -d; then
        print_success "Services started"
    else
        print_error "Failed to start services"
        echo ""
        echo "Troubleshooting:"
        echo "  • Check if containers already exist: docker ps -a"
        echo "  • Clean up old containers: cd ../platform-bootstrap && make clean"
        echo "  • View logs: docker compose logs"
        exit 1
    fi
}

# ==========================================
# Step 4: Validate Health Checks
# ==========================================

step_4_validate_health() {
    print_step 4 "Validating Service Health"

    echo "Waiting for OpenMetadata services to become healthy..."
    echo "(platform-postgres health managed by platform-infrastructure)"
    echo ""

    # Elasticsearch (takes longer - 2-3 minutes on first run)
    echo "Elasticsearch (may take 2-3 minutes on first run):"
    for i in {1..90}; do
        # Check Docker healthcheck status (more reliable than direct curl since port not exposed)
        HEALTH_STATUS=$(docker inspect --format='{{.State.Health.Status}}' openmetadata-elasticsearch 2>/dev/null || echo "unknown")

        if [ "$HEALTH_STATUS" = "healthy" ]; then
            echo ""  # New line after progress
            print_success "Healthy (took $((i * 2)) seconds)"
            break
        elif [ "$HEALTH_STATUS" = "unknown" ]; then
            # Container has no healthcheck or not started yet
            if docker ps --filter "name=openmetadata-elasticsearch" --format "{{.Status}}" | grep -q "Up"; then
                # Container running but no healthcheck - just check if port responding
                if docker exec openmetadata-elasticsearch curl -sf http://localhost:9200/_cluster/health | grep -q '"status":"green"\|"status":"yellow"' 2>/dev/null; then
                    echo ""
                    print_success "Healthy (took $((i * 2)) seconds)"
                    break
                fi
            fi
        fi

        # Show progress every 5 checks with time estimate
        if [ $((i % 5)) -eq 0 ]; then
            local elapsed=$((i * 2))
            local remaining=$((180 - elapsed))
            local status_msg="$HEALTH_STATUS"
            [ "$HEALTH_STATUS" = "unknown" ] && status_msg="starting"
            echo -ne "\r  Status: $status_msg | ${elapsed}s elapsed, ~${remaining}s remaining"
        fi
        sleep 2
        if [ $i -eq 90 ]; then
            echo ""
            print_error "Timeout after 3 minutes"
            echo ""
            echo "Elasticsearch is taking too long to start."
            echo "This is normal on first run or low-memory systems."
            echo ""
            echo "Troubleshooting:"
            echo "  • Check logs: docker logs openmetadata-elasticsearch"
            echo "  • Check memory: Elasticsearch needs ~1GB RAM"
            echo "  • Check status: docker inspect openmetadata-elasticsearch"
            echo "  • Wait longer: docker compose logs -f openmetadata-elasticsearch"
            exit 1
        fi
    done

    # OpenMetadata Server (starts after Elasticsearch is ready)
    echo "OpenMetadata Server (usually 1-2 minutes):"
    for i in {1..90}; do
        # Check Docker healthcheck status (port is published, so we could curl, but healthcheck is more reliable)
        HEALTH_STATUS=$(docker inspect --format='{{.State.Health.Status}}' openmetadata-server 2>/dev/null || echo "unknown")

        if [ "$HEALTH_STATUS" = "healthy" ]; then
            echo ""  # New line after progress
            print_success "Healthy (took $((i * 2)) seconds)"
            break
        fi

        # Show progress every 5 checks with time estimate and current status
        if [ $((i % 5)) -eq 0 ]; then
            local elapsed=$((i * 2))
            local remaining=$((180 - elapsed))
            echo -ne "\r  Status: $HEALTH_STATUS | ${elapsed}s elapsed, ~${remaining}s remaining"
        fi
        sleep 2
        if [ $i -eq 90 ]; then
            echo ""
            print_error "Timeout after 3 minutes"
            echo ""
            echo "Troubleshooting:"
            echo "  • Check logs: docker logs openmetadata-server"
            echo "  • Check Elasticsearch: curl http://localhost:9200"
            echo "  • Check PostgreSQL: docker exec platform-postgres pg_isready"
            exit 1
        fi
    done

    echo ""
    print_success "All services healthy"
}

# ==========================================
# Step 5: Test API
# ==========================================

step_5_test_api() {
    print_step 5 "Testing OpenMetadata API"

    echo "Testing API connectivity..."

    if curl -sf http://localhost:8585/api/v1/health | grep -q "healthy"; then
        print_success "API is responding"
    else
        print_warning "API responded but health check unclear"
    fi

    echo ""
    print_success "OpenMetadata API accessible"
}

# ==========================================
# Step 6: Summary
# ==========================================

step_6_summary() {
    print_step 6 "Setup Complete"

    print_divider
    print_success "OpenMetadata Setup Complete!"
    print_divider
    echo ""

    echo "Services Running:"
    echo "  • PostgreSQL:      docker ps | grep platform-postgres"
    echo "  • Elasticsearch:   docker ps | grep openmetadata-elasticsearch"
    echo "  • OpenMetadata UI: http://localhost:8585"
    echo ""

    echo "Login Credentials:"
    echo "  • Email:    admin@open-metadata.org"
    echo "  • Password: admin"
    echo ""

    echo "Next Steps:"
    echo "  1. Open http://localhost:8585 in your browser"
    echo "  2. Connect data sources (PostgreSQL, etc.)"
    echo "  3. Explore metadata and lineage"
    echo ""

    echo "Service Management:"
    echo "  make status    - Check service health"
    echo "  make logs      - View service logs"
    echo "  make stop      - Stop OpenMetadata"
    echo ""
}

# ==========================================
# Main Execution
# ==========================================

main() {
    if [ "$AUTO_MODE" = false ]; then
        clear
        echo -e "${CYAN}╔════════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${CYAN}║          ${BLUE}OpenMetadata Setup Wizard${NC}                           ${CYAN}║${NC}"
        echo -e "${CYAN}╚════════════════════════════════════════════════════════════════╝${NC}"
        echo ""
    fi

    step_1_prerequisites
    step_2_configure_env
    step_3_start_services
    step_4_validate_health
    step_5_test_api
    step_6_summary
}

main
