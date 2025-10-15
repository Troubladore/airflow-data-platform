#!/bin/bash
# Setup Git Hooks for Platform Bootstrap
# =======================================
# Installs pre-push hook to prevent shipping broken scripts

set -e

# Find script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors for output
if [ -t 1 ] && [ -z "${NO_COLOR}" ]; then
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    CYAN='\033[0;36m'
    NC='\033[0m'
else
    GREEN=''
    YELLOW=''
    CYAN=''
    NC=''
fi

echo "Git Hooks Setup for Platform Bootstrap"
echo "======================================="
echo ""

# Check if we're in a git repository
if [ ! -d "$SCRIPT_DIR/.git" ]; then
    echo -e "${YELLOW}Warning: Not in a git repository${NC}"
    echo "This script should be run from the platform-bootstrap directory"
    exit 1
fi

# Configure git to use our hooks directory
echo "Configuring git to use .githooks directory..."
git config core.hooksPath .githooks

echo -e "${GREEN}✓${NC} Git configured to use .githooks/"
echo ""

# List available hooks
echo "Available hooks:"
if [ -f "$SCRIPT_DIR/.githooks/pre-push" ]; then
    echo -e "  ${GREEN}✓${NC} pre-push - Validates all scripts before push"
else
    echo -e "  ${YELLOW}⚠${NC} pre-push - Not found"
fi
echo ""

# Test the pre-push hook
echo "Testing pre-push hook..."
if [ -x "$SCRIPT_DIR/.githooks/pre-push" ]; then
    echo -e "${GREEN}✓${NC} pre-push hook is executable"

    # Run a quick validation
    echo ""
    echo "Running validation test..."
    if "$SCRIPT_DIR/.githooks/pre-push" > /dev/null 2>&1; then
        echo -e "${GREEN}✓${NC} Validation passed - your scripts are demo-safe!"
    else
        echo -e "${YELLOW}⚠${NC} Some scripts have issues - run ./tests/dry-run-all-scripts.sh for details"
    fi
else
    echo -e "${YELLOW}⚠${NC} pre-push hook is not executable"
    echo "  Run: chmod +x .githooks/pre-push"
fi

echo ""
echo -e "${CYAN}Setup complete!${NC}"
echo ""
echo "The pre-push hook will now run automatically before each push."
echo "It ensures all scripts pass validation tests before deployment."
echo ""
echo "To bypass the hook (not recommended):"
echo "  git push --no-verify"
echo ""
echo "To disable hooks temporarily:"
echo "  git config core.hooksPath .git/hooks"
echo ""
echo "To re-enable hooks:"
echo "  git config core.hooksPath .githooks"