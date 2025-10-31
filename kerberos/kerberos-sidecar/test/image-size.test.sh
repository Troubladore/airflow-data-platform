#!/bin/bash
# Test: Minimal sidecar image size < 60 MB
# Expected: FAIL (current image is 312 MB)

set -e

IMAGE="${IMAGE_NAME:-platform/kerberos-sidecar}:minimal"

echo "========================================"
echo "TEST: Minimal Sidecar Image Size"
echo "========================================"
echo ""

# Check if image exists
if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
    echo "✗ FAIL: Image not found: $IMAGE"
    echo ""
    echo "Build the minimal image first:"
    echo "  cd kerberos-sidecar"
    echo "  docker build -f Dockerfile.minimal -t $IMAGE ."
    echo ""
    exit 1
fi

# Get image size in MB
SIZE_BYTES=$(docker image inspect "$IMAGE" --format='{{.Size}}')
SIZE_MB=$(echo "scale=2; $SIZE_BYTES / 1024 / 1024" | bc)

echo "Image: $IMAGE"
echo "Size: ${SIZE_MB} MB"
echo ""

# Test: Size must be < 60 MB
MAX_SIZE=60
if (( $(echo "$SIZE_MB > $MAX_SIZE" | bc -l) )); then
    echo "✗ FAIL: Image too large (${SIZE_MB} MB > ${MAX_SIZE} MB)"
    echo ""
    echo "Expected: Minimal sidecar < 60 MB"
    echo "Actual: ${SIZE_MB} MB"
    echo ""
    echo "Common causes:"
    echo "  - Build tools included (gcc, g++, musl-dev)"
    echo "  - ODBC/SQL tools included (msodbcsql18, mssql-tools18)"
    echo "  - Python packages included"
    echo "  - Development headers (*-dev packages)"
    echo ""
    exit 1
else
    echo "✓ PASS: Image size acceptable (${SIZE_MB} MB < ${MAX_SIZE} MB)"
    echo ""
    exit 0
fi
