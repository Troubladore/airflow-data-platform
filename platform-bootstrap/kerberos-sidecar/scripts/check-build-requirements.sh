#!/bin/bash
# Build Requirements Check for Kerberos Sidecar
# ==============================================
# Validates environment before attempting sidecar image build
# Detects common issues and provides actionable fixes

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Check marks
CHECK_MARK="${GREEN}✓${NC}"
CROSS_MARK="${RED}✗${NC}"
WARNING="${YELLOW}⚠${NC}"

echo "Build Requirements Check for Kerberos Sidecar"
echo "=============================================="
echo ""

# Exit code tracking
EXIT_CODE=0

# Function to check a condition and report
check_condition() {
    local description="$1"
    local command="$2"
    local success_msg="$3"
    local failure_msg="$4"

    echo -n "Checking: $description... "
    if eval "$command" >/dev/null 2>&1; then
        echo -e "${CHECK_MARK} $success_msg"
        return 0
    else
        echo -e "${CROSS_MARK} $failure_msg"
        return 1
    fi
}

# Load .env if it exists
if [ -f "../.env" ]; then
    source "../.env"
fi

# ==========================================
# 1. Docker Accessibility
# ==========================================
echo -e "${BLUE}=== 1. DOCKER ACCESSIBILITY ===${NC}"
echo ""

if ! command -v docker >/dev/null 2>&1; then
    echo -e "${CROSS_MARK} Docker command not found"
    echo ""
    echo "Docker is required to build the sidecar image."
    echo ""
    echo "To install Docker:"
    echo "  Ubuntu/Debian: curl -fsSL https://get.docker.com | sh"
    echo "  See: https://docs.docker.com/engine/install/"
    echo ""
    EXIT_CODE=1
elif ! docker info >/dev/null 2>&1; then
    echo -e "${CROSS_MARK} Docker daemon not running or not accessible"
    echo ""
    echo "Docker is installed but not running or you don't have permission."
    echo ""
    echo "To fix:"
    echo "  Start Docker daemon: sudo systemctl start docker"
    echo "  Add yourself to docker group: sudo usermod -aG docker \$USER"
    echo "  Then log out and back in"
    echo ""
    EXIT_CODE=1
else
    echo -e "${CHECK_MARK} Docker is running and accessible"
    DOCKER_VERSION=$(docker version --format '{{.Server.Version}}' 2>/dev/null)
    echo "  Version: $DOCKER_VERSION"
    echo ""
fi

# ==========================================
# 2. Disk Space
# ==========================================
echo -e "${BLUE}=== 2. DISK SPACE ===${NC}"
echo ""

# Check available space in /var/lib/docker (where Docker stores images)
DOCKER_ROOT=$(docker info --format '{{.DockerRootDir}}' 2>/dev/null || echo "/var/lib/docker")
AVAILABLE_SPACE=$(df -BG "$DOCKER_ROOT" 2>/dev/null | awk 'NR==2 {print $4}' | sed 's/G//' || echo "0")

# Handle case where AVAILABLE_SPACE is empty or not a number
if [ -z "$AVAILABLE_SPACE" ] || ! [[ "$AVAILABLE_SPACE" =~ ^[0-9]+$ ]]; then
    AVAILABLE_SPACE=0
fi

if [ "$AVAILABLE_SPACE" -lt 2 ] && [ "$AVAILABLE_SPACE" -ne 0 ]; then
    echo -e "${CROSS_MARK} Insufficient disk space"
    echo ""
    echo "Available space at $DOCKER_ROOT: ${AVAILABLE_SPACE}GB"
    echo "Required: At least 2GB for image build"
    echo ""
    echo "To free space:"
    echo "  docker system prune -a  # Remove unused images and containers"
    echo "  docker volume prune     # Remove unused volumes"
    echo ""
    EXIT_CODE=1
elif [ "$AVAILABLE_SPACE" -lt 5 ] && [ "$AVAILABLE_SPACE" -ne 0 ]; then
    echo -e "${WARNING} Limited disk space"
    echo "  Available: ${AVAILABLE_SPACE}GB at $DOCKER_ROOT"
    echo "  Recommended: 5GB or more"
    echo ""
elif [ "$AVAILABLE_SPACE" -eq 0 ]; then
    # Check if we're in WSL2
    if [ -f /proc/sys/fs/binfmt_misc/WSLInterop ]; then
        echo -e "${CHECK_MARK} WSL2 detected - disk space check skipped"
        echo "  (WSL2 uses dynamically allocated disk space)"
        echo ""
    else
        echo -e "${WARNING} Could not determine disk space"
        echo "  Docker root: $DOCKER_ROOT"
        echo "  (Build may fail if insufficient space)"
        echo ""
    fi
else
    echo -e "${CHECK_MARK} Sufficient disk space"
    echo "  Available: ${AVAILABLE_SPACE}GB at $DOCKER_ROOT"
    echo ""
fi

# ==========================================
# 3. Network Connectivity - Alpine Base
# ==========================================
echo -e "${BLUE}=== 3. ALPINE BASE IMAGE ACCESS ===${NC}"
echo ""

# Check if custom IMAGE_ALPINE is set
if [ -n "$IMAGE_ALPINE" ]; then
    echo "Using custom Alpine image: $IMAGE_ALPINE"
    echo ""

    # Parse registry from image
    REGISTRY_HOST=$(echo "$IMAGE_ALPINE" | cut -d'/' -f1)

    # Try to pull (or verify access to) the custom image
    echo -n "Testing access to custom Alpine image... "
    if docker pull "$IMAGE_ALPINE" >/dev/null 2>&1; then
        echo -e "${CHECK_MARK}"
        echo "  Successfully verified $IMAGE_ALPINE"
        echo ""
    else
        echo -e "${CROSS_MARK}"
        echo ""
        echo "Failed to pull custom Alpine image: $IMAGE_ALPINE"
        echo ""

        # Check if this looks like Artifactory
        if [[ "$IMAGE_ALPINE" == *"artifactory"* ]]; then
            echo "This appears to be a corporate Artifactory registry."
            echo ""
            echo "Common issues:"
            echo "  1. Not logged in to registry"
            echo "     Fix: docker login $REGISTRY_HOST"
            echo ""
            echo "  2. Image path incorrect"
            echo "     Fix: Verify path with your DevOps team"
            echo "     Example: artifactory.company.com/docker-remote/library/alpine:3.19"
            echo ""
            echo "  3. Network/VPN not connected"
            echo "     Fix: Connect to corporate network/VPN"
            echo ""
        else
            echo "To fix:"
            echo "  1. Verify image exists: docker pull $IMAGE_ALPINE"
            echo "  2. Check .env configuration"
            echo "  3. Try without IMAGE_ALPINE (use public Alpine)"
            echo ""
        fi
        EXIT_CODE=1
    fi
else
    # Using default public Alpine
    echo "Using public Alpine image: alpine:3.19"
    echo ""

    echo -n "Testing access to docker.io... "
    # Try to reach docker.io
    if timeout 10 docker pull alpine:3.19 >/dev/null 2>&1; then
        echo -e "${CHECK_MARK}"
        echo "  Docker Hub is accessible"
        echo ""
    else
        echo -e "${CROSS_MARK}"
        echo ""
        echo "Cannot reach docker.io (Docker Hub)"
        echo ""

        # Try to determine if it's a proxy issue
        if env | grep -i proxy >/dev/null 2>&1; then
            echo -e "${WARNING} Proxy environment variables detected:"
            env | grep -i proxy | sed 's/^/  /'
            echo ""
            echo "Corporate proxy detected. Common issues:"
            echo ""
            echo "  1. Docker not configured to use proxy"
            echo "     Fix: Add to ~/.docker/config.json:"
            echo '     {
       "proxies": {
         "default": {
           "httpProxy": "http://proxy.company.com:8080",
           "httpsProxy": "http://proxy.company.com:8080",
           "noProxy": "localhost,127.0.0.1"
         }
       }
     }'
            echo ""
            echo "  2. Firewall blocking Docker Hub"
            echo "     Fix: Ask IT to whitelist docker.io"
            echo "     OR: Use corporate Artifactory (set IMAGE_ALPINE in .env)"
            echo ""
        else
            echo "Network connectivity issues. Possible causes:"
            echo ""
            echo "  1. No internet connection"
            echo "     Fix: Check your network connection"
            echo ""
            echo "  2. Firewall blocking Docker Hub"
            echo "     Fix: Check firewall settings or try corporate VPN"
            echo ""
            echo "  3. DNS issues"
            echo "     Fix: Test: ping docker.io"
            echo ""
        fi
        EXIT_CODE=1
    fi
fi

# ==========================================
# 4. Network Connectivity - Microsoft ODBC Drivers
# ==========================================
echo -e "${BLUE}=== 4. MICROSOFT ODBC DRIVER ACCESS ===${NC}"
echo ""

# Check if custom ODBC_DRIVER_URL is set
if [ -n "$ODBC_DRIVER_URL" ]; then
    echo "Using custom ODBC driver URL: $ODBC_DRIVER_URL"
    echo ""

    # Extract host from URL
    ODBC_HOST=$(echo "$ODBC_DRIVER_URL" | sed -E 's|^https?://([^/]+).*|\1|')

    echo -n "Testing access to ODBC driver source... "
    # Try to reach the custom URL
    if timeout 10 curl -f -s -I "${ODBC_DRIVER_URL}/msodbcsql18_18.3.2.1-1_amd64.apk" >/dev/null 2>&1; then
        echo -e "${CHECK_MARK}"
        echo "  ODBC drivers accessible at custom URL"
        echo ""
    else
        echo -e "${CROSS_MARK}"
        echo ""
        echo "Cannot reach custom ODBC driver URL"
        echo ""

        # Check if this looks like Artifactory
        if [[ "$ODBC_DRIVER_URL" == *"artifactory"* ]]; then
            echo "This appears to be a corporate Artifactory repository."
            echo ""
            echo "Common issues:"
            echo "  1. Repository not set up correctly"
            echo "     Fix: Verify with DevOps that ODBC drivers are mirrored"
            echo "     Expected files:"
            echo "       - msodbcsql18_18.3.2.1-1_amd64.apk"
            echo "       - mssql-tools18_18.3.1.1-1_amd64.apk"
            echo ""
            echo "  2. URL path incorrect"
            echo "     Fix: Check .env ODBC_DRIVER_URL setting"
            echo ""
            echo "  3. Requires authentication"
            echo "     Fix: Configure Docker proxy or credentials"
            echo ""
        else
            echo "To fix:"
            echo "  1. Verify URL is correct in .env"
            echo "  2. Test manually: curl -I $ODBC_DRIVER_URL/msodbcsql18_18.3.2.1-1_amd64.apk"
            echo "  3. Try without ODBC_DRIVER_URL (use Microsoft default)"
            echo ""
        fi
        EXIT_CODE=1
    fi
else
    # Using default Microsoft download
    echo "Using Microsoft download: https://download.microsoft.com"
    echo ""

    echo -n "Testing access to download.microsoft.com... "
    # Try to reach Microsoft
    if timeout 10 curl -f -s -I "https://download.microsoft.com/download/3/5/5/355d7943-a338-41a7-858d-53b259ea33f5/msodbcsql18_18.3.2.1-1_amd64.apk" >/dev/null 2>&1; then
        echo -e "${CHECK_MARK}"
        echo "  Microsoft download site is accessible"
        echo ""
    else
        echo -e "${CROSS_MARK}"
        echo ""
        echo "Cannot reach download.microsoft.com"
        echo ""

        # Check for proxy
        if env | grep -i proxy >/dev/null 2>&1; then
            echo -e "${WARNING} Corporate proxy detected"
            echo ""
            echo "Microsoft downloads may be blocked by corporate firewall."
            echo ""
            echo "Solutions:"
            echo "  1. Ask DevOps to mirror ODBC drivers in Artifactory"
            echo "     Required files:"
            echo "       - msodbcsql18_18.3.2.1-1_amd64.apk"
            echo "       - mssql-tools18_18.3.1.1-1_amd64.apk"
            echo ""
            echo "  2. Then set in platform-bootstrap/.env:"
            echo "     ODBC_DRIVER_URL=https://artifactory.company.com/path/to/odbc"
            echo ""
            echo "  3. Or temporarily disable proxy for build"
            echo "     unset http_proxy https_proxy"
            echo "     (Not recommended for corporate environments)"
            echo ""
        else
            echo "Network connectivity issues. Possible causes:"
            echo ""
            echo "  1. Firewall blocking Microsoft downloads"
            echo "     Fix: Check firewall or use VPN"
            echo ""
            echo "  2. No internet connection"
            echo "     Fix: Check network connection"
            echo ""
        fi
        EXIT_CODE=1
    fi
fi

# ==========================================
# 5. Corporate Proxy Guidance
# ==========================================
echo -e "${BLUE}=== 5. CORPORATE PROXY DETECTION ===${NC}"
echo ""

if env | grep -i proxy >/dev/null 2>&1; then
    echo -e "${WARNING} Proxy environment variables detected:"
    env | grep -i proxy | sed 's/^/  /'
    echo ""

    echo "Corporate proxy best practices:"
    echo ""
    echo "1. Configure Docker to use proxy:"
    echo "   Create/edit ~/.docker/config.json with:"
    echo '   {
     "proxies": {
       "default": {
         "httpProxy": "'$(env | grep -i http_proxy | cut -d'=' -f2 | head -1)'",
         "httpsProxy": "'$(env | grep -i https_proxy | cut -d'=' -f2 | head -1)'",
         "noProxy": "localhost,127.0.0.1"
       }
     }
   }'
    echo ""
    echo "2. Use corporate Artifactory for images:"
    echo "   Set in platform-bootstrap/.env:"
    echo "   IMAGE_ALPINE=artifactory.company.com/docker-remote/library/alpine:3.19"
    echo "   ODBC_DRIVER_URL=https://artifactory.company.com/path/to/odbc"
    echo ""
    echo "3. Contact DevOps for correct repository paths"
    echo ""
else
    echo -e "${CHECK_MARK} No corporate proxy detected"
    echo "  Direct internet access available"
    echo ""
fi

# ==========================================
# 6. Build Arguments Preview
# ==========================================
echo -e "${BLUE}=== 6. BUILD CONFIGURATION PREVIEW ===${NC}"
echo ""

echo "The following configuration will be used for build:"
echo ""
if [ -n "$IMAGE_ALPINE" ]; then
    echo "  Base image: ${GREEN}$IMAGE_ALPINE${NC} (custom)"
else
    echo "  Base image: alpine:3.19 (public default)"
fi
echo ""

if [ -n "$ODBC_DRIVER_URL" ]; then
    echo "  ODBC source: ${GREEN}$ODBC_DRIVER_URL${NC} (custom)"
else
    echo "  ODBC source: https://download.microsoft.com (public default)"
fi
echo ""

# ==========================================
# Summary
# ==========================================
echo -e "${BLUE}=== SUMMARY ===${NC}"
echo ""

if [ $EXIT_CODE -eq 0 ]; then
    echo -e "${CHECK_MARK} ${GREEN}All build requirements satisfied${NC}"
    echo ""
    echo "Ready to build! Run:"
    echo "  make build"
    echo ""
else
    echo -e "${CROSS_MARK} ${RED}Build requirements not satisfied${NC}"
    echo ""
    echo "Please fix the issues above before building."
    echo ""
    echo "For help:"
    echo "  - Review error messages and suggested fixes"
    echo "  - Check docs/kerberos-diagnostic-guide.md"
    echo "  - Contact your DevOps team for Artifactory setup"
    echo ""
fi

exit $EXIT_CODE
