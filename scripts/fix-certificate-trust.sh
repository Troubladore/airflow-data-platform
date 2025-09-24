#!/bin/bash
# Fix certificate trust issues - THE FINAL SOLUTION
# Based on definitive diagnosis from diagnose-certificate-state.sh

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}🔧 CERTIFICATE TRUST FIX${NC}"
echo "=========================="
echo
echo "This script fixes the certificate trust chain based on diagnosis."
echo

# Step 1: Run diagnosis first
echo -e "${BLUE}Step 1: Running diagnosis...${NC}"
if [ -f "./scripts/diagnose-certificate-state.sh" ]; then
    # Run diagnosis and capture key findings
    DIAGNOSIS=$(./scripts/diagnose-certificate-state.sh 2>&1)

    # Extract key information
    WINDOWS_MKCERT=$(echo "$DIAGNOSIS" | grep "Windows mkcert" | grep "YES" || echo "")
    WINDOWS_CA_TRUSTED=$(echo "$DIAGNOSIS" | grep "CA trusted in Windows store" | grep "YES" || echo "")
    TRAEFIK_CERT_MOUNT=$(echo "$DIAGNOSIS" | grep "Traefik Cert Mount" | grep "YES" || echo "")

    echo "Diagnosis complete."
else
    echo -e "${RED}diagnosis script not found!${NC}"
    exit 1
fi

# Step 2: Fix Windows CA trust
echo
echo -e "${BLUE}Step 2: Windows CA Trust${NC}"
echo "-------------------------"

if [ -n "$WINDOWS_MKCERT" ] && [ -z "$WINDOWS_CA_TRUSTED" ]; then
    echo -e "${YELLOW}⚠️  Windows has mkcert but CA is NOT trusted${NC}"
    echo
    echo "ACTION REQUIRED (run in Windows PowerShell):"
    echo "============================================="
    echo
    echo -e "${GREEN}# Run this command in Windows PowerShell:${NC}"
    echo "mkcert -install"
    echo
    echo "This will:"
    echo "1. Install the mkcert CA into Windows certificate store"
    echo "2. Make browsers trust certificates signed by this CA"
    echo "3. Eliminate 'Your connection is not private' warnings"
    echo
    echo -e "${YELLOW}After running 'mkcert -install' in Windows:${NC}"
    echo "1. Restart all browsers (Chrome, Edge, Firefox)"
    echo "2. Clear browser cache (Ctrl+Shift+Delete)"
    echo "3. Navigate to https://airflow.localhost"
    echo
    WINDOWS_FIX_NEEDED=true
else
    echo -e "${GREEN}✅ Windows CA trust is configured${NC}"
    WINDOWS_FIX_NEEDED=false
fi

# Step 3: Fix Traefik certificate mounting
echo
echo -e "${BLUE}Step 3: Traefik Certificate Mount${NC}"
echo "---------------------------------"

# Check if Traefik is mounting certificates correctly
TRAEFIK_CONTAINER=$(docker ps --format "{{.Names}}" | grep -E "traefik-traefik|traefik_traefik" | head -1)

if [ -n "$TRAEFIK_CONTAINER" ]; then
    CERT_MOUNT=$(docker inspect "$TRAEFIK_CONTAINER" 2>/dev/null | grep -A5 '"/certs"' | grep '"Source"' | cut -d'"' -f4 || echo "")

    if [ -z "$CERT_MOUNT" ]; then
        echo -e "${YELLOW}⚠️  Traefik is not mounting certificates${NC}"
        echo
        echo "Restarting Traefik with correct configuration..."

        # Find the correct docker-compose file
        if [ -f "$HOME/platform-services/traefik/docker-compose.yml" ]; then
            cd "$HOME/platform-services/traefik"
            docker compose down
            docker compose up -d
            echo -e "${GREEN}✅ Traefik restarted with certificate mounts${NC}"
        else
            echo -e "${RED}❌ Platform services not found at ~/platform-services/traefik${NC}"
            echo "Run platform setup: ansible-playbook -i ansible/inventory/local-dev.ini ansible/setup-wsl2.yml"
        fi
    else
        echo -e "${GREEN}✅ Traefik is mounting certificates from: $CERT_MOUNT${NC}"
    fi
else
    echo -e "${RED}❌ Traefik container not running${NC}"
fi

# Step 4: Sync WSL2 trust store with Windows CA
echo
echo -e "${BLUE}Step 4: WSL2 Trust Store Sync${NC}"
echo "------------------------------"

# Get Windows username
WINDOWS_USERNAME=$(ls -ld /mnt/c/Users/*/ 2>/dev/null | grep -v -E "Public|Default|All Users" | head -1 | awk -F'/' '{print $5}' || echo "")

if [ -n "$WINDOWS_USERNAME" ]; then
    WINDOWS_CA="/mnt/c/Users/$WINDOWS_USERNAME/AppData/Local/mkcert/rootCA.pem"

    if [ -f "$WINDOWS_CA" ]; then
        echo "Windows CA found at: $WINDOWS_CA"

        # Check if this CA is in WSL2 trust store
        WINDOWS_CA_FINGERPRINT=$(openssl x509 -in "$WINDOWS_CA" -noout -fingerprint -sha256 2>/dev/null | cut -d= -f2)

        # Check if it's already in trust store
        CA_IN_STORE=false
        for ca_file in /usr/local/share/ca-certificates/mkcert*.crt; do
            if [ -f "$ca_file" ]; then
                STORE_FINGERPRINT=$(openssl x509 -in "$ca_file" -noout -fingerprint -sha256 2>/dev/null | cut -d= -f2)
                if [ "$WINDOWS_CA_FINGERPRINT" = "$STORE_FINGERPRINT" ]; then
                    CA_IN_STORE=true
                    break
                fi
            fi
        done

        if [ "$CA_IN_STORE" = false ]; then
            echo -e "${YELLOW}Installing Windows CA in WSL2 trust store...${NC}"

            # Copy CA to trust store
            sudo cp "$WINDOWS_CA" "/usr/local/share/ca-certificates/mkcert_windows_ca.crt"

            # Update trust store
            sudo update-ca-certificates

            echo -e "${GREEN}✅ Windows CA installed in WSL2 trust store${NC}"
        else
            echo -e "${GREEN}✅ Windows CA already in WSL2 trust store${NC}"
        fi
    else
        echo -e "${YELLOW}⚠️  Windows CA not found at expected location${NC}"
    fi
else
    echo -e "${RED}❌ Could not determine Windows username${NC}"
fi

# Step 5: Final validation
echo
echo -e "${BLUE}Step 5: Validation${NC}"
echo "------------------"

# Test HTTPS trust
echo -n "Testing HTTPS trust (curl)... "
if timeout 5 curl -s https://traefik.localhost >/dev/null 2>&1; then
    echo -e "${GREEN}✅ TRUSTED${NC}"
    WSL_TRUST_OK=true
else
    echo -e "${RED}❌ NOT TRUSTED${NC}"
    WSL_TRUST_OK=false
fi

# Summary
echo
echo -e "${BLUE}📊 SUMMARY${NC}"
echo "=========="
echo

if [ "$WINDOWS_FIX_NEEDED" = true ]; then
    echo -e "${RED}❌ CRITICAL: Windows CA trust needs to be fixed${NC}"
    echo
    echo "1. Open Windows PowerShell"
    echo "2. Run: mkcert -install"
    echo "3. Restart browsers"
    echo "4. Test: https://airflow.localhost"
    echo
    echo "This is THE fix for browser certificate warnings!"
else
    if [ "$WSL_TRUST_OK" = true ]; then
        echo -e "${GREEN}🎉 Certificate trust is fully configured!${NC}"
        echo
        echo "You should be able to access:"
        echo "• https://airflow.localhost"
        echo "• https://traefik.localhost"
        echo "• https://registry.localhost"
        echo
        echo "Without any browser warnings!"
    else
        echo -e "${YELLOW}⚠️  Some issues remain - check the steps above${NC}"
    fi
fi

echo
echo "After fixing, run './scripts/test-certificate-trust.sh' to verify."
