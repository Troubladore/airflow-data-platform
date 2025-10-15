#!/bin/bash
# Platform Doctor - Diagnose common issues
# =========================================

set -euo pipefail

# Source the shared formatting library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLATFORM_DIR="$(dirname "$SCRIPT_DIR")"
if [ -f "$PLATFORM_DIR/lib/formatting.sh" ]; then
    source "$PLATFORM_DIR/lib/formatting.sh"
else
    # Fallback if library not found
    echo "Warning: formatting library not found, using basic output" >&2
    print_check() { echo "[$1] $2"; }
    print_section() { echo "=== $1 ==="; }
    print_header() { echo "=== $1 ==="; }
    print_success() { echo "$@"; }
    print_error() { echo "Error: $@"; }
    print_warning() { echo "Warning: $@"; }
    CHECK_MARK="[OK]"
    CROSS_MARK="[FAIL]"
    WARNING_SIGN="[WARN]"
    INFO_SIGN="[INFO]"
    GREEN=''
    YELLOW=''
    RED=''
    NC=''
fi

print_title "Running Platform Diagnostics" "🔍"
print_divider 56
echo ""

# Track overall health
HEALTHY=true

# Check function
check() {
    local name=$1
    local command=$2
    local fix=$3

    if eval "$command" >/dev/null 2>&1; then
        print_check "PASS" "$name"
        return 0
    else
        print_check "FAIL" "$name" "Fix: $fix"
        HEALTHY=false
        return 1
    fi
}

# System checks
print_section "System Requirements"

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
    "See: https://docs.astronomer.io/astro/cli/install-cli"

check "Python 3.8+" \
    "python3 --version | grep -E '3\.(8|9|10|11|12)'" \
    "Install Python 3.8 or newer"

check "Git" \
    "git --version" \
    "Install Git"

echo ""
print_section "Network Configuration"

check "Docker network" \
    "docker network inspect platform_network" \
    "Run: docker network create platform_network"

check "Port 8080 available" \
    "! lsof -i:8080" \
    "Stop service using port 8080 (usually another Airflow)"

echo ""
print_section "Platform Services"

check "Kerberos service" \
    "docker ps | grep kerberos-platform-service" \
    "Run: make kerberos-start"

echo ""
print_section "Environment Configuration"

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
print_section "Note: Docker Image Caching"
print_check "INFO" "Docker automatically caches all pulled images" "No local registry service needed for development. Custom images: docker build -t myimage:latest . (cached automatically)"

echo ""
print_section "Kerberos Configuration"

check "krb5.conf exists" \
    "[ -f /etc/krb5.conf ] || [ -f \"\$HOME/.krb5/krb5.conf\" ]" \
    "Create krb5.conf or copy from corporate IT"

check "Kerberos ticket (optional)" \
    "klist -s" \
    "Run: kinit USERNAME@DOMAIN (optional for development)"

echo ""
print_section "Disk Space"

DOCKER_ROOT=$(docker info 2>/dev/null | grep "Docker Root Dir" | awk '{print $NF}')
if [ -n "$DOCKER_ROOT" ]; then
    DISK_USAGE=$(df -h "$DOCKER_ROOT" | tail -1 | awk '{print $5}' | sed 's/%//')
    if [ "$DISK_USAGE" -gt 80 ]; then
        print_check "WARN" "Docker disk usage high: ${DISK_USAGE}%" "Fix: Run 'docker system prune -a' to free space"
        HEALTHY=false
    else
        print_check "PASS" "Docker disk usage: ${DISK_USAGE}%"
    fi
fi

echo ""
print_section "Memory"

if command -v free >/dev/null 2>&1; then
    TOTAL_MEM=$(free -m | grep "^Mem:" | awk '{print $2}')
    AVAIL_MEM=$(free -m | grep "^Mem:" | awk '{print $7}')

    if [ "$AVAIL_MEM" -lt 2048 ]; then
        print_check "WARN" "Low available memory: ${AVAIL_MEM}MB" "Fix: Close unnecessary applications"
        HEALTHY=false
    else
        print_check "PASS" "Available memory: ${AVAIL_MEM}MB"
    fi
fi

echo ""
print_divider 56
if [ "$HEALTHY" = true ]; then
    print_success "Platform is healthy!"
    echo ""
    echo "Ready to start development:"
    echo "  make platform-start"
    echo "  astro dev init my-project"
else
    print_error "Some issues found"
    echo ""
    echo "Fix the issues above, then run:"
    echo "  $0"
fi

exit $([ "$HEALTHY" = true ] && echo 0 || echo 1)
