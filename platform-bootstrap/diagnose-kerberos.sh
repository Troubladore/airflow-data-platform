#!/bin/bash
# Comprehensive Kerberos diagnostic tool for WSL2/Docker integration
# Helps identify and fix common Kerberos ticket sharing issues

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "🔍 Kerberos Diagnostic Tool for Docker Integration"
echo "=================================================="
echo ""

# Function to check a condition and report
check_condition() {
    local description="$1"
    local command="$2"
    local expected="$3"

    echo -n "Checking: $description... "
    if eval "$command" >/dev/null 2>&1; then
        echo -e "${GREEN}✓${NC}"
        return 0
    else
        echo -e "${RED}✗${NC}"
        return 1
    fi
}

# 1. Check host Kerberos tickets
echo -e "\n${BLUE}=== 1. HOST KERBEROS TICKETS ===${NC}"

if command -v klist >/dev/null 2>&1; then
    echo -e "${GREEN}✓ klist command found${NC}"

    # Run klist and capture output
    if klist 2>/dev/null | grep -q "Default principal"; then
        echo -e "${GREEN}✓ Kerberos tickets found!${NC}"
        echo ""
        echo "Ticket details:"
        klist | head -5

        # Extract ticket cache location
        TICKET_CACHE=$(klist 2>/dev/null | grep "Ticket cache:" | sed 's/Ticket cache: //')
        echo ""
        echo -e "${YELLOW}📍 Ticket cache location: $TICKET_CACHE${NC}"

        # Parse different ticket cache formats
        if [[ "$TICKET_CACHE" == FILE:* ]]; then
            CACHE_FILE=${TICKET_CACHE#FILE:}
            echo "  Type: FILE"
            echo "  Path: $CACHE_FILE"
            if [ -f "$CACHE_FILE" ]; then
                echo -e "  ${GREEN}✓ File exists${NC}"
                ls -la "$CACHE_FILE"
            else
                echo -e "  ${RED}✗ File does not exist${NC}"
            fi
        elif [[ "$TICKET_CACHE" == DIR::* ]]; then
            CACHE_DIR=${TICKET_CACHE#DIR::}
            echo "  Type: DIR (collection)"
            echo "  Path: $CACHE_DIR"
            if [ -d "$CACHE_DIR" ]; then
                echo -e "  ${GREEN}✓ Directory exists${NC}"
                echo "  Contents:"
                ls -la "$CACHE_DIR" 2>/dev/null | head -5
            else
                echo -e "  ${RED}✗ Directory does not exist${NC}"
            fi
        elif [[ "$TICKET_CACHE" == KCM:* ]]; then
            echo "  Type: KCM (Kernel Credential Cache)"
            echo -e "  ${YELLOW}⚠️  KCM tickets need special handling for Docker${NC}"
        else
            # Assume it's a simple file path
            echo "  Type: FILE (assumed)"
            if [ -f "$TICKET_CACHE" ]; then
                echo -e "  ${GREEN}✓ File exists at: $TICKET_CACHE${NC}"
            else
                echo -e "  ${RED}✗ File not found at: $TICKET_CACHE${NC}"
            fi
        fi
    else
        echo -e "${RED}✗ No Kerberos tickets found${NC}"
        echo "  Run: kinit YOUR_USERNAME@DOMAIN.COM"
    fi
else
    echo -e "${RED}✗ klist command not found${NC}"
    echo "  Install with: sudo apt-get install krb5-user"
fi

# 2. Check expected ticket locations
echo -e "\n${BLUE}=== 2. COMMON TICKET LOCATIONS ===${NC}"

TICKET_LOCATIONS=(
    "/tmp/krb5cc_$(id -u)"
    "$HOME/.krb5_cache/krb5cc"
    "$HOME/.krb5-cache/dev/tkt"
    "/tmp/krb5cc_*"
)

FOUND_TICKETS=""
for location in "${TICKET_LOCATIONS[@]}"; do
    # Use ls to handle wildcards
    for file in $location; do
        if [ -e "$file" ]; then
            echo -e "${GREEN}✓ Found ticket at: $file${NC}"
            if [ -f "$file" ]; then
                echo "    Size: $(stat -c%s "$file") bytes"
                echo "    Modified: $(stat -c%y "$file" | cut -d' ' -f1,2)"
            elif [ -d "$file" ]; then
                echo "    Type: Directory (ticket collection)"
                echo "    Contents: $(ls -1 "$file" 2>/dev/null | wc -l) files"
            fi
            FOUND_TICKETS="$FOUND_TICKETS $file"
        fi
    done
done

if [ -z "$FOUND_TICKETS" ]; then
    echo -e "${RED}✗ No tickets found in common locations${NC}"
fi

# 3. Check Docker setup
echo -e "\n${BLUE}=== 3. DOCKER ENVIRONMENT ===${NC}"

if docker info >/dev/null 2>&1; then
    echo -e "${GREEN}✓ Docker is running${NC}"

    # Check for platform network
    if docker network ls | grep -q "platform_network"; then
        echo -e "${GREEN}✓ platform_network exists${NC}"
    else
        echo -e "${RED}✗ platform_network does not exist${NC}"
        echo "  Run: docker network create platform_network"
    fi

    # Check for Kerberos cache volume
    if docker volume ls | grep -q "platform_kerberos_cache"; then
        echo -e "${GREEN}✓ platform_kerberos_cache volume exists${NC}"

        # Check volume contents
        echo "  Checking volume contents..."
        docker run --rm -v platform_kerberos_cache:/check:ro alpine ls -la /check/ 2>/dev/null || echo "    (empty)"
    else
        echo -e "${RED}✗ platform_kerberos_cache volume does not exist${NC}"
        echo "  Run: docker volume create platform_kerberos_cache"
    fi

    # Check if kerberos service is running
    if docker ps --format "table {{.Names}}" | grep -q "kerberos-platform-service"; then
        echo -e "${GREEN}✓ kerberos-platform-service is running${NC}"

        # Check service logs
        echo "  Recent logs:"
        docker logs kerberos-platform-service --tail 3 2>&1 | sed 's/^/    /'
    else
        echo -e "${YELLOW}⚠️  kerberos-platform-service is not running${NC}"
        echo "  Run: make platform-start"
    fi
else
    echo -e "${RED}✗ Docker is not running or not accessible${NC}"
fi

# 4. Test ticket sharing
echo -e "\n${BLUE}=== 4. TICKET SHARING TEST ===${NC}"

if docker info >/dev/null 2>&1; then
    echo "Testing ticket visibility in container..."

    docker run --rm \
        --network platform_network \
        -v platform_kerberos_cache:/krb5/cache:ro \
        alpine sh -c '
            echo "  Checking /krb5/cache directory:"
            if [ -d /krb5/cache ]; then
                echo "    ✓ Directory exists"
                echo "    Contents:"
                ls -la /krb5/cache/ | sed "s/^/      /"
                if [ -f /krb5/cache/krb5cc ]; then
                    echo "    ✓ krb5cc file found"
                    echo "      Size: $(stat -c%s /krb5/cache/krb5cc) bytes"
                else
                    echo "    ✗ krb5cc file not found"
                fi
            else
                echo "    ✗ Directory does not exist"
            fi
        '
else
    echo -e "${RED}Cannot test - Docker not available${NC}"
fi

# 5. Recommendations
echo -e "\n${BLUE}=== 5. RECOMMENDATIONS ===${NC}"

if [ -n "$TICKET_CACHE" ]; then
    if [[ "$TICKET_CACHE" == DIR::* ]]; then
        CACHE_DIR=${TICKET_CACHE#DIR::}
        echo -e "${YELLOW}📌 Your tickets are in a directory collection at: $CACHE_DIR${NC}"
        echo ""
        echo "To fix ticket sharing, you need to:"
        echo "1. Update developer-kerberos-simple.yml to mount the correct location:"
        echo "   Change: - \${HOME}/.krb5_cache:/host:ro"
        echo "   To:     - $CACHE_DIR:/host:ro"
        echo ""
        echo "2. Update the copy command to handle directory tickets:"
        echo "   The service needs to copy from $CACHE_DIR/* instead of a single file"
        echo ""
        echo "Or convert to a file-based cache:"
        echo "   export KRB5CCNAME=FILE:/tmp/krb5cc_\$(id -u)"
        echo "   kinit YOUR_USERNAME@DOMAIN.COM"
    elif [[ "$TICKET_CACHE" != FILE:/tmp/krb5cc_* ]]; then
        echo -e "${YELLOW}📌 Your ticket cache is at a non-standard location${NC}"
        echo "Consider using the standard location:"
        echo "   export KRB5CCNAME=/tmp/krb5cc_\$(id -u)"
        echo "   kinit YOUR_USERNAME@DOMAIN.COM"
    fi
fi

# 6. Quick fixes
echo -e "\n${BLUE}=== 6. QUICK FIXES ===${NC}"

echo "Try these commands in order:"
echo ""
echo "1. Ensure Docker setup is correct:"
echo "   docker network create platform_network"
echo "   docker volume create platform_kerberos_cache"
echo ""
echo "2. Get a fresh Kerberos ticket:"
echo "   export KRB5CCNAME=/tmp/krb5cc_\$(id -u)"
echo "   kinit YOUR_USERNAME@DOMAIN.COM"
echo ""
echo "3. Copy ticket to expected location:"
echo "   mkdir -p ~/.krb5_cache"
echo "   cp \$KRB5CCNAME ~/.krb5_cache/krb5cc"
echo ""
echo "4. Start platform services:"
echo "   make platform-start"
echo ""
echo "5. Test again:"
echo "   make test-kerberos-simple"

echo -e "\n${GREEN}Diagnostic complete!${NC}"
