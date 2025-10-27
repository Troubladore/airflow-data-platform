#!/bin/bash
# Quick smoke test - 30 seconds
# Tests: Postgres only, all defaults

set -e

echo "QUICK SMOKE TEST - Postgres Only"
echo "================================="

# Clean
docker ps -q | xargs -r docker stop >/dev/null 2>&1
docker ps -aq | xargs -r docker rm >/dev/null 2>&1

# Run wizard
echo -e "n\nn\nn\n\nn\nn\n5432\n" | timeout 60 ./platform setup >/dev/null 2>&1

# Verify
if docker ps | grep -q platform-postgres; then
    echo "✓ PASS: Container created"
    docker rm -f platform-postgres >/dev/null 2>&1
    exit 0
else
    echo "✗ FAIL: No container"
    exit 1
fi
