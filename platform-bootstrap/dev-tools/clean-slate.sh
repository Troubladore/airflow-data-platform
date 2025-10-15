#!/bin/bash
# Clean Slate - Remove all platform Docker resources
# ===================================================
# Use this when you want to start fresh with a clean environment

set -e

# Source the shared formatting library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLATFORM_DIR="$(dirname "$SCRIPT_DIR")"
if [ -f "$PLATFORM_DIR/lib/formatting.sh" ]; then
    source "$PLATFORM_DIR/lib/formatting.sh"
else
    # Fallback if library not found
    echo "Warning: formatting library not found, using basic output" >&2
    print_msg() { echo "$@"; }
    print_success() { echo "$@"; }
    print_warning() { echo "Warning: $@"; }
    print_error() { echo "Error: $@"; }
    CHECK_MARK="[OK]"
    CROSS_MARK="[FAIL]"
    GREEN=''
    YELLOW=''
    RED=''
    NC=''
fi

print_title "Clean Slate - Platform Docker Cleanup" "🧹"
echo "========================================="
echo ""
print_list_header "This will remove:"
print_bullet "Kerberos sidecar container"
print_bullet "Mock services containers"
print_bullet "platform_network"
echo ""
print_list_header "Optional removals (you choose):"
echo ""

# Helper function for yes/no prompts
ask_yes_no() {
    local prompt="$1"
    read -p "$prompt [y/N]: " -n 1 -r
    echo
    [[ $REPLY =~ ^[Yy]$ ]]
}

# Ask about images
REMOVE_IMAGES=false
if ask_yes_no "Remove built sidecar image? (forces rebuild next time)"; then
    REMOVE_IMAGES=true
    print_arrow "WARN" "Will remove: platform/kerberos-sidecar:latest"
else
    print_arrow "PASS" "Will keep: platform/kerberos-sidecar:latest (reusable)"
fi

echo ""

# Ask about ticket cache
CLEAR_TICKET_CACHE=false
if ask_yes_no "Clear ticket cache volume? (removes stale tickets)"; then
    CLEAR_TICKET_CACHE=true
    print_arrow "WARN" "Will remove: platform_kerberos_cache volume"
else
    print_arrow "PASS" "Will keep: platform_kerberos_cache volume"
fi

echo ""

# Ask about host-side tickets
CLEAR_HOST_TICKETS=false
if ask_yes_no "Clear host-side Kerberos tickets? (removes all ticket caches)"; then
    CLEAR_HOST_TICKETS=true

    # Check if custom directory is configured
    CUSTOM_TICKET_MSG=""
    if [ -f "$PLATFORM_DIR/.env" ]; then
        # Source the .env to check for custom directory
        source "$PLATFORM_DIR/.env" 2>/dev/null || true
        if [ -n "$KERBEROS_TICKET_DIR" ]; then
            EXPANDED_DIR=$(eval echo "$KERBEROS_TICKET_DIR")
            CUSTOM_TICKET_MSG=", $EXPANDED_DIR/*"
        fi
    fi

    print_arrow "WARN" "Will remove: /tmp/krb5*, /dev/shm/krb5*${CUSTOM_TICKET_MSG}"
    print_arrow "WARN" "Warning: This affects ALL users on the host"
else
    print_arrow "PASS" "Will keep: Host-side Kerberos tickets"
fi

echo ""
print_success "Always preserved:"
print_bullet "Your .env configuration"
if [ "$CLEAR_HOST_TICKETS" = false ]; then
    print_bullet "Your Kerberos tickets on host"
fi
echo ""

read -p "Proceed with cleanup? [y/N]: " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cancelled"
    exit 0
fi

echo ""
echo "Stopping and removing containers..."

# Stop services
docker compose down 2>/dev/null || echo "  (no services to stop)"
docker compose -f docker-compose.mock-services.yml down 2>/dev/null || echo "  (no mock services)"

# Remove specific containers by name
docker rm -f kerberos-platform-service 2>/dev/null || echo "  kerberos-platform-service: not found"
docker rm -f mock-delinea 2>/dev/null || echo "  mock-delinea: not found"

echo ""
echo "Removing Docker resources..."

# Handle ticket cache based on purge level
if [ "$CLEAR_TICKET_CACHE" = true ]; then
    # Complete purge - remove volume entirely
    if docker volume rm platform_kerberos_cache 2>/dev/null; then
        print_status "PASS" "Removed platform_kerberos_cache volume (tickets cleared)"
    else
        echo "  platform_kerberos_cache: not found or in use"
    fi
else
    # Just clean - keep volume and tickets
    print_status "PASS" "Keeping platform_kerberos_cache volume (tickets preserved)"
fi

# Remove network
if docker network rm platform_network 2>/dev/null; then
    print_status "PASS" "Removed platform_network"
else
    echo "  platform_network: not found or in use"
fi

echo ""

# Remove built images if requested
if [ "$REMOVE_IMAGES" = true ]; then
    echo "Removing built images..."

    if docker rmi platform/kerberos-sidecar:latest 2>/dev/null; then
        print_status "PASS" "Removed platform/kerberos-sidecar:latest"
    else
        echo "  platform/kerberos-sidecar:latest: not found"
    fi

    if docker rmi platform/kerberos-test:latest 2>/dev/null; then
        print_status "PASS" "Removed platform/kerberos-test:latest"
    else
        echo "  platform/kerberos-test:latest: not found"
    fi

    echo ""
fi

# Clean host-side Kerberos tickets if requested
if [ "$CLEAR_HOST_TICKETS" = true ]; then
    echo "Cleaning host-side Kerberos tickets..."
    echo ""
    print_status "WARN" "Warning: This will remove ALL Kerberos tickets for ALL users"
    print_warning "You will need to run 'kinit' again after cleanup"
    echo ""
    read -p "Are you SURE you want to proceed? [y/N]: " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        removed_count=0

        # Load custom ticket directory from .env if it exists
        if [ -f "$PLATFORM_DIR/.env" ]; then
            # Source the .env file to get KERBEROS_TICKET_DIR
            source "$PLATFORM_DIR/.env" 2>/dev/null || true

            # Clean custom ticket directory if configured
            if [ -n "$KERBEROS_TICKET_DIR" ]; then
                # Expand HOME variable if present
                EXPANDED_DIR=$(eval echo "$KERBEROS_TICKET_DIR")

                if [ -d "$EXPANDED_DIR" ]; then
                    print_status "INFO" "Checking custom ticket directory: $EXPANDED_DIR"

                    # Remove ticket files in custom directory
                    for ticket in "$EXPANDED_DIR"/krb5cc_* "$EXPANDED_DIR"/krb5_* "$EXPANDED_DIR"/tkt* "$EXPANDED_DIR"/dev/tkt*; do
                        if [ -f "$ticket" ] || [ -d "$ticket" ]; then
                            if rm -rf "$ticket" 2>/dev/null; then
                                print_status "PASS" "Removed $ticket"
                                removed_count=$((removed_count + 1))
                            else
                                print_status "WARN" "Could not remove $ticket (permission denied?)"
                            fi
                        fi
                    done
                fi
            fi
        fi

        # Remove file-based ticket caches in /tmp
        for ticket in /tmp/krb5cc_* /tmp/krb5_*; do
            if [ -f "$ticket" ] || [ -d "$ticket" ]; then
                if rm -rf "$ticket" 2>/dev/null; then
                    print_status "PASS" "Removed $ticket"
                    removed_count=$((removed_count + 1))
                else
                    print_status "WARN" "Could not remove $ticket (permission denied?)"
                fi
            fi
        done

        # Remove shared memory ticket caches
        if [ -d "/dev/shm" ]; then
            for ticket in /dev/shm/krb5cc_* /dev/shm/krb5_*; do
                if [ -f "$ticket" ] || [ -d "$ticket" ]; then
                    if rm -rf "$ticket" 2>/dev/null; then
                        print_status "PASS" "Removed $ticket"
                        removed_count=$((removed_count + 1))
                    else
                        print_status "WARN" "Could not remove $ticket (permission denied?)"
                    fi
                fi
            done
        fi

        # Note about keyring caches (cannot be easily cleaned)
        if [ -d "/proc/keys" ]; then
            print_status "INFO" "Note: Keyring-based caches (KEYRING:) require 'keyctl purge' to clean"
            echo "   Run: keyctl purge krb5cc @s (requires root for other users)"
        fi

        if [ $removed_count -eq 0 ]; then
            echo "  No host-side ticket caches found to remove"
        else
            echo ""
            print_status "PASS" "Removed $removed_count ticket cache(s) from host"
        fi

        echo ""
    else
        echo "  Skipped host-side ticket cleanup"
        echo ""
    fi
fi

print_status "PASS" "Clean slate complete!"
echo ""

if [ "$REMOVE_IMAGES" = true ]; then
    echo "Full clean completed. Next run will rebuild sidecar image."
else
    echo "Resources cleaned. Built images preserved for faster restart."
fi

echo ""
echo "To set up again:"
echo "  make kerberos-setup"
echo ""
echo "Your configuration is preserved in:"
echo "  platform-bootstrap/.env"
