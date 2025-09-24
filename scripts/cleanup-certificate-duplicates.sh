#!/bin/bash
# Clean up duplicate/conflicting mkcert CAs from both Windows and WSL2
# This prevents certificate trust confusion

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}🧹 MKCERT CA CLEANUP TOOL${NC}"
echo "=========================="
echo
echo "This script detects and helps clean up duplicate mkcert CAs"
echo "that can cause certificate trust issues."
echo

# ============================================================================
# SECTION 1: Detect duplicate CAs in Windows
# ============================================================================
echo -e "${BLUE}Step 1: Analyzing Windows Certificate Store${NC}"
echo "-------------------------------------------"

if command -v powershell.exe >/dev/null 2>&1; then
    echo "Checking Windows trust store for mkcert CAs..."

    # Get all mkcert CAs with details
    WINDOWS_CAS=$(powershell.exe -Command "
        \$certs = Get-ChildItem -Path 'Cert:\CurrentUser\Root' | Where-Object {\$_.Subject -like '*mkcert*'}
        \$certs | ForEach-Object {
            Write-Output (\$_.Thumbprint + '|' + \$_.Subject + '|' + \$_.NotBefore.ToString('yyyy-MM-dd') + '|' + \$_.NotAfter.ToString('yyyy-MM-dd'))
        }
    " 2>/dev/null | tr -d '\r')

    if [ -n "$WINDOWS_CAS" ]; then
        CA_COUNT=$(echo "$WINDOWS_CAS" | grep -c "|" || echo 0)

        if [ "$CA_COUNT" -gt 1 ]; then
            echo -e "${YELLOW}⚠️  Found $CA_COUNT mkcert CAs in Windows store:${NC}"
            echo

            # Display all CAs with details
            echo "Thumbprint                                       | Created    | Expires    | Subject"
            echo "------------------------------------------------|------------|------------|---------------------------"

            NEWEST_DATE=""
            NEWEST_THUMBPRINT=""

            echo "$WINDOWS_CAS" | while IFS='|' read -r thumbprint subject created expires; do
                if [ -n "$thumbprint" ]; then
                    printf "%-48s | %-10s | %-10s | %s\n" "$thumbprint" "$created" "$expires" "$(echo $subject | cut -c1-50)"

                    # Track the newest CA (by creation date)
                    if [ -z "$NEWEST_DATE" ] || [[ "$created" > "$NEWEST_DATE" ]]; then
                        NEWEST_DATE="$created"
                        NEWEST_THUMBPRINT="$thumbprint"
                    fi
                fi
            done

            echo
            echo -e "${YELLOW}📋 RECOMMENDED ACTION:${NC}"
            echo "Keep only the newest CA and remove the others to avoid conflicts."
            echo
            echo "The newest CA appears to be:"
            echo "  Thumbprint: $NEWEST_THUMBPRINT"
            echo "  Created: $NEWEST_DATE"

            # Save for later use
            echo "$NEWEST_THUMBPRINT" > /tmp/newest_ca_thumbprint.txt

            WINDOWS_CLEANUP_NEEDED=true
        else
            echo -e "${GREEN}✅ Only one mkcert CA found in Windows store${NC}"
            WINDOWS_CLEANUP_NEEDED=false
        fi
    else
        echo "No mkcert CAs found in Windows store"
        WINDOWS_CLEANUP_NEEDED=false
    fi
else
    echo -e "${RED}PowerShell not accessible - cannot check Windows store${NC}"
    WINDOWS_CLEANUP_NEEDED=false
fi

# ============================================================================
# SECTION 2: Detect duplicate CAs in WSL2
# ============================================================================
echo
echo -e "${BLUE}Step 2: Analyzing WSL2 Trust Store${NC}"
echo "----------------------------------"

WSL_CA_COUNT=0
WSL_CAS=""

for ca_file in /usr/local/share/ca-certificates/mkcert*.crt; do
    if [ -f "$ca_file" ]; then
        WSL_CA_COUNT=$((WSL_CA_COUNT + 1))
        CA_FINGERPRINT=$(openssl x509 -in "$ca_file" -noout -fingerprint -sha256 2>/dev/null | cut -d= -f2)
        CA_SUBJECT=$(openssl x509 -in "$ca_file" -noout -subject 2>/dev/null | cut -d= -f2-)
        CA_DATE=$(openssl x509 -in "$ca_file" -noout -startdate 2>/dev/null | cut -d= -f2)

        WSL_CAS="${WSL_CAS}$(basename "$ca_file")|$CA_FINGERPRINT|$CA_DATE|$CA_SUBJECT\n"
    fi
done

if [ "$WSL_CA_COUNT" -gt 1 ]; then
    echo -e "${YELLOW}⚠️  Found $WSL_CA_COUNT mkcert CAs in WSL2 trust store:${NC}"
    echo
    echo -e "$WSL_CAS" | column -t -s '|'
    echo
    WSL_CLEANUP_NEEDED=true
elif [ "$WSL_CA_COUNT" -eq 1 ]; then
    echo -e "${GREEN}✅ Only one mkcert CA found in WSL2 trust store${NC}"
    WSL_CLEANUP_NEEDED=false
else
    echo "No mkcert CAs found in WSL2 trust store"
    WSL_CLEANUP_NEEDED=false
fi

# ============================================================================
# SECTION 3: Check certificate-CA match
# ============================================================================
echo
echo -e "${BLUE}Step 3: Verify Certificate-CA Match${NC}"
echo "-----------------------------------"

# Check if current certificates match any of the CAs
CERT_FILE="$HOME/.local/share/certs/dev-localhost-wild.crt"
if [ -f "$CERT_FILE" ]; then
    echo "Checking which CA signed the current certificates..."

    CERT_ISSUER=$(openssl x509 -in "$CERT_FILE" -noout -issuer 2>/dev/null)
    echo "Certificate issuer: $(echo $CERT_ISSUER | cut -c1-80)..."

    # Try to verify against each CA
    VALID_CA_FOUND=false

    # Check Windows CA
    WINDOWS_USERNAME=$(ls -ld /mnt/c/Users/*/ 2>/dev/null | grep -v -E "Public|Default|All Users" | head -1 | awk -F'/' '{print $5}' || echo "")
    if [ -n "$WINDOWS_USERNAME" ]; then
        WINDOWS_CA="/mnt/c/Users/$WINDOWS_USERNAME/AppData/Local/mkcert/rootCA.pem"
        if [ -f "$WINDOWS_CA" ]; then
            if openssl verify -CAfile "$WINDOWS_CA" "$CERT_FILE" >/dev/null 2>&1; then
                echo -e "${GREEN}✅ Certificates match Windows CA${NC}"
                VALID_CA_FOUND=true
            fi
        fi
    fi

    # Check WSL2 CAs
    for ca_file in /usr/local/share/ca-certificates/mkcert*.crt; do
        if [ -f "$ca_file" ]; then
            if openssl verify -CAfile "$ca_file" "$CERT_FILE" >/dev/null 2>&1; then
                echo -e "${GREEN}✅ Certificates match $(basename $ca_file)${NC}"
                VALID_CA_FOUND=true
            fi
        fi
    done

    if [ "$VALID_CA_FOUND" = false ]; then
        echo -e "${RED}❌ Certificates don't match any current CA${NC}"
        echo "You'll need to regenerate certificates after cleanup"
    fi
fi

# ============================================================================
# SECTION 4: Cleanup Options
# ============================================================================
echo
echo -e "${BLUE}Step 4: Cleanup Actions${NC}"
echo "-----------------------"

if [ "$WINDOWS_CLEANUP_NEEDED" = true ] || [ "$WSL_CLEANUP_NEEDED" = true ]; then
    echo -e "${YELLOW}⚠️  Cleanup recommended to avoid certificate trust issues${NC}"
    echo

    if [ "$WINDOWS_CLEANUP_NEEDED" = true ]; then
        echo -e "${BLUE}Windows Cleanup Commands:${NC}"
        echo "Run these in Windows PowerShell:"
        echo

        if [ -f /tmp/newest_ca_thumbprint.txt ]; then
            KEEP_THUMBPRINT=$(cat /tmp/newest_ca_thumbprint.txt)
            echo "# Option 1: Keep only the newest CA"
            echo "Get-ChildItem -Path 'Cert:\\CurrentUser\\Root' | Where-Object {\$_.Subject -like '*mkcert*' -and \$_.Thumbprint -ne '$KEEP_THUMBPRINT'} | Remove-Item"
        fi

        echo
        echo "# Option 2: Complete reset (remove ALL, then reinstall)"
        echo "mkcert -uninstall"
        echo "mkcert -install"
        echo
    fi

    if [ "$WSL_CLEANUP_NEEDED" = true ]; then
        echo -e "${BLUE}WSL2 Cleanup Commands:${NC}"
        echo "Run these in WSL2:"
        echo
        echo "# Remove all mkcert CAs from trust store"
        echo "sudo rm -f /usr/local/share/ca-certificates/mkcert*.crt"
        echo "sudo update-ca-certificates --fresh"
        echo
        echo "# Then reinstall the correct CA"
        echo "export CAROOT=\"/mnt/c/Users/\$WINDOWS_USERNAME/AppData/Local/mkcert\""
        echo "mkcert -install"
        echo "sudo update-ca-certificates"
        echo
    fi

    echo -e "${BLUE}After Cleanup:${NC}"
    echo "1. Regenerate certificates (if needed)"
    echo "2. Restart Traefik"
    echo "3. Test with: curl https://traefik.localhost"
    echo "4. Test in browser: https://airflow.localhost"
else
    echo -e "${GREEN}✅ No duplicate CAs detected${NC}"
    echo "Your CA configuration looks clean"
fi

# ============================================================================
# SECTION 5: Generate cleanup script
# ============================================================================
echo
echo -e "${BLUE}Step 5: Generate Cleanup Script${NC}"
echo "-------------------------------"

CLEANUP_SCRIPT="/tmp/ca-cleanup.sh"
cat > "$CLEANUP_SCRIPT" << 'EOF'
#!/bin/bash
# Auto-generated CA cleanup script

set -e

echo "🧹 Starting CA cleanup..."

# WSL2 cleanup
echo "Cleaning WSL2 trust store..."
sudo rm -f /usr/local/share/ca-certificates/mkcert*.crt
sudo update-ca-certificates --fresh

echo "✅ WSL2 trust store cleaned"

# Windows cleanup instructions
echo
echo "📋 Now run these commands in Windows PowerShell:"
echo "mkcert -uninstall"
echo "mkcert -install"
echo
echo "Then return here and press Enter to continue..."
read -p ""

# Reinstall in WSL2
WINDOWS_USERNAME=$(ls -ld /mnt/c/Users/*/ 2>/dev/null | grep -v -E "Public|Default|All Users" | head -1 | awk -F'/' '{print $5}' || echo "")
if [ -n "$WINDOWS_USERNAME" ]; then
    export CAROOT="/mnt/c/Users/$WINDOWS_USERNAME/AppData/Local/mkcert"
    echo "Installing Windows CA in WSL2..."
    mkcert -install
    sudo update-ca-certificates
    echo "✅ CA installed in WSL2"
fi

# Regenerate certificates
echo
echo "Regenerating certificates..."
cd "/mnt/c/Users/$WINDOWS_USERNAME/AppData/Local/mkcert"
mkcert -cert-file dev-localhost-wild.crt -key-file dev-localhost-wild.key "*.localhost" localhost 127.0.0.1 ::1
mkcert -cert-file dev-registry.localhost.crt -key-file dev-registry.localhost.key registry.localhost

# Copy to WSL2
cp -f dev-*.crt dev-*.key ~/.local/share/certs/

echo "✅ Certificates regenerated"

# Restart services
echo "Restarting Traefik..."
cd ~/platform-services/traefik
docker compose restart

echo
echo "✅ Cleanup complete!"
echo
echo "Test with:"
echo "  curl https://traefik.localhost"
echo "  Browser: https://airflow.localhost"
EOF

chmod +x "$CLEANUP_SCRIPT"
echo -e "${GREEN}✅ Cleanup script generated: $CLEANUP_SCRIPT${NC}"
echo
echo "To perform complete cleanup, run:"
echo "  $CLEANUP_SCRIPT"

echo
echo -e "${BLUE}📊 SUMMARY${NC}"
echo "=========="
if [ "$WINDOWS_CLEANUP_NEEDED" = true ]; then
    echo -e "${YELLOW}⚠️  Windows: Multiple CAs detected - cleanup recommended${NC}"
fi
if [ "$WSL_CLEANUP_NEEDED" = true ]; then
    echo -e "${YELLOW}⚠️  WSL2: Multiple CAs detected - cleanup recommended${NC}"
fi
if [ "$WINDOWS_CLEANUP_NEEDED" = false ] && [ "$WSL_CLEANUP_NEEDED" = false ]; then
    echo -e "${GREEN}✅ No duplicate CAs detected - system is clean${NC}"
fi
