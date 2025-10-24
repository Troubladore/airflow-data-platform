#!/bin/bash
# Platform Setup Wizard V2 - Streamlined Version
# ===============================================
# Asks all questions upfront, then configures everything
# Optimized for custom + prebuilt images workflow

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

# User selections - ALL collected upfront
NEED_OPENMETADATA=false
NEED_KERBEROS=false
NEED_PAGILA=false
USE_CUSTOM_IMAGES=false
IMAGE_MODE="layered"
POSTGRES_AUTH_MODE=""
DETECTED_DOMAIN=""
DETECTED_USERNAME=""
HAS_KERBEROS_TICKET=false

# Custom image paths (collected upfront when needed)
CUSTOM_IMAGE_POSTGRES=""
CUSTOM_IMAGE_PYTHON=""
CUSTOM_IMAGE_OPENMETADATA=""
CUSTOM_IMAGE_OPENSEARCH=""
CUSTOM_PAGILA_REPO=""

# ==========================================
# Utility Functions
# ==========================================

print_banner() {
    clear
    print_header "Platform Setup Wizard V2"
    echo "Streamlined setup with all questions upfront"
    echo ""
}

ask_yes_no() {
    local prompt="$1"
    local default="${2:-n}"

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

press_enter() {
    echo ""
    read -p "Press Enter to continue..."
}

# ==========================================
# Detection Phase - Gather Environment Info
# ==========================================

detect_environment() {
    print_section "Environment Detection"

    # Detect WSL2
    if uname -r | grep -qi "microsoft\|wsl"; then
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
        print_info "No Kerberos ticket found"
    fi

    # Check Docker
    if docker info >/dev/null 2>&1; then
        print_success "Docker is running"
    else
        print_error "Docker is not running"
        exit 1
    fi

    echo ""
}

# ==========================================
# Question Phase - Collect ALL User Input
# ==========================================

collect_all_user_input() {
    print_header "Configuration Questions"
    echo "Let's gather all the information needed to set up your platform."
    echo "This should only take a minute or two."
    echo ""

    # ============ Service Selection ============
    print_section "Step 1/4: Service Selection"

    echo "Which services do you need for local development?"
    echo ""

    # OpenMetadata
    echo "• OpenMetadata - Metadata Catalog & Data Discovery"
    echo "  Requirements: ~2GB RAM, Docker"
    if ask_yes_no "  Enable OpenMetadata?"; then
        NEED_OPENMETADATA=true
        print_success "OpenMetadata: ENABLED"
    fi

    echo ""

    # Kerberos
    echo "• Kerberos - SQL Server Authentication (Windows/Active Directory)"
    if [ -n "$DETECTED_DOMAIN" ]; then
        echo "  Detected domain: $DETECTED_DOMAIN"
    fi
    if [ "$HAS_KERBEROS_TICKET" = true ]; then
        echo "  You have an active Kerberos ticket"
    fi
    if ask_yes_no "  Enable Kerberos?"; then
        NEED_KERBEROS=true
        print_success "Kerberos: ENABLED"
    fi

    echo ""

    # Pagila
    echo "• Pagila - PostgreSQL Sample Database"
    echo "  Real-world schema for testing"
    if ask_yes_no "  Enable Pagila?"; then
        NEED_PAGILA=true
        print_success "Pagila: ENABLED"
    fi

    # ============ Custom Images Question ============
    echo ""
    print_section "Step 2/4: Image Sources"

    echo "Do you use custom Docker images?"
    echo "(e.g., corporate registry, pre-built images, air-gapped environment)"
    echo ""

    if ask_yes_no "Use custom image sources?" "y"; then  # Default to yes based on user request
        USE_CUSTOM_IMAGES=true
        print_success "Custom images: ENABLED"
        echo ""

        # Image mode question
        echo "How are your custom images built?"
        echo ""
        echo "• Prebuilt: Images include ALL dependencies (faster, no downloads)"
        echo "• Layered: Platform installs packages at runtime"
        echo ""

        if ask_yes_no "Are your images prebuilt with all dependencies?" "y"; then  # Default to yes
            IMAGE_MODE="prebuilt"
            print_success "Using prebuilt mode"
            echo ""
            print_info "Note: With prebuilt images, we won't ask about driver URLs"
            print_info "since everything is already included in your images."
        else
            IMAGE_MODE="layered"
            print_info "Using layered mode"
        fi

        echo ""

        # ============ Collect Image Paths Upfront ============
        print_section "Step 3/4: Custom Image Configuration"

        echo "Please provide your custom image paths."
        echo "Press Enter to use the default (shown in brackets)."
        echo ""

        # PostgreSQL image (always needed)
        echo "PostgreSQL image for platform services:"
        echo "  Default: [postgres:17.5-alpine]"
        read -p "  Custom image: " CUSTOM_IMAGE_POSTGRES
        CUSTOM_IMAGE_POSTGRES="${CUSTOM_IMAGE_POSTGRES:-postgres:17.5-alpine}"
        print_info "Using: $CUSTOM_IMAGE_POSTGRES"
        echo ""

        # Python image (if Kerberos enabled)
        if [ "$NEED_KERBEROS" = true ]; then
            echo "Python runtime image:"
            echo "  Default: [python:3.11-alpine]"
            read -p "  Custom image: " CUSTOM_IMAGE_PYTHON
            CUSTOM_IMAGE_PYTHON="${CUSTOM_IMAGE_PYTHON:-python:3.11-alpine}"
            print_info "Using: $CUSTOM_IMAGE_PYTHON"
            echo ""
        fi

        # OpenMetadata images (if enabled)
        if [ "$NEED_OPENMETADATA" = true ]; then
            echo "OpenMetadata server image:"
            echo "  Default: [docker.getcollate.io/openmetadata/server:1.10.1]"
            read -p "  Custom image: " CUSTOM_IMAGE_OPENMETADATA
            CUSTOM_IMAGE_OPENMETADATA="${CUSTOM_IMAGE_OPENMETADATA:-docker.getcollate.io/openmetadata/server:1.10.1}"
            print_info "Using: $CUSTOM_IMAGE_OPENMETADATA"
            echo ""

            echo "OpenSearch image:"
            echo "  Default: [opensearchproject/opensearch:2.19.2]"
            read -p "  Custom image: " CUSTOM_IMAGE_OPENSEARCH
            CUSTOM_IMAGE_OPENSEARCH="${CUSTOM_IMAGE_OPENSEARCH:-opensearchproject/opensearch:2.19.2}"
            print_info "Using: $CUSTOM_IMAGE_OPENSEARCH"
            echo ""
        fi

        # Pagila repository URL (if enabled)
        if [ "$NEED_PAGILA" = true ]; then
            echo "Pagila Git repository:"
            echo "  Default: [https://github.com/Troubladore/pagila.git]"
            read -p "  Custom URL: " CUSTOM_PAGILA_REPO
            CUSTOM_PAGILA_REPO="${CUSTOM_PAGILA_REPO:-https://github.com/Troubladore/pagila.git}"
            print_info "Using: $CUSTOM_PAGILA_REPO"
            echo ""
        fi

        # Only ask about ODBC drivers if using layered mode with Kerberos
        if [ "$IMAGE_MODE" = "layered" ] && [ "$NEED_KERBEROS" = true ]; then
            echo ""
            print_warning "Layered mode: Need to specify driver download URLs"
            echo ""
            echo "ODBC Driver URL (for SQL Server connectivity):"
            echo "  Default: [Microsoft public download]"
            echo "  Example: https://artifactory.company.com/path/to/odbc"
            read -p "  Custom URL: " CUSTOM_ODBC_URL
            if [ -n "$CUSTOM_ODBC_URL" ]; then
                print_info "Using: $CUSTOM_ODBC_URL"
            else
                print_info "Using: Microsoft public download"
            fi
            echo ""
        fi
    else
        USE_CUSTOM_IMAGES=false
        IMAGE_MODE="layered"
        print_info "Using public Docker images"
    fi

    # ============ PostgreSQL Auth Mode ============
    echo ""
    print_section "Step 4/4: PostgreSQL Authentication"

    echo "For local development, you can use password-less authentication."
    echo "This makes development easier but should NEVER be used in production."
    echo ""

    if ask_yes_no "Enable password-less PostgreSQL for development?" "y"; then
        POSTGRES_AUTH_MODE="trust"
        print_warning "Password-less mode enabled - DEVELOPMENT ONLY!"
    else
        POSTGRES_AUTH_MODE=""
        print_info "Using standard password authentication"
    fi

    echo ""
    print_success "All questions complete!"
    echo ""
    echo "Ready to configure your platform with:"
    echo "  • Services: $([ "$NEED_OPENMETADATA" = true ] && echo "OpenMetadata " || true)$([ "$NEED_KERBEROS" = true ] && echo "Kerberos " || true)$([ "$NEED_PAGILA" = true ] && echo "Pagila" || true)"
    echo "  • Images: $([ "$USE_CUSTOM_IMAGES" = true ] && echo "Custom ($IMAGE_MODE mode)" || echo "Public")"
    echo "  • PostgreSQL: $([ "$POSTGRES_AUTH_MODE" = "trust" ] && echo "Password-less" || echo "Password-protected")"
    echo ""
    press_enter
}

# ==========================================
# Configuration Phase - Apply All Settings
# ==========================================

configure_all_services() {
    print_header "Applying Configuration"

    # Create platform-bootstrap/.env
    print_section "Platform Configuration"

    if [ ! -f "$PLATFORM_DIR/.env" ]; then
        cp "$PLATFORM_DIR/.env.example" "$PLATFORM_DIR/.env"
        print_success "Created platform-bootstrap/.env"
    else
        print_info "Updating platform-bootstrap/.env"
    fi

    # Update service toggles
    sed -i "s/ENABLE_KERBEROS=.*/ENABLE_KERBEROS=$NEED_KERBEROS/" "$PLATFORM_DIR/.env"
    sed -i "s/ENABLE_OPENMETADATA=.*/ENABLE_OPENMETADATA=$NEED_OPENMETADATA/" "$PLATFORM_DIR/.env"

    # Set IMAGE_MODE
    if grep -q "^IMAGE_MODE=" "$PLATFORM_DIR/.env" 2>/dev/null; then
        sed -i "s|^IMAGE_MODE=.*|IMAGE_MODE=$IMAGE_MODE|" "$PLATFORM_DIR/.env"
    else
        echo "" >> "$PLATFORM_DIR/.env"
        echo "# Image mode (layered = runtime install, prebuilt = no runtime install)" >> "$PLATFORM_DIR/.env"
        echo "IMAGE_MODE=$IMAGE_MODE" >> "$PLATFORM_DIR/.env"
    fi

    # Set PostgreSQL auth mode
    if [ -n "$POSTGRES_AUTH_MODE" ]; then
        if grep -q "^POSTGRES_HOST_AUTH_METHOD=" "$PLATFORM_DIR/.env" 2>/dev/null; then
            sed -i "s|^POSTGRES_HOST_AUTH_METHOD=.*|POSTGRES_HOST_AUTH_METHOD=$POSTGRES_AUTH_MODE|" "$PLATFORM_DIR/.env"
        else
            echo "POSTGRES_HOST_AUTH_METHOD=$POSTGRES_AUTH_MODE" >> "$PLATFORM_DIR/.env"
        fi
    fi

    # Set Pagila repo URL if custom
    if [ "$NEED_PAGILA" = true ] && [ -n "$CUSTOM_PAGILA_REPO" ] && [ "$CUSTOM_PAGILA_REPO" != "https://github.com/Troubladore/pagila.git" ]; then
        if grep -q "^PAGILA_REPO_URL=" "$PLATFORM_DIR/.env" 2>/dev/null; then
            sed -i "s|^PAGILA_REPO_URL=.*|PAGILA_REPO_URL=$CUSTOM_PAGILA_REPO|" "$PLATFORM_DIR/.env"
        else
            echo "PAGILA_REPO_URL=$CUSTOM_PAGILA_REPO" >> "$PLATFORM_DIR/.env"
        fi
    fi

    print_success "Platform configuration complete"

    # Configure infrastructure images if custom
    if [ "$USE_CUSTOM_IMAGES" = true ]; then
        print_section "Infrastructure Image Configuration"

        local infra_env="$REPO_ROOT/platform-infrastructure/.env"
        if [ ! -f "$infra_env" ]; then
            cp "$REPO_ROOT/platform-infrastructure/.env.example" "$infra_env"
            print_success "Created platform-infrastructure/.env"
        fi

        # Update PostgreSQL image
        if grep -q "^IMAGE_POSTGRES=" "$infra_env" 2>/dev/null; then
            sed -i "s|^IMAGE_POSTGRES=.*|IMAGE_POSTGRES=$CUSTOM_IMAGE_POSTGRES|" "$infra_env"
        else
            echo "IMAGE_POSTGRES=$CUSTOM_IMAGE_POSTGRES" >> "$infra_env"
        fi

        print_success "Infrastructure images configured"
    else
        # Ensure infrastructure .env exists with defaults
        if [ ! -f "$REPO_ROOT/platform-infrastructure/.env" ]; then
            cp "$REPO_ROOT/platform-infrastructure/.env.example" "$REPO_ROOT/platform-infrastructure/.env"
            # Generate password if not using trust mode
            if [ "$POSTGRES_AUTH_MODE" != "trust" ]; then
                if command -v openssl >/dev/null 2>&1; then
                    INFRA_PASS=$(openssl rand -base64 24)
                else
                    INFRA_PASS=$(head -c 24 /dev/urandom | base64)
                fi
                sed -i "s|PLATFORM_DB_PASSWORD=.*|PLATFORM_DB_PASSWORD=$INFRA_PASS|" "$REPO_ROOT/platform-infrastructure/.env"
            fi
            print_success "Created infrastructure .env with defaults"
        fi
    fi

    # Configure OpenMetadata images if custom
    if [ "$NEED_OPENMETADATA" = true ] && [ "$USE_CUSTOM_IMAGES" = true ]; then
        print_section "OpenMetadata Image Configuration"

        local om_env="$REPO_ROOT/openmetadata/.env"
        if [ ! -f "$om_env" ]; then
            cp "$REPO_ROOT/openmetadata/.env.example" "$om_env"
            print_success "Created openmetadata/.env"
        fi

        # Update images
        if grep -q "^IMAGE_OPENMETADATA_SERVER=" "$om_env" 2>/dev/null; then
            sed -i "s|^IMAGE_OPENMETADATA_SERVER=.*|IMAGE_OPENMETADATA_SERVER=$CUSTOM_IMAGE_OPENMETADATA|" "$om_env"
        else
            echo "IMAGE_OPENMETADATA_SERVER=$CUSTOM_IMAGE_OPENMETADATA" >> "$om_env"
        fi

        if grep -q "^IMAGE_OPENSEARCH=" "$om_env" 2>/dev/null; then
            sed -i "s|^IMAGE_OPENSEARCH=.*|IMAGE_OPENSEARCH=$CUSTOM_IMAGE_OPENSEARCH|" "$om_env"
        else
            echo "IMAGE_OPENSEARCH=$CUSTOM_IMAGE_OPENSEARCH" >> "$om_env"
        fi

        print_success "OpenMetadata images configured"
    fi

    # Configure Kerberos images if custom
    if [ "$NEED_KERBEROS" = true ] && [ "$USE_CUSTOM_IMAGES" = true ]; then
        print_section "Kerberos Image Configuration"

        local kerb_env="$REPO_ROOT/kerberos/.env"
        if [ ! -f "$kerb_env" ]; then
            cp "$REPO_ROOT/kerberos/.env.example" "$kerb_env"
            print_success "Created kerberos/.env"
        fi

        # Update Python image
        if grep -q "^IMAGE_PYTHON=" "$kerb_env" 2>/dev/null; then
            sed -i "s|^IMAGE_PYTHON=.*|IMAGE_PYTHON=$CUSTOM_IMAGE_PYTHON|" "$kerb_env"
        else
            echo "IMAGE_PYTHON=$CUSTOM_IMAGE_PYTHON" >> "$kerb_env"
        fi

        # Set ODBC URL only if layered mode
        if [ "$IMAGE_MODE" = "layered" ] && [ -n "$CUSTOM_ODBC_URL" ]; then
            if grep -q "^ODBC_DRIVER_URL=" "$kerb_env" 2>/dev/null; then
                sed -i "s|^ODBC_DRIVER_URL=.*|ODBC_DRIVER_URL=$CUSTOM_ODBC_URL|" "$kerb_env"
            else
                echo "ODBC_DRIVER_URL=$CUSTOM_ODBC_URL" >> "$kerb_env"
            fi
        fi

        print_success "Kerberos images configured"
    fi

    print_success "All configuration files updated!"
}

# ==========================================
# Service Setup Phase - Start Everything
# ==========================================

setup_services() {
    print_header "Starting Services"

    # Start infrastructure (always)
    print_section "Platform Infrastructure"
    echo "Starting PostgreSQL and network..."
    if cd "$REPO_ROOT/platform-infrastructure" && make start; then
        print_success "Infrastructure started"
    else
        print_error "Infrastructure setup failed"
        exit 1
    fi

    # Setup OpenMetadata
    if [ "$NEED_OPENMETADATA" = true ]; then
        print_section "OpenMetadata Setup"
        echo "Starting OpenMetadata..."
        if cd "$REPO_ROOT/openmetadata" && ./setup.sh --auto; then
            print_success "OpenMetadata started successfully!"
            echo ""
            echo "OpenMetadata is now accessible at: http://localhost:8585"
            echo "Default login: admin@open-metadata.org / admin"
            echo ""
            press_enter
        else
            print_error "OpenMetadata setup failed"
            exit 1
        fi
    fi

    # Setup Kerberos
    if [ "$NEED_KERBEROS" = true ]; then
        print_section "Kerberos Setup"
        echo "Configuring Kerberos ticket sharing..."
        echo ""
        if [ "$IMAGE_MODE" = "prebuilt" ]; then
            print_info "Using prebuilt images - skipping driver downloads"
        fi
        echo ""

        # Export IMAGE_MODE so Kerberos setup can detect it
        export IMAGE_MODE

        # Note: With prebuilt images, the Kerberos setup should be faster
        if cd "$REPO_ROOT/kerberos" && ./setup.sh; then
            print_success "Kerberos configured successfully!"
            echo ""
            echo "Kerberos ticket sharing is now active."
            echo "Your containers can authenticate to SQL Server."
            echo ""
            press_enter
        else
            print_error "Kerberos setup failed"
            exit 1
        fi
    fi

    # Setup Pagila
    if [ "$NEED_PAGILA" = true ]; then
        print_section "Pagila Database"
        echo "Setting up Pagila sample database..."
        if "$PLATFORM_DIR/setup-scripts/setup-pagila.sh" --yes; then
            print_success "Pagila database created successfully!"
            echo ""
            echo "Sample database is ready at: localhost:5432/pagila"
            if [ "$POSTGRES_AUTH_MODE" = "trust" ]; then
                echo "Connection: User 'postgres' with no password"
            else
                echo "Connection: User 'postgres' with password from .env"
            fi
            echo ""
            press_enter
        else
            print_error "Pagila setup failed"
            exit 1
        fi
    fi
}

# ==========================================
# Summary Phase
# ==========================================

show_summary() {
    clear
    print_divider
    print_success "Platform Setup Complete!"
    print_divider
    echo ""

    echo "Configuration Summary:"
    echo ""
    echo "  Image Mode: $IMAGE_MODE"
    if [ "$USE_CUSTOM_IMAGES" = true ]; then
        echo "  Custom Images: YES"
        if [ "$IMAGE_MODE" = "prebuilt" ]; then
            echo "  • No runtime downloads needed"
            echo "  • Faster container startup"
        fi
    else
        echo "  Custom Images: NO (using public)"
    fi
    echo ""

    echo "Active Services:"
    echo ""

    if [ "$NEED_OPENMETADATA" = true ]; then
        print_check "RUNNING" "OpenMetadata"
        echo "    URL: http://localhost:8585"
        echo "    Login: admin@open-metadata.org / admin"
        echo ""
    fi

    if [ "$NEED_KERBEROS" = true ]; then
        print_check "RUNNING" "Kerberos Sidecar"
        echo "    Status: Sharing tickets with containers"
        if [ -n "$DETECTED_DOMAIN" ]; then
            echo "    Domain: $DETECTED_DOMAIN"
        fi
        echo ""
    fi

    if [ "$NEED_PAGILA" = true ]; then
        print_check "RUNNING" "Pagila Database"
        echo "    Host: localhost:5432"
        echo "    Database: pagila"
        if [ "$POSTGRES_AUTH_MODE" = "trust" ]; then
            echo "    User: postgres (no password)"
        else
            echo "    User: postgres (password in .env)"
        fi
        echo ""
    fi

    echo "Next Steps:"
    echo ""
    echo "  1. Check platform status:"
    echo "     cd $PLATFORM_DIR && make platform-status"
    echo ""

    if [ "$NEED_OPENMETADATA" = true ]; then
        echo "  2. Access OpenMetadata:"
        echo "     open http://localhost:8585"
        echo ""
    fi

    echo "Service Management:"
    echo "  • Start all: make platform-start"
    echo "  • Stop all:  make platform-stop"
    echo "  • Status:    make platform-status"
    echo ""

    if [ "$USE_CUSTOM_IMAGES" = true ] && [ "$IMAGE_MODE" = "prebuilt" ]; then
        print_info "Using prebuilt images - no driver downloads required!"
    fi
}

# ==========================================
# Main Flow
# ==========================================

main() {
    print_banner

    echo "Welcome to the streamlined platform setup!"
    echo "This wizard will ask all questions upfront, then configure everything."
    echo ""
    press_enter

    # Phase 1: Detect environment
    detect_environment

    # Phase 2: Collect ALL user input upfront
    collect_all_user_input

    # Phase 3: Apply all configuration
    configure_all_services

    # Phase 4: Start services
    setup_services

    # Phase 5: Show summary
    show_summary
}

# Run the wizard
main