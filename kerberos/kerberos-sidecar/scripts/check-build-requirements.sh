#!/bin/bash
# Build Requirements Check for Kerberos Sidecar
# ==============================================
# Validates environment before attempting sidecar image build
# Detects common issues and provides actionable fixes

set -e

# Source the shared formatting library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLATFORM_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"
if [ -f "$PLATFORM_DIR/lib/formatting.sh" ]; then
    source "$PLATFORM_DIR/lib/formatting.sh"
else
    # Fallback if library not found
    echo "Warning: formatting library not found, using basic output" >&2
    print_msg() { echo "$@"; }
    print_section() { echo "=== $1 ==="; }
    print_check() { echo "[$1] $2"; }
    print_error() { echo "Error: $@"; }
    print_warning() { echo "Warning: $@"; }
    print_success() { echo "$@"; }
    CHECK_MARK="[OK]"
    CROSS_MARK="[FAIL]"
    WARNING_SIGN="[WARN]"
    GREEN=''
    YELLOW=''
    RED=''
    BLUE=''
    NC=''
fi

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
        print_msg "${CHECK_MARK} $success_msg"
        return 0
    else
        print_msg "${CROSS_MARK} $failure_msg"
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
print_section "1. DOCKER ACCESSIBILITY"
echo ""

if ! command -v docker >/dev/null 2>&1; then
    print_check "FAIL" "Docker command not found"
    echo ""
    echo "Docker is required to build the sidecar image."
    echo ""
    echo "To install Docker:"
    echo "  Ubuntu/Debian: curl -fsSL https://get.docker.com | sh"
    echo "  See: https://docs.docker.com/engine/install/"
    echo ""
    EXIT_CODE=1
elif ! docker info >/dev/null 2>&1; then
    print_check "FAIL" "Docker daemon not running or not accessible"
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
    DOCKER_VERSION=$(docker version --format '{{.Server.Version}}' 2>/dev/null)
    print_check "PASS" "Docker is running and accessible" "Version: $DOCKER_VERSION"
    echo ""
fi

# ==========================================
# 2. Disk Space
# ==========================================
print_section "2. DISK SPACE"
echo ""

# Check available space in /var/lib/docker (where Docker stores images)
DOCKER_ROOT=$(docker info --format '{{.DockerRootDir}}' 2>/dev/null || echo "/var/lib/docker")
AVAILABLE_SPACE=$(df -BG "$DOCKER_ROOT" 2>/dev/null | awk 'NR==2 {print $4}' | sed 's/G//' || echo "0")

# Handle case where AVAILABLE_SPACE is empty or not a number
if [ -z "$AVAILABLE_SPACE" ] || ! [[ "$AVAILABLE_SPACE" =~ ^[0-9]+$ ]]; then
    AVAILABLE_SPACE=0
fi

if [ "$AVAILABLE_SPACE" -lt 2 ] && [ "$AVAILABLE_SPACE" -ne 0 ]; then
    print_check "FAIL" "Insufficient disk space"
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
    print_check "WARN" "Limited disk space" "Available: ${AVAILABLE_SPACE}GB at $DOCKER_ROOT. Recommended: 5GB or more"
    echo ""
elif [ "$AVAILABLE_SPACE" -eq 0 ]; then
    # Check if we're in WSL2
    if [ -f /proc/sys/fs/binfmt_misc/WSLInterop ]; then
        print_check "PASS" "WSL2 detected - disk space check skipped" "WSL2 uses dynamically allocated disk space"
        echo ""
    else
        print_check "WARN" "Could not determine disk space" "Docker root: $DOCKER_ROOT. Build may fail if insufficient space"
        echo ""
    fi
else
    print_check "PASS" "Sufficient disk space" "Available: ${AVAILABLE_SPACE}GB at $DOCKER_ROOT"
    echo ""
fi

# ==========================================
# 3. Network Connectivity - Alpine Base
# ==========================================
print_section "3. ALPINE BASE IMAGE ACCESS"
echo ""

# Check if custom IMAGE_ALPINE is set
if [ -n "$IMAGE_ALPINE" ]; then
    echo "Using custom Alpine image: $IMAGE_ALPINE"
    echo ""

    # Parse registry from image
    REGISTRY_HOST=$(echo "$IMAGE_ALPINE" | cut -d'/' -f1)

    # Try to pull (or verify access to) the custom image
    if docker pull "$IMAGE_ALPINE" >/dev/null 2>&1; then
        print_check "PASS" "Custom Alpine image verified" "$IMAGE_ALPINE"
        echo ""
    else
        print_check "FAIL" "Failed to pull custom Alpine image"
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

    # Try to reach docker.io
    if timeout 10 docker pull alpine:3.19 >/dev/null 2>&1; then
        print_check "PASS" "Docker Hub is accessible"
        echo ""
    else
        print_check "FAIL" "Cannot reach docker.io (Docker Hub)"
        echo ""

        # Try to determine if it's a proxy issue
        if env | grep -i proxy >/dev/null 2>&1; then
            print_check "WARN" "Proxy environment variables detected"
            env | grep -i proxy | sed 's/^/    /'
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
print_section "4. MICROSOFT ODBC DRIVER ACCESS"
echo ""

# Check if custom ODBC_DRIVER_URL is set
if [ -n "$ODBC_DRIVER_URL" ]; then
    echo "Using custom ODBC driver URL: $ODBC_DRIVER_URL"
    echo ""

    # Extract host from URL
    ODBC_HOST=$(echo "$ODBC_DRIVER_URL" | sed -E 's|^https?://([^/]+).*|\1|')

    # Try to reach the custom URL
    if timeout 10 curl -f -s -I "${ODBC_DRIVER_URL}/msodbcsql18_18.3.2.1-1_amd64.apk" >/dev/null 2>&1; then
        print_check "PASS" "ODBC drivers accessible at custom URL"
        echo ""
    else
        print_check "FAIL" "Cannot reach custom ODBC driver URL"
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

    # Try to reach Microsoft
    if timeout 10 curl -f -s -I "https://download.microsoft.com/download/3/5/5/355d7943-a338-41a7-858d-53b259ea33f5/msodbcsql18_18.3.2.1-1_amd64.apk" >/dev/null 2>&1; then
        print_check "PASS" "Microsoft download site is accessible"
        echo ""
    else
        print_check "FAIL" "Cannot reach download.microsoft.com"
        echo ""

        # Check for proxy
        if env | grep -i proxy >/dev/null 2>&1; then
            print_check "WARN" "Corporate proxy detected"
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
print_section "5. CORPORATE PROXY DETECTION"
echo ""

if env | grep -i proxy >/dev/null 2>&1; then
    print_check "WARN" "Proxy environment variables detected"
    env | grep -i proxy | sed 's/^/    /'
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
    print_check "PASS" "No corporate proxy detected" "Direct internet access available"
    echo ""
fi

# ==========================================
# 6. Build Arguments Preview
# ==========================================
print_section "6. BUILD CONFIGURATION PREVIEW"
echo ""

echo "The following configuration will be used for build:"
echo ""
if [ -n "$IMAGE_ALPINE" ]; then
    print_check "INFO" "Base image: $IMAGE_ALPINE (custom)"
else
    echo "  Base image: alpine:3.19 (public default)"
fi

if [ -n "$ODBC_DRIVER_URL" ]; then
    print_check "INFO" "ODBC source: $ODBC_DRIVER_URL (custom)"
else
    echo "  ODBC source: https://download.microsoft.com (public default)"
fi
echo ""

# ==========================================
# Summary
# ==========================================
print_section "SUMMARY"
echo ""

if [ $EXIT_CODE -eq 0 ]; then
    print_success "All build requirements satisfied"
    echo ""
    echo "Ready to build! Run:"
    echo "  make build"
    echo ""
else
    print_error "Build requirements not satisfied"
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
