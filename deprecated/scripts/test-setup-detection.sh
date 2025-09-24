#!/bin/bash
# Test script to validate platform setup detection logic
# This ensures the setup doesn't prompt users for things that are already done

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}🧪 TESTING SETUP DETECTION LOGIC${NC}"
echo "=================================="
echo

# Test 1: Certificate Detection
echo -e "${BLUE}1️⃣ Certificate Detection${NC}"
echo "-------------------------"

# Check if certificates exist in either location
CERT_DIR="${HOME}/.local/share/certs"
WINDOWS_USERNAME="${WINDOWS_USERNAME:-${USER}}"
WINDOWS_CERT="/mnt/c/Users/${WINDOWS_USERNAME}/AppData/Local/mkcert/dev-localhost-wild.crt"
WSL_CERT="${CERT_DIR}/dev-localhost-wild.crt"

if [ -f "$WINDOWS_CERT" ]; then
    echo -e "${GREEN}✅ Windows certificates found${NC}"
    echo "   Location: $WINDOWS_CERT"
elif [ -f "$WSL_CERT" ]; then
    echo -e "${GREEN}✅ WSL2 certificates found${NC}"
    echo "   Location: $WSL_CERT"
else
    echo -e "${YELLOW}⚠️  No certificates found${NC}"
    echo "   Expected locations:"
    echo "   - Windows: $WINDOWS_CERT"
    echo "   - WSL2: $WSL_CERT"
fi

# Test 2: mkcert Installation
echo
echo -e "${BLUE}2️⃣ mkcert Installation${NC}"
echo "-----------------------"

# Check WSL2 mkcert
if command -v mkcert >/dev/null 2>&1; then
    MKCERT_VERSION=$(mkcert -version 2>/dev/null || echo "unknown")
    echo -e "${GREEN}✅ mkcert installed in WSL2${NC}"
    echo "   Version: $MKCERT_VERSION"
else
    echo -e "${YELLOW}⚠️  mkcert not installed in WSL2${NC}"
fi

# Test 3: Docker Status
echo
echo -e "${BLUE}3️⃣ Docker Status${NC}"
echo "-----------------"

if docker info >/dev/null 2>&1; then
    echo -e "${GREEN}✅ Docker daemon is running${NC}"
    DOCKER_VERSION=$(docker version --format '{{.Server.Version}}' 2>/dev/null || echo "unknown")
    echo "   Version: $DOCKER_VERSION"
else
    echo -e "${RED}❌ Docker daemon not accessible${NC}"
fi

# Test 4: Platform Services
echo
echo -e "${BLUE}4️⃣ Platform Services${NC}"
echo "---------------------"

# Check if Traefik and Registry are running
if docker ps --filter "name=traefik-traefik" --format "{{.Status}}" 2>/dev/null | grep -q "Up"; then
    echo -e "${GREEN}✅ Traefik is running${NC}"
else
    echo -e "${YELLOW}⚠️  Traefik not running${NC}"
fi

if docker ps --filter "name=traefik-registry" --format "{{.Status}}" 2>/dev/null | grep -q "Up"; then
    echo -e "${GREEN}✅ Registry is running${NC}"
else
    echo -e "${YELLOW}⚠️  Registry not running${NC}"
fi

# Test 5: Platform Images
echo
echo -e "${BLUE}5️⃣ Platform Images${NC}"
echo "-------------------"

if curl -s https://registry.localhost/v2/_catalog 2>/dev/null | grep -q "platform/airflow-base"; then
    echo -e "${GREEN}✅ Platform Airflow image exists in registry${NC}"

    # Check tags
    TAGS=$(curl -s https://registry.localhost/v2/platform/airflow-base/tags/list 2>/dev/null | python3 -c "import sys, json; print(','.join(json.load(sys.stdin).get('tags', [])))" 2>/dev/null || echo "")
    if [ -n "$TAGS" ]; then
        echo "   Tags: $TAGS"

        # Verify both required tags exist
        if [[ "$TAGS" == *"3.0-10"* ]] && [[ "$TAGS" == *"latest"* ]]; then
            echo -e "${GREEN}   ✅ Both required tags present${NC}"
        else
            echo -e "${YELLOW}   ⚠️  Missing required tags (need: 3.0-10, latest)${NC}"
        fi
    fi
else
    echo -e "${YELLOW}⚠️  Platform image not found in registry${NC}"
fi

# Test 6: Hosts File Entries
echo
echo -e "${BLUE}6️⃣ Host Entries${NC}"
echo "----------------"

for host in traefik.localhost registry.localhost airflow.localhost; do
    if getent hosts $host >/dev/null 2>&1; then
        echo -e "${GREEN}✅ $host resolves${NC}"
    else
        echo -e "${YELLOW}⚠️  $host does not resolve${NC}"
    fi
done

# Summary
echo
echo -e "${BLUE}📊 DETECTION TEST SUMMARY${NC}"
echo "========================="

# Determine what the setup should skip
SHOULD_SKIP=""
SHOULD_PROMPT=""

if [ -f "$WINDOWS_CERT" ] || [ -f "$WSL_CERT" ]; then
    SHOULD_SKIP="${SHOULD_SKIP}\n  ✅ Should skip: Certificate generation prompt"
else
    SHOULD_PROMPT="${SHOULD_PROMPT}\n  ⚠️  Should prompt: Certificate generation"
fi

if command -v mkcert >/dev/null 2>&1; then
    SHOULD_SKIP="${SHOULD_SKIP}\n  ✅ Should skip: mkcert installation in WSL2"
fi

if docker info >/dev/null 2>&1; then
    SHOULD_SKIP="${SHOULD_SKIP}\n  ✅ Should skip: Docker startup warnings"
else
    SHOULD_PROMPT="${SHOULD_PROMPT}\n  ⚠️  Should prompt: Docker Desktop setup"
fi

echo -e "${GREEN}What setup should SKIP:${NC}"
echo -e "$SHOULD_SKIP"

if [ -n "$SHOULD_PROMPT" ]; then
    echo
    echo -e "${YELLOW}What setup should PROMPT for:${NC}"
    echo -e "$SHOULD_PROMPT"
fi

echo
echo "Run the platform setup to verify it respects these detections:"
echo "  ansible-playbook -i ansible/inventory/local-dev.ini ansible/site.yml"
