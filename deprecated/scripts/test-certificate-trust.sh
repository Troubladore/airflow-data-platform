#!/bin/bash
# Comprehensive certificate trust testing across Windows/WSL2 boundary

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}🔒 COMPREHENSIVE CERTIFICATE TRUST TEST${NC}"
echo "============================================="
echo

# Test 1: WSL2 command-line trust
echo -e "${BLUE}1. WSL2 Command-Line Trust Test${NC}"
if curl -s --max-time 5 https://traefik.localhost > /dev/null 2>&1; then
    echo -e "   ✅ WSL2 curl: ${GREEN}TRUSTED${NC}"
else
    echo -e "   ❌ WSL2 curl: ${RED}NOT TRUSTED${NC}"
fi

# Test 2: WSL2 openssl verification
echo -e "${BLUE}2. WSL2 OpenSSL Certificate Chain Test${NC}"
if echo "Q" | openssl s_client -connect traefik.localhost:443 -servername traefik.localhost -verify_return_error -brief 2>/dev/null | grep -q "Verification: OK"; then
    echo -e "   ✅ WSL2 OpenSSL: ${GREEN}VALID CHAIN${NC}"
else
    echo -e "   ❌ WSL2 OpenSSL: ${RED}VERIFICATION FAILED${NC}"
fi

# Test 3: Certificate file analysis
echo -e "${BLUE}3. Certificate File Analysis${NC}"
if [ -f "/home/$(whoami)/.local/share/certs/dev-localhost-wild.crt" ]; then
    echo -e "   ✅ WSL2 Certificate File: ${GREEN}EXISTS${NC}"
    # Check certificate details
    issuer=$(openssl x509 -in ~/.local/share/certs/dev-localhost-wild.crt -noout -issuer 2>/dev/null | sed 's/issuer=//')
    echo "   📋 Issuer: $issuer"
else
    echo -e "   ❌ WSL2 Certificate File: ${RED}MISSING${NC}"
fi

# Test 4: System trust store check
echo -e "${BLUE}4. System Trust Store Analysis${NC}"
ca_count=$(ls /usr/local/share/ca-certificates/ 2>/dev/null | grep -c mkcert || echo 0)
echo "   📋 WSL2 CA certificates installed: $ca_count"

# Test 5: Windows mkcert status check
echo -e "${BLUE}5. Windows mkcert Installation Check${NC}"
if command -v powershell.exe >/dev/null 2>&1; then
    # Check if mkcert is available on Windows
    if powershell.exe -Command "Get-Command mkcert -ErrorAction SilentlyContinue" >/dev/null 2>&1; then
        echo -e "   ✅ Windows mkcert: ${GREEN}INSTALLED${NC}"

        # Check Windows CA installation status
        echo -e "${BLUE}6. Windows CA Trust Status${NC}"
        if powershell.exe -Command "mkcert -CAROOT" >/dev/null 2>&1; then
            caroot=$(powershell.exe -Command "mkcert -CAROOT" 2>/dev/null | tr -d '\r')
            echo "   📋 Windows CAROOT: $caroot"

            # Check if CA is actually trusted in Windows store
            if powershell.exe -Command "Get-ChildItem -Path 'Cert:\CurrentUser\Root' | Where-Object {\\$_.Subject -like '*mkcert*'}" 2>/dev/null | grep -q "Subject"; then
                echo -e "   ✅ Windows CA Trust: ${GREEN}INSTALLED${NC}"
            else
                echo -e "   ❌ Windows CA Trust: ${RED}NOT INSTALLED${NC}"
                echo -e "   ${YELLOW}💡 Fix: Run 'mkcert -install' in Windows PowerShell${NC}"
            fi
        else
            echo -e "   ❌ Windows CAROOT: ${RED}CANNOT ACCESS${NC}"
        fi
    else
        echo -e "   ❌ Windows mkcert: ${RED}NOT FOUND${NC}"
    fi
else
    echo -e "   ❌ PowerShell: ${RED}NOT ACCESSIBLE${NC}"
fi

# Test 6: Browser simulation test using Node.js if available
echo -e "${BLUE}7. Browser Trust Simulation${NC}"
if command -v node >/dev/null 2>&1; then
    # Create a temporary Node.js script to test HTTPS without ignoring certificates
    cat > /tmp/cert_test.js << 'EOF'
const https = require('https');

const options = {
    hostname: 'traefik.localhost',
    port: 443,
    path: '/api/http/services',
    method: 'GET',
    // Don't ignore certificate errors - this simulates browser behavior
    rejectUnauthorized: true
};

const req = https.request(options, (res) => {
    console.log('✅ Browser simulation: TRUSTED');
    process.exit(0);
});

req.on('error', (e) => {
    if (e.code === 'CERT_UNTRUSTED' || e.code === 'UNABLE_TO_VERIFY_LEAF_SIGNATURE') {
        console.log('❌ Browser simulation: NOT TRUSTED');
        console.log('   Error:', e.message);
    } else {
        console.log('❌ Browser simulation: CONNECTION ERROR');
        console.log('   Error:', e.message);
    }
    process.exit(1);
});

req.end();
EOF

    if timeout 10 node /tmp/cert_test.js 2>/dev/null; then
        echo -e "   ${GREEN}Node.js HTTPS test passed${NC}"
    else
        echo -e "   ${RED}Node.js HTTPS test failed${NC}"
    fi
    rm -f /tmp/cert_test.js
else
    echo "   ℹ️ Node.js not available for browser simulation"
fi

# Test 7: Platform service connectivity
echo -e "${BLUE}8. Platform Service Connectivity${NC}"
services=("traefik.localhost" "registry.localhost")
for service in "${services[@]}"; do
    if timeout 5 curl -s "https://$service" >/dev/null 2>&1; then
        echo -e "   ✅ $service: ${GREEN}ACCESSIBLE${NC}"
    else
        echo -e "   ❌ $service: ${RED}NOT ACCESSIBLE${NC}"
    fi
done

echo
echo -e "${BLUE}📋 DIAGNOSIS SUMMARY${NC}"
echo "==================="
echo

# Determine the issue
wsl2_trust=$(curl -s --max-time 3 https://traefik.localhost >/dev/null 2>&1 && echo "OK" || echo "FAIL")
windows_ca_check="UNKNOWN"

if command -v powershell.exe >/dev/null 2>&1; then
    if powershell.exe -Command "Get-ChildItem -Path 'Cert:\CurrentUser\Root' | Where-Object {\$_.Subject -like '*mkcert*'}" 2>/dev/null | grep -q "Subject"; then
        windows_ca_check="OK"
    else
        windows_ca_check="FAIL"
    fi
fi

if [ "$wsl2_trust" = "OK" ] && [ "$windows_ca_check" = "OK" ]; then
    echo -e "${GREEN}🎉 CERTIFICATE TRUST: FULLY CONFIGURED${NC}"
    echo "Both WSL2 and Windows trust stores are properly configured"
elif [ "$wsl2_trust" = "OK" ] && [ "$windows_ca_check" = "FAIL" ]; then
    echo -e "${YELLOW}⚠️  PARTIAL CONFIGURATION: WSL2 OK, Windows CA missing${NC}"
    echo
    echo -e "${BLUE}💡 SOLUTION:${NC}"
    echo "Run Windows certificate trust setup:"
    echo "1. Open Windows PowerShell (regular user is fine)"
    echo "2. Run: mkcert -install"
    echo "3. Restart browsers to pick up new trust store"
elif [ "$wsl2_trust" = "FAIL" ]; then
    echo -e "${RED}❌ WSL2 TRUST ISSUE: Platform setup incomplete${NC}"
    echo
    echo -e "${BLUE}💡 SOLUTION:${NC}"
    echo "Re-run platform setup:"
    echo "ansible-playbook -i ansible/inventory/local-dev.ini ansible/setup-wsl2.yml"
else
    echo -e "${YELLOW}⚠️  MIXED RESULTS: Manual diagnosis required${NC}"
fi

echo
