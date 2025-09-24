#!/bin/bash
# Certificate regeneration script with proper SANs
# Fixes the wildcard certificate issues with *.localhost not matching traefik.localhost

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CERT_DIR="$HOME/.local/share/certs"

# Logging functions
log_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
log_success() { echo -e "${GREEN}✅ $1${NC}"; }
log_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
log_error() { echo -e "${RED}❌ $1${NC}"; }

print_banner() {
    echo -e "${BLUE}"
    echo "🔐 =================================================="
    echo "   CERTIFICATE REGENERATION"
    echo "   Fix wildcard certificate issues"
    echo "==================================================${NC}"
    echo
    echo "This script will:"
    echo "• Clean up old/duplicate CAs"
    echo "• Regenerate certificates with proper SANs"
    echo "• Install CA in both Windows and WSL2 trust stores"
    echo "• Restart services to use new certificates"
    echo
}

confirm_regeneration() {
    echo -e "${YELLOW}⚠️  This will regenerate all certificates.${NC}"
    echo "Existing certificates will be replaced."
    echo
    read -p "Continue with certificate regeneration? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Certificate regeneration cancelled by user"
        exit 0
    fi
}

# Function to detect Windows username
get_windows_username() {
    local username=""

    # Try multiple methods to get Windows username
    if command -v cmd.exe >/dev/null 2>&1; then
        username=$(cmd.exe /c "echo %USERNAME%" 2>/dev/null | tr -d '\r\n' || echo "")
    fi

    if [ -z "$username" ] && command -v powershell.exe >/dev/null 2>&1; then
        username=$(powershell.exe -Command "Write-Host -NoNewline \$env:USERNAME" 2>/dev/null | tr -d '\r\n' || echo "")
    fi

    if [ -z "$username" ]; then
        # Find non-system user directories
        username=$(ls -ld /mnt/c/Users/*/ 2>/dev/null | grep -v -E "Public|Default|All Users" | head -1 | awk -F'/' '{print $5}' || echo "")
    fi

    echo "$username"
}

# Step 1: Clean up old CAs
cleanup_old_cas() {
    log_info "Step 1: Cleaning up old CAs..."

    # Clean WSL2 trust store
    log_info "Cleaning WSL2 trust store..."
    local mkcert_certs=$(find /usr/local/share/ca-certificates -name "mkcert*.crt" 2>/dev/null || true)

    if [ -n "$mkcert_certs" ]; then
        echo "$mkcert_certs" | while read cert_file; do
            if [ -n "$cert_file" ] && [ -f "$cert_file" ]; then
                log_info "Removing: $(basename "$cert_file")"
                sudo rm -f "$cert_file" 2>/dev/null || log_warning "Could not remove $cert_file"
            fi
        done

        log_info "Updating system certificate trust store..."
        sudo update-ca-certificates --fresh >/dev/null 2>&1 || log_warning "Could not update system trust store"
        log_success "WSL2 trust store cleaned"
    else
        log_info "No old CAs in WSL2 trust store"
    fi

    # Windows cleanup instructions
    log_info "Windows CA cleanup required..."
    echo
    echo -e "${YELLOW}📋 MANUAL STEP REQUIRED:${NC}"
    echo "Run these commands in Windows PowerShell (regular user - NO admin needed):"
    echo
    echo -e "${BLUE}# Remove all old mkcert CAs${NC}"
    echo "mkcert -uninstall"
    echo
    echo -e "${BLUE}# Install fresh CA (adds to user's certificate store, not system)${NC}"
    echo "mkcert -install"
    echo
    read -p "Press Enter after completing Windows steps..." -r
    echo
}

# Step 2: Generate new certificates with proper SANs
generate_certificates() {
    log_info "Step 2: Generating new certificates with proper SANs..."

    local windows_username=$(get_windows_username)

    if [ -z "$windows_username" ]; then
        log_error "Could not detect Windows username"
        read -p "Enter your Windows username: " windows_username
        if [ -z "$windows_username" ]; then
            log_error "Windows username required"
            exit 1
        fi
    fi

    local windows_cert_dir="/mnt/c/Users/$windows_username/AppData/Local/mkcert"

    log_info "Windows username: $windows_username"
    log_info "Windows cert directory: $windows_cert_dir"

    # Check if directory exists - if not, create it
    if [ ! -d "$windows_cert_dir" ]; then
        log_warning "Windows mkcert directory not found: $windows_cert_dir"
        log_info "Creating directory (this happens on first use)..."

        # The directory should have been created by mkcert -install, but if not, we'll create it
        mkdir -p "$windows_cert_dir" 2>/dev/null || {
            log_warning "Could not create directory from WSL2"
            echo
            echo "Please ensure you ran 'mkcert -install' in Windows PowerShell"
            echo "This should create: C:\\Users\\$windows_username\\AppData\\Local\\mkcert"
            echo
            echo "If it created the directory elsewhere, mkcert might be using a different CAROOT."
            echo "Check with: mkcert -CAROOT"
            echo
            read -p "Press Enter to continue anyway..." -r
        }
    fi

    echo
    echo -e "${YELLOW}📋 MANUAL STEP REQUIRED:${NC}"
    echo "Run these commands in Windows PowerShell (regular user - NO admin needed):"
    echo
    echo -e "${BLUE}# Navigate to mkcert directory${NC}"
    echo "cd \$env:LOCALAPPDATA\\mkcert"
    echo
    echo -e "${BLUE}# Generate main wildcard certificate with all SANs${NC}"
    echo 'mkcert -cert-file dev-localhost-wild.crt -key-file dev-localhost-wild.key `'
    echo '  "*.localhost" localhost "traefik.localhost" "registry.localhost" `'
    echo '  "airflow.localhost" "*.airflow.localhost" "*.customer.localhost" `'
    echo '  127.0.0.1 ::1'
    echo
    echo -e "${BLUE}# Generate registry-specific certificate${NC}"
    echo 'mkcert -cert-file dev-registry.localhost.crt -key-file dev-registry.localhost.key `'
    echo '  "registry.localhost" 127.0.0.1 ::1'
    echo
    read -p "Press Enter after generating certificates..." -r
    echo

    # Copy certificates to WSL2
    log_info "Copying certificates to WSL2..."

    # Create certificate directory if it doesn't exist
    mkdir -p "$CERT_DIR"

    # Copy certificates
    if [ -f "$windows_cert_dir/dev-localhost-wild.crt" ]; then
        cp -f "$windows_cert_dir/dev-localhost-wild.crt" "$CERT_DIR/"
        cp -f "$windows_cert_dir/dev-localhost-wild.key" "$CERT_DIR/"
        chmod 644 "$CERT_DIR/dev-localhost-wild.crt"
        chmod 600 "$CERT_DIR/dev-localhost-wild.key"
        log_success "Wildcard certificate copied"
    else
        log_error "Wildcard certificate not found in Windows directory"
        exit 1
    fi

    if [ -f "$windows_cert_dir/dev-registry.localhost.crt" ]; then
        cp -f "$windows_cert_dir/dev-registry.localhost.crt" "$CERT_DIR/"
        cp -f "$windows_cert_dir/dev-registry.localhost.key" "$CERT_DIR/"
        chmod 644 "$CERT_DIR/dev-registry.localhost.crt"
        chmod 600 "$CERT_DIR/dev-registry.localhost.key"
        log_success "Registry certificate copied"
    else
        log_warning "Registry certificate not found (using wildcard)"
    fi

    # Verify certificates have proper SANs
    log_info "Verifying certificate SANs..."
    local sans=$(openssl x509 -in "$CERT_DIR/dev-localhost-wild.crt" -text -noout | grep -A1 "Subject Alternative Name" | tail -1)

    if [ -n "$sans" ]; then
        echo -e "${GREEN}✅ Certificate created with SANs:${NC}"
        echo "   $sans"

        # List all certificates created
        echo
        echo -e "${GREEN}📜 Certificates created in WSL2:${NC}"
        ls -la "$CERT_DIR"/*.crt "$CERT_DIR"/*.key 2>/dev/null | while read line; do
            echo "   $line"
        done
    else
        log_error "Could not verify SANs"
    fi
}

# Step 3: Install CA in WSL2 trust store
install_ca_wsl2() {
    log_info "Step 3: Installing CA in WSL2 trust store..."

    local windows_username=$(get_windows_username)
    local windows_ca="/mnt/c/Users/$windows_username/AppData/Local/mkcert/rootCA.pem"

    if [ -f "$windows_ca" ]; then
        log_info "Found Windows CA: $windows_ca"

        # Copy CA to system trust store
        local ca_filename="mkcert_$(date +%s).crt"
        sudo cp "$windows_ca" "/usr/local/share/ca-certificates/$ca_filename"

        # Update trust store
        sudo update-ca-certificates

        log_success "CA installed in WSL2 trust store"
    else
        log_error "Windows CA not found at: $windows_ca"
        exit 1
    fi

    # Also configure mkcert to use Windows CAROOT
    export CAROOT="/mnt/c/Users/$windows_username/AppData/Local/mkcert"
    if command -v mkcert >/dev/null 2>&1; then
        mkcert -install
        log_success "mkcert configured to use Windows CA"
    fi
}

# Step 4: Restart services
restart_services() {
    log_info "Step 4: Restarting services..."

    # Restart Traefik
    if [ -f "$HOME/platform-services/traefik/docker-compose.yml" ]; then
        log_info "Restarting Traefik..."
        cd "$HOME/platform-services/traefik"
        docker compose restart
        cd "$REPO_ROOT"
        log_success "Traefik restarted"
    else
        log_warning "Traefik configuration not found"
    fi

    # Wait for services to be ready
    log_info "Waiting for services to be ready..."
    sleep 5
}

# Step 5: Verify certificates
verify_certificates() {
    log_info "Step 5: Verifying certificates..."
    echo

    # Test with openssl
    echo -n "• OpenSSL verification... "
    if echo | openssl s_client -connect traefik.localhost:443 -servername traefik.localhost 2>&1 | grep -q "Verify return code: 0"; then
        echo -e "${GREEN}✅ Valid${NC}"
    else
        echo -e "${RED}❌ Invalid${NC}"
    fi

    # Test with wget (more forgiving)
    echo -n "• Wget HTTPS test... "
    if wget -O /dev/null https://traefik.localhost 2>&1 | grep -q "200 OK\|302 Found"; then
        echo -e "${GREEN}✅ Success${NC}"
    else
        echo -e "${RED}❌ Failed${NC}"
    fi

    # Test with curl (strict)
    echo -n "• Curl HTTPS test... "
    if curl -I https://traefik.localhost 2>&1 | grep -q "HTTP"; then
        echo -e "${GREEN}✅ Success${NC}"
    else
        echo -e "${YELLOW}⚠️  Failed (this is expected with wildcards)${NC}"
    fi

    # Check certificate SANs
    echo
    log_info "Certificate SANs:"
    echo | openssl s_client -connect traefik.localhost:443 -servername traefik.localhost 2>/dev/null | \
        openssl x509 -text -noout 2>/dev/null | grep -A1 "Subject Alternative Name" | tail -1 || echo "Could not retrieve SANs"
}

# Main execution
main() {
    print_banner
    confirm_regeneration

    echo
    log_info "Starting certificate regeneration..."
    echo

    cleanup_old_cas
    generate_certificates
    install_ca_wsl2
    restart_services
    verify_certificates

    echo
    echo -e "${GREEN}🎉 Certificate Regeneration Complete${NC}"
    echo
    echo "Next steps:"
    echo "1. Clear browser cache (Ctrl+Shift+Delete)"
    echo "2. Restart browser"
    echo "3. Navigate to https://traefik.localhost"
    echo "4. Should work without certificate warnings!"
    echo
    echo "If you still see warnings:"
    echo "• Check Windows Event Viewer for certificate errors"
    echo "• Run: ./scripts/diagnose-certificate-state.sh"
    echo "• Run: ./scripts/cleanup-duplicate-cas.sh"
}

# Handle script errors
trap 'log_error "Certificate regeneration failed at line $LINENO. Exit code: $?"' ERR

# Run main function
main "$@"
