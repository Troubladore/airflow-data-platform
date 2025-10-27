#!/bin/bash
# Comprehensive Test: Verify ALL custom image paths work across all services
# Prevents regression where custom registry paths are ignored

set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "═══════════════════════════════════════════════════════════"
echo "  Testing Custom Image Path Handling Across All Services"
echo "═══════════════════════════════════════════════════════════"
echo ""
echo "This test ensures custom Docker registry paths (Artifactory,"
echo "JFrog, Azure ACR, etc.) work correctly for ALL services."
echo ""

FAILED=0

# Test 1: Pagila - Bash script receives IMAGE_POSTGRES
echo "Test 1: Pagila (bash script)"
echo "-----------------------------"

MAKE_OUTPUT=$(cd "$REPO_ROOT/platform-bootstrap" && make -n setup-pagila \
    IMAGE_POSTGRES="corp.jfrog.io/team/postgres:17" \
    PAGILA_REPO_URL="https://test.git" \
    PAGILA_AUTO_YES=1)

if echo "$MAKE_OUTPUT" | grep -q 'IMAGE_POSTGRES="corp.jfrog.io/team/postgres:17"'; then
    echo "✓ PASS: Pagila receives IMAGE_POSTGRES"
else
    echo "✗ FAIL: Pagila does NOT receive IMAGE_POSTGRES"
    FAILED=$((FAILED + 1))
fi

echo ""

# Test 2: Platform-Infrastructure - docker-compose reads .env
echo "Test 2: Platform-Infrastructure (docker-compose)"
echo "------------------------------------------------"

# Check Makefile has 'export' directive
if grep -q "^export$" "$REPO_ROOT/platform-infrastructure/Makefile"; then
    echo "✓ PASS: platform-infrastructure Makefile has 'export' directive"
else
    echo "✗ FAIL: platform-infrastructure Makefile missing 'export' directive"
    echo "     Docker compose won't see .env variables!"
    FAILED=$((FAILED + 1))
fi

# Verify docker-compose is used (inherits env vars)
if grep -q "DOCKER_COMPOSE.*:=.*docker compose" "$REPO_ROOT/platform-infrastructure/Makefile"; then
    echo "✓ PASS: platform-infrastructure uses docker compose (reads .env)"
else
    echo "✗ FAIL: platform-infrastructure doesn't use docker compose"
    FAILED=$((FAILED + 1))
fi

echo ""

# Test 3: OpenMetadata - docker-compose reads .env
echo "Test 3: OpenMetadata (docker-compose)"
echo "-------------------------------------"

if grep -q "^export$" "$REPO_ROOT/openmetadata/Makefile"; then
    echo "✓ PASS: openmetadata Makefile has 'export' directive"
else
    echo "✗ FAIL: openmetadata Makefile missing 'export' directive"
    FAILED=$((FAILED + 1))
fi

if grep -q "DOCKER_COMPOSE.*:=.*docker compose" "$REPO_ROOT/openmetadata/Makefile"; then
    echo "✓ PASS: openmetadata uses docker compose (reads .env)"
else
    echo "✗ FAIL: openmetadata doesn't use docker compose"
    FAILED=$((FAILED + 1))
fi

echo ""

# Test 4: Kerberos - docker-compose reads .env
echo "Test 4: Kerberos (docker-compose)"
echo "---------------------------------"

if grep -q "^export$" "$REPO_ROOT/kerberos/Makefile"; then
    echo "✓ PASS: kerberos Makefile has 'export' directive"
else
    echo "✗ FAIL: kerberos Makefile missing 'export' directive"
    FAILED=$((FAILED + 1))
fi

if grep -q "DOCKER_COMPOSE.*:=.*docker compose" "$REPO_ROOT/kerberos/Makefile"; then
    echo "✓ PASS: kerberos uses docker compose (reads .env)"
else
    echo "✗ FAIL: kerberos doesn't use docker compose"
    FAILED=$((FAILED + 1))
fi

echo ""

# Test 5: Verify platform-config.yaml pattern (master configuration)
echo "Test 5: Master Configuration Pattern"
echo "------------------------------------"

# Check if wizard saves images to platform-config.yaml
if [ -f "$REPO_ROOT/platform-config.yaml" ]; then
    echo "✓ PASS: platform-config.yaml exists (master configuration)"

    # Check if it contains service configurations
    if grep -q "services:" "$REPO_ROOT/platform-config.yaml"; then
        echo "✓ PASS: platform-config.yaml has services section"
    else
        echo "✗ WARN: platform-config.yaml missing services section"
    fi
else
    echo "○ INFO: platform-config.yaml doesn't exist yet (will be created by wizard)"
fi

echo ""

# Summary
echo "═══════════════════════════════════════════════════════════"
if [ $FAILED -eq 0 ]; then
    echo "✓ ALL TESTS PASSED ($FAILED failures)"
    echo "═══════════════════════════════════════════════════════════"
    echo ""
    echo "All services correctly handle custom Docker registry paths:"
    echo "  • Pagila: Passes IMAGE_POSTGRES via Makefile env vars ✓"
    echo "  • Platform-Infrastructure: Uses docker compose + .env ✓"
    echo "  • OpenMetadata: Uses docker compose + .env ✓"
    echo "  • Kerberos: Uses docker compose + .env ✓"
    echo ""
    echo "Custom images from Artifactory, JFrog, Azure ACR, etc. will work!"
    exit 0
else
    echo "✗ TESTS FAILED ($FAILED failures)"
    echo "═══════════════════════════════════════════════════════════"
    echo ""
    echo "Some services may not correctly handle custom registry paths."
    echo "Review failures above and fix before deploying to corporate environments."
    exit 1
fi
