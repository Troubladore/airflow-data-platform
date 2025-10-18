#!/bin/bash
# Cleanup OpenMetadata Services
# ==============================
# Purpose: Remove OpenMetadata containers and optionally volumes
# Safe: Prompts before removing data volumes (cataloged metadata is valuable!)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLATFORM_DIR="$(dirname "$SCRIPT_DIR")"

# Load formatting library
if [ -f "$PLATFORM_DIR/lib/formatting.sh" ]; then
    source "$PLATFORM_DIR/lib/formatting.sh"
else
    print_info() { echo "[INFO] $1"; }
    print_success() { echo "[SUCCESS] $1"; }
    print_warning() { echo "[WARNING] $1"; }
    print_error() { echo "[ERROR] $1"; }
fi

# Parse arguments
AUTO_YES=false
REMOVE_VOLUMES=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -y|--yes) AUTO_YES=true; shift ;;
        --remove-volumes) REMOVE_VOLUMES=true; shift ;;
        --help|-h)
            echo "Cleanup OpenMetadata Services"
            echo ""
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  -y, --yes            Auto-yes to prompts"
            echo "  --remove-volumes     Remove data volumes (WARNING: loses cataloged metadata!)"
            echo "  -h, --help           Show this help"
            echo ""
            echo "Examples:"
            echo "  $0                   # Interactive (asks about volumes)"
            echo "  $0 -y                # Stop services, keep volumes"
            echo "  $0 --remove-volumes  # Remove everything including data"
            exit 0
            ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

ask_yes_no() {
    if [ "$AUTO_YES" = true ]; then
        return 0
    fi
    local prompt="$1"
    read -p "$prompt [y/N]: " -n 1 -r
    echo
    [[ $REPLY =~ ^[Yy]$ ]]
}

echo "OpenMetadata Cleanup"
echo "===================="
echo ""

# Check if OpenMetadata is running
if ! docker ps --format '{{.Names}}' | grep -qE "(openmetadata-server|platform-postgres|openmetadata-elasticsearch)"; then
    print_info "OpenMetadata services are not running"

    # Check for stopped containers
    if docker ps -a --format '{{.Names}}' | grep -qE "(openmetadata-server|platform-postgres)"; then
        print_info "Found stopped OpenMetadata containers"
    else
        print_info "No OpenMetadata containers found"
        echo "Nothing to clean up."
        exit 0
    fi
fi

# Determine what to remove
if [ "$REMOVE_VOLUMES" = true ]; then
    REMOVE_VOLS=true
else
    if [ "$AUTO_YES" = false ]; then
        echo "This will stop OpenMetadata services (containers removed, data preserved)."
        echo ""
        print_warning "OpenMetadata data volumes contain your cataloged metadata:"
        echo "  - Database services you've configured"
        echo "  - Table metadata you've ingested"
        echo "  - Descriptions and tags you've added"
        echo "  - Elasticsearch indices"
        echo ""

        if ask_yes_no "Also remove data volumes? (WARNING: This deletes your catalog work!)"; then
            REMOVE_VOLS=true
        else
            REMOVE_VOLS=false
        fi
    else
        # Auto-yes mode: keep volumes by default (safe)
        REMOVE_VOLS=false
    fi
fi

echo ""
print_info "Stopping OpenMetadata services..."

# Stop using docker compose
cd "$PLATFORM_DIR"

if [ "$REMOVE_VOLS" = true ]; then
    print_warning "Removing containers AND volumes (data will be lost!)"
    docker compose -f docker-compose.yml -f docker-compose.openmetadata.yml down -v

    echo ""
    print_success "OpenMetadata completely removed (including data)"
    echo ""
    print_info "Removed:"
    echo "  ✓ openmetadata-server container"
    echo "  ✓ platform-postgres container"
    echo "  ✓ openmetadata-elasticsearch container"
    echo "  ✓ platform_postgres_data volume (metadata lost!)"
    echo "  ✓ openmetadata_es_data volume (indices lost!)"
else
    print_info "Removing containers (keeping data volumes)"
    docker compose -f docker-compose.yml -f docker-compose.openmetadata.yml down

    echo ""
    print_success "OpenMetadata services stopped (data preserved)"
    echo ""
    print_info "Removed:"
    echo "  ✓ openmetadata-server container"
    echo "  ✓ platform-postgres container"
    echo "  ✓ openmetadata-elasticsearch container"
    echo ""
    print_info "Preserved:"
    echo "  ✓ platform_postgres_data volume (your cataloged metadata)"
    echo "  ✓ openmetadata_es_data volume (search indices)"
    echo ""
    print_info "To remove data volumes later: $0 --remove-volumes"
fi

echo ""
print_info "To restart: make platform-start"
