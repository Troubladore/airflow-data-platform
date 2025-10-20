#!/bin/bash
# Platform Setup Wizard
# =====================
# Comprehensive guided setup for all platform services
# Detects environment, asks questions, configures services

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLATFORM_DIR="$(dirname "$SCRIPT_DIR")"
REPO_ROOT="$(dirname "$PLATFORM_DIR")"

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
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}                  ${BOLD}${BLUE}Platform Setup Wizard${NC}                        ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}              ${BLUE}Composable Data Platform Services${NC}                ${CYAN}║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

print_section() {
    echo ""
    echo -e "${BOLD}${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}$1${NC}"
    echo -e "${BOLD}${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
}

print_success() { echo -e "${GREEN}✓${NC} $1"; }
print_error() { echo -e "${RED}✗${NC} $1"; }
print_warning() { echo -e "${YELLOW}⚠${NC}  $1"; }
print_info() { echo -e "${CYAN}ℹ${NC}  $1"; }

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
    echo -e "${BOLD}OpenMetadata${NC} - Metadata Catalog & Data Discovery"
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
    echo -e "${BOLD}Kerberos${NC} - SQL Server Authentication (Windows/Active Directory)"
    echo "  • Connect to corporate SQL Server databases"
    echo "  • Use your domain credentials (no passwords in code!)"
    echo "  • Required: Domain membership, kinit access"

    if [ -n "$DETECTED_DOMAIN" ]; then
        echo -e "  • ${GREEN}Auto-detected: Domain $DETECTED_DOMAIN${NC}"
    fi
    if [ "$HAS_KERBEROS_TICKET" = true ]; then
        echo -e "  • ${GREEN}You already have a valid Kerberos ticket${NC}"
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
    echo -e "${BOLD}Pagila${NC} - PostgreSQL Sample Database"
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

    press_enter
}

# ==========================================
# Corporate Infrastructure
# ==========================================

ask_corporate_infrastructure() {
    print_section "Corporate Infrastructure"

    echo "Does your organization use corporate infrastructure?"
    echo ""
    echo -e "${BOLD}Artifactory / Internal Registries${NC}"
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
            echo "  • openmetadata/.env - IMAGE_POSTGRES, IMAGE_ELASTICSEARCH, etc."
        fi
        if [ "$NEED_KERBEROS" = true ]; then
            echo "  • kerberos/.env - ODBC_DRIVER_URL, etc."
        fi
        echo ""
        print_info "Also run: docker login artifactory.company.com"
    else
        print_info "Corporate infrastructure: DISABLED (using public registries)"
    fi

    press_enter
}

# ==========================================
# Configure Services
# ==========================================

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

setup_openmetadata() {
    if [ "$NEED_OPENMETADATA" = false ]; then
        return 0
    fi

    print_section "OpenMetadata Setup"

    echo "Setting up OpenMetadata..."
    echo ""

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
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                                                                  ║${NC}"
    echo -e "${GREEN}║                  ${BOLD}Platform Setup Complete!${NC}${GREEN}                     ║${NC}"
    echo -e "${GREEN}║                                                                  ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    echo -e "${BOLD}Active Services:${NC}"
    echo ""

    if [ "$NEED_OPENMETADATA" = true ]; then
        echo -e "  ${GREEN}✓${NC} OpenMetadata"
        echo "      UI:    http://localhost:8585"
        echo "      Login: admin@open-metadata.org / admin"
        echo ""
    fi

    if [ "$NEED_KERBEROS" = true ]; then
        echo -e "  ${GREEN}✓${NC} Kerberos Sidecar"
        echo "      Status: Sharing tickets with containers"
        echo "      Domain: ${DETECTED_DOMAIN:-Configured}"
        echo ""
    fi

    if [ "$NEED_PAGILA" = true ]; then
        echo -e "  ${GREEN}✓${NC} Pagila Test Database"
        echo "      Host: localhost:5432"
        echo "      Database: pagila"
        echo "      User: postgres (trust auth - no password)"
        echo ""
    fi

    echo -e "${BOLD}Next Steps:${NC}"
    echo ""
    echo "  1. Check platform status:"
    echo "     ${CYAN}cd $PLATFORM_DIR && make platform-status${NC}"
    echo ""

    if [ "$NEED_OPENMETADATA" = true ]; then
        echo "  2. Access OpenMetadata UI:"
        echo "     ${CYAN}open http://localhost:8585${NC}"
        echo ""
    fi

    if [ "$NEED_PAGILA" = true ] && [ "$NEED_OPENMETADATA" = true ]; then
        echo "  3. Connect Pagila to OpenMetadata:"
        echo "     • Add PostgreSQL connection in OpenMetadata UI"
        echo "     • Host: pagila-postgres, Port: 5432, Database: pagila"
        echo ""
    fi

    echo "  4. Create Airflow project:"
    echo "     ${CYAN}astro dev init my-project${NC}"
    echo ""

    echo -e "${BOLD}Service Management:${NC}"
    echo ""
    echo "  Platform Orchestrator:"
    echo "    ${CYAN}cd $PLATFORM_DIR${NC}"
    echo "    ${CYAN}make platform-start${NC}    # Start all enabled services"
    echo "    ${CYAN}make platform-stop${NC}     # Stop all services"
    echo "    ${CYAN}make platform-status${NC}   # Check service health"
    echo ""
    echo "  Individual Services:"
    if [ "$NEED_OPENMETADATA" = true ]; then
        echo "    ${CYAN}cd $REPO_ROOT/openmetadata && make status${NC}"
    fi
    if [ "$NEED_KERBEROS" = true ]; then
        echo "    ${CYAN}cd $REPO_ROOT/kerberos && make status${NC}"
    fi
    echo ""

    echo -e "${BOLD}Configuration Files:${NC}"
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

    # Step 5: Setup each service (with progressive validation)
    setup_openmetadata
    setup_kerberos
    setup_pagila

    # Step 6: Final summary
    show_final_summary
}

detect_environment() {
    print_section "Step 1/6: Environment Detection"

    # Detect WSL2
    if [ -f /proc/sys/fs/binfmt_misc/WSLInterop ]; then
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
