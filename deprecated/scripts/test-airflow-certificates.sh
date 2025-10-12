#!/bin/bash
# Test Airflow HTTPS certificate trust
# Creates a minimal Airflow deployment to validate platform certificates

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TEST_DIR="$REPO_ROOT/test-airflow-certs"
REGISTRY_HOST="registry.localhost"

echo -e "${BLUE}🚀 AIRFLOW CERTIFICATE VALIDATION TEST${NC}"
echo "========================================"
echo
echo "This test will:"
echo "• Create a minimal Airflow deployment"
echo "• Build and push image to local registry"
echo "• Start Airflow with Traefik integration"
echo "• Verify HTTPS works without certificate warnings"
echo

# Step 1: Create test deployment directory
echo -e "${BLUE}Step 1: Setting up test deployment${NC}"
rm -rf "$TEST_DIR"
mkdir -p "$TEST_DIR"
cd "$TEST_DIR"

# Step 2: Initialize Astro project
echo -e "${BLUE}Step 2: Initializing Airflow project${NC}"
astro dev init --name test-certs

# Step 2.5: Update Dockerfile to use platform base image
echo -e "${BLUE}Step 2.5: Configuring to use platform base image${NC}"
cat > Dockerfile << 'EOF'
FROM registry.localhost/platform/airflow-base:3.0-10
EOF

# Step 3: Create docker-compose.override.yml for Traefik
echo -e "${BLUE}Step 3: Configuring Traefik integration${NC}"
cat > docker-compose.override.yml << 'EOF'
version: "3.8"

networks:
  edge:
    external: true
  airflow:
    name: test-airflow-net

services:
  webserver:
    networks:
      - airflow
      - edge
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.airflow-test.rule=Host(`airflow.localhost`)"
      - "traefik.http.routers.airflow-test.entrypoints=websecure"
      - "traefik.http.routers.airflow-test.tls=true"
      - "traefik.http.services.airflow-test.loadbalancer.server.port=8080"
      - "traefik.docker.network=edge"

  scheduler:
    networks:
      - airflow

  postgres:
    networks:
      - airflow

  triggerer:
    networks:
      - airflow
EOF

# Step 4: Build Airflow image
echo -e "${BLUE}Step 4: Building Airflow image${NC}"
docker build -t "$REGISTRY_HOST/airflow-test:latest" .

# Step 5: Test registry push
echo -e "${BLUE}Step 5: Testing registry push${NC}"
if docker push "$REGISTRY_HOST/airflow-test:latest"; then
    echo -e "${GREEN}✅ Image pushed to registry successfully${NC}"

    # Verify it's in the registry
    if curl -s "https://$REGISTRY_HOST/v2/_catalog" | grep -q "airflow-test"; then
        echo -e "${GREEN}✅ Image verified in registry catalog${NC}"
    fi
else
    echo -e "${YELLOW}⚠️  Registry push failed (non-critical for certificate test)${NC}"
fi

# Step 6: Start Airflow
echo -e "${BLUE}Step 6: Starting Airflow${NC}"
astro dev start --wait 5m

# Give it a moment to stabilize
sleep 10

# Step 7: Test HTTPS access
echo -e "${BLUE}Step 7: Testing HTTPS certificate trust${NC}"
echo

# Test with curl
echo -n "• Testing with curl... "
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 10 https://airflow.localhost 2>/dev/null || echo "000")
if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ]; then
    echo -e "${GREEN}✅ HTTPS works (HTTP $HTTP_CODE)${NC}"
elif [ "$HTTP_CODE" = "000" ]; then
    echo -e "${RED}❌ SSL certificate error${NC}"
else
    echo -e "${YELLOW}⚠️  HTTP $HTTP_CODE${NC}"
fi

# Test certificate verification
echo -n "• Verifying certificate chain... "
CERT_CHECK=$(echo | openssl s_client -connect airflow.localhost:443 -servername airflow.localhost 2>&1 | grep "Verify return code")
if [[ "$CERT_CHECK" == *"Verify return code: 0"* ]]; then
    echo -e "${GREEN}✅ Valid certificate chain${NC}"
else
    echo -e "${RED}❌ Certificate verification failed${NC}"
fi

# Test with Node.js browser simulation
if command -v node >/dev/null 2>&1; then
    echo -n "• Browser simulation test... "
    cat > /tmp/airflow_browser_test.js << 'EOF'
const https = require('https');
const options = {
    hostname: 'airflow.localhost',
    port: 443,
    path: '/',
    method: 'GET',
    rejectUnauthorized: true
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

    RESULT=$(timeout 10 node /tmp/airflow_browser_test.js 2>&1 || echo "ERROR:FAILED")
    if [[ "$RESULT" == *"SUCCESS"* ]]; then
        echo -e "${GREEN}✅ Browser would trust certificate${NC}"
    else
        echo -e "${RED}❌ Browser would show certificate warning${NC}"
    fi
    rm -f /tmp/airflow_browser_test.js
fi

echo
echo -e "${BLUE}Step 8: Cleanup options${NC}"
echo "-------------------------------"
echo
echo "Test deployment is running at:"
echo "• https://airflow.localhost (should work without certificate warnings!)"
echo
echo "Default credentials:"
echo "• Username: admin"
echo "• Password: admin"
echo
echo "To stop and clean up:"
echo "  cd $TEST_DIR && astro dev stop"
echo "  rm -rf $TEST_DIR"
echo
echo "Or keep it running to test in your browser!"
echo

# Summary
echo -e "${BLUE}📊 TEST SUMMARY${NC}"
echo "==============="
if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ]; then
    echo -e "${GREEN}🎉 AIRFLOW HTTPS IS WORKING!${NC}"
    echo
    echo "You can now access https://airflow.localhost in your browser"
    echo "without any certificate warnings!"
    exit 0
else
    echo -e "${RED}❌ Certificate trust issue detected${NC}"
    echo
    echo "Run these diagnostics:"
    echo "1. ./scripts/diagnose-certificate-state.sh"
    echo "2. ./scripts/test-certificate-trust.sh"
    exit 1
fi
