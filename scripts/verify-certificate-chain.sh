#!/bin/bash
# Verify which CA actually signed the certificates and if it matches what's trusted

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}🔍 CERTIFICATE CHAIN VERIFICATION${NC}"
echo "===================================="
echo

# Step 1: Get the CA that signed the current certificates
echo -e "${BLUE}Step 1: Identify CA that signed current certificates${NC}"
echo "----------------------------------------------------"

CERT_FILE="$HOME/.local/share/certs/dev-localhost-wild.crt"

if [ -f "$CERT_FILE" ]; then
    echo "Checking certificate: $CERT_FILE"

    # Get the issuer (CA) fingerprint from the certificate
    CERT_ISSUER=$(openssl x509 -in "$CERT_FILE" -noout -issuer 2>/dev/null)
    echo "Certificate issued by: $CERT_ISSUER"

    # Get the CA that would have signed this
    CERT_CA_FINGERPRINT=$(openssl x509 -in "$CERT_FILE" -noout -text 2>/dev/null | grep -A2 "Authority Key Identifier" | grep "keyid" | cut -d: -f2- | tr -d ' :' || echo "")
    echo "CA Key ID: $CERT_CA_FINGERPRINT"
else
    echo -e "${RED}Certificate not found!${NC}"
    exit 1
fi

echo
echo -e "${BLUE}Step 2: Check Windows CA files${NC}"
echo "------------------------------"

# Find Windows username
WINDOWS_USERNAME=$(ls -ld /mnt/c/Users/*/ 2>/dev/null | grep -v -E "Public|Default|All Users" | head -1 | awk -F'/' '{print $5}' || echo "")

if [ -n "$WINDOWS_USERNAME" ]; then
    WINDOWS_MKCERT_DIR="/mnt/c/Users/$WINDOWS_USERNAME/AppData/Local/mkcert"

    if [ -d "$WINDOWS_MKCERT_DIR" ]; then
        echo "Windows mkcert directory: $WINDOWS_MKCERT_DIR"

        # Check the current rootCA.pem
        if [ -f "$WINDOWS_MKCERT_DIR/rootCA.pem" ]; then
            echo
            echo "Current Windows rootCA.pem:"
            WINDOWS_CA_SUBJECT=$(openssl x509 -in "$WINDOWS_MKCERT_DIR/rootCA.pem" -noout -subject 2>/dev/null)
            WINDOWS_CA_FINGERPRINT=$(openssl x509 -in "$WINDOWS_MKCERT_DIR/rootCA.pem" -noout -fingerprint -sha256 2>/dev/null | cut -d= -f2)
            WINDOWS_CA_KEYID=$(openssl x509 -in "$WINDOWS_MKCERT_DIR/rootCA.pem" -noout -text 2>/dev/null | grep -A1 "Subject Key Identifier" | tail -1 | tr -d ' :' || echo "")

            echo "  Subject: $WINDOWS_CA_SUBJECT"
            echo "  SHA256: $WINDOWS_CA_FINGERPRINT"
            echo "  KeyID: $WINDOWS_CA_KEYID"

            # Check if this CA could have signed our certificate
            echo
            echo -n "Could this CA have signed our certificate? "
            if [[ "$CERT_ISSUER" == *"$WINDOWS_CA_SUBJECT"* ]] || [[ "$CERT_CA_FINGERPRINT" == "$WINDOWS_CA_KEYID" ]]; then
                echo -e "${GREEN}YES - This is likely the correct CA${NC}"
                CORRECT_CA_FINGERPRINT="$WINDOWS_CA_FINGERPRINT"
            else
                echo -e "${RED}NO - Different CA${NC}"
            fi
        fi
    fi
fi

echo
echo -e "${BLUE}Step 3: Check WSL2 trust store${NC}"
echo "------------------------------"

echo "CAs in WSL2 system trust store:"
for ca_file in /usr/local/share/ca-certificates/mkcert*.crt; do
    if [ -f "$ca_file" ]; then
        CA_FINGERPRINT=$(openssl x509 -in "$ca_file" -noout -fingerprint -sha256 2>/dev/null | cut -d= -f2)
        CA_SUBJECT=$(openssl x509 -in "$ca_file" -noout -subject 2>/dev/null | cut -d= -f2-)

        echo "  • $(basename "$ca_file")"
        echo "    Subject: $CA_SUBJECT"
        echo "    SHA256: $CA_FINGERPRINT"

        if [ "$CA_FINGERPRINT" = "$CORRECT_CA_FINGERPRINT" ]; then
            echo -e "    ${GREEN}✅ MATCHES Windows CA${NC}"
        else
            echo -e "    ${YELLOW}⚠️  Different CA${NC}"
        fi
    fi
done

echo
echo -e "${BLUE}Step 4: Verify certificate chain${NC}"
echo "---------------------------------"

# Create a temporary CA bundle with the Windows CA
if [ -f "$WINDOWS_MKCERT_DIR/rootCA.pem" ]; then
    echo -n "Testing certificate chain validation... "

    # Verify the certificate against the Windows CA
    if openssl verify -CAfile "$WINDOWS_MKCERT_DIR/rootCA.pem" "$CERT_FILE" >/dev/null 2>&1; then
        echo -e "${GREEN}✅ VALID CHAIN${NC}"
        echo "The certificate was signed by the Windows CA"
        CHAIN_VALID=true
    else
        echo -e "${RED}❌ INVALID CHAIN${NC}"
        echo "The certificate was NOT signed by the current Windows CA"
        CHAIN_VALID=false
    fi
fi

echo
echo -e "${BLUE}Step 5: Test HTTPS with specific CA${NC}"
echo "------------------------------------"

if [ "$CHAIN_VALID" = true ] && [ -f "$WINDOWS_MKCERT_DIR/rootCA.pem" ]; then
    echo -n "Testing HTTPS with Windows CA... "

    # Test curl with the specific CA
    if curl --cacert "$WINDOWS_MKCERT_DIR/rootCA.pem" -s https://traefik.localhost >/dev/null 2>&1; then
        echo -e "${GREEN}✅ SUCCESS${NC}"
    else
        echo -e "${RED}❌ FAILED${NC}"
    fi

    echo -n "Testing HTTPS with system trust... "
    if curl -s https://traefik.localhost >/dev/null 2>&1; then
        echo -e "${GREEN}✅ SUCCESS${NC}"
    else
        echo -e "${RED}❌ FAILED${NC}"
        echo
        echo "The correct CA may not be in the system trust store"
        echo "Or there may be conflicting CAs"
    fi
fi

echo
echo -e "${BLUE}Step 6: Windows Trust Store Analysis${NC}"
echo "------------------------------------"

echo "Checking Windows trust store (via PowerShell)..."
if command -v powershell.exe >/dev/null 2>&1; then
    # Get all mkcert CAs from Windows
    WINDOWS_CAS=$(powershell.exe -Command "Get-ChildItem -Path 'Cert:\CurrentUser\Root' | Where-Object {\$_.Subject -like '*mkcert*'} | ForEach-Object { \$_.Thumbprint + '|' + \$_.Subject }" 2>/dev/null | tr -d '\r')

    if [ -n "$WINDOWS_CAS" ]; then
        echo "Found multiple mkcert CAs in Windows store:"
        echo "$WINDOWS_CAS" | while IFS='|' read -r thumbprint subject; do
            if [ -n "$thumbprint" ]; then
                echo "  • Thumbprint: $thumbprint"
                echo "    Subject: $subject"

                # Convert Windows thumbprint to compare with our CA
                if [ -n "$CORRECT_CA_FINGERPRINT" ]; then
                    # Windows thumbprint is SHA1, our fingerprint is SHA256, so we can't directly compare
                    # But we can check if this might be the right one based on subject
                    if [[ "$subject" == *"$(echo $WINDOWS_CA_SUBJECT | cut -d= -f2-)"* ]]; then
                        echo -e "    ${GREEN}✅ Likely the correct CA based on subject${NC}"
                    fi
                fi
            fi
        done

        echo
        echo -e "${YELLOW}⚠️  MULTIPLE CAs DETECTED${NC}"
        echo "Having multiple mkcert CAs can cause confusion."
        echo "Consider cleaning up old CAs from Windows trust store."
    fi
fi

echo
echo -e "${BLUE}📊 SUMMARY${NC}"
echo "=========="

if [ "$CHAIN_VALID" = true ]; then
    echo -e "${GREEN}✅ Certificate chain is valid${NC}"
    echo "The certificates match the current Windows CA"
else
    echo -e "${RED}❌ Certificate chain mismatch${NC}"
    echo "The certificates were signed by a different CA"
    echo
    echo "This means the certificates need to be regenerated with the current CA"
    echo "OR the old CA that signed them needs to be restored"
fi

echo
if [ -n "$WINDOWS_CAS" ] && [[ "$WINDOWS_CAS" == *$'\n'* ]]; then
    echo -e "${YELLOW}⚠️  Clean up Windows trust store:${NC}"
    echo "You have multiple mkcert CAs which can cause issues."
    echo
    echo "To fix in Windows PowerShell:"
    echo "1. List all mkcert CAs:"
    echo "   Get-ChildItem -Path 'Cert:\\CurrentUser\\Root' | Where-Object {\$_.Subject -like '*mkcert*'}"
    echo
    echo "2. Remove old/duplicate CAs (keep only the current one):"
    echo "   Get-ChildItem -Path 'Cert:\\CurrentUser\\Root' | Where-Object {\$_.Subject -like '*mkcert*' -and \$_.Thumbprint -ne 'CURRENT_THUMBPRINT'} | Remove-Item"
    echo
    echo "3. Or complete reset:"
    echo "   mkcert -uninstall  # Remove all mkcert CAs"
    echo "   mkcert -install    # Install fresh CA"
    echo "   # Then regenerate all certificates"
fi
