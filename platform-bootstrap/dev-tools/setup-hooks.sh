#!/bin/bash
# Setup Git Hooks for Platform Bootstrap
# =======================================
# Installs pre-push hook to prevent shipping broken scripts

set -e

# Find script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLATFORM_DIR="$(dirname "$SCRIPT_DIR")"
if [ -f "$PLATFORM_DIR/lib/formatting.sh" ]; then
    source "$PLATFORM_DIR/lib/formatting.sh"
else
    # Fallback if library not found
    echo "Warning: formatting library not found, using basic output" >&2
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    CYAN='\033[0;36m'
    NC='\033[0m'
fi

print_header "Git Hooks Setup for Platform Bootstrap"
echo ""

# Check if we're in a git repository
if [ ! -d "$PLATFORM_DIR/.git" ] && [ ! -d "$PLATFORM_DIR/../.git" ]; then
    print_check "WARN" "Not in a git repository"
    echo "This script should be run from the platform-bootstrap directory"
    exit 1
fi

# Configure git to use our hooks directory
print_check "INFO" "Configuring git to use .githooks directory..."
git config core.hooksPath "$PLATFORM_DIR/.githooks"

print_check "PASS" "Git configured to use .githooks/"
echo ""

# List available hooks
print_section "Available Hooks"
if [ -f "$PLATFORM_DIR/.githooks/pre-commit" ]; then
    print_check "PASS" "pre-commit - Prevents direct commits to main branch"
else
    print_check "WARN" "pre-commit - Not found"
fi
if [ -f "$PLATFORM_DIR/.githooks/pre-push" ]; then
    print_check "PASS" "pre-push - Validates all scripts before push"
else
    print_check "WARN" "pre-push - Not found"
fi
echo ""

# Test the hooks
print_section "Testing Hooks"
if [ -x "$PLATFORM_DIR/.githooks/pre-commit" ]; then
    print_check "PASS" "pre-commit hook is executable"
else
    print_check "FAIL" "pre-commit hook is not executable"
    echo "  Run: chmod +x $PLATFORM_DIR/.githooks/pre-commit"
fi

if [ -x "$PLATFORM_DIR/.githooks/pre-push" ]; then
    print_check "PASS" "pre-push hook is executable"

    # Run a quick validation
    echo ""
    print_check "INFO" "Running validation test..."
    if "$PLATFORM_DIR/.githooks/pre-push" > /dev/null 2>&1; then
        print_check "PASS" "Validation passed - your scripts are demo-safe!"
    else
        print_check "WARN" "Some scripts have issues - run $PLATFORM_DIR/tests/dry-run-all-scripts.sh for details"
    fi
else
    print_check "FAIL" "pre-push hook is not executable"
    echo "  Run: chmod +x $PLATFORM_DIR/.githooks/pre-push"
fi

echo ""
print_status "Setup complete!"
echo ""
echo "The hooks will now run automatically:"
print_bullet "pre-commit: Blocks direct commits to main"
print_bullet "pre-push: Validates scripts before pushing"
echo ""
print_section "Hook Management"
echo "To bypass hooks (not recommended):"
echo "  git push --no-verify"
echo ""
echo "To disable hooks temporarily:"
echo "  git config core.hooksPath .git/hooks"
echo ""
echo "To re-enable hooks:"
echo "  git config core.hooksPath .githooks"