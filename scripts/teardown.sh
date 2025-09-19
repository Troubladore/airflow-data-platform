#!/bin/bash
# Complete platform teardown script
# Removes all platform components for clean testing environment

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PLATFORM_SERVICES_DIR="$HOME/platform-services"
CERT_DIR="$HOME/.local/share/certs"

# Logging functions
log_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_banner() {
    echo -e "${BLUE}"
    echo "🧹 =================================================="
    echo "   ASTRONOMER AIRFLOW PLATFORM TEARDOWN"
    echo "   Complete Environment Reset Script"
    echo "==================================================${NC}"
    echo
    echo "This script will remove:"
    echo "• All Docker containers and services"
    echo "• Platform configuration files"
    echo "• WSL2 certificates (optional)"
    echo "• Docker volumes and networks"
    echo "• Generated configuration files"
    echo
    echo "Manual cleanup guidance provided for:"
    echo "• Windows certificates and CA"
    echo "• Windows hosts file entries"
    echo "• Docker Desktop settings"
    echo
}

confirm_teardown() {
    echo -e "${YELLOW}⚠️  This will completely tear down your platform environment.${NC}"
    echo "You will need to re-run setup to restore functionality."
    echo
    read -p "Continue with teardown? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Teardown cancelled by user"
        exit 0
    fi
}

# Function to run Ansible teardown if available
run_ansible_teardown() {
    log_info "Running Ansible-based teardown..."

    if [ -f "$REPO_ROOT/ansible/teardown.yml" ]; then
        cd "$REPO_ROOT"

        # Check if Ansible is installed
        if command -v ansible-playbook &> /dev/null; then
            log_info "Executing Ansible teardown playbook..."
            ansible-playbook -i ansible/inventory/local-dev.ini ansible/teardown.yml || {
                log_warning "Ansible teardown had issues, continuing with manual cleanup..."
            }
        else
            log_warning "Ansible not found, proceeding with manual teardown"
        fi
    else
        log_warning "Ansible teardown playbook not found, proceeding with manual teardown"
    fi
}

# Docker service cleanup
cleanup_docker_services() {
    log_info "Cleaning up Docker services..."

    # Check if Docker is available and running
    if ! command -v docker &> /dev/null; then
        log_warning "Docker command not found - skipping Docker cleanup"
        return 0
    fi

    # Check if Docker daemon is running
    if ! docker info &> /dev/null; then
        log_warning "Docker daemon not running - skipping Docker cleanup"
        log_info "To clean up Docker resources later, start Docker and re-run this script"
        return 0
    fi

    # Stop and remove Traefik/Registry services
    if [ -f "$PLATFORM_SERVICES_DIR/traefik/docker-compose.yml" ]; then
        log_info "Stopping platform services..."
        cd "$PLATFORM_SERVICES_DIR/traefik"
        docker compose down --volumes --remove-orphans || log_warning "Some services may have already been stopped"
        log_success "Platform services stopped"
    fi

    # Remove any remaining platform containers (check various naming patterns)
    log_info "Removing remaining platform containers..."
    docker ps -aq --filter "name=traefik" | xargs -r docker rm -f 2>/dev/null || true
    docker ps -aq --filter "name=registry" | xargs -r docker rm -f 2>/dev/null || true
    docker ps -aq --filter "label=com.docker.compose.project=traefik-bundle" | xargs -r docker rm -f 2>/dev/null || true

    # Clean up networks (check various naming patterns)
    log_info "Cleaning up Docker networks..."
    docker network ls --filter "name=traefik" -q | xargs -r docker network rm 2>/dev/null || true
    docker network ls --filter "label=com.docker.compose.project=traefik-bundle" -q | xargs -r docker network rm 2>/dev/null || true

    # Remove platform images (using grep since Docker filters don't support wildcards the way we need)
    log_info "Cleaning up platform images..."
    # Remove registry.localhost images (custom built images)
    docker images --format "{{.Repository}}:{{.Tag}} {{.ID}}" | grep "^registry\.localhost" | awk '{print $2}' | xargs -r docker rmi -f 2>/dev/null || true
    # Remove demo images
    docker images --format "{{.Repository}}:{{.Tag}} {{.ID}}" | grep "/demo/" | awk '{print $2}' | xargs -r docker rmi -f 2>/dev/null || true
    # Remove traefik base images
    docker images --filter "reference=traefik" -q | xargs -r docker rmi -f 2>/dev/null || true
    # Remove registry base images
    docker images --filter "reference=registry" -q | xargs -r docker rmi -f 2>/dev/null || true

    # Remove platform volumes by name (including compose-generated names)
    log_info "Cleaning up platform volumes..."
    docker volume ls -q | grep -E "(traefik|registry)" | xargs -r docker volume rm 2>/dev/null || true

    # Clean up any remaining unused volumes
    docker volume prune -f || log_warning "Volume cleanup had issues"

    log_success "Docker cleanup completed"
}

# Configuration file cleanup
cleanup_configuration_files() {
    log_info "Cleaning up configuration files..."

    # Remove platform services directory
    if [ -d "$PLATFORM_SERVICES_DIR" ]; then
        rm -rf "$PLATFORM_SERVICES_DIR"
        log_success "Removed platform services directory: $PLATFORM_SERVICES_DIR"
    fi

    # Remove any temporary working directories
    if [ -d "$HOME/work/astro-local-config-full" ]; then
        log_info "Found old working directory, removing..."
        rm -rf "$HOME/work/astro-local-config-full"
        log_success "Removed old working directory"
    fi

    log_success "Configuration cleanup completed"
}

# Certificate cleanup with options
cleanup_certificates() {
    log_info "Certificate cleanup options..."

    if [ -d "$CERT_DIR" ]; then
        echo
        echo "WSL2 certificates found in: $CERT_DIR"
        echo
        echo "Choose certificate cleanup level:"
        echo "1) Keep WSL2 certificates (recommended for quick rebuild)"
        echo "2) Remove WSL2 certificates only"
        echo "3) Complete teardown (removes WSL2 certs + attempts Windows cleanup)"
        echo
        read -p "Enter choice (1-3): " -n 1 -r cert_choice
        echo
        CLEANUP_CHOICE="$cert_choice"

        case $cert_choice in
            2)
                rm -rf "$CERT_DIR"
                log_success "Removed WSL2 certificates"
                ;;
            3)
                perform_complete_teardown
                ;;
            *)
                log_info "Keeping WSL2 certificates for quick rebuild"
                ;;
        esac
    else
        echo
        echo "No WSL2 certificates found."
        echo
        echo "Choose cleanup level:"
        echo "1) Skip certificate cleanup"
        echo "2) Skip certificate cleanup"
        echo "3) Complete teardown (attempts Windows cleanup)"
        echo
        read -p "Enter choice (1-3): " -n 1 -r cert_choice
        echo
        CLEANUP_CHOICE="$cert_choice"

        if [ "$cert_choice" == "3" ]; then
            perform_complete_teardown
        else
            log_info "No WSL2 certificates to clean up"
        fi
    fi
}

# Complete teardown with Windows cleanup attempts
perform_complete_teardown() {
    log_info "Performing complete teardown with Windows cleanup..."

    # Step 1: Remove WSL2 certificates
    if [ -d "$CERT_DIR" ]; then
        rm -rf "$CERT_DIR"
        log_success "Removed WSL2 certificates"
    fi

    # Step 2: Attempt Windows certificate cleanup
    log_info "Attempting Windows certificate cleanup..."

    # Get Windows username
    local windows_username
    if command -v cmd.exe &> /dev/null; then
        windows_username=$(/mnt/c/Windows/System32/cmd.exe /c "echo %USERNAME%" 2>/dev/null | tr -d '\r\n' || echo "")
    fi

    # If auto-detection failed, ask the user
    if [ -z "$windows_username" ]; then
        echo
        echo "Could not automatically determine Windows username."
        read -p "Enter your Windows username (or press Enter to skip Windows cleanup): " windows_username
        if [ -z "$windows_username" ]; then
            log_info "Skipping Windows cleanup - no username provided"
            return
        fi
    fi

    if [ -n "$windows_username" ]; then
        local win_cert_dir="/mnt/c/Users/$windows_username/AppData/Local/mkcert"

        # Try to remove Windows certificates
        if [ -d "$win_cert_dir" ]; then
            if rm -rf "$win_cert_dir" 2>/dev/null; then
                log_success "Removed Windows mkcert certificates"
            else
                log_warning "Could not remove Windows certificates - manual cleanup needed"
                echo "  Manual command: Remove-Item \"\$env:LOCALAPPDATA\\mkcert\" -Recurse -Force"
            fi
        else
            log_info "No Windows mkcert certificates found"
        fi

        # Check if mkcert CA is installed before attempting to remove it
        log_info "Checking for mkcert CA certificates in system trust store..."
        local ca_exists=false

        # Check if CA is installed using mkcert -CAROOT (safer than -uninstall)
        if /mnt/c/Windows/System32/cmd.exe /c "mkcert -CAROOT" >/dev/null 2>&1; then
            ca_exists=true
        elif /mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe -Command "mkcert -CAROOT" >/dev/null 2>&1; then
            ca_exists=true
        fi

        if [ "$ca_exists" = true ]; then
            log_info "Removing mkcert CA certificates from system trust store..."
            local ca_uninstalled=false

            # Try direct mkcert command first (works if mkcert is in PATH)
            if /mnt/c/Windows/System32/cmd.exe /c "mkcert -uninstall" 2>/dev/null; then
                log_success "Removed mkcert CA certificates from trust store (direct)"
                ca_uninstalled=true
            # Try PowerShell (Scoop adds programs to PATH, so just call mkcert directly)
            elif /mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe -Command "mkcert -uninstall" 2>/dev/null; then
                log_success "Removed mkcert CA certificates from trust store (via PowerShell)"
                ca_uninstalled=true
            fi

            if [ "$ca_uninstalled" = false ]; then
                log_warning "Could not remove mkcert CA certificates - manual cleanup needed"
                echo "  Try these commands:"
                echo "    mkcert -uninstall"
                echo "    OR in PowerShell: mkcert -uninstall"
            fi
        else
            log_info "No mkcert CA certificates found in system trust store"
        fi

        # Check if mkcert program is actually installed before prompting
        local mkcert_installed=false
        if /mnt/c/Windows/System32/cmd.exe /c "where mkcert" >/dev/null 2>&1; then
            mkcert_installed=true
        elif /mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe -Command "Get-Command mkcert -ErrorAction SilentlyContinue" >/dev/null 2>&1; then
            mkcert_installed=true
        fi

        if [ "$mkcert_installed" = true ]; then
            # Ask if user wants to remove mkcert program itself
            echo
            echo "The mkcert program is installed and could be used for future platform rebuilds."
            read -p "Do you want to uninstall the mkcert program entirely? (y/N): " -n 1 -r remove_mkcert
            echo

            if [[ $remove_mkcert =~ ^[Yy]$ ]]; then
                log_info "Attempting to uninstall mkcert program..."
                # Try PowerShell with scoop uninstall
                if /mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe -Command "scoop uninstall mkcert" 2>/dev/null; then
                    log_success "Uninstalled mkcert program via Scoop"
                # Try other package managers
                elif /mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe -Command "choco uninstall mkcert -y" 2>/dev/null; then
                    log_success "Uninstalled mkcert program via Chocolatey"
                else
                    log_warning "Could not uninstall mkcert program - manual removal needed"
                    echo "  Try these commands:"
                    echo "    scoop uninstall mkcert"
                    echo "    OR: choco uninstall mkcert"
                    echo "    OR: winget uninstall mkcert"
                fi
            else
                log_info "Keeping mkcert program installed (recommended for future rebuilds)"
            fi
        else
            log_info "mkcert program is not installed on this system"
        fi
    else
        log_warning "Could not determine Windows username for certificate cleanup"
    fi

    # Step 3: Attempt Windows hosts file cleanup
    log_info "Attempting Windows hosts file cleanup..."

    local hosts_file="/mnt/c/Windows/System32/drivers/etc/hosts"
    if [ -f "$hosts_file" ]; then
        # Create a backup first
        local backup_file="/tmp/hosts_backup_$(date +%Y%m%d_%H%M%S)"
        if cp "$hosts_file" "$backup_file" 2>/dev/null; then
            log_info "Created hosts file backup: $backup_file"

            # Try to remove the entries
            if sed -i '/127\.0\.0\.1.*registry\.localhost/d; /127\.0\.0\.1.*traefik\.localhost/d' "$hosts_file" 2>/dev/null; then
                log_success "Removed localhost entries from Windows hosts file"
            else
                log_warning "Could not modify Windows hosts file - manual cleanup needed"
                show_manual_hosts_cleanup
            fi
        else
            log_warning "Could not backup/modify Windows hosts file - manual cleanup needed"
            show_manual_hosts_cleanup
        fi
    else
        log_warning "Windows hosts file not accessible - manual cleanup needed"
        show_manual_hosts_cleanup
    fi

    log_success "Complete teardown attempted - see any warnings above for manual steps"
}

# Show manual hosts file cleanup
show_manual_hosts_cleanup() {
    echo
    echo -e "${YELLOW}📋 Manual Hosts File Cleanup${NC}"
    echo
    echo "Edit C:\\Windows\\System32\\drivers\\etc\\hosts as Administrator"
    echo "Remove these lines:"
    echo "  127.0.0.1 registry.localhost"
    echo "  127.0.0.1 traefik.localhost"
    echo
    echo "Corporate environments: Use your organization's host management tool"
    echo
}

# Show manual cleanup instructions
show_manual_certificate_cleanup() {
    echo
    echo -e "${YELLOW}📋 Manual Certificate Cleanup Guide${NC}"
    echo
    echo "For complete certificate and hosts cleanup, re-run this script"
    echo "and select option 3 'Complete teardown' when prompted."
    echo
    echo "Or manually:"
    echo
    echo "🔐 Windows Certificates (as Administrator):"
    echo "  Remove-Item \"\$env:LOCALAPPDATA\\mkcert\" -Recurse -Force"
    echo "  mkcert -uninstall"
    echo
    echo "🌐 Windows Hosts File (as Administrator):"
    echo "  Edit C:\\Windows\\System32\\drivers\\etc\\hosts"
    echo "  Remove: 127.0.0.1 registry.localhost"
    echo "  Remove: 127.0.0.1 traefik.localhost"
    echo
}

# Docker Desktop guidance
show_docker_desktop_guidance() {
    echo
    echo -e "${YELLOW}📋 Docker Desktop Reset (Optional)${NC}"
    echo
    echo "If you want to completely reset Docker Desktop:"
    echo
    echo "1. Open Docker Desktop"
    echo "2. Go to Settings (gear icon)"
    echo "3. Go to 'Troubleshoot' tab"
    echo "4. Click 'Reset to Factory defaults'"
    echo
    echo "Or to just reset WSL2 integration:"
    echo "1. Go to Settings → Resources → WSL Integration"
    echo "2. Disable integration for your WSL2 distro"
    echo "3. Apply & Restart"
    echo "4. Re-enable when ready to rebuild"
    echo
}

# Verification of teardown
verify_teardown() {
    log_info "Verifying teardown completion..."

    local issues_found=0

    # Check for remaining containers (skip if Docker not available)
    local remaining_containers=0
    if command -v docker &> /dev/null && docker info &> /dev/null; then
        remaining_containers=$(docker ps -aq 2>/dev/null | xargs -r docker inspect --format '{{.Name}} {{.Config.Labels}}' 2>/dev/null | grep -E "(traefik|registry)" | wc -l)
    else
        log_info "Skipping container verification - Docker not available"
    fi
    if [ "$remaining_containers" -gt 0 ]; then
        log_warning "Found $remaining_containers remaining platform containers:"
        docker ps -a --format "table {{.Names}}\t{{.Status}}" 2>/dev/null | grep -E "(traefik|registry)" || true
        echo "  Remove by name: docker ps -aq --filter \"name=traefik\" --filter \"name=registry\" | xargs docker rm -f"
        echo "  Remove by label: docker ps -aq --filter \"label=com.docker.compose.project=traefik-bundle\" | xargs docker rm -f"
        issues_found=$((issues_found + 1))
    fi

    # Check for remaining volumes (using grep to catch compose-generated names)
    local remaining_volumes=0
    if command -v docker &> /dev/null && docker info &> /dev/null; then
        remaining_volumes=$(docker volume ls -q 2>/dev/null | grep -E "(traefik|registry)" | wc -l)
    fi
    if [ "$remaining_volumes" -gt 0 ]; then
        log_warning "Found $remaining_volumes remaining platform volumes:"
        docker volume ls 2>/dev/null | grep -E "(traefik|registry)" | awk '{print "  " $2}' || true
        echo "  Remove all: docker volume ls -q | grep -E \"(traefik|registry)\" | xargs docker volume rm"
        echo "  ⚠️  This will delete all data stored in these volumes"
        issues_found=$((issues_found + 1))
    fi

    # Check for remaining images
    local remaining_images=0
    if command -v docker &> /dev/null && docker info &> /dev/null; then
        remaining_images=$(docker images --format "{{.Repository}}:{{.Tag}}" 2>/dev/null | grep -E "(^traefik|^registry[^.]|^registry\.localhost)" | wc -l)
    fi
    if [ "$remaining_images" -gt 0 ]; then
        log_warning "Found $remaining_images remaining platform images:"
        docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}" 2>/dev/null | grep -E "(^traefik|^registry[^.]|^registry\.localhost)" || true
        echo "  Remove registry.localhost: docker images --format \"{{.Repository}}:{{.Tag}} {{.ID}}\" | grep \"^registry\\.localhost\" | awk '{print \$2}' | xargs docker rmi -f"
        echo "  Remove base images: docker images --filter \"reference=traefik\" --filter \"reference=registry\" -q | xargs docker rmi -f"
        issues_found=$((issues_found + 1))
    fi

    # Check configuration directories
    if [ -d "$PLATFORM_SERVICES_DIR" ]; then
        log_warning "Platform services directory still exists: $PLATFORM_SERVICES_DIR"
        echo "  Run: rm -rf $PLATFORM_SERVICES_DIR"
        issues_found=$((issues_found + 1))
    fi

    # Test connectivity (should fail after teardown)
    log_info "Testing service connectivity (should fail after teardown)..."
    if command -v curl &> /dev/null; then
        if curl -k -s --connect-timeout 3 https://registry.localhost/v2/_catalog &>/dev/null; then
            log_warning "Registry still responding - teardown may be incomplete"
            issues_found=$((issues_found + 1))
        fi

        if curl -k -s --connect-timeout 3 https://traefik.localhost/api/http/services &>/dev/null; then
            log_warning "Traefik still responding - teardown may be incomplete"
            issues_found=$((issues_found + 1))
        fi
    else
        log_info "curl not available - skipping connectivity test"
    fi

    if [ $issues_found -eq 0 ]; then
        log_success "Teardown verification passed - environment is clean"
    else
        log_warning "Teardown verification found $issues_found potential issues"
        echo "You may need to manually address the warnings above"
    fi
}

# Summary and rebuild instructions
show_rebuild_instructions() {
    echo
    echo -e "${GREEN}🎉 Teardown Complete${NC}"
    echo
    echo "Platform components removed:"
    echo "✅ Docker containers and services"
    echo "✅ Configuration files and directories"
    echo "✅ Docker volumes and networks"
    echo "✅ Test images and containers"
    echo
    echo -e "${BLUE}🔄 To Rebuild Platform:${NC}"
    echo
    echo "Full rebuild (Ansible method - recommended):"
    echo "  cd $REPO_ROOT"
    echo "  ansible-playbook -i ansible/inventory/local-dev.ini ansible/site.yml"
    echo
    echo "Alternative rebuild (manual scripts):"
    echo "  ./scripts/setup.sh"
    echo
    echo "Quick validation after rebuild:"
    echo "  ansible-playbook -i ansible/inventory/local-dev.ini ansible/validate-all.yml"
    echo
    echo -e "${YELLOW}💡 Tip: If you kept certificates, rebuild will be much faster!${NC}"
    echo
}

# Global variable to track cleanup choice
CLEANUP_CHOICE=""

# Main execution
main() {
    print_banner
    confirm_teardown

    echo
    log_info "Starting platform teardown..."
    echo

    # Run teardown steps
    run_ansible_teardown
    cleanup_docker_services
    cleanup_configuration_files
    cleanup_certificates

    # Verification
    echo
    verify_teardown

    # Manual cleanup guidance (only if not complete teardown)
    if [ "$CLEANUP_CHOICE" != "3" ]; then
        show_manual_certificate_cleanup
    fi
    show_docker_desktop_guidance

    # Final summary
    show_rebuild_instructions
}

# Handle script errors
trap 'log_error "Teardown script failed at line $LINENO. Exit code: $?"' ERR

# Run main function
main "$@"
