#!/bin/bash
# Setup Pagila Test Database
# ===========================
# Purpose: Install and configure pagila PostgreSQL sample database
# Idempotent: Yes (safe to run multiple times)
# Prerequisites: Docker running, platform_network exists
# Corporate: Respects IMAGE_POSTGRES from .env for Artifactory support

set -e

# ==========================================
# Configuration
# ==========================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLATFORM_DIR="$(dirname "$SCRIPT_DIR")"
# Pagila repository URL - configurable for corporate environments
# Can be overridden in .env with PAGILA_REPO_URL
PAGILA_REPO_URL_DEFAULT="https://github.com/Troubladore/pagila.git"
PAGILA_DIR="$(dirname "$(dirname "$PLATFORM_DIR")")/pagila"
CONTAINER_NAME="pagila"  # Matches docker-compose.yml service name

# ==========================================
# Source Libraries
# ==========================================

# Load formatting library
if [ -f "$PLATFORM_DIR/lib/formatting.sh" ]; then
    source "$PLATFORM_DIR/lib/formatting.sh"
else
    # Fallback formatting
    echo "Warning: formatting library not found" >&2
    print_check() { echo "[$1] $2"; }
    print_header() { echo "=== $1 ==="; }
    print_success() { echo "[SUCCESS] $1"; }
    print_error() { echo "[ERROR] $1"; }
    print_info() { echo "[INFO] $1"; }
    print_warning() { echo "[WARNING] $1"; }
    GREEN='' RED='' YELLOW='' CYAN='' NC=''
fi

# Load .env for corporate configuration
if [ -f "$PLATFORM_DIR/.env" ]; then
    source "$PLATFORM_DIR/.env"
fi

# Set pagila repo URL (allow .env override for corporate git servers)
PAGILA_REPO_URL="${PAGILA_REPO_URL:-$PAGILA_REPO_URL_DEFAULT}"

# ==========================================
# Parse Arguments
# ==========================================

AUTO_YES=false
RESET=false

show_help() {
    cat << EOF
Pagila Test Database Setup

Usage: $0 [OPTIONS]

Options:
  -y, --yes     Auto-yes to all prompts
  --reset       Remove existing pagila and reinstall
  -h, --help    Show this help

This script:
  1. Clones pagila repository (configurable URL)
  2. Starts pagila PostgreSQL container
  3. Loads sample schema and data
  4. Connects to platform_network

Corporate Environment:
  Set variables in .env for corporate infrastructure:
    IMAGE_POSTGRES=artifactory.company.com/docker-remote/library/postgres:17.5-alpine
    PAGILA_REPO_URL=https://git.company.com/forks/pagila.git

Examples:
  $0                     # Interactive setup
  $0 --yes               # Non-interactive
  $0 --reset             # Clean reinstall

EOF
}

while [[ $# -gt 0 ]]; do
    case $1 in
        -y|--yes) AUTO_YES=true; shift ;;
        --reset) RESET=true; shift ;;
        -h|--help) show_help; exit 0 ;;
        *) echo "Unknown option: $1"; show_help; exit 1 ;;
    esac
done

# Helper for yes/no prompts
ask_yes_no() {
    if [ "$AUTO_YES" = true ]; then
        return 0
    fi
    local prompt="$1"
    read -p "$prompt [y/N]: " -n 1 -r
    echo
    [[ $REPLY =~ ^[Yy]$ ]]
}

# ==========================================
# Main Setup
# ==========================================

print_header "Pagila Test Database Setup"
echo ""

# Check Docker is running
if ! docker info >/dev/null 2>&1; then
    print_error "Docker is not running"
    echo "Start Docker and try again"
    exit 1
fi

print_check "PASS" "Docker is running"

# Check for platform network
if ! docker network inspect platform_network >/dev/null 2>&1; then
    print_warning "platform_network not found"
    print_info "Creating network..."
    docker network create platform_network
    print_success "Network created"
fi

print_check "PASS" "platform_network exists"
echo ""

# ==========================================
# Handle Reset
# ==========================================

if [ "$RESET" = true ]; then
    print_warning "Reset mode: Removing existing pagila setup"
    echo ""

    # Stop and remove container
    if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        print_info "Removing container: $CONTAINER_NAME"
        docker rm -f "$CONTAINER_NAME" 2>/dev/null || true
    fi

    # Remove volume
    if docker volume ls --format '{{.Name}}' | grep -q "^pagila_data$"; then
        print_info "Removing volume: pagila_data"
        docker volume rm pagila_data 2>/dev/null || true
    fi

    # Remove directory
    if [ -d "$PAGILA_DIR" ]; then
        print_info "Removing directory: $PAGILA_DIR"
        rm -rf "$PAGILA_DIR"
    fi

    print_success "Cleanup complete"
    echo ""
fi

# ==========================================
# Clean Up Old Pagila Resources (Defensive)
# ==========================================

print_info "Checking for old pagila resources (from previous setups)..."

OLD_RESOURCES_FOUND=false

# Check for old container with different name (before we renamed to pagila-postgres)
if docker ps -a --format '{{.Names}}' | grep -q "^pagila$"; then
    print_warning "Found old 'pagila' container (previous naming convention)"
    OLD_RESOURCES_FOUND=true
fi

# Check for old volumes with various naming patterns
for vol in "pagila_pgdata" "pagila-pgdata" "pgdata"; do
    if docker volume ls --format '{{.Name}}' | grep -q "^${vol}$"; then
        print_warning "Found old volume: $vol"
        OLD_RESOURCES_FOUND=true
    fi
done

if [ "$OLD_RESOURCES_FOUND" = true ]; then
    echo ""
    print_warning "Detected pagila Docker resources from previous setup"
    print_info "These should be cleaned up to avoid conflicts with new naming/configuration"
    echo ""

    if ask_yes_no "Clean up old pagila Docker resources now?"; then
        print_info "Removing old containers..."
        docker rm -f pagila 2>/dev/null || true
        docker rm -f pagila-postgres 2>/dev/null || true
        docker rm -f pagila-jsonb-restore 2>/dev/null || true

        print_info "Removing old volumes..."
        docker volume rm pagila_pgdata 2>/dev/null || true
        docker volume rm pagila-pgdata 2>/dev/null || true
        docker volume rm pgdata 2>/dev/null || true

        print_success "Old resources cleaned up"
        echo ""
        print_info "Fresh pagila installation will proceed..."
    else
        print_warning "Proceeding with old resources present"
        print_info "If issues occur, run: $0 --reset"
    fi
fi

echo ""

# ==========================================
# Clone Pagila Repository
# ==========================================

print_header "Pagila Repository Management"
echo ""
print_info "📌 Pagila is managed as a separate repository (clean architecture)"
print_info "Repository: $PAGILA_REPO_URL"

# Show if using corporate or public URL
if [[ "$PAGILA_REPO_URL" != "$PAGILA_REPO_URL_DEFAULT" ]]; then
    print_info "(Corporate git server - configured in .env)"
elif [[ "$PAGILA_REPO_URL" == *"github.com"* ]]; then
    print_info "(Public GitHub - default)"
fi

print_info "Location: $PAGILA_DIR"
print_info ""
print_info "This script automatically manages the pagila sibling repo."
print_info "You don't need to clone it manually - it's handled for you!"
echo ""

print_info "Checking for pagila repository..."

if [ -d "$PAGILA_DIR" ]; then
    print_check "PASS" "Pagila directory exists: $PAGILA_DIR"

    if ask_yes_no "Update pagila repository?"; then
        print_info "Updating pagila..."
        cd "$PAGILA_DIR"
        git pull
        cd "$PLATFORM_DIR"
        print_success "Pagila updated"
    fi
else
    print_info "Cloning pagila from: $PAGILA_REPO_URL"
    print_info "Destination: $PAGILA_DIR"
    echo ""

    cd "$(dirname "$PAGILA_DIR")"
    if git clone "$PAGILA_REPO_URL" pagila; then
        print_success "Pagila cloned successfully"
        cd "$PLATFORM_DIR"
    else
        print_error "Failed to clone pagila"
        echo ""
        echo "Troubleshooting:"
        echo "  1. Check internet connectivity"
        echo "  2. Verify repository URL: $PAGILA_REPO_URL"
        echo "  3. Check git is installed: git --version"
        exit 1
    fi
fi

echo ""

# ==========================================
# Create .env Configuration (If Needed)
# ==========================================

print_info "Checking for pagila .env configuration..."

PAGILA_ENV_FILE="$PAGILA_DIR/.env"

if [ ! -f "$PAGILA_ENV_FILE" ]; then
    print_info "Creating .env from .env.example..."
    print_info "(Consistent with platform pattern - configuration in .env, not password files)"

    if [ -f "$PAGILA_DIR/.env.example" ]; then
        cp "$PAGILA_DIR/.env.example" "$PAGILA_ENV_FILE"

        # Generate random password in .env
        if command -v openssl >/dev/null 2>&1; then
            RANDOM_PASSWORD=$(openssl rand -base64 32)
        else
            RANDOM_PASSWORD=$(head -c 32 /dev/urandom | base64)
        fi

        # Replace default password with random one
        sed -i "s/POSTGRES_PASSWORD=changeme_generate_random_password/POSTGRES_PASSWORD=$RANDOM_PASSWORD/" "$PAGILA_ENV_FILE"

        print_success ".env created with random password"
        echo ""
        print_info "Note: Pagila uses 'trust' authentication (pg_hba.conf)"
        print_info "      Password in .env just suppresses warnings"
        print_info "      Developers can connect via DBeaver/pgAdmin without password!"
    else
        print_warning ".env.example not found - creating minimal .env"

        cat > "$PAGILA_ENV_FILE" << EOF
# Pagila Configuration (auto-generated)
IMAGE_POSTGRES=${IMAGE_POSTGRES:-postgres:17.5-alpine}
POSTGRES_PASSWORD=$(openssl rand -base64 32 2>/dev/null || echo "postgres")
PAGILA_PORT=5432
EOF
        print_success "Minimal .env created"
    fi
else
    print_check "PASS" ".env exists"
fi

echo ""

# ==========================================
# Start Pagila Container
# ==========================================

print_info "Checking for pagila container..."

# Check if container already running
if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    print_check "PASS" "Pagila container is running"
    echo ""

    if ! ask_yes_no "Restart pagila container?"; then
        print_info "Using existing container"
        # Skip to validation
        SKIP_START=true
    else
        print_info "Restarting container..."
        docker restart "$CONTAINER_NAME"
        sleep 3
        SKIP_START=true
    fi
elif docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    print_warning "Pagila container exists but is stopped"
    print_info "Starting existing container..."
    docker start "$CONTAINER_NAME"
    sleep 3
    SKIP_START=true
fi

if [ "${SKIP_START:-false}" = false ]; then
    print_info "Starting new pagila container..."
    echo ""

    # Get PostgreSQL image (respects corporate .env)
    POSTGRES_IMAGE="${IMAGE_POSTGRES:-postgres:15}"
    print_info "Using PostgreSQL image: $POSTGRES_IMAGE"

    if [[ "$POSTGRES_IMAGE" == *"artifactory"* ]]; then
        print_info "Corporate Artifactory image detected"
        print_warning "Ensure you've run: docker login artifactory.company.com"
        echo ""
    fi

    # Check if pagila has docker-compose setup
    if [ -f "$PAGILA_DIR/docker-compose.yml" ]; then
        print_info "Using pagila's docker-compose.yml"
        cd "$PAGILA_DIR"

        # Pass IMAGE_POSTGRES to pagila's compose
        export IMAGE_POSTGRES="$POSTGRES_IMAGE"

        if docker compose up -d; then
            print_success "Pagila started via docker compose"
        else
            print_error "Docker compose failed"
            exit 1
        fi

        cd "$PLATFORM_DIR"
    else
        # Fallback: Start with docker run
        print_info "Starting pagila with docker run (pagila repo has no docker-compose.yml)"

        docker run -d \
            --name "$CONTAINER_NAME" \
            --network platform_network \
            -e POSTGRES_USER=postgres \
            -e POSTGRES_PASSWORD=postgres \
            -e POSTGRES_DB=pagila \
            -p 5432:5432 \
            -v pagila_data:/var/lib/postgresql/data \
            "$POSTGRES_IMAGE"

        print_success "Container started"

        # Wait for PostgreSQL to be ready
        echo ""
        echo -n "Waiting for PostgreSQL to initialize"
        for i in {1..30}; do
            if docker exec "$CONTAINER_NAME" pg_isready -U postgres >/dev/null 2>&1; then
                echo " ✓"
                break
            fi
            sleep 1
            echo -n "."

            if [ $i -eq 30 ]; then
                echo ""
                print_error "PostgreSQL did not start in time"
                exit 1
            fi
        done

        # Load schema and data
        echo ""
        print_info "Loading pagila schema and data..."

        if [ -f "$PAGILA_DIR/pagila-schema.sql" ] && [ -f "$PAGILA_DIR/pagila-data.sql" ]; then
            docker exec -i "$CONTAINER_NAME" psql -U postgres -d pagila < "$PAGILA_DIR/pagila-schema.sql" >/dev/null
            docker exec -i "$CONTAINER_NAME" psql -U postgres -d pagila < "$PAGILA_DIR/pagila-data.sql" >/dev/null
            print_success "Pagila schema and data loaded"
        else
            print_warning "Schema files not found in $PAGILA_DIR"
            echo "Database created but empty"
        fi
    fi
fi

echo ""

# ==========================================
# Validate Setup
# ==========================================

print_info "Validating pagila setup..."
echo ""

# Test: Container is running
if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    print_check "PASS" "Container running"
else
    print_check "FAIL" "Container not running"
    exit 1
fi

# Test: PostgreSQL is ready
if docker exec "$CONTAINER_NAME" pg_isready -U postgres >/dev/null 2>&1; then
    print_check "PASS" "PostgreSQL is ready"
else
    print_check "FAIL" "PostgreSQL not ready"
    exit 1
fi

# Test: Pagila database exists
if docker exec "$CONTAINER_NAME" psql -U postgres -lqt 2>/dev/null | grep -q "pagila"; then
    print_check "PASS" "pagila database exists"
else
    print_check "FAIL" "pagila database not found"
    exit 1
fi

# Test: Tables exist
TABLE_COUNT=$(docker exec "$CONTAINER_NAME" psql -U postgres -d pagila -t -c "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public'" 2>/dev/null | tr -d ' ')

if [ -n "$TABLE_COUNT" ] && [ "$TABLE_COUNT" -gt 0 ]; then
    print_check "PASS" "Found $TABLE_COUNT tables in pagila database"
else
    print_check "WARN" "Database exists but appears empty"
    echo ""
    echo "To load data manually:"
    echo "  cd $PAGILA_DIR"
    echo "  docker exec -i $CONTAINER_NAME psql -U postgres -d pagila < pagila-schema.sql"
    echo "  docker exec -i $CONTAINER_NAME psql -U postgres -d pagila < pagila-data.sql"
fi

# Test: Network connectivity
if docker network inspect platform_network --format '{{range .Containers}}{{.Name}} {{end}}' | grep -q "$CONTAINER_NAME"; then
    print_check "PASS" "Connected to platform_network"
else
    print_check "WARN" "Not on platform_network (may need manual connection)"
fi

echo ""
print_divider
print_success "Pagila setup complete!"
print_divider
echo ""

# ==========================================
# Summary
# ==========================================

echo "Connection details:"
echo "  Host (from platform):  pagila-postgres:5432"
echo "  Host (from host):      localhost:${PAGILA_PORT:-5432}"
echo "  Database:              pagila"
echo "  Username:              postgres"
echo "  Password:              (trust auth - no password needed!)"
echo ""
echo "Developer-friendly features:"
echo "  ✓ Trust authentication enabled (pg_hba.conf)"
echo "  ✓ Connect from DBeaver/pgAdmin without password"
echo "  ✓ Localhost-only binding (127.0.0.1 - secure!)"
echo "  ✓ Platform services access via Docker network"
echo ""
echo "Quick test:"
echo "  docker exec $CONTAINER_NAME psql -U postgres -d pagila -c '\\dt'"
echo ""
echo "Stop pagila:"
echo "  docker stop $CONTAINER_NAME"
echo ""
echo "Remove pagila:"
echo "  $0 --reset"
echo ""

# Show what's next
if [ -d "$PLATFORM_DIR/../airflow-data-platform-examples/openmetadata-ingestion" ]; then
    echo "Ready for OpenMetadata ingestion example:"
    echo "  cd ~/repos/airflow-data-platform-examples/openmetadata-ingestion"
    echo "  astro dev start"
    echo "  # Trigger: openmetadata_ingest_pagila"
    echo ""
fi

exit 0
