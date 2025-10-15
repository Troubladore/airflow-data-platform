#!/bin/bash
# Clean Slate - Remove all platform Docker resources
# ===================================================
# Use this when you want to start fresh with a clean environment

set -e

# Colors
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m'

echo "🧹 Clean Slate - Platform Docker Cleanup"
echo "========================================="
echo ""
echo -e "${YELLOW}This will remove:${NC}"
echo "  • Kerberos sidecar container"
echo "  • Mock services containers"
echo "  • platform_network"
echo ""
echo -e "${YELLOW}Optional removals (you choose):${NC}"
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
    echo -e "  ${YELLOW}→ Will remove: platform/kerberos-sidecar:latest${NC}"
else
    echo -e "  ${GREEN}→ Will keep: platform/kerberos-sidecar:latest (reusable)${NC}"
fi

echo ""

# Ask about ticket cache
CLEAR_TICKET_CACHE=false
if ask_yes_no "Clear ticket cache volume? (removes stale tickets)"; then
    CLEAR_TICKET_CACHE=true
    echo -e "  ${YELLOW}→ Will remove: platform_kerberos_cache volume${NC}"
else
    echo -e "  ${GREEN}→ Will keep: platform_kerberos_cache volume${NC}"
fi

echo ""
echo -e "${GREEN}Always preserved:${NC}"
echo "  • Your .env configuration"
echo "  • Your Kerberos tickets on host"
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
        echo -e "${GREEN}✓${NC} Removed platform_kerberos_cache volume (tickets cleared)"
    else
        echo "  platform_kerberos_cache: not found or in use"
    fi
else
    # Just clean - keep volume and tickets
    echo -e "${GREEN}✓${NC} Keeping platform_kerberos_cache volume (tickets preserved)"
fi

# Remove network
if docker network rm platform_network 2>/dev/null; then
    echo -e "${GREEN}✓${NC} Removed platform_network"
else
    echo "  platform_network: not found or in use"
fi

echo ""

# Remove built images if requested
if [ "$REMOVE_IMAGES" = true ]; then
    echo "Removing built images..."

    if docker rmi platform/kerberos-sidecar:latest 2>/dev/null; then

    if docker rmi platform/kerberos-test:latest 2>/dev/null; then
        echo -e "${GREEN}✓${NC} Removed platform/kerberos-test:latest"
    else
        echo "  platform/kerberos-test:latest: not found"
    fi
        echo -e "${GREEN}✓${NC} Removed platform/kerberos-sidecar:latest"
    else
        echo "  platform/kerberos-sidecar:latest: not found"
    fi

    echo ""
fi

echo -e "${GREEN}✓ Clean slate complete!${NC}"
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
