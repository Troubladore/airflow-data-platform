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
echo "  • platform_kerberos_cache volume"
echo "  • platform_network"
echo ""
echo -e "${YELLOW}Options:${NC}"
echo "  1. Clean resources only (keep built images)"
echo "  2. Full clean (also remove built images - forces rebuild)"
echo ""

read -p "Choose [1-2, default 1]: " -n 1 -r cleanup_level
echo
cleanup_level=${cleanup_level:-1}

REMOVE_IMAGES=false
if [ "$cleanup_level" = "2" ]; then
    REMOVE_IMAGES=true
    echo ""
    echo -e "${YELLOW}Full clean selected - will also remove:${NC}"
    echo "  • platform/kerberos-sidecar:latest image"
    echo "  • This forces a complete rebuild next time"
    echo ""
fi

echo -e "${GREEN}Preserved:${NC}"
echo "  • Your .env configuration"
echo "  • Your Kerberos tickets on host"
if [ "$REMOVE_IMAGES" = false ]; then
    echo "  • Built sidecar image (reusable)"
fi
echo ""

read -p "Continue? [y/N]: " -n 1 -r
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

# Remove volume
if docker volume rm platform_kerberos_cache 2>/dev/null; then
    echo -e "${GREEN}✓${NC} Removed platform_kerberos_cache volume"
else
    echo "  platform_kerberos_cache: not found or in use"
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
