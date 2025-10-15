#!/bin/bash
# Comprehensive Kerberos Setup Wizard
# ====================================
# Guides developers through the entire Kerberos configuration process
# for Docker-based Airflow development with SQL Server authentication

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Progress state file for resume capability
STATE_FILE="/tmp/.kerberos-setup-state"
TOTAL_STEPS=11
CURRENT_STEP=1

# Configuration variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DETECTED_DOMAIN=""
DETECTED_USERNAME=""
DETECTED_TICKET_DIR=""
CORPORATE_ENV=false

# ==========================================
# Utility Functions
# ==========================================

print_banner() {
    clear
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}          ${BLUE}Kerberos Setup Wizard for Airflow Development${NC}         ${CYAN}║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

print_step() {
    local step_num=$1
    local step_desc=$2
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}Step ${step_num}/${TOTAL_STEPS}: ${step_desc}${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC}  $1"
}

print_info() {
    echo -e "${CYAN}ℹ${NC}  $1"
}

save_state() {
    echo "$CURRENT_STEP" > "$STATE_FILE"
}

load_state() {
    if [ -f "$STATE_FILE" ]; then
        CURRENT_STEP=$(cat "$STATE_FILE")
        return 0
    fi
    return 1
}

clear_state() {
    rm -f "$STATE_FILE"
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
# Detection Functions
# ==========================================

detect_windows_info() {
    # Try to detect Windows domain and username if in WSL2
    if [ -f /proc/sys/fs/binfmt_misc/WSLInterop ]; then
        if command -v powershell.exe >/dev/null 2>&1; then
            DETECTED_DOMAIN=$(powershell.exe -Command "([System.DirectoryServices.ActiveDirectory.Domain]::GetComputerDomain()).Name" 2>/dev/null | tr -d '\r' | tr '[:lower:]' '[:upper:]')
            if [ -n "$DETECTED_DOMAIN" ] && [[ "$DETECTED_DOMAIN" != *"Exception"* ]]; then
                print_info "Detected Windows domain: ${CYAN}$DETECTED_DOMAIN${NC}"
            fi

            DETECTED_USERNAME=$(powershell.exe -Command "\$env:USERNAME" 2>/dev/null | tr -d '\r')
            if [ -n "$DETECTED_USERNAME" ]; then
                print_info "Detected Windows username: ${CYAN}$DETECTED_USERNAME${NC}"
            fi
        fi
    fi
}

# ==========================================
# Step Functions
# ==========================================

step_1_prerequisites() {
    print_step 1 "Checking Prerequisites"

    local all_ok=true

    # Check krb5-user
    echo -n "Checking for krb5-user... "
    if command -v klist >/dev/null 2>&1 && command -v kinit >/dev/null 2>&1; then
        print_success "Found"
    else
        print_error "Not found"
        echo ""
        echo "  Kerberos tools are required. Install with:"
        echo -e "  ${CYAN}sudo apt-get update && sudo apt-get install -y krb5-user${NC}"
        all_ok=false
    fi

    # Check Docker
    echo -n "Checking for Docker... "
    if command -v docker >/dev/null 2>&1; then
        print_success "Found"

        # Check if Docker daemon is running
        echo -n "Checking if Docker daemon is running... "
        if docker info >/dev/null 2>&1; then
            print_success "Running"
        else
            print_error "Not running"
            echo ""
            echo "  Start Docker with:"
            echo -e "  ${CYAN}sudo systemctl start docker${NC}"
            echo "  or"
            echo -e "  ${CYAN}sudo service docker start${NC}"
            all_ok=false
        fi
    else
        print_error "Not found"
        echo ""
        echo "  Docker is required. Install from: https://docs.docker.com/engine/install/"
        all_ok=false
    fi

    # Check docker compose
    echo -n "Checking for Docker Compose... "
    if docker compose version >/dev/null 2>&1; then
        print_success "Found ($(docker compose version | head -1))"
    else
        print_error "Not found"
        echo ""
        echo "  Docker Compose v2+ is required."
        echo "  It's usually included with Docker Desktop or can be installed as a plugin."
        all_ok=false
    fi

    # Detect Windows info if in WSL2
    detect_windows_info

    echo ""
    if [ "$all_ok" = true ]; then
        print_success "All prerequisites are installed!"
        save_state
        return 0
    else
        echo ""
        print_error "Some prerequisites are missing."
        echo ""
        if ask_yes_no "Would you like to continue anyway? (not recommended)"; then
            save_state
            return 0
        else
            echo ""
            echo "Please install missing prerequisites and run this wizard again."
            exit 1
        fi
    fi
}

step_2_krb5_conf() {
    print_step 2 "Validating krb5.conf Configuration"

    local krb5_conf="/etc/krb5.conf"

    echo -n "Checking for $krb5_conf... "
    if [ -f "$krb5_conf" ]; then
        print_success "Found"

        echo ""
        echo "Current configuration:"
        echo "----------------------------------------"
        head -20 "$krb5_conf" | sed 's/^/  /'
        echo "  ..."
        echo "----------------------------------------"

        # Try to extract default realm
        if grep -q "default_realm" "$krb5_conf"; then
            local realm=$(grep "default_realm" "$krb5_conf" | head -1 | sed 's/.*= *//' | tr -d ' ')
            print_info "Default realm: ${CYAN}$realm${NC}"

            # Use detected realm if we don't have one yet
            if [ -z "$DETECTED_DOMAIN" ] && [ -n "$realm" ]; then
                DETECTED_DOMAIN="$realm"
            fi
        fi

        echo ""
        print_success "krb5.conf is properly configured"
        save_state
        return 0
    else
        print_error "Not found"
        echo ""
        echo "  The file /etc/krb5.conf is required for Kerberos authentication."
        echo ""
        echo -e "  ${YELLOW}Options:${NC}"
        echo "  1. Contact your IT department for the correct krb5.conf"
        echo "  2. Copy it from another working system"
        echo "  3. Use your organization's domain controller DNS to auto-configure"
        echo ""

        if ask_yes_no "Do you want to continue without krb5.conf? (not recommended)"; then
            print_warning "Continuing without proper krb5.conf - authentication may fail"
            save_state
            return 0
        else
            echo ""
            echo "Please configure krb5.conf and run this wizard again."
            exit 1
        fi
    fi
}

step_3_test_kdc() {
    print_step 3 "Testing KDC Reachability"

    # If user already has a valid ticket, KDC is obviously reachable - skip test
    if klist -s 2>/dev/null; then
        print_info "You already have a valid Kerberos ticket"
        klist 2>/dev/null | head -3 | sed 's/^/  /'
        echo ""
        print_success "KDC is reachable (you have a valid ticket!)"
        echo ""
        print_info "Skipping network connectivity test - ticket proves KDC works"
        save_state
        return 0
    fi

    # No ticket yet - test KDC connectivity
    # Extract KDC from krb5.conf if available
    local kdc=""
    if [ -f /etc/krb5.conf ]; then
        kdc=$(grep -m 1 "kdc = " /etc/krb5.conf | sed 's/.*kdc = *//' | tr -d ' ')
    fi

    if [ -n "$kdc" ]; then
        print_info "Testing connection to KDC: ${CYAN}$kdc${NC}"
        echo ""
        print_info "Method: TCP connection test to port 88"
        echo ""

        # Try to reach KDC on port 88 (Kerberos)
        local kdc_host=$(echo "$kdc" | cut -d: -f1)
        local kdc_port=$(echo "$kdc" | cut -d: -f2)
        [ "$kdc_port" = "$kdc_host" ] && kdc_port="88"

        echo -n "Testing ${kdc_host}:${kdc_port}... "
        if timeout 5 bash -c "echo > /dev/tcp/$kdc_host/$kdc_port" 2>/dev/null; then
            print_success "Reachable"
            echo ""
            print_success "KDC is accessible"
        else
            print_error "TCP test failed"
            echo ""
            print_warning "TCP connectivity test failed, but this doesn't necessarily mean there's a problem"
            print_info "The KDC may be reachable via UDP or DNS SRV records"
            echo ""
            print_info "We'll verify in the next step by actually obtaining a ticket"
            echo ""
            echo -e "  ${YELLOW}Possible solutions:${NC}"
            echo "  1. Connect to your corporate VPN"
            echo "  2. Check your network connection"
            echo "  3. Verify krb5.conf has correct KDC address"
            echo ""

            if ! ask_yes_no "Continue anyway?"; then
                echo ""
                echo "Please connect to VPN and run this wizard again."
                exit 1
            fi
        fi
    else
        print_warning "Could not detect KDC from krb5.conf"
        print_info "Skipping KDC reachability test"
    fi

    save_state
}

step_4_kerberos_ticket() {
    print_step 4 "Checking for Kerberos Ticket"

    echo -n "Checking for active Kerberos ticket... "
    if klist -s 2>/dev/null; then
        print_success "Found"
        echo ""
        echo "Current ticket details:"
        echo "----------------------------------------"
        klist | head -5 | sed 's/^/  /'
        echo "----------------------------------------"

        # Extract principal and expiry
        local principal=$(klist 2>/dev/null | grep "Default principal:" | sed 's/Default principal: //')
        local expiry=$(klist 2>/dev/null | grep "Expires" | head -1 | awk '{print $3, $4}')

        if [ -n "$principal" ]; then
            print_info "Principal: ${CYAN}$principal${NC}"

            # Extract domain and username
            DETECTED_DOMAIN=$(echo "$principal" | sed 's/.*@//')
            DETECTED_USERNAME=$(echo "$principal" | sed 's/@.*//')
        fi

        if [ -n "$expiry" ]; then
            print_info "Expires: ${CYAN}$expiry${NC}"
        fi

        echo ""
        if ask_yes_no "Would you like to use this ticket?"; then
            print_success "Using existing ticket"
            save_state
            return 0
        else
            echo ""
            print_info "Will obtain a new ticket..."
        fi
    else
        print_error "No active ticket found"
        echo ""
    fi

    # Obtain new ticket
    echo ""
    echo "You need a Kerberos ticket to proceed."
    echo ""

    # Suggest username
    local suggested_user=""
    if [ -n "$DETECTED_USERNAME" ]; then
        suggested_user="$DETECTED_USERNAME"
    elif [ -n "$(whoami)" ]; then
        suggested_user="$(whoami)"
    fi

    local username=""
    if [ -n "$suggested_user" ]; then
        read -p "Enter your username [${suggested_user}]: " username
        username=${username:-$suggested_user}
    else
        read -p "Enter your username: " username
    fi

    if [ -z "$username" ]; then
        print_error "Username is required"
        return 1
    fi

    # Construct principal
    local principal=""
    if [ -n "$DETECTED_DOMAIN" ]; then
        principal="${username}@${DETECTED_DOMAIN}"
    else
        read -p "Enter your domain (e.g., COMPANY.COM): " domain
        principal="${username}@${domain}"
        DETECTED_DOMAIN="$domain"
    fi

    echo ""
    echo -e "Running: ${CYAN}kinit $principal${NC}"
    echo ""

    if kinit "$principal"; then
        echo ""
        print_success "Ticket obtained successfully!"
        echo ""
        klist | head -5 | sed 's/^/  /'

        # Update detected username
        DETECTED_USERNAME="$username"

        save_state
        return 0
    else
        echo ""
        print_error "Failed to obtain Kerberos ticket"
        echo ""
        echo -e "  ${YELLOW}Possible issues:${NC}"
        echo "  1. Incorrect password"
        echo "  2. Not connected to VPN"
        echo "  3. Username or domain is incorrect"
        echo "  4. Account may be locked or expired"
        echo ""

        if ask_yes_no "Try again?"; then
            return $(step_4_kerberos_ticket)
        else
            exit 1
        fi
    fi
}

step_5_detect_ticket_location() {
    print_step 5 "Detecting Ticket Location"

    print_info "Running Kerberos diagnostic tool..."
    echo ""

    # Run diagnose-kerberos.sh and capture output
    if [ -f "$SCRIPT_DIR/diagnose-kerberos.sh" ]; then
        # Run diagnostic and parse output
        local diag_output=$("$SCRIPT_DIR/diagnose-kerberos.sh" 2>&1)

        # Try to extract configuration from diagnostic output
        DETECTED_TICKET_DIR=$(echo "$diag_output" | grep "^KERBEROS_TICKET_DIR=" | cut -d= -f2)

        # Show relevant parts of diagnostic output
        echo "$diag_output" | sed -n '/=== 1\. HOST KERBEROS TICKETS ===/,/=== 2\. COMMON TICKET LOCATIONS ===/p' | head -n -1

        if [ -n "$DETECTED_TICKET_DIR" ]; then
            echo ""
            print_success "Ticket location detected successfully!"
            echo ""
            echo -e "  ${BLUE}Configuration Value:${NC}"
            echo -e "    Ticket directory: ${CYAN}$DETECTED_TICKET_DIR${NC}"
            echo ""
            echo -e "  The sidecar will automatically find and copy tickets from this directory."

            save_state
            return 0
        else
            echo ""
            print_warning "Could not auto-detect ticket location"

            # Show where to look in the diagnostic output
            echo ""
            echo "Full diagnostic output saved to /tmp/kerberos-diagnostic.log"
            echo "$diag_output" > /tmp/kerberos-diagnostic.log

            echo ""
            print_info "You can:"
            echo "  1. Review the diagnostic log: less /tmp/kerberos-diagnostic.log"
            echo "  2. Manually configure values in the next step"
            echo "  3. Exit and run: ${CYAN}./diagnose-kerberos.sh${NC} for detailed guidance"
            echo ""

            if ask_yes_no "Continue with manual configuration?"; then
                save_state
                return 0
            else
                exit 1
            fi
        fi
    else
        print_error "diagnose-kerberos.sh not found"
        echo ""
        print_info "Manual configuration will be required in the next step"
        save_state
    fi
}

step_6_update_env() {
    print_step 6 "Updating .env Configuration"

    local env_file="$SCRIPT_DIR/.env"
    local env_example="$SCRIPT_DIR/.env.example"

    # Check if .env exists
    if [ ! -f "$env_file" ]; then
        echo -n "Creating .env from .env.example... "
        if [ -f "$env_example" ]; then
            cp "$env_example" "$env_file"
            print_success "Created"
        else
            print_error ".env.example not found"
            echo ""
            echo "Creating minimal .env file..."
            cat > "$env_file" << EOF
# Platform Bootstrap Configuration
COMPANY_DOMAIN=COMPANY.COM
KERBEROS_TICKET_DIR=/tmp
EOF
            print_success "Created minimal .env"
        fi
        echo ""
    fi

    # Show current configuration
    echo "Current .env configuration:"
    echo "----------------------------------------"

    # Check for both old and new variables
    local has_old_config=false
    if grep -qE "^KERBEROS_CACHE_(TYPE|PATH|TICKET)=" "$env_file" 2>/dev/null; then
        has_old_config=true
        echo -e "  ${YELLOW}Found old 3-variable configuration (needs migration):${NC}"
        grep -E "^KERBEROS_CACHE_(TYPE|PATH|TICKET)=" "$env_file" | sed 's/^/    OLD: /'
        echo ""
    fi

    grep -E "^(COMPANY_DOMAIN|KERBEROS_TICKET_DIR)=" "$env_file" 2>/dev/null | sed 's/^/  /' || echo "  (no Kerberos configuration found)"
    echo "----------------------------------------"

    if [ "$has_old_config" = true ]; then
        echo ""
        print_warning "Old configuration format detected"
        echo ""
        if ask_yes_no "Replace old 3-variable config with new single variable?" "y"; then
            # Remove old variables
            sed -i '/^KERBEROS_CACHE_TYPE=/d' "$env_file"
            sed -i '/^KERBEROS_CACHE_PATH=/d' "$env_file"
            sed -i '/^KERBEROS_CACHE_TICKET=/d' "$env_file"
            print_success "Old configuration removed"
        fi
    fi

    echo ""

    # Determine if we have detected values
    if [ -n "$DETECTED_TICKET_DIR" ]; then
        echo "Detected configuration:"
        echo "----------------------------------------"
        [ -n "$DETECTED_DOMAIN" ] && echo "  COMPANY_DOMAIN=$DETECTED_DOMAIN"
        echo "  KERBEROS_TICKET_DIR=$DETECTED_TICKET_DIR"
        echo "----------------------------------------"
        echo ""

        # Check if current .env already matches detected values
        local needs_update=false
        local current_dir=$(grep "^KERBEROS_TICKET_DIR=" "$env_file" 2>/dev/null | cut -d= -f2-)

        if [ "$current_dir" != "$DETECTED_TICKET_DIR" ]; then
            needs_update=true
        fi

        if [ "$needs_update" = false ]; then
            print_success ".env already has correct configuration - no update needed!"
            save_state
            return 0
        fi

        if ask_yes_no "Update .env with these detected values?" "y"; then
            # Update .env file
            if [ -n "$DETECTED_DOMAIN" ]; then
                if grep -q "^COMPANY_DOMAIN=" "$env_file"; then
                    sed -i "s|^COMPANY_DOMAIN=.*|COMPANY_DOMAIN=$DETECTED_DOMAIN|" "$env_file"
                else
                    echo "COMPANY_DOMAIN=$DETECTED_DOMAIN" >> "$env_file"
                fi
            fi

            # Update or add KERBEROS_TICKET_DIR
            if grep -q "^KERBEROS_TICKET_DIR=" "$env_file"; then
                sed -i "s|^KERBEROS_TICKET_DIR=.*|KERBEROS_TICKET_DIR=$DETECTED_TICKET_DIR|" "$env_file"
            else
                echo "KERBEROS_TICKET_DIR=$DETECTED_TICKET_DIR" >> "$env_file"
            fi

            print_success ".env file updated successfully!"
            save_state
            return 0
        fi
    fi

    # Manual configuration
    echo ""
    echo -e "${YELLOW}Manual configuration required${NC}"
    echo ""

    if ask_yes_no "Would you like to manually edit .env now?"; then
        ${EDITOR:-nano} "$env_file"
        echo ""
        print_success "Configuration saved"
    else
        print_warning "Skipping .env update - you'll need to configure it manually"
        echo ""
        echo -e "  Edit: ${CYAN}$env_file${NC}"
        echo ""
        echo "  Required variables:"
        echo "    COMPANY_DOMAIN=YOUR_DOMAIN.COM"
        echo "    KERBEROS_TICKET_DIR=/path/to/ticket/directory"
    fi

    save_state
}

step_7_corporate_environment() {
    print_step 7 "Corporate Environment Configuration"

    echo "Does your organization block access to public Docker registries"
    echo "(Docker Hub, download.microsoft.com, etc.)?"
    echo ""
    print_info "Corporate environments typically require using Artifactory or internal mirrors"
    echo ""

    if ask_yes_no "Are you in a corporate environment with restricted internet access?"; then
        CORPORATE_ENV=true
        echo ""
        print_info "Corporate environment detected"
        echo ""
        echo "This setup will need to pull several Docker images."
        echo "Each may be in a different Artifactory repository path."
        echo ""
        print_warning "Ask your DevOps team for the exact paths, or reference your"
        print_warning "organization's Artifactory documentation."
        echo ""

        # Check if .env already has corporate config
        if [ -f "$SCRIPT_DIR/.env" ]; then
            local has_config=false
            if grep -q "^IMAGE_ALPINE=" "$SCRIPT_DIR/.env" && ! grep -q "^IMAGE_ALPINE=$" "$SCRIPT_DIR/.env"; then
                has_config=true
            fi

            if [ "$has_config" = true ]; then
                print_success ".env already has corporate configuration"
                echo ""
                echo "Current settings:"
                grep -E "^(IMAGE_ALPINE|IMAGE_PYTHON|IMAGE_MOCKSERVER|ODBC_DRIVER_URL)=" "$SCRIPT_DIR/.env" 2>/dev/null | sed 's/^/  /' || echo "  (partial configuration)"
                echo ""

                if ask_yes_no "Use existing configuration?" "y"; then
                    save_state
                    return 0
                fi
            fi
        fi

        echo ""
        print_info "Configure Artifactory paths for Docker images"
        echo ""
        echo "Press Enter to use public defaults (if Artifactory mirrors them automatically)"
        echo ""

        # IMAGE_ALPINE (for sidecar base + testing)
        echo -e "${CYAN}1. Alpine Linux (sidecar base + diagnostic tests):${NC}"
        echo "   ${YELLOW}Public default:${NC} alpine:3.19 (from registry-1.docker.io)"
        echo "   ${YELLOW}Also pulls:${NC}     alpine:latest"
        echo ""
        echo "   Corporate example:"
        echo "   artifactory.yourcompany.com/docker-remote/library/alpine:3.19"
        echo ""
        read -p "   Your Artifactory path (or Enter to use public): " image_alpine

        # IMAGE_PYTHON (for testing scripts)
        echo ""
        echo -e "${CYAN}2. Python (for testing scripts):${NC}"
        echo "   ${YELLOW}Public default:${NC} python:3.11-alpine (from registry-1.docker.io)"
        echo ""
        echo "   ${YELLOW}Golden images:${NC} You can substitute your organization's approved image"
        echo "                   Examples: python:3.11-slim, chainguard/python:latest, etc."
        echo ""
        echo "   Corporate example:"
        echo "   artifactory.yourcompany.com/docker-remote/library/python:3.11-alpine"
        echo "   artifactory.yourcompany.com/chainguard/python:3.11"
        echo ""
        read -p "   Your image path (full path including tag): " image_python

        # IMAGE_MOCKSERVER (mock services)
        echo ""
        echo -e "${CYAN}3. MockServer (for mock Delinea service):${NC}"
        echo "   ${YELLOW}Public default:${NC} mockserver/mockserver:latest (from registry-1.docker.io)"
        echo ""
        echo "   Corporate example:"
        echo "   artifactory.yourcompany.com/docker-remote/mockserver/mockserver:latest"
        echo ""
        read -p "   Your Artifactory path (or Enter to use public): " image_mockserver

        # IMAGE_ASTRONOMER (for when they create Airflow projects)
        echo ""
        echo -e "${CYAN}4. Astronomer Runtime (for your Airflow projects):${NC}"
        echo "   ${YELLOW}Public default:${NC} quay.io/astronomer/astro-runtime:11.10.0"
        echo "                   (from quay.io registry)"
        echo ""
        echo "   Corporate example:"
        echo "   artifactory.yourcompany.com/quay-remote/astronomer/astro-runtime:11.10.0"
        echo ""
        read -p "   Your Artifactory path (or Enter to use public): " image_astronomer

        # ODBC_DRIVER_URL (Microsoft binaries)
        echo ""
        echo -e "${CYAN}5. Microsoft ODBC Drivers (binary downloads):${NC}"
        echo -e "   ${YELLOW}Public default:${NC}"
        echo "   https://download.microsoft.com/download/3/5/5/355d7943-a338-41a7-858d-53b259ea33f5/"
        echo ""
        echo "   ${YELLOW}Files:${NC} msodbcsql18_18.3.2.1-1_amd64.apk"
        echo "          mssql-tools18_18.3.1.1-1_amd64.apk"
        echo ""
        echo "   Corporate example:"
        echo "   https://artifactory.yourcompany.com/microsoft-binaries/odbc/v18.3"
        echo ""
        read -p "   Your Artifactory mirror URL (or Enter to use public): " odbc_url

        # Update .env
        echo ""
        print_info "Updating .env with corporate configuration..."
        echo ""

        local env_file="$SCRIPT_DIR/.env"
        if [ ! -f "$env_file" ]; then
            cp "$SCRIPT_DIR/.env.example" "$env_file"
        fi

        # Helper function to update .env variable
        update_env_var() {
            local var_name=$1
            local var_value=$2
            local env_file=$3

            if [ -n "$var_value" ]; then
                if grep -q "^${var_name}=" "$env_file"; then
                    sed -i "s|^${var_name}=.*|${var_name}=${var_value}|" "$env_file"
                elif grep -q "^# ${var_name}=" "$env_file"; then
                    sed -i "s|^# ${var_name}=.*|${var_name}=${var_value}|" "$env_file"
                else
                    echo "${var_name}=${var_value}" >> "$env_file"
                fi
                echo "  ✓ $var_name"
            fi
        }

        # Update all configured variables
        update_env_var "IMAGE_ALPINE" "$image_alpine" "$env_file"
        update_env_var "IMAGE_PYTHON" "$image_python" "$env_file"
        update_env_var "IMAGE_MOCKSERVER" "$image_mockserver" "$env_file"
        update_env_var "IMAGE_ASTRONOMER" "$image_astronomer" "$env_file"
        update_env_var "ODBC_DRIVER_URL" "$odbc_url" "$env_file"
        update_env_var "PIP_INDEX_URL" "$pip_index_url" "$env_file"
        update_env_var "PIP_TRUSTED_HOST" "$pip_trusted_host" "$env_file"

        echo ""
        print_success "Corporate configuration saved to .env"

        echo ""
        print_warning "IMPORTANT: Docker login required!"
        echo ""
        echo "Before building, you must authenticate to your Artifactory:"
        echo -e "  ${CYAN}docker login artifactory.yourcompany.com${NC}"
        echo ""

        if ask_yes_no "Have you already run docker login for your Artifactory?" "y"; then
            print_success "Docker login confirmed"
        else
            echo ""
            print_info "Please login to Artifactory now:"
            echo ""
            echo -e "  ${CYAN}docker login ${image_alpine%%/*}${NC}"
            echo ""
            read -p "Press Enter after you've logged in..."
        fi

        echo ""
        print_success "Corporate environment configured!"
        print_info "Build will use your Artifactory paths"

    else
        print_info "Using public internet (Docker Hub, Microsoft downloads)"
        print_warning "Ensure you have internet connectivity for image pulls"
    fi

    echo ""
    save_state
}

step_8_build_sidecar() {
    print_step 8 "Building Kerberos Sidecar Image"

    echo -n "Checking for existing image... "
    if docker image inspect platform/kerberos-sidecar:latest >/dev/null 2>&1; then
        print_success "Found"
        echo ""

        local image_date=$(docker image inspect platform/kerberos-sidecar:latest --format='{{.Created}}' | cut -d'T' -f1)
        print_info "Image created: ${CYAN}$image_date${NC}"

        echo ""
        if ask_yes_no "Rebuild the image?"; then
            echo ""
            print_info "Rebuilding..."
        else
            print_success "Using existing image"
            save_state
            return 0
        fi
    else
        print_error "Not found"
        echo ""
        print_info "Building sidecar image (this may take a few minutes)..."
    fi

    echo ""

    # Build the image
    if [ -d "$SCRIPT_DIR/kerberos-sidecar" ]; then
        cd "$SCRIPT_DIR/kerberos-sidecar"

        if [ -f "Makefile" ]; then
            if make build; then
                echo ""
                print_success "Sidecar image built successfully!"
                save_state
                cd "$SCRIPT_DIR"
                return 0
            else
                echo ""
                print_error "Failed to build sidecar image"
                cd "$SCRIPT_DIR"
                return 1
            fi
        else
            print_error "Makefile not found in kerberos-sidecar/"
            cd "$SCRIPT_DIR"
            return 1
        fi
    else
        print_error "kerberos-sidecar directory not found"
        echo ""
        echo "  Expected location: $SCRIPT_DIR/kerberos-sidecar/"
        return 1
    fi
}

step_9_start_services() {
    print_step 9 "Starting Platform Services"

    # Ensure Docker networks and volumes exist
    echo "Setting up Docker infrastructure..."
    echo ""

    echo -n "Creating platform_network... "
    if docker network create platform_network 2>/dev/null; then
        print_success "Created"
    elif docker network ls | grep -q "platform_network"; then
        print_info "Already exists"
    else
        print_warning "Failed to create (may already exist from previous setup)"
    fi

    echo -n "Creating platform_kerberos_cache volume... "
    if docker volume create platform_kerberos_cache 2>/dev/null; then
        print_success "Created"
    elif docker volume ls | grep -q "platform_kerberos_cache"; then
        print_info "Already exists"
    else
        print_warning "Failed to create"
    fi

    echo ""
    print_info "Starting services with docker compose..."
    echo ""

    cd "$SCRIPT_DIR"

    if docker compose up -d; then
        echo ""
        print_success "Services started successfully!"
        echo ""

        # Wait a moment for services to initialize
        echo -n "Waiting for services to initialize"
        for i in {1..3}; do
            sleep 1
            echo -n "."
        done
        echo ""
        echo ""

        # Show running services
        echo "Running services:"
        docker compose ps

        save_state
        return 0
    else
        echo ""
        print_error "Failed to start services"
        echo ""
        echo "  Check the logs with:"
        echo -e "  ${CYAN}docker compose logs${NC}"
        return 1
    fi
}

step_10_test_ticket_sharing() {
    print_step 10 "Testing Kerberos Ticket Sharing"

    print_info "Running simple ticket sharing test..."
    echo ""

    # Check if test script exists
    if [ ! -f "$SCRIPT_DIR/test_kerberos_simple.py" ]; then
        print_warning "test_kerberos_simple.py not found"
        print_info "Skipping ticket sharing test"
        save_state
        return 0
    fi

    # Determine test image (use configured from .env or default)
    # Load .env to get IMAGE_PYTHON if configured
    if [ -f "$SCRIPT_DIR/.env" ]; then
        source "$SCRIPT_DIR/.env" 2>/dev/null || true
    fi

    local test_image="${IMAGE_PYTHON:-python:3.11-alpine}"

    # Detect package manager based on image
    local install_cmd="apk add --no-cache krb5"  # Alpine default
    if [[ "$test_image" == *"debian"* ]] || [[ "$test_image" == *"ubuntu"* ]] || [[ "$test_image" == *":3.11"* ]] && [[ "$test_image" != *"alpine"* ]]; then
        install_cmd="apt-get update -qq && apt-get install -y -qq krb5-user"
    elif [[ "$test_image" == *"chainguard"* ]] || [[ "$test_image" == *"wolfi"* ]]; then
        install_cmd="apk add --no-cache krb5"  # Wolfi uses apk
    fi

    print_info "Using test image: ${CYAN}$test_image${NC}"
    echo -e "  Package install: $install_cmd"
    echo ""

    # Run the test
    if docker run --rm \
        --network platform_network \
        -v platform_kerberos_cache:/krb5/cache:ro \
        -v "$SCRIPT_DIR/test_kerberos_simple.py:/app/test.py" \
        -e KRB5CCNAME=/krb5/cache/krb5cc \
        "$test_image" \
        sh -c "$install_cmd >/dev/null 2>&1 && python /app/test.py" 2>&1 | tee /tmp/kerberos-test-output.txt | grep -q "SUCCESS"; then

        echo ""
        print_success "Ticket sharing test PASSED!"
        echo ""
        print_success "Kerberos tickets are successfully shared with containers"

        save_state
        return 0
    else
        echo ""
        print_error "Ticket sharing test FAILED"
        echo ""
        echo "Test output saved to: /tmp/kerberos-test-output.txt"
        # Smart failure analysis
        local test_output=$(cat /tmp/kerberos-test-output.txt 2>/dev/null || echo "")

        echo -e "${BLUE}Analyzing failure...${NC}"
        echo ""

        # Check 1: Is sidecar even running?
        if ! docker ps --format "{{.Names}}" | grep -q "kerberos-platform-service"; then
            print_error "ROOT CAUSE: Kerberos sidecar is NOT running"
            echo ""
            echo -e "${BLUE}FIX:${NC}"
            echo "  Sidecar failed to start in Step 9. Check logs:"
            echo "    ${CYAN}docker compose logs developer-kerberos-service${NC}"

        # Check 2: Sidecar running but no ticket in volume?
        elif echo "$test_output" | grep -q "does NOT exist"; then
            print_error "ROOT CAUSE: Sidecar running but ticket not copied to volume"
            echo ""

            # Check if sidecar itself has a ticket
            if docker exec kerberos-platform-service klist -s 2>/dev/null; then
                print_warning "Sidecar HAS ticket, but not sharing it"
                echo ""
                echo -e "${BLUE}FIX:${NC}"
                echo "  Check what's in volume:"
                echo "    ${CYAN}docker exec kerberos-platform-service ls -la /krb5/cache/${NC}"
            else
                print_error "Sidecar does NOT have ticket"
                echo ""
                echo -e "${BLUE}FIX:${NC}"
                echo -e "  Sidecar can't obtain tickets. Check logs:"
                echo -e "    ${CYAN}docker logs kerberos-platform-service --tail 30${NC}"
                echo ""
                echo -e "  Common causes:"
                echo -e "    - Wrong ticket path in .env (KERBEROS_TICKET_DIR)"
                echo -e "    - Missing password/keytab configuration"
            fi

        else
            print_warning "Test failed for unknown reason"
            echo ""
            echo "  Output: /tmp/kerberos-test-output.txt"
            echo "  Diagnostic: ${CYAN}./diagnose-kerberos.sh${NC}"
        fi

        echo ""
        if ask_yes_no "Continue anyway?"; then
            save_state
            return 0
        else
            return 1
        fi
    fi
}

step_11_test_sql_server() {
    print_step 11 "Testing SQL Server Connection (Optional)"

    echo "This step tests authentication to an actual SQL Server database."
    echo ""
    print_info "This is optional but recommended to verify end-to-end connectivity"
    echo ""

    # Check if test image exists, offer to build if not
    if ! docker image inspect platform/kerberos-test:latest >/dev/null 2>&1; then
        echo ""
        print_warning "Test image not found (platform/kerberos-test:latest)"
        echo ""
        print_info "The test image has pyodbc pre-installed (avoids runtime pip downloads)"
        print_info "For corporate environments, this prevents PyPI access during testing"
        echo ""

        if ask_yes_no "Build test image now? (recommended for corporate environments)" "y"; then
            echo ""
            print_info "Building test image..."
            cd "$SCRIPT_DIR/kerberos-sidecar"
            if make build-test-image; then
                cd "$SCRIPT_DIR"
                print_success "Test image built successfully!"
            else
                cd "$SCRIPT_DIR"
                print_warning "Test image build failed - will use runtime install instead"
                echo "  (may fail if PyPI is blocked)"
            fi
            echo ""
        fi
    fi

    if ! ask_yes_no "Would you like to test SQL Server connection?"; then
        print_info "Skipping SQL Server test"
        save_state
        return 0
    fi

    echo ""

    # Check for saved SQL Server details from previous run
    local saved_server=""
    local saved_database=""
    if [ -f "$SCRIPT_DIR/.env" ]; then
        saved_server=$(grep "^TEST_SQL_SERVER=" "$SCRIPT_DIR/.env" 2>/dev/null | cut -d= -f2)
        saved_database=$(grep "^TEST_SQL_DATABASE=" "$SCRIPT_DIR/.env" 2>/dev/null | cut -d= -f2)
    fi

    if [ -n "$saved_server" ] && [ -n "$saved_database" ]; then
        print_info "Found saved SQL Server configuration:"
        echo "  Server:   $saved_server"
        echo "  Database: $saved_database"
        echo ""

        if ask_yes_no "Use these settings?" "y"; then
            sql_server="$saved_server"
            sql_database="$saved_database"
        else
            saved_server=""
            saved_database=""
        fi
    fi

    # Prompt for SQL Server details if not using saved
    if [ -z "$saved_server" ]; then
        echo "You'll need:"
        echo "  1. SQL Server hostname (e.g., sqlserver01.company.com)"
        echo "  2. Database name (e.g., TestDB or AdventureWorks)"
        echo ""
        print_info "Ask your DBA or check your team's documentation for test servers"
        echo ""

        read -p "SQL Server hostname (or 'skip' to skip): " sql_server

        if [ "$sql_server" = "skip" ] || [ -z "$sql_server" ]; then
            print_info "Skipping SQL Server test"
            save_state
            return 0
        fi

        read -p "Database name: " sql_database

        if [ -z "$sql_database" ]; then
            print_warning "Database name is required for SQL Server test"
            print_info "Skipping SQL Server test"
            save_state
            return 0
        fi

        # Save for future runs
        echo ""
        if ask_yes_no "Save these SQL Server details for future tests?" "y"; then
            if grep -q "^TEST_SQL_SERVER=" "$SCRIPT_DIR/.env" 2>/dev/null; then
                sed -i "s|^TEST_SQL_SERVER=.*|TEST_SQL_SERVER=$sql_server|" "$SCRIPT_DIR/.env"
            else
                echo "TEST_SQL_SERVER=$sql_server" >> "$SCRIPT_DIR/.env"
            fi

            if grep -q "^TEST_SQL_DATABASE=" "$SCRIPT_DIR/.env" 2>/dev/null; then
                sed -i "s|^TEST_SQL_DATABASE=.*|TEST_SQL_DATABASE=$sql_database|" "$SCRIPT_DIR/.env"
            else
                echo "TEST_SQL_DATABASE=$sql_database" >> "$SCRIPT_DIR/.env"
            fi

            print_success "SQL Server details saved to .env"
        fi
    fi

    echo ""
    print_info "Testing connection to ${CYAN}${sql_server}/${sql_database}${NC}..."
    echo ""

    # Check if test script exists
    if [ -f "$SCRIPT_DIR/test-kerberos.sh" ]; then
        if "$SCRIPT_DIR/test-kerberos.sh" "$sql_server" "$sql_database"; then
            echo ""
            print_success "SQL Server connection test PASSED!"
            save_state
            return 0
        else
            echo ""
            print_error "SQL Server connection test FAILED"
            echo ""
            print_info "This may be due to:"
            echo "  1. Incorrect server/database name"
            echo "  2. Network connectivity issues"
            echo "  3. Permission problems"
            echo "  4. Server not configured for Kerberos"
            echo ""
            print_info "The basic ticket sharing is working, so you can still proceed"
        fi
    else
        print_warning "test-kerberos.sh not found - skipping SQL Server test"
    fi

    save_state
}

# ==========================================
# Summary and Next Steps
# ==========================================

show_summary() {
    print_banner
    echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║${NC}                    ${GREEN}Setup Complete!${NC}                             ${GREEN}║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    echo -e "${CYAN}Configuration Summary:${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # Show configuration
    if [ -f "$SCRIPT_DIR/.env" ]; then
        grep -E "^(COMPANY_DOMAIN|KERBEROS_TICKET_DIR)=" "$SCRIPT_DIR/.env" 2>/dev/null | sed 's/^/  /' || echo "  (configuration not found)"
    fi

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    echo -e "${CYAN}Running Services:${NC}"
    docker compose ps 2>/dev/null | sed 's/^/  /'
    echo ""

    echo -e "${CYAN}What's Next:${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo -e "  1. ${GREEN}Create or start your Airflow project:${NC}"
    echo -e "     ${CYAN}astro dev init my-project${NC}    # New project"
    echo -e "     ${CYAN}cd my-project && astro dev start${NC}"
    echo ""
    echo -e "  2. ${GREEN}Your Airflow containers will automatically have access to:${NC}"
    echo "     • Kerberos tickets (for SQL Server authentication)"
    echo "     • Shared network (platform_network)"
    echo ""
    echo -e "  3. ${GREEN}Useful commands:${NC}"
    echo -e "     ${CYAN}make platform-status${NC}       # Check service status"
    echo -e "     ${CYAN}make kerberos-test${NC}         # Verify Kerberos ticket"
    echo -e "     ${CYAN}make test-kerberos-simple${NC}  # Test ticket sharing"
    echo -e "     ${CYAN}docker compose logs${NC}        # View service logs"
    echo ""
    echo -e "  4. ${GREEN}Managing Kerberos tickets:${NC}"
    echo -e "     ${CYAN}klist${NC}                      # Check ticket status"
    echo -e "     ${CYAN}kinit $DETECTED_USERNAME@$DETECTED_DOMAIN${NC}  # Renew ticket"
    echo -e "     ${CYAN}./diagnose-kerberos.sh${NC}     # Troubleshoot issues"
    echo ""
    echo -e "  5. ${GREEN}When done for the day:${NC}"
    echo -e "     ${CYAN}make platform-stop${NC}         # Stop all services"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    if [ -n "$DETECTED_DOMAIN" ]; then
        print_info "Your domain: ${CYAN}$DETECTED_DOMAIN${NC}"
    fi

    if [ -n "$DETECTED_USERNAME" ]; then
        print_info "Your username: ${CYAN}$DETECTED_USERNAME${NC}"
    fi

    echo ""
    print_success "Kerberos setup is complete and ready to use!"
    echo ""

    # Clear state file since we're done
    clear_state
}

show_help() {
    echo "Kerberos Setup Wizard"
    echo ""
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  --resume    Resume from last saved step"
    echo "  --reset     Clear saved state and start fresh"
    echo "  --help      Show this help message"
    echo ""
    echo "This wizard guides you through setting up Kerberos authentication"
    echo "for Docker-based Airflow development with SQL Server."
    echo ""
}

# ==========================================
# Main Execution
# ==========================================

main() {
    # Parse command line arguments
    case "${1:-}" in
        --help|-h)
            show_help
            exit 0
            ;;
        --reset)
            clear_state
            echo "State cleared. Starting fresh..."
            echo ""
            ;;
        --resume)
            if load_state; then
                echo "Resuming from step $CURRENT_STEP..."
                echo ""
            else
                echo "No saved state found. Starting from beginning..."
                CURRENT_STEP=1
            fi
            ;;
        "")
            # Check for existing state
            if load_state; then
                print_warning "Found saved progress from previous run"
                if ask_yes_no "Resume from step $CURRENT_STEP?"; then
                    echo ""
                else
                    CURRENT_STEP=1
                    clear_state
                fi
            fi
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac

    # Show banner
    print_banner

    echo "This wizard will guide you through setting up Kerberos authentication"
    echo "for Docker-based Airflow development."
    echo ""
    echo "The setup process includes:"
    echo "  • Checking prerequisites"
    echo "  • Validating Kerberos configuration"
    echo "  • Obtaining Kerberos tickets"
    echo "  • Configuring Docker integration"
    echo "  • Testing the setup"
    echo ""

    if [ $CURRENT_STEP -eq 1 ]; then
        press_enter
    fi

    # Execute steps
    [ $CURRENT_STEP -le 1 ] && { step_1_prerequisites && CURRENT_STEP=2; }
    [ $CURRENT_STEP -le 2 ] && { step_2_krb5_conf && CURRENT_STEP=3; }
    [ $CURRENT_STEP -le 3 ] && { step_3_test_kdc && CURRENT_STEP=4; }
    [ $CURRENT_STEP -le 4 ] && { step_4_kerberos_ticket && CURRENT_STEP=5; }
    [ $CURRENT_STEP -le 5 ] && { step_5_detect_ticket_location && CURRENT_STEP=6; }
    [ $CURRENT_STEP -le 6 ] && { step_6_update_env && CURRENT_STEP=7; }
    [ $CURRENT_STEP -le 7 ] && { step_7_corporate_environment && CURRENT_STEP=8; }
    [ $CURRENT_STEP -le 8 ] && { step_8_build_sidecar && CURRENT_STEP=9; }
    [ $CURRENT_STEP -le 9 ] && { step_9_start_services && CURRENT_STEP=10; }
    [ $CURRENT_STEP -le 10 ] && { step_10_test_ticket_sharing && CURRENT_STEP=11; }
    [ $CURRENT_STEP -le 11 ] && { step_11_test_sql_server && CURRENT_STEP=12; }

    # Pause before showing summary
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    read -p "Press Enter to view setup summary..."
    echo ""

    # Show summary
    show_summary
}

# Run main function
main "$@"
