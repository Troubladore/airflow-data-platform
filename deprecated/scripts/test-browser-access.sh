#!/bin/bash
# Test browser-like access to all HTTPS services
# Simulates what a real browser would experience

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}🌐 BROWSER ACCESS SIMULATION TEST${NC}"
echo "===================================="
echo

# Test configurations
SERVICES=(
    "traefik.localhost|Traefik Dashboard"
    "registry.localhost|Container Registry"
    "airflow.localhost|Airflow UI"
)

TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# ============================================================================
# Test 1: DNS Resolution
# ============================================================================
echo -e "${BLUE}Test 1: DNS Resolution${NC}"
echo "----------------------"

for service_info in "${SERVICES[@]}"; do
    IFS='|' read -r service name <<< "$service_info"
    echo -n "• $name ($service)... "

    TOTAL_TESTS=$((TOTAL_TESTS + 1))

    # Check if it resolves
    if getent hosts "$service" >/dev/null 2>&1 || nslookup "$service" >/dev/null 2>&1; then
        echo -e "${GREEN}✅ Resolves${NC}"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        echo -e "${RED}❌ DNS failure${NC}"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
done

# ============================================================================
# Test 2: TCP Connectivity
# ============================================================================
echo
echo -e "${BLUE}Test 2: TCP Connectivity (Port 443)${NC}"
echo "------------------------------------"

for service_info in "${SERVICES[@]}"; do
    IFS='|' read -r service name <<< "$service_info"
    echo -n "• $name... "

    TOTAL_TESTS=$((TOTAL_TESTS + 1))

    if timeout 2 bash -c "echo > /dev/tcp/$service/443" 2>/dev/null; then
        echo -e "${GREEN}✅ Port open${NC}"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        echo -e "${RED}❌ Port closed/timeout${NC}"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
done

# ============================================================================
# Test 3: Certificate Verification
# ============================================================================
echo
echo -e "${BLUE}Test 3: Certificate Chain Verification${NC}"
echo "--------------------------------------"

for service_info in "${SERVICES[@]}"; do
    IFS='|' read -r service name <<< "$service_info"
    echo -n "• $name... "

    TOTAL_TESTS=$((TOTAL_TESTS + 1))

    # Check certificate with openssl
    CERT_CHECK=$(echo | openssl s_client -connect "$service:443" -servername "$service" 2>&1 | grep "Verify return code")

    if [[ "$CERT_CHECK" == *"Verify return code: 0"* ]]; then
        echo -e "${GREEN}✅ Valid certificate${NC}"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        ERROR_CODE=$(echo "$CERT_CHECK" | grep -oE "Verify return code: [0-9]+" | cut -d: -f2 | xargs)
        echo -e "${RED}❌ Certificate error (code $ERROR_CODE)${NC}"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
done

# ============================================================================
# Test 4: HTTPS GET Request (curl)
# ============================================================================
echo
echo -e "${BLUE}Test 4: HTTPS GET Request (curl)${NC}"
echo "---------------------------------"

for service_info in "${SERVICES[@]}"; do
    IFS='|' read -r service name <<< "$service_info"
    echo -n "• $name... "

    TOTAL_TESTS=$((TOTAL_TESTS + 1))

    # Try with system trust store (should work if CA is trusted)
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 "https://$service" 2>/dev/null || echo "000")

    if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "401" ] || [ "$HTTP_CODE" = "404" ]; then
        echo -e "${GREEN}✅ HTTPS OK (HTTP $HTTP_CODE)${NC}"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    elif [ "$HTTP_CODE" = "000" ]; then
        # SSL error - try with -k to see if it's just trust
        HTTP_CODE_INSECURE=$(curl -k -s -o /dev/null -w "%{http_code}" --connect-timeout 5 "https://$service" 2>/dev/null || echo "000")
        if [ "$HTTP_CODE_INSECURE" != "000" ]; then
            echo -e "${YELLOW}⚠️  SSL trust issue (works with -k: HTTP $HTTP_CODE_INSECURE)${NC}"
        else
            echo -e "${RED}❌ Connection failed${NC}"
        fi
        FAILED_TESTS=$((FAILED_TESTS + 1))
    else
        echo -e "${YELLOW}⚠️  HTTP $HTTP_CODE${NC}"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
done

# ============================================================================
# Test 5: Node.js Browser Simulation
# ============================================================================
echo
echo -e "${BLUE}Test 5: Browser Simulation (Node.js)${NC}"
echo "------------------------------------"

if command -v node >/dev/null 2>&1; then
    for service_info in "${SERVICES[@]}"; do
        IFS='|' read -r service name <<< "$service_info"
        echo -n "• $name... "

        TOTAL_TESTS=$((TOTAL_TESTS + 1))

        # Create Node.js test
        cat > /tmp/browser_test.js << EOF
const https = require('https');
const options = {
    hostname: '$service',
    port: 443,
    path: '/',
    method: 'GET',
    rejectUnauthorized: true  // This simulates browser behavior
};

const req = https.request(options, (res) => {
    console.log('SUCCESS:' + res.statusCode);
    process.exit(0);
});

req.on('error', (e) => {
    console.log('ERROR:' + e.code);
    process.exit(1);
});

req.setTimeout(5000, () => {
    console.log('ERROR:TIMEOUT');
    req.destroy();
});

req.end();
EOF

        RESULT=$(timeout 10 node /tmp/browser_test.js 2>&1 || echo "ERROR:FAILED")

        if [[ "$RESULT" == *"SUCCESS"* ]]; then
            HTTP_CODE=$(echo "$RESULT" | grep -oE "SUCCESS:[0-9]+" | cut -d: -f2)
            echo -e "${GREEN}✅ Browser trust OK (HTTP $HTTP_CODE)${NC}"
            PASSED_TESTS=$((PASSED_TESTS + 1))
        elif [[ "$RESULT" == *"CERT"* ]] || [[ "$RESULT" == *"UNABLE_TO_VERIFY"* ]]; then
            echo -e "${RED}❌ Certificate not trusted by browser${NC}"
            FAILED_TESTS=$((FAILED_TESTS + 1))
        elif [[ "$RESULT" == *"ECONNREFUSED"* ]]; then
            echo -e "${RED}❌ Connection refused${NC}"
            FAILED_TESTS=$((FAILED_TESTS + 1))
        else
            echo -e "${RED}❌ Failed ($(echo $RESULT | cut -c1-30)...)${NC}"
            FAILED_TESTS=$((FAILED_TESTS + 1))
        fi
    done

    rm -f /tmp/browser_test.js
else
    echo "Node.js not available - skipping browser simulation"
fi

# ============================================================================
# Test 6: Check actual running services
# ============================================================================
echo
echo -e "${BLUE}Test 6: Service Container Status${NC}"
echo "--------------------------------"

echo -n "• Traefik container... "
if docker ps --format "{{.Names}}" | grep -q "traefik-traefik"; then
    echo -e "${GREEN}✅ Running${NC}"
else
    echo -e "${RED}❌ Not running${NC}"
fi

echo -n "• Registry container... "
if docker ps --format "{{.Names}}" | grep -q "registry"; then
    echo -e "${GREEN}✅ Running${NC}"
else
    echo -e "${RED}❌ Not running${NC}"
fi

echo -n "• Airflow containers... "
AIRFLOW_COUNT=$(docker ps --format "{{.Names}}" | grep -c airflow || echo 0)
if [ "$AIRFLOW_COUNT" -gt 0 ]; then
    echo -e "${GREEN}✅ $AIRFLOW_COUNT running${NC}"
else
    echo -e "${YELLOW}⚠️  None running${NC}"
fi

# ============================================================================
# Summary
# ============================================================================
echo
echo -e "${BLUE}📊 TEST SUMMARY${NC}"
echo "==============="
echo
echo "Total Tests: $TOTAL_TESTS"
echo -e "Passed: ${GREEN}$PASSED_TESTS${NC}"
echo -e "Failed: ${RED}$FAILED_TESTS${NC}"
echo

if [ "$FAILED_TESTS" -eq 0 ]; then
    echo -e "${GREEN}🎉 ALL TESTS PASSED!${NC}"
    echo
    echo "Your browser should be able to access:"
    echo "• https://traefik.localhost"
    echo "• https://registry.localhost"
    echo "• https://airflow.localhost (if deployed)"
    echo
    echo "Without any certificate warnings!"
    exit 0
else
    echo -e "${RED}❌ SOME TESTS FAILED${NC}"
    echo
    echo "Browser access will likely show certificate warnings."
    echo
    echo -e "${BLUE}Troubleshooting:${NC}"

    # Check for common issues
    if docker ps --format "{{.Names}}" | grep -q "traefik-traefik"; then
        # Traefik is running, so it's likely a certificate issue
        echo "1. Certificate trust issue detected"
        echo "   Run: ./scripts/diagnose-certificate-state.sh"
        echo
        echo "2. If Windows has multiple CAs:"
        echo "   Run: ./scripts/cleanup-duplicate-cas.sh"
        echo
        echo "3. Install CA in Windows (PowerShell):"
        echo "   mkcert -install"
    else
        # Traefik not running
        echo "1. Traefik not running"
        echo "   Run: cd ~/platform-services/traefik && docker compose up -d"
    fi

    echo
    echo "After fixing, run this test again to verify."
    exit 1
fi
