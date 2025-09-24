#!/bin/bash
# Comprehensive Platform Validation Test Suite
# Validates that the entire platform setup is complete and functional

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Test results tracking
TESTS_PASSED=0
TESTS_FAILED=0
FAILURES=""

# Function to run a test
run_test() {
    local test_name="$1"
    local test_command="$2"
    local expected="$3"

    echo -n "• $test_name... "

    if result=$(eval "$test_command" 2>&1); then
        if [[ "$expected" == "" ]] || [[ "$result" == *"$expected"* ]]; then
            echo -e "${GREEN}✅${NC}"
            TESTS_PASSED=$((TESTS_PASSED + 1))
            return 0
        fi
    fi

    echo -e "${RED}❌${NC}"
    TESTS_FAILED=$((TESTS_FAILED + 1))
    FAILURES="${FAILURES}\n  ❌ $test_name: $result"
    return 1
}

echo -e "${BLUE}🧪 COMPREHENSIVE PLATFORM VALIDATION TEST SUITE${NC}"
echo "================================================="
echo

# ============================================================================
# SECTION 1: INFRASTRUCTURE COMPONENTS
# ============================================================================
echo -e "${BLUE}1️⃣ Infrastructure Components${NC}"
echo "------------------------------"

# Check Docker is running
run_test "Docker daemon running" \
    "docker info --format '{{.ServerVersion}}' | grep -q ." \
    ""

# Check Docker Compose version
run_test "Docker Compose available" \
    "docker compose version --short | grep -q ." \
    ""

# Check edge network exists and is owned by Traefik
run_test "Edge network exists" \
    "docker network inspect edge --format='{{.Name}}'" \
    "edge"

run_test "Edge network owned by Traefik" \
    "docker network inspect edge --format='{{index .Labels \"com.docker.compose.project\"}}'" \
    "traefik"

# Check Traefik is running
run_test "Traefik container running" \
    "docker ps --filter 'name=traefik-traefik' --format '{{.Status}}' | grep -q 'Up'" \
    ""

# Check Registry is running
run_test "Registry container running" \
    "docker ps --filter 'name=traefik-registry' --format '{{.Status}}' | grep -q 'Up'" \
    ""

# Check both are on edge network
run_test "Traefik on edge network" \
    "docker inspect traefik-traefik-1 --format='{{range \$key, \$value := .NetworkSettings.Networks}}{{if eq \$key \"edge\"}}found{{end}}{{end}}'" \
    "found"

run_test "Registry on edge network" \
    "docker inspect traefik-registry-1 --format='{{range \$key, \$value := .NetworkSettings.Networks}}{{if eq \$key \"edge\"}}found{{end}}{{end}}'" \
    "found"

echo

# ============================================================================
# SECTION 2: CERTIFICATES AND HTTPS
# ============================================================================
echo -e "${BLUE}2️⃣ Certificates and HTTPS${NC}"
echo "--------------------------"

# Check certificate files exist
run_test "Certificate files exist in WSL2" \
    "test -f /home/troubladore/.local/share/certs/dev-localhost-wild.crt && echo 'exists'" \
    "exists"

run_test "Certificate key exists in WSL2" \
    "test -f /home/troubladore/.local/share/certs/dev-localhost-wild.key && echo 'exists'" \
    "exists"

# Test HTTPS without certificate warnings (302 is OK for Traefik dashboard redirect)
run_test "Traefik HTTPS (no cert warning)" \
    "curl -s -o /dev/null -w '%{http_code}' https://traefik.localhost | grep -E '200|302' && echo 'ok'" \
    "ok"

run_test "Registry HTTPS (no cert warning)" \
    "curl -s -o /dev/null -w '%{http_code}' https://registry.localhost/v2/" \
    "200"

# Verify certificate chain
run_test "Traefik certificate valid" \
    "echo | openssl s_client -connect traefik.localhost:443 -servername traefik.localhost 2>&1 | grep 'Verify return code: 0' | head -1 | grep -q '0' && echo 'valid'" \
    "valid"

run_test "Registry certificate valid" \
    "echo | openssl s_client -connect registry.localhost:443 -servername registry.localhost 2>&1 | grep 'Verify return code: 0' | head -1 | grep -q '0' && echo 'valid'" \
    "valid"

echo

# ============================================================================
# SECTION 3: PLATFORM IMAGES
# ============================================================================
echo -e "${BLUE}3️⃣ Platform Images${NC}"
echo "-------------------"

# Check platform Airflow base image exists with BOTH required tags
run_test "Platform image exists in registry" \
    "curl -s https://registry.localhost/v2/platform/airflow-base/tags/list | grep -q 'platform/airflow-base' && echo 'found'" \
    "found"

run_test "Platform image has 3.0-10 tag" \
    "curl -s https://registry.localhost/v2/platform/airflow-base/tags/list | python3 -c \"import sys, json; tags = json.load(sys.stdin).get('tags', []); print('found' if '3.0-10' in tags else 'missing: ' + str(tags))\"" \
    "found"

run_test "Platform image has latest tag" \
    "curl -s https://registry.localhost/v2/platform/airflow-base/tags/list | python3 -c \"import sys, json; tags = json.load(sys.stdin).get('tags', []); print('found' if 'latest' in tags else 'missing: ' + str(tags))\"" \
    "found"

# Verify BOTH tags are present (critical test)
run_test "Platform image has ALL required tags" \
    "curl -s https://registry.localhost/v2/platform/airflow-base/tags/list | python3 -c \"import sys, json; tags = set(json.load(sys.stdin).get('tags', [])); required = {'3.0-10', 'latest'}; print('complete' if required.issubset(tags) else f'incomplete: has {tags}, needs {required}')\"" \
    "complete"

# Test pulling the image
run_test "Platform image is pullable" \
    "docker pull registry.localhost/platform/airflow-base:3.0-10 2>&1 | grep -E '(Downloaded|Image is up to date)' | head -1 | grep -q . && echo 'success'" \
    "success"

echo

# ============================================================================
# SECTION 4: HOST ENTRIES
# ============================================================================
echo -e "${BLUE}4️⃣ Host Entries${NC}"
echo "----------------"

# Check host entries
run_test "traefik.localhost resolves" \
    "getent hosts traefik.localhost | grep -q '127.0.0.1' && echo 'resolved'" \
    "resolved"

run_test "registry.localhost resolves" \
    "getent hosts registry.localhost | grep -q '127.0.0.1' && echo 'resolved'" \
    "resolved"

run_test "airflow.localhost resolves" \
    "getent hosts airflow.localhost | grep -q '127.0.0.1' && echo 'resolved'" \
    "resolved"

echo

# ============================================================================
# SECTION 5: AIRFLOW DEPLOYMENT TEST
# ============================================================================
echo -e "${BLUE}5️⃣ Airflow Deployment Test${NC}"
echo "---------------------------"

# Create a minimal Airflow test
TEST_DIR="/tmp/airflow-validation-$$"
echo "Creating test Airflow deployment in $TEST_DIR..."

mkdir -p "$TEST_DIR"
cd "$TEST_DIR"

# Initialize Astro project
if astro dev init --name validation-test >/dev/null 2>&1; then
    echo -e "  ${GREEN}✓${NC} Astro project initialized"
else
    echo -e "  ${RED}✗${NC} Failed to initialize Astro project"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Update Dockerfile to use platform image
cat > Dockerfile << 'EOF'
FROM registry.localhost/platform/airflow-base:3.0-10
EOF

# Create docker-compose.override.yml for Traefik
cat > docker-compose.override.yml << 'EOF'
networks:
  edge:
    external: true

services:
  api-server:
    networks:
      - default
      - edge
    environment:
      - AIRFLOW__WEBSERVER__WEB_SERVER_HOST=0.0.0.0
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.airflow-validation.rule=Host(`airflow.localhost`)"
      - "traefik.http.routers.airflow-validation.entrypoints=websecure"
      - "traefik.http.routers.airflow-validation.tls=true"
      - "traefik.http.services.airflow-validation.loadbalancer.server.port=8080"
      - "traefik.docker.network=edge"
EOF

# Start Airflow
echo "Starting Airflow (this may take a moment)..."
if astro dev start --wait 3m >/dev/null 2>&1; then
    echo -e "  ${GREEN}✓${NC} Airflow started successfully"
    TESTS_PASSED=$((TESTS_PASSED + 1))

    # Wait for services to stabilize
    sleep 10

    # Test HTTPS access to Airflow
    run_test "Airflow HTTPS accessible" \
        "curl -s -o /dev/null -w '%{http_code}' --connect-timeout 10 https://airflow.localhost" \
        "200"

    # Test certificate validity for Airflow
    run_test "Airflow certificate valid" \
        "curl -sv https://airflow.localhost 2>&1 | grep -q 'SSL certificate verify ok' && echo 'valid'" \
        "valid"

    # Test that API is responding
    run_test "Airflow API health check" \
        "curl -s http://localhost:8080/api/v2/monitor/health | grep -q 'healthy' && echo 'healthy'" \
        "healthy"

    # Clean up
    echo "Stopping test Airflow deployment..."
    astro dev stop >/dev/null 2>&1
else
    echo -e "  ${RED}✗${NC} Failed to start Airflow"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Clean up test directory
cd /
rm -rf "$TEST_DIR"

echo

# ============================================================================
# SECTION 6: BROWSER SIMULATION
# ============================================================================
echo -e "${BLUE}6️⃣ Browser Simulation Tests${NC}"
echo "----------------------------"

# Create Node.js browser simulation test
cat > /tmp/browser_test.js << 'EOF'
const https = require('https');
const services = ['traefik.localhost', 'registry.localhost', 'airflow.localhost'];
let passed = 0;
let failed = 0;

function testService(hostname) {
    return new Promise((resolve) => {
        const options = {
            hostname: hostname,
            port: 443,
            path: '/',
            method: 'GET',
            rejectUnauthorized: true,
            timeout: 5000
        };

        const req = https.request(options, (res) => {
            console.log(`  ✅ ${hostname}: Certificate trusted (HTTP ${res.statusCode})`);
            passed++;
            resolve(true);
        });

        req.on('error', (e) => {
            if (e.code === 'ENOTFOUND') {
                console.log(`  ⚠️  ${hostname}: DNS resolution failed (needs hosts entry)`);
            } else if (e.code === 'UNABLE_TO_VERIFY_LEAF_SIGNATURE') {
                console.log(`  ❌ ${hostname}: Certificate not trusted`);
            } else {
                console.log(`  ❌ ${hostname}: ${e.code}`);
            }
            failed++;
            resolve(false);
        });

        req.setTimeout(5000, () => {
            console.log(`  ❌ ${hostname}: Timeout`);
            failed++;
            req.destroy();
            resolve(false);
        });

        req.end();
    });
}

async function runTests() {
    for (const service of services) {
        await testService(service);
    }

    console.log(`\nBrowser simulation: ${passed} passed, ${failed} failed`);
    process.exit(failed > 0 ? 1 : 0);
}

runTests();
EOF

if command -v node >/dev/null 2>&1; then
    node /tmp/browser_test.js
    if [ $? -eq 0 ]; then
        TESTS_PASSED=$((TESTS_PASSED + 3))
    else
        TESTS_FAILED=$((TESTS_FAILED + 3))
    fi
else
    echo "  ⚠️  Node.js not installed - skipping browser simulation"
fi

rm -f /tmp/browser_test.js

echo

# ============================================================================
# FINAL SUMMARY
# ============================================================================
echo -e "${BLUE}📊 TEST SUMMARY${NC}"
echo "==============="
echo
echo -e "Tests Passed: ${GREEN}$TESTS_PASSED${NC}"
echo -e "Tests Failed: ${RED}$TESTS_FAILED${NC}"

if [ $TESTS_FAILED -gt 0 ]; then
    echo
    echo -e "${RED}❌ PLATFORM VALIDATION FAILED${NC}"
    echo
    echo "Failed tests:"
    echo -e "$FAILURES"
    echo
    echo "Troubleshooting:"
    echo "1. Check platform setup: ansible-playbook -i ansible/inventory/local-dev.ini ansible/site.yml"
    echo "2. Verify Docker is running: docker info"
    echo "3. Check service logs: docker compose logs -f --tail=50 (in ~/platform-services/traefik)"
    echo "4. Ensure hosts entries are added (Windows admin required)"
    exit 1
else
    echo
    echo -e "${GREEN}🎉 ALL PLATFORM VALIDATION TESTS PASSED!${NC}"
    echo
    echo "The platform is fully operational with:"
    echo "✅ Edge network owned by Traefik"
    echo "✅ HTTPS working without certificate warnings"
    echo "✅ Platform Airflow images available"
    echo "✅ Host entries configured"
    echo "✅ Airflow deployable with HTTPS"
    echo
    echo "You can now deploy Airflow projects with full HTTPS support!"
    exit 0
fi
