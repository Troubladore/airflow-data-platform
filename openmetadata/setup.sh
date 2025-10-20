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
    print_success() { echo "+ $1"; }
    print_error() { echo "x $1"; }
    print_warning() { echo "! $1"; }
    print_info() { echo "i $1"; }
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
        if ask_yes_no "Overwrite with new configuration?"; then
            echo "Creating new .env..."
        else
            print_info "Using existing .env"
            return 0
        fi
    fi

    # Copy example
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

    # Update passwords in .env
    sed -i "s/PLATFORM_DB_PASSWORD=.*/PLATFORM_DB_PASSWORD=$PLATFORM_PASS/" "$env_file"
    sed -i "s/OPENMETADATA_DB_PASSWORD=.*/OPENMETADATA_DB_PASSWORD=$OPENMETADATA_PASS/" "$env_file"

    print_success "Generated secure database passwords"
    echo ""
    print_success "Configuration complete"
}

# ==========================================
# Step 3: Start Services
# ==========================================

step_3_start_services() {
    print_step 3 "Starting OpenMetadata Services"

    echo "Starting services (this may take 2-3 minutes on first run)..."
    echo ""

    cd "$SCRIPT_DIR"

    if docker compose up -d; then
        print_success "Services started"
    else
        print_error "Failed to start services"
        exit 1
    fi
}

# ==========================================
# Step 4: Validate Health Checks
# ==========================================

step_4_validate_health() {
    print_step 4 "Validating Service Health"

    echo "Waiting for services to become healthy..."
    echo ""

    # PostgreSQL
    echo -n "PostgreSQL: "
    for i in {1..30}; do
        if docker exec platform-postgres pg_isready -U platform_admin >/dev/null 2>&1; then
            print_success "Healthy"
            break
        fi
        sleep 2
        if [ $i -eq 30 ]; then
            print_error "Timeout"
            echo "Check logs: docker logs platform-postgres"
            exit 1
        fi
    done

    # Elasticsearch
    echo -n "Elasticsearch: "
    for i in {1..60}; do
        if curl -sf http://localhost:9200/_cluster/health >/dev/null 2>&1; then
            print_success "Healthy"
            break
        fi
        sleep 2
        if [ $i -eq 60 ]; then
            print_error "Timeout"
            echo "Check logs: docker logs openmetadata-elasticsearch"
            exit 1
        fi
    done

    # OpenMetadata Server
    echo -n "OpenMetadata Server: "
    for i in {1..90}; do
        if curl -sf http://localhost:8585/api/v1/health >/dev/null 2>&1; then
            print_success "Healthy"
            break
        fi
        sleep 2
        if [ $i -eq 90 ]; then
            print_error "Timeout"
            echo "Check logs: docker logs openmetadata-server"
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
