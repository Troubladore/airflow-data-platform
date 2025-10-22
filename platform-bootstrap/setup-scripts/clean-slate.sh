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
echo "This will clean up the composable platform architecture:"
echo ""
print_list_header "Services that will be removed:"
print_bullet "platform-infrastructure (platform-postgres, platform_network)"
print_bullet "openmetadata (opensearch, server, migration containers)"
print_bullet "kerberos-sidecar (ticket sharing service)"
print_bullet "pagila (if running)"
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
if ask_yes_no "Remove ALL platform images? (forces re-download/rebuild next time)"; then
    REMOVE_IMAGES=true
    print_arrow "WARN" "Will remove: All platform, OpenMetadata, PostgreSQL, Elasticsearch images"
else
    print_arrow "PASS" "Will keep: Downloaded images (faster next startup)"
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

REPO_ROOT="$(dirname "$PLATFORM_DIR")"

echo ""
echo "Stopping and removing services..."
echo ""

# Stop optional services first
if ask_yes_no "Remove OpenMetadata?"; then
    echo "Stopping OpenMetadata..."
    cd "$REPO_ROOT/openmetadata" && make stop 2>/dev/null || true
    # Remove both old elasticsearch and new opensearch containers
    docker rm -f openmetadata-server openmetadata-elasticsearch openmetadata-opensearch openmetadata-migrate 2>/dev/null || true
    cd "$PLATFORM_DIR"
    if ask_yes_no "  Also remove OpenMetadata data volumes (search indices)?"; then
        # Remove both old elasticsearch and new opensearch volumes
        docker volume rm openmetadata_es_data openmetadata_elasticsearch_data openmetadata_opensearch_data 2>/dev/null || true
        print_success "OpenMetadata data removed"
    else
        print_info "OpenMetadata data preserved"
    fi
    echo ""
fi

if ask_yes_no "Remove Kerberos sidecar service?"; then
    echo "Stopping Kerberos sidecar..."
    cd "$REPO_ROOT/kerberos" && make stop 2>/dev/null || docker rm -f kerberos-sidecar 2>/dev/null || true
    cd "$PLATFORM_DIR"
    echo ""
fi

if ask_yes_no "Remove Pagila?"; then
    echo "Stopping Pagila..."
    # Handle both old and new container names (including jsonb restore container)
    docker stop pagila pagila-postgres pagila-jsonb-restore pgadmin pgadmin4 2>/dev/null || true
    docker rm pagila pagila-postgres pagila-jsonb-restore pgadmin pgadmin4 2>/dev/null || true
    if ask_yes_no "  Also remove Pagila data volume?"; then
        # Remove all possible Pagila volume names
        docker volume rm pagila_pgdata pagila_postgres-data 2>/dev/null || true
        print_success "Pagila data removed"
    else
        print_info "Pagila data preserved"
    fi
    # Remove pagila repository directory
    if ask_yes_no "  Also remove pagila repository directory?"; then
        rm -rf "$REPO_ROOT/../pagila" "$REPO_ROOT/pagila" 2>/dev/null || true
        print_success "Pagila repository removed"
    else
        print_info "Pagila repository preserved"
    fi
    echo ""
fi

# Infrastructure cleanup (ask last - it's the foundation)
if ask_yes_no "Remove platform-infrastructure (PostgreSQL + network)?"; then
    echo ""
    print_warning "This removes the SHARED foundation!"
    print_warning "Affects: Airflow metastore, OpenMetadata catalog, all platform DBs"
    if ask_yes_no "  Are you sure? This deletes ALL platform data!"; then
        echo "Stopping infrastructure..."
        cd "$REPO_ROOT/platform-infrastructure" && make stop 2>/dev/null || docker rm -f platform-postgres 2>/dev/null || true
        cd "$PLATFORM_DIR"
        if ask_yes_no "    Remove platform_postgres_data volume (DELETES ALL DATA)?"; then
            docker volume rm platform_postgres_data 2>/dev/null || true
            print_warning "Platform data deleted!"
        else
            print_info "Platform data preserved"
        fi
        docker network rm platform_network 2>/dev/null || true
    else
        print_info "Infrastructure preserved"
    fi
    echo ""
fi

echo ""
echo "Cleaning up Docker resources..."
echo ""

# Handle ticket cache volume
if [ "$CLEAR_TICKET_CACHE" = true ]; then
    if docker volume rm platform_kerberos_cache 2>/dev/null; then
        print_success "Removed platform_kerberos_cache volume"
    else
        print_info "platform_kerberos_cache: not found"
    fi
fi

# Remove platform images if requested
if [ "$REMOVE_IMAGES" = true ]; then
    echo "Removing all platform images..."

    # Built images (platform namespace)
    docker rmi platform/kerberos-sidecar:latest 2>/dev/null && echo "  ✓ Removed platform/kerberos-sidecar" || true
    docker rmi platform/kerberos-test:latest 2>/dev/null && echo "  ✓ Removed platform/kerberos-test" || true

    # Remove images by pattern (works for any registry including corporate)
    echo ""
    echo "Removing OpenMetadata images from any registry..."
    # Remove ANY openmetadata image (version-agnostic)
    for img in $(docker images --format "{{.Repository}}:{{.Tag}}" | grep -i "openmetadata"); do
        docker rmi "$img" 2>/dev/null && echo "  ✓ Removed $img" || true
    done

    echo "Removing Elasticsearch images from any registry..."
    # Remove ANY elasticsearch image
    for img in $(docker images --format "{{.Repository}}:{{.Tag}}" | grep -i "elasticsearch"); do
        docker rmi "$img" 2>/dev/null && echo "  ✓ Removed $img" || true
    done

    echo "Removing OpenSearch images from any registry..."
    # Remove ANY opensearch image
    for img in $(docker images --format "{{.Repository}}:{{.Tag}}" | grep -i "opensearch"); do
        docker rmi "$img" 2>/dev/null && echo "  ✓ Removed $img" || true
    done

    echo "Removing PostgreSQL images from any registry..."
    # Remove ANY postgres image (including corporate registry paths)
    # This catches postgres:*, */postgres:*, artifactory.*/postgres:*, etc.
    for img in $(docker images --format "{{.Repository}}:{{.Tag}}" | grep -i "postgres"); do
        docker rmi "$img" 2>/dev/null && echo "  ✓ Removed $img" || true
    done

    echo "Removing pgAdmin images from any registry..."
    for img in $(docker images --format "{{.Repository}}:{{.Tag}}" | grep -E "pgadmin4"); do
        docker rmi "$img" 2>/dev/null && echo "  ✓ Removed $img" || true
    done

    echo "Removing Alpine images from any registry..."
    # Remove ANY standalone alpine image (but not postgres:*-alpine, etc.)
    for img in $(docker images --format "{{.Repository}}:{{.Tag}}" | grep -E "^alpine:|/alpine:"); do
        docker rmi "$img" 2>/dev/null && echo "  ✓ Removed $img" || true
    done

    print_success "All platform images removed (will re-download on next startup)"
    echo ""
fi

# Clean up anonymous volumes
echo "Removing anonymous/orphaned volumes..."
docker volume prune -f >/dev/null 2>&1 || true
print_success "Anonymous volumes cleaned"
echo ""

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
