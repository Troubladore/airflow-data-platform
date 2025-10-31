#!/usr/bin/env bash
# Test: Chainguard Base Support
# Purpose: Verify Dockerfile.minimal accepts IMAGE_ALPINE build arg and works with alternative bases
# TDD Phase: RED (write failing test first)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOCKERFILE_DIR="$(dirname "$SCRIPT_DIR")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "========================================="
echo "Test: Chainguard Base Support"
echo "========================================="

# Test 1: Verify Dockerfile accepts IMAGE_ALPINE build arg
echo -e "\n${YELLOW}Test 1: Dockerfile accepts IMAGE_ALPINE build arg${NC}"
if grep -q "ARG IMAGE_ALPINE" "$DOCKERFILE_DIR/Dockerfile"; then
    echo -e "${GREEN}✓ PASS${NC}: Dockerfile has IMAGE_ALPINE build arg"
else
    echo -e "${RED}✗ FAIL${NC}: Dockerfile missing IMAGE_ALPINE build arg"
    exit 1
fi

# Verify it's used in FROM statement
if grep -q 'FROM ${IMAGE_ALPINE:-alpine:3.19}' "$DOCKERFILE_DIR/Dockerfile"; then
    echo -e "${GREEN}✓ PASS${NC}: IMAGE_ALPINE used in FROM statement with default"
else
    echo -e "${RED}✗ FAIL${NC}: IMAGE_ALPINE not properly used in FROM statement"
    exit 1
fi

# Test 2: Build with default alpine:3.19
echo -e "\n${YELLOW}Test 2: Build with default Alpine base (alpine:3.19)${NC}"
IMAGE_NAME="platform/kerberos-sidecar:test-alpine-default"
if docker build \
    -f "$DOCKERFILE_DIR/Dockerfile" \
    -t "$IMAGE_NAME" \
    "$DOCKERFILE_DIR" > /dev/null 2>&1; then
    echo -e "${GREEN}✓ PASS${NC}: Built successfully with default alpine:3.19"
else
    echo -e "${RED}✗ FAIL${NC}: Failed to build with default alpine:3.19"
    exit 1
fi

# Check image size < 60 MB
IMAGE_SIZE=$(docker image inspect "$IMAGE_NAME" --format='{{.Size}}')
IMAGE_SIZE_MB=$((IMAGE_SIZE / 1024 / 1024))
if [ "$IMAGE_SIZE_MB" -lt 60 ]; then
    echo -e "${GREEN}✓ PASS${NC}: Image size with alpine:3.19 is ${IMAGE_SIZE_MB} MB (< 60 MB)"
else
    echo -e "${RED}✗ FAIL${NC}: Image size with alpine:3.19 is ${IMAGE_SIZE_MB} MB (>= 60 MB)"
    exit 1
fi

# Cleanup
docker rmi "$IMAGE_NAME" > /dev/null 2>&1

# Test 3: Try to build with Chainguard Wolfi base (if accessible)
echo -e "\n${YELLOW}Test 3: Build with Chainguard Wolfi base (if accessible)${NC}"
CHAINGUARD_IMAGE="cgr.dev/chainguard/wolfi-base:latest"
IMAGE_NAME="platform/kerberos-sidecar:test-chainguard"

# Try to pull Chainguard image to test accessibility
echo "Attempting to pull Chainguard Wolfi base image..."
if docker pull "$CHAINGUARD_IMAGE" > /dev/null 2>&1; then
    echo -e "${GREEN}✓${NC} Chainguard image accessible, testing build..."

    # Try to build with Chainguard base
    if docker build \
        -f "$DOCKERFILE_DIR/Dockerfile" \
        --build-arg IMAGE_ALPINE="$CHAINGUARD_IMAGE" \
        -t "$IMAGE_NAME" \
        "$DOCKERFILE_DIR" > /dev/null 2>&1; then
        echo -e "${GREEN}✓ PASS${NC}: Built successfully with Chainguard Wolfi base"

        # Check image size still < 60 MB
        IMAGE_SIZE=$(docker image inspect "$IMAGE_NAME" --format='{{.Size}}')
        IMAGE_SIZE_MB=$((IMAGE_SIZE / 1024 / 1024))
        if [ "$IMAGE_SIZE_MB" -lt 60 ]; then
            echo -e "${GREEN}✓ PASS${NC}: Image size with Chainguard base is ${IMAGE_SIZE_MB} MB (< 60 MB)"
        else
            echo -e "${RED}✗ FAIL${NC}: Image size with Chainguard base is ${IMAGE_SIZE_MB} MB (>= 60 MB)"
            docker rmi "$IMAGE_NAME" > /dev/null 2>&1
            exit 1
        fi

        # Cleanup
        docker rmi "$IMAGE_NAME" > /dev/null 2>&1
    else
        echo -e "${RED}✗ FAIL${NC}: Failed to build with Chainguard Wolfi base"
        echo "Note: Chainguard base may require package name adjustments (apk vs. apk-tools)"
        exit 1
    fi
else
    echo -e "${YELLOW}⊘ SKIP${NC}: Chainguard image not accessible (may require authentication)"
    echo "Note: In corporate environments, configure registry authentication:"
    echo "  docker login cgr.dev"
    echo "  or use internal mirror: --build-arg IMAGE_ALPINE=artifactory.company.com/chainguard/wolfi-base"
fi

# Test 4: Verify corporate registry documentation exists
echo -e "\n${YELLOW}Test 4: Corporate registry usage documented${NC}"
if grep -q "Corporate Artifactory" "$DOCKERFILE_DIR/Dockerfile"; then
    echo -e "${GREEN}✓ PASS${NC}: Corporate registry support documented in Dockerfile"
else
    echo -e "${RED}✗ FAIL${NC}: Missing corporate registry documentation in Dockerfile"
    exit 1
fi

if grep -q "Chainguard" "$DOCKERFILE_DIR/Dockerfile"; then
    echo -e "${GREEN}✓ PASS${NC}: Chainguard Wolfi usage documented"
else
    echo -e "${YELLOW}⚠ WARN${NC}: Chainguard usage could be documented"
fi

if grep -q "Examples:" "$DOCKERFILE_DIR/Dockerfile"; then
    echo -e "${GREEN}✓ PASS${NC}: Build examples provided in Dockerfile"
else
    echo -e "${YELLOW}⚠ WARN${NC}: Build examples could be added"
fi

echo -e "\n${GREEN}========================================="
echo "All Chainguard Base Tests PASSED"
echo "=========================================${NC}"
echo ""
echo "Summary:"
echo "  - Dockerfile accepts IMAGE_ALPINE build arg"
echo "  - Default alpine:3.19 builds successfully (< 60 MB)"
echo "  - Chainguard Wolfi base compatible (if accessible)"
echo "  - Corporate registry usage documented"
echo ""
echo "Usage examples:"
echo "  # Default Alpine:"
echo "  docker build -f Dockerfile -t platform/kerberos-sidecar:minimal ."
echo ""
echo "  # Corporate Artifactory:"
echo "  docker build -f Dockerfile \\"
echo "    --build-arg IMAGE_ALPINE=artifactory.company.com/alpine:3.19 \\"
echo "    -t platform/kerberos-sidecar:minimal ."
echo ""
echo "  # Chainguard Wolfi (requires auth):"
echo "  docker build -f Dockerfile \\"
echo "    --build-arg IMAGE_ALPINE=cgr.dev/chainguard/wolfi-base:latest \\"
echo "    -t platform/kerberos-sidecar:minimal ."
