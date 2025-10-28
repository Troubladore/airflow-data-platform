#!/bin/bash
# Test script for Pagila corporate image handling

set -e

# Test function
test_pagila_with_corporate_image() {
    echo "Testing Pagila with corporate image..."

    # Set corporate image
    export IMAGE_POSTGRES="mycorp.jfrog.io/docker-mirror/mycorp-approved-images/postgres/17.5:2025.10.01"

    # Check if image exists locally
    if docker image inspect "$IMAGE_POSTGRES" >/dev/null 2>&1; then
        echo "✓ Corporate image exists locally: $IMAGE_POSTGRES"
    else
        echo "✗ Corporate image not found locally: $IMAGE_POSTGRES"
        echo "  Creating mock image..."
        docker tag postgres:17.5-alpine "$IMAGE_POSTGRES"
    fi

    # Test Pagila setup (dry run)
    echo "Would start Pagila with image: $IMAGE_POSTGRES"

    # Check if docker compose would pull
    echo "Checking if Docker would try to pull..."
    if echo "$IMAGE_POSTGRES" | grep -q '/'; then
        echo "  ⚠ Corporate registry image detected"
        echo "  Docker compose/run will try to pull if not found locally"
        echo "  Solution: Check if image exists locally first"
    else
        echo "  Standard Docker Hub image - will pull if needed"
    fi
}

# Run test
test_pagila_with_corporate_image