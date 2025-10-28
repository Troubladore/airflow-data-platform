#!/bin/bash
# Enhanced path diagnostics for "No such file or directory" errors
# =================================================================
# This script traces exactly where commands are running and what they're trying to access

# Don't use set -e so we can capture all errors
set +e

# Enable trace mode to see each command
set -x

# Find repo root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "=== STARTING IN DIRECTORY: $SCRIPT_DIR ==="

# Function to show current directory context
show_context() {
    echo ""
    echo ">>> CURRENT CONTEXT:"
    echo "    PWD: $(pwd)"
    echo "    SCRIPT_DIR: $SCRIPT_DIR"
    echo "    Listing current directory:"
    ls -la | head -5
    echo ""
}

echo "============================================"
echo "PATH RESOLUTION DIAGNOSTICS"
echo "============================================"

# 1. Where are we starting?
echo ""
echo "1. INITIAL LOCATION:"
show_context

# 2. Check if we can get to platform-infrastructure
echo "2. TRYING TO CD TO platform-infrastructure:"
cd "$SCRIPT_DIR/platform-infrastructure" 2>&1 || {
    echo "FAILED! Error: $?"
    echo "This could cause 'No such file or directory'"

    # Try alternate paths
    echo "Trying from parent directory..."
    cd "$SCRIPT_DIR"
    ls -la | grep platform
}
show_context

# 3. Check symlink resolution
echo "3. CHECKING .env SYMLINK:"
if [ -L .env ]; then
    echo ".env is a symlink"
    echo "Points to: $(readlink .env)"
    echo "Resolves to: $(realpath .env 2>&1)"

    # Check if target exists
    if [ -e .env ]; then
        echo "Target EXISTS"
    else
        echo "TARGET MISSING! - This would cause 'No such file or directory'"
    fi
else
    echo ".env is not a symlink or doesn't exist"
    ls -la .env 2>&1
fi

# 4. Test Make command with trace
echo ""
echo "4. TRACING MAKE COMMAND:"
echo "Current directory: $(pwd)"
echo "Running: make -d start (debug mode)"
make -d start 2>&1 | grep -E "(Entering|Leaving|No such|not found|cannot|failed)" | head -20

# Also try with shell trace
echo ""
echo "Make with shell trace:"
make SHELL='sh -x' start 2>&1 | head -30

# 5. Docker Compose path resolution
echo ""
echo "5. DOCKER COMPOSE PATH RESOLUTION:"
echo "Current directory: $(pwd)"

# Check what docker-compose is looking for
echo "Docker Compose file search:"
docker compose config --dry-run 2>&1 | grep -E "(Looking|Searching|not found|No such)"

# Show what files docker compose sees
echo ""
echo "Files Docker Compose can see:"
docker compose config --services 2>&1

# 6. Check relative path from Makefile
echo ""
echo "6. MAKEFILE PATH REFERENCES:"
if [ -f Makefile ]; then
    echo "Searching for relative paths in Makefile:"
    grep -E '\.\./|\./' Makefile | head -10

    echo ""
    echo "Searching for file operations in Makefile:"
    grep -E '(test -f|test -d|\[ -f|\[ -d|cat |source )' Makefile | head -10
fi

# 7. Test the actual docker compose command that fails
echo ""
echo "7. ACTUAL DOCKER COMPOSE COMMAND:"
echo "PWD before: $(pwd)"

# This is what the Makefile runs
DOCKER_COMPOSE="docker compose"
echo "Running: $DOCKER_COMPOSE up -d"
$DOCKER_COMPOSE up -d 2>&1 | tee /tmp/compose-output.txt

echo "PWD after: $(pwd)"

# Parse the output for path errors
echo ""
echo "8. ERROR ANALYSIS:"
if grep -q "No such file or directory" /tmp/compose-output.txt; then
    echo "FOUND 'No such file or directory' error!"
    echo "Context around error:"
    grep -B2 -A2 "No such file or directory" /tmp/compose-output.txt

    # Try to identify what file is missing
    echo ""
    echo "Attempting to identify missing file:"
    grep -oE '(\/[^[:space:]]+|[^[:space:]]+\.(yml|yaml|env|sh))' /tmp/compose-output.txt | sort -u
fi

# 9. Check docker-compose.yml for path references
echo ""
echo "9. DOCKER-COMPOSE.YML PATH REFERENCES:"
if [ -f docker-compose.yml ]; then
    echo "Volume mounts:"
    grep -E '(volumes:|-).*:' docker-compose.yml | grep -v '^#'

    echo ""
    echo "Build contexts:"
    grep -E '(build:|context:)' docker-compose.yml

    echo ""
    echo "Env files:"
    grep -E 'env_file:' docker-compose.yml
fi

# 10. Summary
echo ""
echo "============================================"
echo "DIAGNOSTIC SUMMARY:"
echo "============================================"

# Check each potential issue
ISSUES_FOUND=0

if [ ! -d "$SCRIPT_DIR/platform-infrastructure" ]; then
    echo "❌ platform-infrastructure directory not found from repo root"
    ISSUES_FOUND=$((ISSUES_FOUND + 1))
fi

if [ -L platform-infrastructure/.env ] && [ ! -e platform-infrastructure/.env ]; then
    echo "❌ platform-infrastructure/.env is a broken symlink"
    ISSUES_FOUND=$((ISSUES_FOUND + 1))
fi

if ! command -v docker compose &> /dev/null; then
    echo "❌ 'docker compose' command not found (might need docker-compose instead)"
    ISSUES_FOUND=$((ISSUES_FOUND + 1))
fi

if [ $ISSUES_FOUND -eq 0 ]; then
    echo "✓ No obvious path issues found"
    echo ""
    echo "The 'No such file or directory' might be from:"
    echo "  1. A script referenced in docker-compose.yml"
    echo "  2. A volume mount path that doesn't exist"
    echo "  3. An entrypoint script inside the container"
    echo "  4. A file referenced in the Makefile"
fi

echo ""
echo "Full output saved to: /tmp/compose-output.txt"
echo "To see the exact command sequence that fails, review the trace output above."