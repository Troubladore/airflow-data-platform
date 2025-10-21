#!/bin/bash
# Platform Setup Wizard
# =====================
# Comprehensive guided setup for all platform services
# Detects environment, asks questions, configures services

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLATFORM_DIR="$(dirname "$SCRIPT_DIR")"
REPO_ROOT="$(dirname "$PLATFORM_DIR")"

# Load formatting library
if [ -f "$PLATFORM_DIR/lib/formatting.sh" ]; then
    source "$PLATFORM_DIR/lib/formatting.sh"
else
    # Fallback if library not found
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

# User selections
NEED_OPENMETADATA=false
NEED_KERBEROS=false
NEED_PAGILA=false
NEED_ARTIFACTORY=false
DETECTED_DOMAIN=""
DETECTED_USERNAME=""
HAS_KERBEROS_TICKET=false

# ==========================================
# Utility Functions
# ==========================================

print_banner() {
    clear
    print_header "Platform Setup Wizard"
    echo "Composable Data Platform Services"
    echo ""
}

# print_section is already in formatting.sh, but add wrapper for consistency
wizard_section() {
    print_section "$1"
}

# print_success, print_error, print_warning, print_info provided by formatting.sh

ask_yes_no() {
    local prompt="$1"
    read -p "$prompt [y/N]: " answer
    case "$answer" in
        [Yy]* ) return 0;;
        * ) return 1;;
    esac
}

press_enter() {
    echo ""
    read -p "Press Enter to continue..."
}

# ==========================================
# Detection Functions
# ==========================================

detect_environment() {
    print_section "Environment Detection"

    # Detect WSL2
    if [ -f /proc/sys/fs/binfmt_misc/WSLInterop ]; then
        print_success "WSL2 detected"

        # Detect Windows domain
        if command -v powershell.exe >/dev/null 2>&1; then
            DETECTED_DOMAIN=$(powershell.exe -Command "([System.DirectoryServices.ActiveDirectory.Domain]::GetComputerDomain()).Name" 2>/dev/null | tr -d '\r' | tr '[:lower:]' '[:upper:]')
            if [ -n "$DETECTED_DOMAIN" ] && [[ "$DETECTED_DOMAIN" != *"Exception"* ]]; then
                print_success "Windows domain detected: $DETECTED_DOMAIN"
            else
                print_info "No Windows domain detected (not domain-joined)"
            fi

            DETECTED_USERNAME=$(powershell.exe -Command "\$env:USERNAME" 2>/dev/null | tr -d '\r')
            if [ -n "$DETECTED_USERNAME" ]; then
                print_info "Windows username: $DETECTED_USERNAME"
            fi
        fi
    else
        print_info "Native Linux environment"
    fi

    # Check for existing Kerberos ticket
    if command -v klist >/dev/null 2>&1 && klist -s 2>/dev/null; then
        print_success "Active Kerberos ticket found"
        HAS_KERBEROS_TICKET=true
    else
        print_info "No Kerberos ticket found (not needed for PostgreSQL-only setup)"
    fi

    # Check Docker
    if docker info >/dev/null 2>&1; then
        print_success "Docker is running"
    else
        print_error "Docker is not running"
        exit 1
    fi

    press_enter
}

# ==========================================
# Service Selection
# ==========================================

ask_service_needs() {
    print_section "Service Selection"

    echo "Which services do you need for local development?"
    echo ""

    # OpenMetadata
    echo "OpenMetadata - Metadata Catalog & Data Discovery"
    echo "  • Catalog databases (PostgreSQL, SQL Server, etc.)"
    echo "  • Track data lineage and quality"
    echo "  • Collaborate on data documentation"
    echo "  • Requirements: ~2GB RAM, Docker"
    echo ""
    if ask_yes_no "Enable OpenMetadata?"; then
        NEED_OPENMETADATA=true
        print_success "OpenMetadata: ENABLED"
    else
        print_info "OpenMetadata: DISABLED"
    fi

    echo ""

    # Kerberos
    echo "Kerberos - SQL Server Authentication (Windows/Active Directory)"
    echo "  • Connect to corporate SQL Server databases"
    echo "  • Use your domain credentials (no passwords in code!)"
    echo "  • Required: Domain membership, kinit access"

    if [ -n "$DETECTED_DOMAIN" ]; then
        print_info "Auto-detected: Domain $DETECTED_DOMAIN"
    fi
    if [ "$HAS_KERBEROS_TICKET" = true ]; then
        print_success "You already have a valid Kerberos ticket"
    fi
    echo ""

    if ask_yes_no "Enable Kerberos?"; then
        NEED_KERBEROS=true
        print_success "Kerberos: ENABLED"
    else
        print_info "Kerberos: DISABLED (PostgreSQL-only mode)"
    fi

    echo ""

    # Pagila
    echo "Pagila - PostgreSQL Sample Database"
    echo "  • Test data for OpenMetadata ingestion"
    echo "  • Real-world schema (film rental database)"
    echo "  • Requirements: ~100MB disk"
    echo ""
    if ask_yes_no "Enable Pagila?"; then
        NEED_PAGILA=true
        print_success "Pagila: ENABLED"
    else
        print_info "Pagila: DISABLED"
    fi

    echo ""

    # Validate at least one service selected
    if [ "$NEED_OPENMETADATA" = false ] && [ "$NEED_KERBEROS" = false ]; then
        print_warning "No services selected!"
        echo ""
        if ask_yes_no "Exit setup?"; then
            exit 0
        else
            ask_service_needs
            return
        fi
    fi
}

# ==========================================
# Corporate Infrastructure
# ==========================================

ask_corporate_infrastructure() {
    print_section "Corporate Infrastructure"

    echo "Does your organization use corporate infrastructure?"
    echo ""
    echo "Artifactory / Internal Registries"
    echo "  • Internal Docker registry (artifactory.company.com)"
    echo "  • Internal PyPI mirror"
    echo "  • Internal git servers"
    echo ""

    if ask_yes_no "Configure corporate infrastructure?"; then
        NEED_ARTIFACTORY=true
        print_success "Corporate infrastructure: ENABLED"
        echo ""

        print_info "You'll need to configure image sources in each service's .env file:"
        if [ "$NEED_OPENMETADATA" = true ]; then
            echo "  • openmetadata/.env - IMAGE_POSTGRES, IMAGE_OPENSEARCH, etc."
        fi
        if [ "$NEED_KERBEROS" = true ]; then
            echo "  • kerberos/.env - ODBC_DRIVER_URL, etc."
        fi
        echo ""
        print_info "Also run: docker login artifactory.company.com"
    else
        print_info "Corporate infrastructure: DISABLED (using public registries)"
    fi
}

# ==========================================
# Configure Services
# ==========================================

# Interactive configuration for a single .env property
# Args: $1=env_file, $2=property_name, $3=current_value, $4=description
configure_env_property() {
    local env_file="$1"
    local property="$2"
    local current_value="$3"
    local description="$4"

    echo ""
    echo "$property"
    echo "  Description: $description"
    echo "  Current: ${current_value:-[not set]}"
    echo ""
    read -p "  New value (press Enter to keep current): " new_value

    if [ -n "$new_value" ]; then
        # Update the value using | delimiter to avoid sed issues with URLs
        if grep -q "^${property}=" "$env_file" 2>/dev/null; then
            sed -i "s|^${property}=.*|${property}=${new_value}|" "$env_file"
        else
            echo "${property}=${new_value}" >> "$env_file"
        fi
        print_success "Updated: $property=$new_value"
    else
        print_info "Kept: $property=$current_value"
    fi
}

# Configure infrastructure .env for corporate environments
# Always offers review in corporate mode, requires config if missing
configure_infrastructure_env_interactive() {
    local env_file="$REPO_ROOT/platform-infrastructure/.env"
    local required_props=("IMAGE_POSTGRES")
    local missing_props=()
    local all_defined=true

    print_section "Infrastructure Configuration"

    # Check if .env exists
    if [ ! -f "$env_file" ]; then
        print_info "No .env file found in platform-infrastructure/"
        echo "Creating from template..."
        cp "$REPO_ROOT/platform-infrastructure/.env.example" "$env_file"

        # Generate password
        if command -v openssl >/dev/null 2>&1; then
            INFRA_PASS=$(openssl rand -base64 24)
        else
            INFRA_PASS=$(head -c 24 /dev/urandom | base64)
        fi
        sed -i "s|PLATFORM_DB_PASSWORD=.*|PLATFORM_DB_PASSWORD=$INFRA_PASS|" "$env_file"

        print_success "Created platform-infrastructure/.env with secure password"
        echo ""
    fi

    # Check which required properties are defined (not commented out)
    for prop in "${required_props[@]}"; do
        if ! grep -q "^${prop}=" "$env_file"; then
            missing_props+=("$prop")
            all_defined=false
        fi
    done

    # In corporate mode, ALWAYS offer to review settings
    if [ "$all_defined" = false ]; then
        # Some properties missing - MUST configure
        echo "Some required properties are not configured:"
        for prop in "${missing_props[@]}"; do
            echo "  • $prop"
        done
        echo ""
        echo "Since configuration is incomplete, let's review ALL settings..."
        echo ""

        # Prompt for ALL properties when ANY are missing
        configure_infrastructure_env_prompts "$env_file"
    else
        # All properties defined - but in corporate mode, still offer review
        print_info "Current Docker image configuration:"
        echo ""
        # Show current settings
        source "$env_file" 2>/dev/null || true
        echo "  IMAGE_POSTGRES=${IMAGE_POSTGRES:-[not set]}"
        echo ""

        if ask_yes_no "Do you want to review/update these corporate registry settings?"; then
            # Prompt for ALL properties
            configure_infrastructure_env_prompts "$env_file"
        else
            print_info "Using existing configuration"
        fi
    fi
}

# Prompt for each infrastructure property
configure_infrastructure_env_prompts() {
    local env_file="$1"

    # Load current values
    source "$env_file" 2>/dev/null || true

    echo ""
    print_info "Configure ALL Docker image sources for corporate environment"
    echo ""
    echo "Press Enter to keep current values, or enter new corporate registry paths."
    echo ""
    echo "Examples:"
    echo "  • Public:    postgres:17.5-alpine"
    echo "  • Corporate: artifactory.company.com/docker-remote/library/postgres:17.5-alpine"
    echo ""

    # Prompt for ALL properties (not just missing ones)
    configure_env_property "$env_file" \
        "IMAGE_POSTGRES" \
        "${IMAGE_POSTGRES:-postgres:17.5-alpine}" \
        "PostgreSQL image for platform services"

    echo ""
    print_success "Infrastructure configuration complete"
}

# Configure OpenMetadata .env for corporate environments
# Always offers review in corporate mode, requires config if missing
configure_openmetadata_env_interactive() {
    local env_file="$REPO_ROOT/openmetadata/.env"
    local required_props=("IMAGE_OPENMETADATA_SERVER" "IMAGE_OPENSEARCH")
    local missing_props=()
    local all_defined=true

    print_section "OpenMetadata Configuration"

    # Check if .env exists
    if [ ! -f "$env_file" ]; then
        print_info "No .env file found in openmetadata/"
        echo "Creating from template..."
        cp "$REPO_ROOT/openmetadata/.env.example" "$env_file"
        print_success "Created openmetadata/.env"
        echo ""
    fi

    # Check which required properties are defined (not commented out)
    for prop in "${required_props[@]}"; do
        if ! grep -q "^${prop}=" "$env_file"; then
            missing_props+=("$prop")
            all_defined=false
        fi
    done

    # In corporate mode, ALWAYS offer to review settings
    if [ "$all_defined" = false ]; then
        # Some properties missing - MUST configure
        echo "Some required properties are not configured:"
        for prop in "${missing_props[@]}"; do
            echo "  • $prop"
        done
        echo ""
        echo "Since configuration is incomplete, let's review ALL settings..."
        echo ""

        # Prompt for ALL properties when ANY are missing
        configure_openmetadata_env_prompts "$env_file"
    else
        # All properties defined - but in corporate mode, still offer review
        print_info "Current Docker image configuration:"
        echo ""
        # Show current settings
        source "$env_file" 2>/dev/null || true
        echo "  IMAGE_OPENMETADATA_SERVER=${IMAGE_OPENMETADATA_SERVER:-[not set]}"
        echo "  IMAGE_OPENSEARCH=${IMAGE_OPENSEARCH:-[not set]}"
        echo ""

        if ask_yes_no "Do you want to review/update these corporate registry settings?"; then
            # Prompt for ALL properties
            configure_openmetadata_env_prompts "$env_file"
        else
            print_info "Using existing configuration"
        fi
    fi
}

# Prompt for OpenMetadata Docker images
configure_openmetadata_env_prompts() {
    local env_file="$1"

    # Load current values
    source "$env_file" 2>/dev/null || true

    echo ""
    print_info "Configure ALL Docker image sources for OpenMetadata"
    echo ""
    echo "Press Enter to keep current values, or enter new corporate registry paths."
    echo ""

    configure_env_property "$env_file" \
        "IMAGE_OPENMETADATA_SERVER" \
        "${IMAGE_OPENMETADATA_SERVER:-docker.getcollate.io/openmetadata/server:1.10.1}" \
        "OpenMetadata server image"

    configure_env_property "$env_file" \
        "IMAGE_OPENSEARCH" \
        "${IMAGE_OPENSEARCH:-opensearchproject/opensearch:2.19.2}" \
        "OpenSearch image for OpenMetadata search (v2.19.2 - latest supported)"

    echo ""
    print_success "OpenMetadata configuration complete"
}

configure_platform_env() {
    print_section "Platform Configuration"

    echo "Creating platform-bootstrap/.env..."

    # Create/update .env
    if [ ! -f "$PLATFORM_DIR/.env" ]; then
        cp "$PLATFORM_DIR/.env.example" "$PLATFORM_DIR/.env"
    fi

    # Update service toggles
    sed -i "s/ENABLE_KERBEROS=.*/ENABLE_KERBEROS=$NEED_KERBEROS/" "$PLATFORM_DIR/.env"
    sed -i "s/ENABLE_OPENMETADATA=.*/ENABLE_OPENMETADATA=$NEED_OPENMETADATA/" "$PLATFORM_DIR/.env"

    print_success "Platform configuration updated"
    echo ""
    echo "  ENABLE_KERBEROS=$NEED_KERBEROS"
    echo "  ENABLE_OPENMETADATA=$NEED_OPENMETADATA"
}

setup_infrastructure() {
    print_section "Shared Infrastructure Setup"

    echo "Setting up platform infrastructure (always required)..."
    echo "  • PostgreSQL: Shared OLTP for Airflow, OpenMetadata, etc."
    echo "  • Network: platform_network for service communication"
    echo ""

    # If corporate mode, configure image sources BEFORE starting services
    if [ "$NEED_ARTIFACTORY" = true ]; then
        configure_infrastructure_env_interactive
        echo ""
    else
        # Non-corporate mode: Just ensure .env exists with defaults
        if [ ! -f "$REPO_ROOT/platform-infrastructure/.env" ]; then
            cp "$REPO_ROOT/platform-infrastructure/.env.example" "$REPO_ROOT/platform-infrastructure/.env"
            # Generate password
            if command -v openssl >/dev/null 2>&1; then
                INFRA_PASS=$(openssl rand -base64 24)
            else
                INFRA_PASS=$(head -c 24 /dev/urandom | base64)
            fi
            sed -i "s|PLATFORM_DB_PASSWORD=.*|PLATFORM_DB_PASSWORD=$INFRA_PASS|" "$REPO_ROOT/platform-infrastructure/.env"
            print_success "Generated infrastructure .env with secure password"
        else
            print_info "Infrastructure .env already exists"
        fi
    fi

    # Start infrastructure
    echo ""
    echo "Starting infrastructure services..."
    if cd "$REPO_ROOT/platform-infrastructure" && make start; then
        print_success "Infrastructure started"
    else
        print_error "Infrastructure setup failed"
        exit 1
    fi

    cd "$PLATFORM_DIR"
}

setup_openmetadata() {
    if [ "$NEED_OPENMETADATA" = false ]; then
        return 0
    fi

    print_section "OpenMetadata Setup"

    echo "Setting up OpenMetadata..."
    echo ""

    # If corporate mode, configure OpenMetadata image sources first
    if [ "$NEED_ARTIFACTORY" = true ]; then
        configure_openmetadata_env_interactive
        echo ""
    fi

    # Call OpenMetadata's progressive validation setup
    if cd "$REPO_ROOT/openmetadata" && ./setup.sh --auto; then
        print_success "OpenMetadata setup complete"
    else
        print_error "OpenMetadata setup failed"
        exit 1
    fi

    cd "$PLATFORM_DIR"
}

setup_kerberos() {
    if [ "$NEED_KERBEROS" = false ]; then
        return 0
    fi

    print_section "Kerberos Setup"

    echo "Setting up Kerberos..."
    echo ""
    echo "Running Kerberos configuration wizard..."
    echo "(This includes 11 validation steps for Kerberos ticket sharing)"
    echo ""

    press_enter

    # Call Kerberos comprehensive setup
    if cd "$REPO_ROOT/kerberos" && ./setup.sh; then
        print_success "Kerberos setup complete"
    else
        print_error "Kerberos setup failed"
        exit 1
    fi

    cd "$PLATFORM_DIR"
}

setup_pagila() {
    if [ "$NEED_PAGILA" = false ]; then
        return 0
    fi

    print_section "Pagila Setup"

    echo "Setting up Pagila test database..."
    echo ""

    if "$PLATFORM_DIR/setup-scripts/setup-pagila.sh" --yes; then
        print_success "Pagila setup complete"
    else
        print_error "Pagila setup failed"
        exit 1
    fi
}

# ==========================================
# Final Summary
# ==========================================

show_final_summary() {
    clear
    print_divider
    print_success "Platform Setup Complete!"
    print_divider
    echo ""

    echo "Active Services:"
    echo ""

    if [ "$NEED_OPENMETADATA" = true ]; then
        print_check "PASS" "OpenMetadata"
        echo "      UI:    http://localhost:8585"
        echo "      Login: admin@open-metadata.org / admin"
        echo ""
    fi

    if [ "$NEED_KERBEROS" = true ]; then
        print_check "PASS" "Kerberos Sidecar"
        echo "      Status: Sharing tickets with containers"
        echo "      Domain: ${DETECTED_DOMAIN:-Configured}"
        echo ""
    fi

    if [ "$NEED_PAGILA" = true ]; then
        print_check "PASS" "Pagila Test Database"
        echo "      Host: localhost:5432"
        echo "      Database: pagila"
        echo "      User: postgres (trust auth - no password)"
        echo ""
    fi

    echo "Next Steps:"
    echo ""
    echo "  1. Check platform status:"
    echo "     cd $PLATFORM_DIR && make platform-status"
    echo ""

    if [ "$NEED_OPENMETADATA" = true ]; then
        echo "  2. Access OpenMetadata UI:"
        echo "     open http://localhost:8585"
        echo ""
    fi

    if [ "$NEED_PAGILA" = true ] && [ "$NEED_OPENMETADATA" = true ]; then
        echo "  3. Connect Pagila to OpenMetadata:"
        echo "     • Add PostgreSQL connection in OpenMetadata UI"
        echo "     • Host: pagila-postgres, Port: 5432, Database: pagila"
        echo ""
    fi

    echo "  4. Create Airflow project:"
    echo "     astro dev init my-project"
    echo ""

    echo "Service Management:"
    echo ""
    echo "  Platform Orchestrator:"
    echo "    cd $PLATFORM_DIR"
    echo "    make platform-start    # Start all enabled services"
    echo "    make platform-stop     # Stop all services"
    echo "    make platform-status   # Check service health"
    echo ""
    echo "  Individual Services:"
    if [ "$NEED_OPENMETADATA" = true ]; then
        echo "    cd $REPO_ROOT/openmetadata && make status"
    fi
    if [ "$NEED_KERBEROS" = true ]; then
        echo "    cd $REPO_ROOT/kerberos && make status"
    fi
    echo ""

    echo "Configuration Files:"
    echo "  • $PLATFORM_DIR/.env           (service toggles)"
    if [ "$NEED_OPENMETADATA" = true ]; then
        echo "  • $REPO_ROOT/openmetadata/.env  (OpenMetadata config)"
    fi
    if [ "$NEED_KERBEROS" = true ]; then
        echo "  • $REPO_ROOT/kerberos/.env      (Kerberos config)"
    fi
    echo ""
}

# ==========================================
# Main Wizard Flow
# ==========================================

main() {
    print_banner

    echo "Welcome! This wizard will help you set up your local data platform."
    echo "It will detect your environment and guide you through configuration."
    echo ""

    press_enter

    # Step 1: Detect environment
    detect_environment

    # Step 2: Ask what services they need
    ask_service_needs

    # Step 3: Corporate infrastructure questions
    ask_corporate_infrastructure

    # Step 4: Configure platform .env
    configure_platform_env

    # Step 5: Setup infrastructure (always first)
    setup_infrastructure

    # Step 6: Setup optional services (with progressive validation)
    setup_openmetadata
    setup_kerberos
    setup_pagila

    # Step 7: Final summary
    show_final_summary
}

detect_environment() {
    print_section "Step 1/6: Environment Detection"

    # Detect WSL2 (check kernel version for "microsoft" or "WSL")
    if uname -r | grep -qi "microsoft\|wsl"; then
        print_success "WSL2 detected"

        # Detect Windows domain
        if command -v powershell.exe >/dev/null 2>&1; then
            DETECTED_DOMAIN=$(powershell.exe -Command "([System.DirectoryServices.ActiveDirectory.Domain]::GetComputerDomain()).Name" 2>/dev/null | tr -d '\r' | tr '[:lower:]' '[:upper:]')
            if [ -n "$DETECTED_DOMAIN" ] && [[ "$DETECTED_DOMAIN" != *"Exception"* ]]; then
                print_success "Windows domain: $DETECTED_DOMAIN"
            else
                print_info "No Windows domain (machine not domain-joined)"
            fi

            DETECTED_USERNAME=$(powershell.exe -Command "\$env:USERNAME" 2>/dev/null | tr -d '\r')
            if [ -n "$DETECTED_USERNAME" ]; then
                print_info "Windows username: $DETECTED_USERNAME"
            fi
        fi
    else
        print_info "Native Linux environment"
    fi

    # Check for existing Kerberos ticket
    if command -v klist >/dev/null 2>&1 && klist -s 2>/dev/null; then
        print_success "Active Kerberos ticket found"
        HAS_KERBEROS_TICKET=true
        TICKET_INFO=$(klist | head -5)
    else
        print_info "No Kerberos ticket (run 'kinit' if you need SQL Server access)"
    fi

    # Check Docker
    if docker info >/dev/null 2>&1; then
        print_success "Docker is running"
    else
        print_error "Docker is not running - please start Docker Desktop"
        exit 1
    fi

    echo ""
    print_success "Environment detection complete"
}

press_enter() {
    echo ""
    read -p "Press Enter to continue..."
}

# Run the wizard
main
