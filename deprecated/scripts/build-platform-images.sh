#!/bin/bash
# Build and push platform images to local registry
# This should be part of the standard platform setup

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REGISTRY_HOST="registry.localhost"

echo -e "${BLUE}📦 PLATFORM IMAGE BUILDER${NC}"
echo "=========================="
echo
echo "This builds and pushes platform images that all projects depend on:"
echo "• Airflow base image with common dependencies"
echo "• Data processing runners (future)"
echo

# Check prerequisites
echo -e "${BLUE}Checking prerequisites...${NC}"

# Check if registry is accessible
if ! curl -s "https://$REGISTRY_HOST/v2/_catalog" >/dev/null 2>&1; then
    echo -e "${RED}❌ Registry not accessible at https://$REGISTRY_HOST${NC}"
    echo
    echo "Please ensure platform setup is complete:"
    echo "  ansible-playbook -i ansible/inventory/local-dev.ini ansible/setup-wsl2.yml"
    exit 1
fi
echo -e "${GREEN}✅ Registry is accessible${NC}"

# Check if Traefik is running
if ! docker ps --format "{{.Names}}" | grep -q "traefik"; then
    echo -e "${YELLOW}⚠️  Traefik not running - starting it${NC}"
    if [ -d "$HOME/platform-services/traefik" ]; then
        cd "$HOME/platform-services/traefik"
        docker compose up -d
        cd "$REPO_ROOT"
    fi
fi

# Build Layer 1: Platform Base Airflow Image
echo
echo -e "${BLUE}Building Platform Airflow Base Image${NC}"
echo "-------------------------------------"

if [ -f "$REPO_ROOT/layer1-platform/docker/airflow-base.Dockerfile" ]; then
    cd "$REPO_ROOT/layer1-platform"

    # Check for required files
    if [ ! -f "requirements.txt" ]; then
        echo -e "${YELLOW}Creating minimal requirements.txt${NC}"
        echo "# Platform base requirements" > requirements.txt
        echo "apache-airflow-providers-microsoft-mssql==4.3.2" >> requirements.txt
    fi

    if [ ! -d "airflow_plugins" ]; then
        echo -e "${YELLOW}Creating empty plugins directory${NC}"
        mkdir -p airflow_plugins
    fi

    echo "Building image..."
    if docker build -f docker/airflow-base.Dockerfile \
        -t "$REGISTRY_HOST/platform/airflow-base:3.0-10" \
        -t "$REGISTRY_HOST/platform/airflow-base:latest" .; then
        echo -e "${GREEN}✅ Build successful${NC}"

        # Push to registry
        echo "Pushing to registry..."
        if docker push "$REGISTRY_HOST/platform/airflow-base:3.0-10" && \
           docker push "$REGISTRY_HOST/platform/airflow-base:latest"; then
            echo -e "${GREEN}✅ Pushed to registry${NC}"
        else
            echo -e "${RED}❌ Failed to push to registry${NC}"
            exit 1
        fi
    else
        echo -e "${RED}❌ Build failed${NC}"
        exit 1
    fi
else
    echo -e "${RED}❌ Dockerfile not found at layer1-platform/docker/airflow-base.Dockerfile${NC}"
    exit 1
fi

# Verify image is in registry
echo
echo -e "${BLUE}Verifying registry contents...${NC}"
CATALOG=$(curl -s "https://$REGISTRY_HOST/v2/_catalog")
echo "Registry catalog: $CATALOG"

if echo "$CATALOG" | grep -q "platform/airflow-base"; then
    echo -e "${GREEN}✅ Platform Airflow image confirmed in registry${NC}"

    # Get tags
    TAGS=$(curl -s "https://$REGISTRY_HOST/v2/platform/airflow-base/tags/list" 2>/dev/null || echo "{}")
    if [ -n "$TAGS" ] && [ "$TAGS" != "{}" ]; then
        echo "Available tags: $TAGS"
    fi
else
    echo -e "${YELLOW}⚠️  Image not showing in catalog yet${NC}"
fi

# Summary
echo
echo -e "${BLUE}📊 BUILD SUMMARY${NC}"
echo "================"
echo
echo -e "${GREEN}✅ Platform images built and pushed successfully!${NC}"
echo
echo "Images available:"
echo "• ${REGISTRY_HOST}/platform/airflow-base:3.0-10"
echo "• ${REGISTRY_HOST}/platform/airflow-base:latest"
echo
echo "These images can now be used as base images in:"
echo "• Airflow projects (FROM ${REGISTRY_HOST}/platform/airflow-base:latest)"
echo "• Data processing containers"
echo "• Development environments"
echo
echo "Next steps:"
echo "1. Test Airflow with: ./scripts/test-airflow-certificates.sh"
echo "2. Use in projects: FROM ${REGISTRY_HOST}/platform/airflow-base:latest"
