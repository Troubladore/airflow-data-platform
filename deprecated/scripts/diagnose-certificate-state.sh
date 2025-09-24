#!/bin/bash
# Systematic certificate state detection - NO assumptions, only facts
# This script definitively establishes what exists and what doesn't

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# State variables - we'll fill these in
WINDOWS_USERNAME=""
WINDOWS_MKCERT_INSTALLED="UNKNOWN"
WINDOWS_MKCERT_PATH=""
WINDOWS_CA_EXISTS="UNKNOWN"
WINDOWS_CA_PATH=""
WINDOWS_CA_FINGERPRINT=""
WINDOWS_CERTS_EXIST="UNKNOWN"
WINDOWS_CERT_FILES=""

WSL_MKCERT_INSTALLED="UNKNOWN"
WSL_MKCERT_PATH=""
WSL_CERTS_EXIST="UNKNOWN"
WSL_CERT_PATH=""
WSL_CA_IN_TRUST_STORE="UNKNOWN"
WSL_CA_FINGERPRINT=""

TRAEFIK_RUNNING="UNKNOWN"
TRAEFIK_CERT_MOUNTED="UNKNOWN"
TRAEFIK_CERT_PATH=""

echo -e "${BLUE}🔍 SYSTEMATIC CERTIFICATE STATE DETECTION${NC}"
echo "==========================================="
echo "No assumptions. Only facts."
echo

# ============================================================================
# SECTION 1: Windows Environment Detection
# ============================================================================
echo -e "${BLUE}[1/6] Windows Environment Detection${NC}"
echo "------------------------------------"

# 1.1 Detect Windows username
echo -n "• Detecting Windows username... "
# Try multiple methods
if command -v cmd.exe >/dev/null 2>&1; then
    WINDOWS_USERNAME=$(cmd.exe /c "echo %USERNAME%" 2>/dev/null | tr -d '\r\n' || echo "")
fi
if [ -z "$WINDOWS_USERNAME" ] && command -v powershell.exe >/dev/null 2>&1; then
    WINDOWS_USERNAME=$(powershell.exe -Command "Write-Host -NoNewline \$env:USERNAME" 2>/dev/null | tr -d '\r\n' || echo "")
fi
if [ -z "$WINDOWS_USERNAME" ]; then
    # Last resort - check who owns Windows directories (but exclude system dirs)
    WINDOWS_USERNAME=$(ls -ld /mnt/c/Users/*/ 2>/dev/null | grep -v -E "Public|Default|All Users" | head -1 | awk -F'/' '{print $5}' || echo "")
fi

# Additional validation - "All Users" is not a valid username
if [ "$WINDOWS_USERNAME" = "All Users" ] || [ "$WINDOWS_USERNAME" = "Public" ] || [ "$WINDOWS_USERNAME" = "Default" ]; then
    # Try looking for actual user directories with Desktop folders
    for userdir in /mnt/c/Users/*/; do
        basename_user=$(basename "$userdir")
        if [ -d "$userdir/Desktop" ] && [ "$basename_user" != "Public" ] && [ "$basename_user" != "Default" ] && [ "$basename_user" != "All Users" ]; then
            WINDOWS_USERNAME="$basename_user"
            break
        fi
    done
fi

if [ -n "$WINDOWS_USERNAME" ]; then
    echo -e "${GREEN}FOUND: $WINDOWS_USERNAME${NC}"
else
    echo -e "${RED}NOT FOUND${NC}"
fi

# 1.2 Check if mkcert is installed on Windows
echo -n "• Checking Windows mkcert installation... "
WINDOWS_MKCERT_INSTALLED="NO"

# Try PowerShell first (more reliable)
if command -v powershell.exe >/dev/null 2>&1; then
    # Use a more robust PowerShell command that handles scoop shims
    MKCERT_CHECK=$(powershell.exe -Command "try { Get-Command mkcert -ErrorAction Stop; Write-Output 'FOUND' } catch { Write-Output 'NOTFOUND' }" 2>/dev/null | tr -d '\r\n' || echo "")
    if [[ "$MKCERT_CHECK" == *"FOUND"* ]]; then
        WINDOWS_MKCERT_INSTALLED="YES"
        WINDOWS_MKCERT_PATH=$(powershell.exe -Command "(Get-Command mkcert -ErrorAction SilentlyContinue).Source" 2>/dev/null | tr -d '\r\n' || echo "")
    fi
fi

# Fallback to cmd.exe
if [ "$WINDOWS_MKCERT_INSTALLED" = "NO" ] && command -v cmd.exe >/dev/null 2>&1; then
    if cmd.exe /c "where mkcert" >/dev/null 2>&1; then
        WINDOWS_MKCERT_INSTALLED="YES"
        WINDOWS_MKCERT_PATH=$(cmd.exe /c "where mkcert" 2>/dev/null | head -1 | tr -d '\r\n' || echo "")
    fi
fi

# Direct check for common installation locations
if [ "$WINDOWS_MKCERT_INSTALLED" = "NO" ]; then
    # Check scoop installation
    if [ -f "/mnt/c/Users/$WINDOWS_USERNAME/scoop/shims/mkcert.exe" ]; then
        WINDOWS_MKCERT_INSTALLED="YES"
        WINDOWS_MKCERT_PATH="C:\\Users\\$WINDOWS_USERNAME\\scoop\\shims\\mkcert.exe"
    fi
fi

if [ "$WINDOWS_MKCERT_INSTALLED" = "YES" ]; then
    echo -e "${GREEN}YES${NC}"
    echo "  └─ Path: $WINDOWS_MKCERT_PATH"

    # Check if CA is trusted in Windows store
    echo -n "  └─ CA trusted in Windows store... "
    if powershell.exe -Command "Get-ChildItem -Path 'Cert:\CurrentUser\Root' | Where-Object {\$_.Subject -like '*mkcert*'}" 2>/dev/null | grep -q "mkcert"; then
        echo -e "${GREEN}YES${NC}"
        WINDOWS_CA_TRUSTED="YES"
    else
        echo -e "${RED}NO - Run 'mkcert -install' in Windows${NC}"
        WINDOWS_CA_TRUSTED="NO"
    fi
else
    echo -e "${RED}NO${NC}"
fi

# 1.3 Check for Windows CA and certificates
if [ -n "$WINDOWS_USERNAME" ]; then
    echo -n "• Checking Windows mkcert directory... "
    WINDOWS_MKCERT_DIR="/mnt/c/Users/$WINDOWS_USERNAME/AppData/Local/mkcert"

    if [ -d "$WINDOWS_MKCERT_DIR" ]; then
        echo -e "${GREEN}EXISTS${NC}"
        echo "  └─ Path: $WINDOWS_MKCERT_DIR"

        # List all files
        echo "  └─ Contents:"
        ls -la "$WINDOWS_MKCERT_DIR" 2>/dev/null | grep -v "^total" | grep -v "^\." | while read line; do
            echo "      $line"
        done

        # Check for CA
        WINDOWS_CA_EXISTS="NO"
        for ca_file in "$WINDOWS_MKCERT_DIR"/rootCA*.pem "$WINDOWS_MKCERT_DIR"/*CA*.pem; do
            if [ -f "$ca_file" ]; then
                WINDOWS_CA_EXISTS="YES"
                WINDOWS_CA_PATH="$ca_file"
                WINDOWS_CA_FINGERPRINT=$(openssl x509 -in "$ca_file" -noout -fingerprint -sha256 2>/dev/null | cut -d= -f2 || echo "ERROR")
                echo -e "  └─ CA Found: ${GREEN}YES${NC}"
                echo "      └─ File: $(basename "$ca_file")"
                echo "      └─ SHA256: $WINDOWS_CA_FINGERPRINT"
                break
            fi
        done

        # Check for certificates
        WINDOWS_CERTS_EXIST="NO"
        for cert_file in "$WINDOWS_MKCERT_DIR"/*.crt "$WINDOWS_MKCERT_DIR"/*.pem; do
            if [ -f "$cert_file" ] && [[ ! "$cert_file" =~ rootCA|CA ]]; then
                WINDOWS_CERTS_EXIST="YES"
                echo "  └─ Certificate: $(basename "$cert_file")"
            fi
        done
    else
        echo -e "${RED}NOT FOUND${NC}"
    fi
else
    echo "• Skipping Windows mkcert check (no username)"
fi

# ============================================================================
# SECTION 2: WSL2 mkcert Installation
# ============================================================================
echo
echo -e "${BLUE}[2/6] WSL2 Environment${NC}"
echo "----------------------"

# 2.0 Check WSL2 username
echo -n "• WSL2 username... "
WSL_USERNAME=$(whoami)
echo -e "${GREEN}$WSL_USERNAME${NC}"

# Compare with Windows username
if [ -n "$WINDOWS_USERNAME" ]; then
    if [ "$WSL_USERNAME" != "$WINDOWS_USERNAME" ]; then
        echo -e "  └─ ${YELLOW}⚠️  Different from Windows username ($WINDOWS_USERNAME)${NC}"
    else
        echo -e "  └─ ✅ Matches Windows username"
    fi
fi

echo
echo -e "${BLUE}[3/6] WSL2 mkcert Status${NC}"
echo "------------------------"

# 3.1 Check if mkcert is installed in WSL2
echo -n "• WSL2 mkcert installation... "
if command -v mkcert >/dev/null 2>&1; then
    WSL_MKCERT_INSTALLED="YES"
    WSL_MKCERT_PATH=$(which mkcert)
    echo -e "${GREEN}YES${NC}"
    echo "  └─ Path: $WSL_MKCERT_PATH"
    echo -n "  └─ Version: "
    mkcert -version 2>/dev/null || echo "unknown"
else
    WSL_MKCERT_INSTALLED="NO"
    echo -e "${RED}NO${NC}"
fi

# 3.2 Check WSL2 CAROOT
if [ "$WSL_MKCERT_INSTALLED" = "YES" ]; then
    echo -n "• WSL2 CAROOT location... "
    WSL_CAROOT=$(mkcert -CAROOT 2>/dev/null || echo "")
    if [ -n "$WSL_CAROOT" ]; then
        echo "$WSL_CAROOT"
        if [ -d "$WSL_CAROOT" ]; then
            echo "  └─ Contents:"
            ls -la "$WSL_CAROOT" 2>/dev/null | grep -v "^total" | grep -v "^\." | while read line; do
                echo "      $line"
            done
        else
            echo -e "  └─ ${RED}Directory doesn't exist!${NC}"
        fi
    else
        echo -e "${RED}UNKNOWN${NC}"
    fi
fi

# ============================================================================
# SECTION 4: WSL2 Certificate Files
# ============================================================================
echo
echo -e "${BLUE}[4/7] WSL2 Certificate Files${NC}"
echo "----------------------------"

# 4.1 Check local certificate directory
WSL_CERT_DIR="$HOME/.local/share/certs"
echo -n "• WSL2 certificate directory ($WSL_CERT_DIR)... "
if [ -d "$WSL_CERT_DIR" ]; then
    WSL_CERTS_EXIST="YES"
    echo -e "${GREEN}EXISTS${NC}"
    echo "  └─ Contents:"
    ls -la "$WSL_CERT_DIR" 2>/dev/null | grep -v "^total" | grep -v "^\." | while read line; do
        echo "      $line"
    done

    # Check certificate fingerprints
    for cert in "$WSL_CERT_DIR"/*.crt; do
        if [ -f "$cert" ]; then
            fingerprint=$(openssl x509 -in "$cert" -noout -fingerprint -sha256 2>/dev/null | cut -d= -f2 || echo "ERROR")
            echo "  └─ $(basename "$cert") SHA256: $fingerprint"
        fi
    done
else
    WSL_CERTS_EXIST="NO"
    echo -e "${RED}NOT FOUND${NC}"
fi

# ============================================================================
# SECTION 5: System Trust Store
# ============================================================================
echo
echo -e "${BLUE}[5/7] System Trust Store${NC}"
echo "------------------------"

# 5.1 Check system CA certificates directory
echo -n "• System CA directory (/usr/local/share/ca-certificates)... "
if [ -d "/usr/local/share/ca-certificates" ]; then
    echo -e "${GREEN}EXISTS${NC}"

    # List mkcert CAs
    mkcert_cas=$(find /usr/local/share/ca-certificates -name "mkcert*.crt" 2>/dev/null)
    if [ -n "$mkcert_cas" ]; then
        WSL_CA_IN_TRUST_STORE="YES"
        echo "  └─ mkcert CAs found:"
        echo "$mkcert_cas" | while read ca_file; do
            if [ -f "$ca_file" ]; then
                fingerprint=$(openssl x509 -in "$ca_file" -noout -fingerprint -sha256 2>/dev/null | cut -d= -f2 || echo "ERROR")
                echo "      • $(basename "$ca_file")"
                echo "        SHA256: $fingerprint"
                WSL_CA_FINGERPRINT="$fingerprint"
            fi
        done
    else
        WSL_CA_IN_TRUST_STORE="NO"
        echo -e "  └─ ${RED}No mkcert CAs found${NC}"
    fi
else
    echo -e "${RED}NOT FOUND${NC}"
fi

# 5.2 Check if certificates are actually trusted
echo -n "• Testing actual trust (curl https://traefik.localhost)... "
if timeout 5 curl -s https://traefik.localhost >/dev/null 2>&1; then
    echo -e "${GREEN}TRUSTED${NC}"
else
    echo -e "${RED}NOT TRUSTED${NC}"
fi

# ============================================================================
# SECTION 6: Docker/Traefik Status
# ============================================================================
echo
echo -e "${BLUE}[6/7] Docker/Traefik Configuration${NC}"
echo "----------------------------------"

# 6.1 Check if Traefik is running
echo -n "• Traefik container status... "
if docker ps --format "{{.Names}}" 2>/dev/null | grep -q traefik; then
    TRAEFIK_RUNNING="YES"
    echo -e "${GREEN}RUNNING${NC}"

    # Get container details (find the actual traefik container, not registry)
    TRAEFIK_CONTAINER=$(docker ps --format "{{.Names}}" | grep -E "traefik-traefik|traefik_traefik" | head -1)
    # Fallback to any traefik container
    if [ -z "$TRAEFIK_CONTAINER" ]; then
        TRAEFIK_CONTAINER=$(docker ps --format "{{.Names}}" | grep traefik | grep -v registry | head -1)
    fi
    echo "  └─ Container: $TRAEFIK_CONTAINER"

    # Check certificate mount (without jq since it's not installed)
    echo -n "  └─ Certificate mount... "
    CERT_MOUNT=$(docker inspect "$TRAEFIK_CONTAINER" 2>/dev/null | grep -A5 '"/certs"' | grep '"Source"' | cut -d'"' -f4 || echo "")
    if [ -n "$CERT_MOUNT" ]; then
        TRAEFIK_CERT_MOUNTED="YES"
        TRAEFIK_CERT_PATH="$CERT_MOUNT"
        echo -e "${GREEN}YES${NC}"
        echo "      └─ Source: $CERT_MOUNT"

        # Check if mounted certificates actually exist
        if [ -d "$CERT_MOUNT" ]; then
            cert_count=$(ls -1 "$CERT_MOUNT"/*.crt 2>/dev/null | wc -l || echo 0)
            key_count=$(ls -1 "$CERT_MOUNT"/*.key 2>/dev/null | wc -l || echo 0)
            echo "      └─ Files: $cert_count certificates, $key_count keys"
        else
            echo -e "      └─ ${RED}Mount source doesn't exist!${NC}"
        fi
    else
        TRAEFIK_CERT_MOUNTED="NO"
        echo -e "${RED}NO${NC}"
    fi
else
    TRAEFIK_RUNNING="NO"
    echo -e "${RED}NOT RUNNING${NC}"
fi

# ============================================================================
# SECTION 7: Airflow Service Test
# ============================================================================
echo
echo -e "${BLUE}[7/8] Airflow Service Test${NC}"
echo "-----------------------------"

# 7.1 Check if Airflow is running
echo -n "• Airflow containers... "
AIRFLOW_CONTAINERS=$(docker ps --format "{{.Names}}" | grep -i airflow | wc -l)
if [ "$AIRFLOW_CONTAINERS" -gt 0 ]; then
    echo -e "${GREEN}$AIRFLOW_CONTAINERS running${NC}"
    docker ps --format "table {{.Names}}\t{{.Status}}" | grep -i airflow | while read line; do
        echo "  └─ $line"
    done

    # Test Airflow webserver connectivity
    echo -n "• Airflow webserver accessibility... "
    AIRFLOW_PORT=$(docker ps --format "table {{.Names}}\t{{.Ports}}" | grep -i webserver | grep -oE "0.0.0.0:([0-9]+)" | cut -d: -f2 | head -1)
    if [ -n "$AIRFLOW_PORT" ]; then
        if timeout 5 curl -s "http://localhost:$AIRFLOW_PORT" >/dev/null 2>&1; then
            echo -e "${GREEN}YES (port $AIRFLOW_PORT)${NC}"
        else
            echo -e "${RED}NOT ACCESSIBLE on port $AIRFLOW_PORT${NC}"
        fi
    else
        echo -e "${YELLOW}No exposed port found${NC}"
    fi
else
    echo -e "${YELLOW}None running${NC}"
    echo "  └─ Deploy Airflow to test HTTPS access"
fi

# ============================================================================
# SECTION 8: Diagnosis Summary
# ============================================================================
echo
echo -e "${BLUE}[8/8] DIAGNOSIS SUMMARY${NC}"
echo "======================="
echo

# Print state table
echo "Component                    | Status      | Details"
echo "-----------------------------|-------------|----------------------------------------"
printf "%-28s | %-11s | %s\n" "Windows Username" "$([ -n "$WINDOWS_USERNAME" ] && echo "FOUND" || echo "NOT FOUND")" "$WINDOWS_USERNAME"
printf "%-28s | %-11s | %s\n" "Windows mkcert" "$WINDOWS_MKCERT_INSTALLED" "$WINDOWS_MKCERT_PATH"
printf "%-28s | %-11s | %s\n" "Windows CA" "$WINDOWS_CA_EXISTS" "$([ "$WINDOWS_CA_EXISTS" = "YES" ] && echo "SHA256: ${WINDOWS_CA_FINGERPRINT:0:16}..." || echo "")"
printf "%-28s | %-11s | %s\n" "Windows Certificates" "$WINDOWS_CERTS_EXIST" ""
printf "%-28s | %-11s | %s\n" "WSL2 mkcert" "$WSL_MKCERT_INSTALLED" "$WSL_MKCERT_PATH"
printf "%-28s | %-11s | %s\n" "WSL2 Certificates" "$WSL_CERTS_EXIST" "$WSL_CERT_DIR"
printf "%-28s | %-11s | %s\n" "WSL2 CA in Trust Store" "$WSL_CA_IN_TRUST_STORE" "$([ "$WSL_CA_IN_TRUST_STORE" = "YES" ] && echo "SHA256: ${WSL_CA_FINGERPRINT:0:16}..." || echo "")"
printf "%-28s | %-11s | %s\n" "Traefik Running" "$TRAEFIK_RUNNING" "$TRAEFIK_CONTAINER"
printf "%-28s | %-11s | %s\n" "Traefik Cert Mount" "$TRAEFIK_CERT_MOUNTED" "$TRAEFIK_CERT_PATH"

echo
echo -e "${BLUE}🎯 ISSUE IDENTIFICATION${NC}"
echo "======================"

# Identify the specific issue
ISSUE_COUNT=0

# Check 1: Windows mkcert not installed
if [ "$WINDOWS_MKCERT_INSTALLED" = "NO" ]; then
    echo -e "${RED}❌ ISSUE $((++ISSUE_COUNT)): mkcert not installed on Windows${NC}"
    echo "   This is the root cause - browsers check Windows trust store"
    echo "   SOLUTION: Install mkcert on Windows first"
fi

# Check 2: Windows CA doesn't exist
if [ "$WINDOWS_MKCERT_INSTALLED" = "YES" ] && [ "$WINDOWS_CA_EXISTS" = "NO" ]; then
    echo -e "${RED}❌ ISSUE $((++ISSUE_COUNT)): mkcert installed but CA not created${NC}"
    echo "   SOLUTION: Run 'mkcert -install' on Windows"
fi

# Check 3: CA fingerprint mismatch
if [ "$WINDOWS_CA_EXISTS" = "YES" ] && [ "$WSL_CA_IN_TRUST_STORE" = "YES" ]; then
    if [ "$WINDOWS_CA_FINGERPRINT" != "$WSL_CA_FINGERPRINT" ]; then
        echo -e "${RED}❌ ISSUE $((++ISSUE_COUNT)): CA fingerprint mismatch${NC}"
        echo "   Windows CA: ${WINDOWS_CA_FINGERPRINT:0:32}..."
        echo "   WSL2 CA:    ${WSL_CA_FINGERPRINT:0:32}..."
        echo "   SOLUTION: Re-sync CAs between Windows and WSL2"
    fi
fi

# Check 4: WSL2 mkcert not installed
if [ "$WSL_MKCERT_INSTALLED" = "NO" ]; then
    echo -e "${YELLOW}⚠️  ISSUE $((++ISSUE_COUNT)): mkcert not installed in WSL2${NC}"
    echo "   Not critical if Windows mkcert works, but needed for WSL2 tools"
fi

# Check 5: Certificates don't exist
if [ "$WSL_CERTS_EXIST" = "NO" ]; then
    echo -e "${RED}❌ ISSUE $((++ISSUE_COUNT)): WSL2 certificates don't exist${NC}"
    echo "   SOLUTION: Generate or copy certificates"
fi

# Check 6: Traefik not using certificates
if [ "$TRAEFIK_RUNNING" = "YES" ] && [ "$TRAEFIK_CERT_MOUNTED" = "NO" ]; then
    echo -e "${RED}❌ ISSUE $((++ISSUE_COUNT)): Traefik not mounting certificates${NC}"
    echo "   SOLUTION: Fix docker-compose.yml certificate mount"
fi

# Check 7: Traefik mounting wrong path
if [ "$TRAEFIK_CERT_MOUNTED" = "YES" ] && [ ! -d "$TRAEFIK_CERT_PATH" ]; then
    echo -e "${RED}❌ ISSUE $((++ISSUE_COUNT)): Traefik mounting non-existent path${NC}"
    echo "   Mounted: $TRAEFIK_CERT_PATH (doesn't exist)"
    echo "   SOLUTION: Update docker-compose.yml to mount correct path"
fi

if [ $ISSUE_COUNT -eq 0 ]; then
    echo -e "${GREEN}✅ No obvious issues found - may need deeper investigation${NC}"
fi

echo
echo -e "${BLUE}📝 RECOMMENDED ACTIONS${NC}"
echo "====================="

# Generate specific action plan based on findings
ACTION_NUM=0

if [ "$WINDOWS_MKCERT_INSTALLED" = "NO" ]; then
    echo -e "${YELLOW}$((++ACTION_NUM)). Install mkcert on Windows:${NC}"
    echo "   Open PowerShell as regular user and run:"
    echo "   scoop install mkcert"
    echo "   OR: choco install mkcert"
    echo "   OR: Download from https://github.com/FiloSottile/mkcert/releases"
    echo
fi

if [ "$WINDOWS_MKCERT_INSTALLED" = "YES" ] && [ "$WINDOWS_CA_EXISTS" = "NO" ]; then
    echo -e "${YELLOW}$((++ACTION_NUM)). Install CA on Windows:${NC}"
    echo "   In PowerShell: mkcert -install"
    echo
fi

if [ "$WINDOWS_CA_EXISTS" = "YES" ] && [ "$WINDOWS_CERTS_EXIST" = "NO" ]; then
    echo -e "${YELLOW}$((++ACTION_NUM)). Generate certificates on Windows:${NC}"
    echo "   cd %LOCALAPPDATA%\\mkcert"
    echo "   mkcert -cert-file dev-localhost-wild.crt -key-file dev-localhost-wild.key \"*.localhost\" localhost 127.0.0.1 ::1"
    echo "   mkcert -cert-file dev-registry.localhost.crt -key-file dev-registry.localhost.key registry.localhost"
    echo
fi

if [ "$WSL_MKCERT_INSTALLED" = "NO" ]; then
    echo -e "${YELLOW}$((++ACTION_NUM)). Install mkcert in WSL2:${NC}"
    echo "   The Ansible playbook should do this, or manually:"
    echo "   wget -O mkcert https://dl.filippo.io/mkcert/latest?for=linux/amd64"
    echo "   chmod +x mkcert && sudo mv mkcert /usr/local/bin/"
    echo
fi

if [ "$WINDOWS_CA_EXISTS" = "YES" ] && [ "$WSL_CA_IN_TRUST_STORE" = "NO" ]; then
    echo -e "${YELLOW}$((++ACTION_NUM)). Install Windows CA in WSL2:${NC}"
    echo "   export CAROOT=\"$WINDOWS_MKCERT_DIR\""
    echo "   mkcert -install"
    echo "   sudo update-ca-certificates"
    echo
fi

if [ $ACTION_NUM -eq 0 ]; then
    echo -e "${GREEN}No actions needed based on current state${NC}"
fi

echo
echo "Save this output! Run again after taking actions to verify progress."
