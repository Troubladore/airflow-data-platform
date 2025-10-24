#!/bin/bash
# Comprehensive Kerberos Setup Wizard
# ====================================
# Guides developers through the entire Kerberos configuration process
# for Docker-based Airflow development with SQL Server authentication

set -e

# Find the platform root and source the formatting library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLATFORM_DIR="$(dirname "$SCRIPT_DIR")/platform-bootstrap"

# Source the shared formatting library
if [ -f "$PLATFORM_DIR/lib/formatting.sh" ]; then
    source "$PLATFORM_DIR/lib/formatting.sh"
else
    # Fallback if library not found - define minimal formatting
    echo "Warning: formatting library not found at $PLATFORM_DIR/lib/formatting.sh" >&2
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

# Progress state file for resume capability
STATE_FILE="/tmp/.kerberos-setup-state"
TOTAL_STEPS=11
CURRENT_STEP=1

# Configuration variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLATFORM_DIR="$(dirname "$SCRIPT_DIR")"  # Parent directory containing all platform scripts
DETECTED_DOMAIN=""
DETECTED_USERNAME=""
DETECTED_TICKET_DIR=""
CORPORATE_ENV=false

# ==========================================
# Utility Functions
# ==========================================

print_banner() {
    clear
    print_divider
    echo "          Kerberos Setup Wizard for Airflow Development"
    print_divider
    echo ""
}

print_step() {
    local step_num=$1
    local step_desc=$2
    echo ""
    print_section "Step ${step_num}/${TOTAL_STEPS}: ${step_desc}"
}

# print_success, print_error, print_warning, print_info are already in formatting.sh
# No need to redefine them

print_command() {
    # Print a command (indented for clarity)
    echo "  $1"
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
    # Use uname -r check (more reliable than WSLInterop file)
    if uname -r | grep -qi "microsoft\|wsl"; then
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
        print_command "sudo apt-get update && sudo apt-get install -y krb5-user"
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
            print_command "sudo systemctl start docker"
            echo "  or"
            print_command "sudo service docker start"
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
        print_warning "Options:"
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
            print_warning "Possible solutions:"
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
        local expiry=$(klist 2>/dev/null | grep -A1 "Default principal" | grep "Valid starting" | sed 's/.*Expires[[:space:]]*//;s/^[[:space:]]*//')

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
    print_info "Running: kinit $principal"
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
        print_warning "Possible issues:"
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

step_5_configure_ticket_location() {
    print_step 5 "Configure Ticket Location"

    # This merged step handles everything:
    # 1. Create .env if needed
    # 2. Run diagnostic to detect ticket location
    # 3. Validate existing or detected configuration
    # 4. Update .env with working values

    local env_file="$PLATFORM_DIR/.env"
    local env_example="$PLATFORM_DIR/.env.example"

    # Step 5a: Ensure .env exists
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

    # Step 5b: Check current configuration
    echo "Checking current configuration..."
    echo ""

    local current_ticket_dir=$(grep "^KERBEROS_TICKET_DIR=" "$env_file" 2>/dev/null | cut -d= -f2-)
    local current_domain=$(grep "^COMPANY_DOMAIN=" "$env_file" 2>/dev/null | cut -d= -f2-)

    # If we have valid config already, test it
    if [ -n "$current_ticket_dir" ] && [ "$current_ticket_dir" != "/tmp" ]; then
        echo "Found existing configuration:"
        echo "  KERBEROS_TICKET_DIR=$current_ticket_dir"
        [ -n "$current_domain" ] && echo "  COMPANY_DOMAIN=$current_domain"
        echo ""

        # Quick validation - does the directory exist and contain tickets?
        if [ -d "$current_ticket_dir" ]; then
            local ticket_count=$(find "$current_ticket_dir" -maxdepth 1 -name "krb5cc*" 2>/dev/null | wc -l)
            if [ "$ticket_count" -gt 0 ]; then
                print_success "Configuration is valid - ticket directory contains $ticket_count ticket(s)"

                # Check if sidecar exists but is stopped, and auto-start it
                if docker ps -a --format "{{.Names}}" | grep -q "kerberos-platform-service"; then
                    if ! docker ps --format "{{.Names}}" | grep -q "kerberos-platform-service"; then
                        echo ""
                        print_warning "Kerberos sidecar exists but is stopped"
                        echo -n "Starting kerberos-platform-service... "
                        if docker start kerberos-platform-service >/dev/null 2>&1; then
                            print_success "Started"
                            sleep 2  # Give it time to initialize
                        else
                            print_error "Failed to start"
                        fi
                    fi
                fi

                # Test if sidecar can access it (if running)
                if docker ps --format "{{.Names}}" | grep -q "kerberos-platform-service"; then
                    echo ""
                    echo -n "Testing sidecar access to tickets... "
                    if docker exec kerberos-platform-service ls "$current_ticket_dir" >/dev/null 2>&1; then
                        print_success "Sidecar can access ticket directory"
                        save_state
                        return 0
                    else
                        print_warning "Sidecar cannot access directory (may need restart)"
                    fi
                else
                    # Sidecar not running yet, config is good
                    save_state
                    return 0
                fi
            else
                print_warning "Directory exists but contains no tickets"
            fi
        else
            print_warning "Configured directory does not exist: $current_ticket_dir"
        fi
        echo ""
    fi

    # Step 5c: Run diagnostic to detect ticket location
    print_info "Running diagnostic to detect ticket location..."
    echo ""

    if [ -f "$SCRIPT_DIR/diagnostics/diagnose-kerberos.sh" ]; then
        # Run diagnostic and capture output
        local diag_output=$("$SCRIPT_DIR/diagnostics/diagnose-kerberos.sh" 2>&1)

        # Try to extract configuration from diagnostic output
        DETECTED_TICKET_DIR=$(echo "$diag_output" | grep "^KERBEROS_TICKET_DIR=" | cut -d= -f2)

        # Show relevant parts of diagnostic output
        echo "$diag_output" | sed -n '/=== 1\. HOST KERBEROS TICKETS ===/,/=== 2\. COMMON TICKET LOCATIONS ===/p' | head -n -1

        if [ -n "$DETECTED_TICKET_DIR" ]; then
            echo ""
            print_success "Ticket location detected: ${CYAN}$DETECTED_TICKET_DIR${NC}"

            # Update detected domain if we found one
            if [ -z "$DETECTED_DOMAIN" ] && [ -n "$current_domain" ]; then
                DETECTED_DOMAIN="$current_domain"
            fi
        else
            echo ""
            print_warning "Could not auto-detect ticket location"
            echo "Full diagnostic output saved to /tmp/kerberos-diagnostic.log"
            echo "$diag_output" > /tmp/kerberos-diagnostic.log
        fi
    else
        print_error "diagnose-kerberos.sh not found"
    fi

    # Step 5d: Update .env with detected or manual values
    echo ""
    local needs_update=false

    # Determine what to update
    if [ -n "$DETECTED_TICKET_DIR" ] && [ "$current_ticket_dir" != "$DETECTED_TICKET_DIR" ]; then
        needs_update=true
        echo "Configuration update needed:"
        echo "  Current: KERBEROS_TICKET_DIR=${current_ticket_dir:-'(not set)'}"
        echo "  Detected: KERBEROS_TICKET_DIR=$DETECTED_TICKET_DIR"
        echo ""

        if ask_yes_no "Update .env with detected value?" "y"; then
            # Update KERBEROS_TICKET_DIR
            if grep -q "^KERBEROS_TICKET_DIR=" "$env_file"; then
                sed -i "s|^KERBEROS_TICKET_DIR=.*|KERBEROS_TICKET_DIR=$DETECTED_TICKET_DIR|" "$env_file"
            else
                echo "KERBEROS_TICKET_DIR=$DETECTED_TICKET_DIR" >> "$env_file"
            fi

            # Update COMPANY_DOMAIN if detected
            if [ -n "$DETECTED_DOMAIN" ]; then
                if grep -q "^COMPANY_DOMAIN=" "$env_file"; then
                    sed -i "s|^COMPANY_DOMAIN=.*|COMPANY_DOMAIN=$DETECTED_DOMAIN|" "$env_file"
                else
                    echo "COMPANY_DOMAIN=$DETECTED_DOMAIN" >> "$env_file"
                fi
            fi

            print_success ".env updated with detected values"
            save_state
            return 0
        fi
    elif [ -z "$current_ticket_dir" ] || [ "$current_ticket_dir" = "/tmp" ]; then
        # No valid configuration, need manual setup
        print_warning "Manual configuration required"
        echo ""
        echo "You need to specify where Kerberos tickets are stored."
        echo "Common locations:"
        echo "  - /tmp/krb5cc_$(id -u)"
        echo "  - /var/run/user/$(id -u)"
        echo "  - Custom keytab location"
        echo ""

        if ask_yes_no "Would you like to manually edit .env now?" "y"; then
            ${EDITOR:-nano} "$env_file"
            print_success "Configuration saved"
        else
            print_warning "You'll need to configure KERBEROS_TICKET_DIR in .env manually"
            echo "Edit: ${CYAN}$env_file${NC}"
        fi
    else
        # Configuration looks good
        print_success "Configuration validated"
    fi

    # Step 5e: Final validation if sidecar is running
    if docker ps --format "{{.Names}}" | grep -q "kerberos-platform-service"; then
        echo ""
        print_info "Restarting sidecar to pick up configuration changes..."
        docker restart kerberos-platform-service >/dev/null 2>&1
        sleep 2
    fi

    save_state
}

step_6_corporate_environment() {
    print_step 6 "Corporate Environment Configuration"

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
        if [ -f "$PLATFORM_DIR/.env" ]; then
            local has_config=false
            if grep -q "^IMAGE_ALPINE=" "$PLATFORM_DIR/.env" && ! grep -q "^IMAGE_ALPINE=$" "$PLATFORM_DIR/.env"; then
                has_config=true
            fi

            if [ "$has_config" = true ]; then
                print_success ".env already has corporate configuration"
                echo ""
                echo "Current settings:"
                grep -E "^(IMAGE_ALPINE|IMAGE_PYTHON|IMAGE_MOCKSERVER|ODBC_DRIVER_URL)=" "$PLATFORM_DIR/.env" 2>/dev/null | sed 's/^/  /' || echo "  (partial configuration)"
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
        print_info "1. Alpine Linux (sidecar base + diagnostic tests):"
        echo "   Public default: alpine:3.19 (from registry-1.docker.io)"
        echo "   Also pulls:     alpine:latest"
        echo ""
        echo "   Corporate example:"
        echo "   artifactory.yourcompany.com/docker-remote/library/alpine:3.19"
        echo ""
        read -p "   Your Artifactory path (or Enter to use public): " image_alpine

        # IMAGE_PYTHON (for testing scripts)
        echo ""
        print_info "2. Python (for testing scripts):"
        echo "   Public default: python:3.11-alpine (from registry-1.docker.io)"
        echo ""
        echo "   Golden images: You can substitute your organization's approved image"
        echo "                   Examples: python:3.11-slim, chainguard/python:latest, etc."
        echo ""
        echo "   Corporate example:"
        echo "   artifactory.yourcompany.com/docker-remote/library/python:3.11-alpine"
        echo "   artifactory.yourcompany.com/chainguard/python:3.11"
        echo ""
        read -p "   Your image path (full path including tag): " image_python

        # IMAGE_MOCKSERVER (mock services)
        echo ""
        print_info "3. MockServer (for mock Delinea service):"
        echo "   Public default: mockserver/mockserver:latest (from registry-1.docker.io)"
        echo ""
        echo "   Corporate example:"
        echo "   artifactory.yourcompany.com/docker-remote/mockserver/mockserver:latest"
        echo ""
        read -p "   Your Artifactory path (or Enter to use public): " image_mockserver

        # IMAGE_ASTRONOMER (for when they create Airflow projects)
        echo ""
        print_info "4. Astronomer Runtime (for your Airflow projects):"
        echo "   Public default: quay.io/astronomer/astro-runtime:11.10.0"
        echo "                   (from quay.io registry)"
        echo ""
        echo "   Corporate example:"
        echo "   artifactory.yourcompany.com/quay-remote/astronomer/astro-runtime:11.10.0"
        echo ""
        read -p "   Your Artifactory path (or Enter to use public): " image_astronomer

        # ODBC_DRIVER_URL (Microsoft binaries)
        echo ""
        print_info "5. Microsoft ODBC Drivers (binary downloads):"
        echo "   Public default:"
        echo "   https://download.microsoft.com/download/3/5/5/355d7943-a338-41a7-858d-53b259ea33f5/"
        echo ""
        echo "   Files: msodbcsql18_18.3.2.1-1_amd64.apk"
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

        local env_file="$PLATFORM_DIR/.env"
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
        print_command "docker login artifactory.yourcompany.com"
        echo ""

        if ask_yes_no "Have you already run docker login for your Artifactory?" "y"; then
            print_success "Docker login confirmed"
        else
            echo ""
            print_info "Please login to Artifactory now:"
            echo ""
            print_command "docker login ${image_alpine%%/*}"
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

step_7_build_sidecar() {
    print_step 7 "Building Kerberos Sidecar Image"

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
    if [ -d "$PLATFORM_DIR/kerberos-sidecar" ]; then
        cd "$PLATFORM_DIR/kerberos-sidecar"

        if [ -f "Makefile" ]; then
            if make build; then
                echo ""
                print_success "Sidecar image built successfully!"
                save_state
                cd "$PLATFORM_DIR"
                return 0
            else
                echo ""
                print_error "Failed to build sidecar image"
                cd "$PLATFORM_DIR"
                return 1
            fi
        else
            print_error "Makefile not found in kerberos-sidecar/"
            cd "$PLATFORM_DIR"
            return 1
        fi
    else
        print_error "kerberos-sidecar directory not found"
        echo ""
        echo "  Expected location: $PLATFORM_DIR/kerberos-sidecar/"
        return 1
    fi
}

step_8_start_services() {
    print_step 8 "Starting Platform Services"

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

    cd "$PLATFORM_DIR"

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
        print_command "docker compose logs"
        return 1
    fi
}

step_9_test_ticket_sharing() {
    print_step 9 "Testing Kerberos Ticket Sharing"

    print_info "Running simple ticket sharing test..."
    echo ""

    # Check if test script exists
    if [ ! -f "$PLATFORM_DIR/test_kerberos_simple.py" ]; then
        print_warning "test_kerberos_simple.py not found"
        print_info "Skipping ticket sharing test"
        save_state
        return 0
    fi

    # Determine test image (use configured from .env or default)
    # Load .env to get IMAGE_PYTHON if configured
    if [ -f "$PLATFORM_DIR/.env" ]; then
        source "$PLATFORM_DIR/.env" 2>/dev/null || true
    fi

    # Use IMAGE_KERBEROS_TEST if set, otherwise fall back to IMAGE_PYTHON
    local test_image="${IMAGE_KERBEROS_TEST:-${IMAGE_PYTHON:-python:3.11-alpine}}"

    # Check image mode
    local image_mode="${IMAGE_MODE:-layered}"

    local test_command=""
    if [ "$image_mode" = "prebuilt" ]; then
        # Prebuilt mode - assume krb5 is already installed
        print_info "Using test image (prebuilt mode): $test_image"
        echo "  Mode: Prebuilt - expecting krb5 pre-installed"
        test_command="python /app/test.py"
    else
        # Layered mode - install packages at runtime
        # Detect package manager based on image
        local install_cmd="apk add --no-cache krb5"  # Alpine default
        if [[ "$test_image" == *"debian"* ]] || [[ "$test_image" == *"ubuntu"* ]] || [[ "$test_image" == *":3.11"* ]] && [[ "$test_image" != *"alpine"* ]]; then
            install_cmd="apt-get update -qq && apt-get install -y -qq krb5-user"
        elif [[ "$test_image" == *"chainguard"* ]] || [[ "$test_image" == *"wolfi"* ]]; then
            install_cmd="apk add --no-cache krb5"  # Wolfi uses apk
        fi

        print_info "Using test image (layered mode): $test_image"
        echo "  Package install: $install_cmd"
        test_command="$install_cmd >/dev/null 2>&1 && python /app/test.py"
    fi
    echo ""

    # Run the test
    if docker run --rm \
        --network platform_network \
        -v platform_kerberos_cache:/krb5/cache:ro \
        -v "$PLATFORM_DIR/test_kerberos_simple.py:/app/test.py" \
        -e KRB5CCNAME=/krb5/cache/krb5cc \
        "$test_image" \
        sh -c "$test_command" 2>&1 | tee /tmp/kerberos-test-output.txt | grep -q "SUCCESS"; then

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

        print_info "Analyzing failure..."
        echo ""

        # Check 1: Is sidecar even running?
        if ! docker ps --format "{{.Names}}" | grep -q "kerberos-platform-service"; then
            print_error "ROOT CAUSE: Kerberos sidecar is NOT running"
            echo ""
            print_info "FIX:"
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
                print_info "FIX:"
                echo "  Check what's in volume:"
                echo "    ${CYAN}docker exec kerberos-platform-service ls -la /krb5/cache/${NC}"
            else
                print_error "Sidecar does NOT have ticket"
                echo ""
                print_info "FIX:"
                echo -e "  Sidecar can't obtain tickets. Check logs:"
                print_command "docker logs kerberos-platform-service --tail 30"
                echo ""
                echo -e "  Common causes:"
                echo -e "    - Wrong ticket path in .env (KERBEROS_TICKET_DIR)"
                echo -e "    - Missing password/keytab configuration"
            fi

        else
            print_warning "Test failed for unknown reason"
            echo ""
            echo "  Output: /tmp/kerberos-test-output.txt"
            echo "  Diagnostic: ${CYAN}./diagnostics/diagnose-kerberos.sh${NC}"
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

step_10_test_sql_direct() {
    print_step 10 "Testing Direct SQL Server Connection (Pre-flight)"

    if ! ask_yes_no "Test direct SQL Server connection?"; then
        print_info "Skipping direct SQL test"
        save_state
        return 0
    fi

    echo ""

    # Get SQL Server details (reuse from Step 11 if already provided)
    local sql_server=""
    local sql_database=""

    # Check for saved SQL Server details
    if [ -f "$PLATFORM_DIR/.env" ]; then
        sql_server=$(grep "^TEST_SQL_SERVER=" "$PLATFORM_DIR/.env" 2>/dev/null | cut -d= -f2)
        sql_database=$(grep "^TEST_SQL_DATABASE=" "$PLATFORM_DIR/.env" 2>/dev/null | cut -d= -f2)
    fi

    if [ -n "$sql_server" ] && [ -n "$sql_database" ]; then
        print_info "Using saved SQL Server configuration:"
        echo "  Server:   $sql_server"
        echo "  Database: $sql_database"
        echo ""
    else
        echo "Enter SQL Server details for connectivity test:"
        echo ""
        read -p "SQL Server hostname (or 'skip' to skip): " sql_server

        if [ "$sql_server" = "skip" ] || [ -z "$sql_server" ]; then
            print_info "Skipping direct SQL test"
            save_state
            return 0
        fi

        read -p "Database name: " sql_database

        if [ -z "$sql_database" ]; then
            print_warning "Database name required"
            print_info "Skipping direct SQL test"
            save_state
            return 0
        fi

        # Save for Step 11
        echo "TEST_SQL_SERVER=$sql_server" >> "$PLATFORM_DIR/.env"
        echo "TEST_SQL_DATABASE=$sql_database" >> "$PLATFORM_DIR/.env"
    fi

    echo ""
    print_info "Testing connection to ${CYAN}${sql_server}${NC}..."
    echo ""

    # Check if direct test script exists
    if [ -f "$PLATFORM_DIR/diagnostics/test-sql-direct.sh" ]; then
        if "$PLATFORM_DIR/diagnostics/test-sql-direct.sh" "$sql_server" "$sql_database"; then
            echo ""
            print_success "Direct SQL Server connection PASSED!"
            print_info "Network connectivity confirmed - ready for sidecar test"
            save_state
            return 0
        else
            echo ""
            print_warning "Direct connection failed - this is usually a network issue"
            print_info "The sidecar test (Step 11) will likely also fail"
            echo ""
            print_info "Common causes:"
            echo "  - Not on VPN"
            echo "  - SQL Server name incorrect"
            echo "  - Firewall blocking port 1433"
            echo "  - SQL Server not configured for Kerberos"
        fi
    else
        print_warning "test-sql-direct.sh not found"
        print_info "Cannot perform direct connectivity test"
    fi

    save_state
}

step_11_test_sql_via_sidecar() {
    print_step 11 "Testing SQL Server Connection via Sidecar"

    echo "This step tests SQL Server authentication THROUGH the sidecar."
    echo ""
    print_info "This verifies the complete Kerberos ticket sharing flow"
    echo ""

    if ! ask_yes_no "Test SQL Server connection via sidecar?"; then
        print_info "Skipping sidecar SQL test"
        save_state
        return 0
    fi

    echo ""

    # Get SQL Server details (should be saved from Step 10)
    local sql_server=""
    local sql_database=""

    if [ -f "$PLATFORM_DIR/.env" ]; then
        sql_server=$(grep "^TEST_SQL_SERVER=" "$PLATFORM_DIR/.env" 2>/dev/null | cut -d= -f2)
        sql_database=$(grep "^TEST_SQL_DATABASE=" "$PLATFORM_DIR/.env" 2>/dev/null | cut -d= -f2)
    fi

    if [ -z "$sql_server" ] || [ -z "$sql_database" ]; then
        echo "Enter SQL Server details:"
        echo ""
        read -p "SQL Server hostname (or 'skip' to skip): " sql_server

        if [ "$sql_server" = "skip" ] || [ -z "$sql_server" ]; then
            print_info "Skipping sidecar SQL test"
            save_state
            return 0
        fi

        read -p "Database name: " sql_database

        if [ -z "$sql_database" ]; then
            print_warning "Database name required"
            print_info "Skipping sidecar SQL test"
            save_state
            return 0
        fi
    else
        print_info "Using SQL Server configuration from Step 10:"
        echo "  Server:   $sql_server"
        echo "  Database: $sql_database"
        echo ""
    fi

    print_info "Testing connection via sidecar to ${CYAN}${sql_server}/${sql_database}${NC}..."
    echo ""

    # Use the sidecar test script
    if [ -f "$PLATFORM_DIR/diagnostics/test-sql-simple.sh" ]; then
        if "$PLATFORM_DIR/diagnostics/test-sql-simple.sh" "$sql_server" "$sql_database"; then
            echo ""
            print_success "SQL Server sidecar test PASSED!"
            print_success "Kerberos authentication is working end-to-end!"
            save_state
            return 0
        else
            echo ""
            print_error "SQL Server sidecar test FAILED"
            echo ""

            # Smart diagnosis based on Step 10 result
            if [ -f "$PLATFORM_DIR/.env" ] && grep -q "DIRECT_SQL_PASSED=true" "$PLATFORM_DIR/.env" 2>/dev/null; then
                print_warning "Direct connection worked but sidecar failed"
                echo ""
                echo "This indicates a Kerberos ticket issue:"
                echo "  - Sidecar may not have the ticket"
                echo "  - Ticket may not be valid for SQL Server"
                echo "  - SQL Server SPN may not be configured"
            else
                print_info "Both direct and sidecar tests failed"
                echo ""
                echo "Fix network connectivity first (Step 10)"
            fi

            echo ""
            print_info "Run diagnostics: ${CYAN}./diagnostics/diagnose-kerberos.sh${NC}"
        fi
    else
        print_warning "test-sql-simple.sh not found"
    fi

    save_state
}

# ==========================================
# Summary and Next Steps
# ==========================================

show_summary() {
    print_banner
    print_success "Setup Complete!"
    print_divider
    echo ""

    print_header "Configuration Summary"

    # Show configuration
    if [ -f "$PLATFORM_DIR/.env" ]; then
        grep -E "^(COMPANY_DOMAIN|KERBEROS_TICKET_DIR)=" "$PLATFORM_DIR/.env" 2>/dev/null | sed 's/^/  /' || echo "  (configuration not found)"
    fi

    print_divider
    echo ""

    print_header "Running Services"
    docker compose ps 2>/dev/null | sed 's/^/  /'
    echo ""

    print_header "What's Next"
    echo ""
    echo "  1. Create or start your Airflow project:"
    print_command "astro dev init my-project    # New project"
    print_command "cd my-project && astro dev start"
    echo ""
    echo "  2. Your Airflow containers will automatically have access to:"
    echo "     • Kerberos tickets (for SQL Server authentication)"
    echo "     • Shared network (platform_network)"
    echo ""
    echo "  3. Useful commands:"
    print_command "make platform-status       # Check service status"
    print_command "make kerberos-test         # Verify Kerberos ticket"
    print_command "make test-kerberos-simple  # Test ticket sharing"
    print_command "docker compose logs        # View service logs"
    echo ""
    echo "  4. Managing Kerberos tickets:"
    print_command "klist                      # Check ticket status"
    print_command "kinit $DETECTED_USERNAME@$DETECTED_DOMAIN  # Renew ticket"
    print_command "./diagnostics/diagnose-kerberos.sh  # Troubleshoot issues"
    echo ""
    echo "  5. When done for the day:"
    print_command "make platform-stop         # Stop all services"
    echo ""
    print_divider
    echo ""

    if [ -n "$DETECTED_DOMAIN" ]; then
        print_info "Your domain: $DETECTED_DOMAIN"
    fi

    if [ -n "$DETECTED_USERNAME" ]; then
        print_info "Your username: $DETECTED_USERNAME"
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

    # Execute steps (11 total, Step 5 & 6 merged)
    [ $CURRENT_STEP -le 1 ] && { step_1_prerequisites && CURRENT_STEP=2; }
    [ $CURRENT_STEP -le 2 ] && { step_2_krb5_conf && CURRENT_STEP=3; }
    [ $CURRENT_STEP -le 3 ] && { step_3_test_kdc && CURRENT_STEP=4; }
    [ $CURRENT_STEP -le 4 ] && { step_4_kerberos_ticket && CURRENT_STEP=5; }
    [ $CURRENT_STEP -le 5 ] && { step_5_configure_ticket_location && CURRENT_STEP=6; }
    [ $CURRENT_STEP -le 6 ] && { step_6_corporate_environment && CURRENT_STEP=7; }
    [ $CURRENT_STEP -le 7 ] && { step_7_build_sidecar && CURRENT_STEP=8; }
    [ $CURRENT_STEP -le 8 ] && { step_8_start_services && CURRENT_STEP=9; }
    [ $CURRENT_STEP -le 9 ] && { step_9_test_ticket_sharing && CURRENT_STEP=10; }
    [ $CURRENT_STEP -le 10 ] && { step_10_test_sql_direct && CURRENT_STEP=11; }
    [ $CURRENT_STEP -le 11 ] && { step_11_test_sql_via_sidecar && CURRENT_STEP=12; }

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
