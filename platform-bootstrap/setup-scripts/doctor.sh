#!/bin/bash
# Platform Doctor - Diagnose common issues
# =========================================

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "🔍 Running Platform Diagnostics"
echo "==============================="
echo ""

# Track overall health
HEALTHY=true

# Check function
check() {
    local name=$1
    local command=$2
    local fix=$3

    echo -n "Checking $name... "

    if eval "$command" >/dev/null 2>&1; then
        echo -e "${GREEN}✓${NC}"
        return 0
    else
        echo -e "${RED}✗${NC}"
        echo "  Fix: $fix"
        HEALTHY=false
        return 1
    fi
}

# System checks
echo "System Requirements:"
echo "-------------------"

check "Docker" \
    "docker --version" \
    "Install Docker Desktop or Docker Engine"

check "Docker Compose" \
    "docker-compose --version" \
    "Install Docker Compose v2"

check "Docker daemon" \
    "docker ps" \
    "Start Docker Desktop or 'sudo systemctl start docker'"

check "Astronomer CLI" \
    "astro version" \
    "Run: curl -sSL install.astronomer.io | sudo bash -s"

check "Python 3.8+" \
    "python3 --version | grep -E '3\.(8|9|10|11|12)'" \
    "Install Python 3.8 or newer"

check "Git" \
    "git --version" \
    "Install Git"

echo ""
echo "Network Configuration:"
echo "---------------------"

check "Docker network" \
    "docker network inspect platform_network" \
    "Run: docker network create platform_network"

check "Port 5000 available" \
    "! lsof -i:5000" \
    "Stop service using port 5000 or change REGISTRY_CACHE_PORT"

check "Port 8080 available" \
    "! lsof -i:8080" \
    "Stop service using port 8080 (usually another Airflow)"

echo ""
echo "Platform Services:"
echo "-----------------"

check "Registry cache" \
    "curl -s http://localhost:5000/v2/_catalog" \
    "Run: make registry-start"

check "Kerberos service" \
    "docker ps | grep kerberos-platform-service" \
    "Run: make kerberos-start"

echo ""
echo "Environment Configuration:"
echo "-------------------------"

check "HOME variable" \
    "[ -n \"\$HOME\" ]" \
    "Set HOME environment variable"

check ".docker directory" \
    "[ -d \"\$HOME/.docker\" ]" \
    "Run Docker Desktop once to create .docker directory"

check "WSL2 (if Windows)" \
    "[ \"\$(uname -r | grep -i microsoft)\" = \"\" ] || [ -f /proc/sys/fs/binfmt_misc/WSLInterop ]" \
    "Enable WSL2 in Windows Features"

echo ""
echo "Artifactory Access:"
echo "------------------"

if [ -n "${ARTIFACTORY_URL:-}" ]; then
    check "Artifactory connectivity" \
        "curl -s -o /dev/null -w '%{http_code}' https://${ARTIFACTORY_URL} | grep -qE '200|401|403'" \
        "Check VPN connection or ARTIFACTORY_URL setting"

    check "Artifactory credentials" \
        "[ -n \"\${ARTIFACTORY_USERNAME:-}\" ] && [ -n \"\${ARTIFACTORY_PASSWORD:-}\" ]" \
        "Set ARTIFACTORY_USERNAME and ARTIFACTORY_PASSWORD"
else
    echo -e "${YELLOW}⚠${NC} ARTIFACTORY_URL not set (offline mode)"
fi

echo ""
echo "Kerberos Configuration:"
echo "----------------------"

check "krb5.conf exists" \
    "[ -f /etc/krb5.conf ] || [ -f \"\$HOME/.krb5/krb5.conf\" ]" \
    "Create krb5.conf or copy from corporate IT"

check "Kerberos ticket (optional)" \
    "klist -s" \
    "Run: kinit USERNAME@DOMAIN (optional for development)"

echo ""
echo "Disk Space:"
echo "----------"

DOCKER_ROOT=$(docker info 2>/dev/null | grep "Docker Root Dir" | awk '{print $NF}')
if [ -n "$DOCKER_ROOT" ]; then
    DISK_USAGE=$(df -h "$DOCKER_ROOT" | tail -1 | awk '{print $5}' | sed 's/%//')
    if [ "$DISK_USAGE" -gt 80 ]; then
        echo -e "${YELLOW}⚠${NC} Docker disk usage high: ${DISK_USAGE}%"
        echo "  Fix: Run 'docker system prune -a' to free space"
        HEALTHY=false
    else
        echo -e "${GREEN}✓${NC} Docker disk usage: ${DISK_USAGE}%"
    fi
fi

echo ""
echo "Memory:"
echo "-------"

if command -v free >/dev/null 2>&1; then
    TOTAL_MEM=$(free -m | grep "^Mem:" | awk '{print $2}')
    AVAIL_MEM=$(free -m | grep "^Mem:" | awk '{print $7}')

    if [ "$AVAIL_MEM" -lt 2048 ]; then
        echo -e "${YELLOW}⚠${NC} Low available memory: ${AVAIL_MEM}MB"
        echo "  Fix: Close unnecessary applications"
        HEALTHY=false
    else
        echo -e "${GREEN}✓${NC} Available memory: ${AVAIL_MEM}MB"
    fi
fi

echo ""
echo "================================"
if [ "$HEALTHY" = true ]; then
    echo -e "${GREEN}✓ Platform is healthy!${NC}"
    echo ""
    echo "Ready to start development:"
    echo "  make platform-start"
    echo "  astro dev init my-project"
else
    echo -e "${RED}✗ Some issues found${NC}"
    echo ""
    echo "Fix the issues above, then run:"
    echo "  $0"
fi

exit $([ "$HEALTHY" = true ] && echo 0 || echo 1)
