#!/bin/bash
# Install pinned pipx dependencies from pipx-requirements.txt
# This script can be used by setup scripts and dependency scanners

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PIPX_REQUIREMENTS="$REPO_ROOT/ansible/pipx-requirements.txt"

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}📦 Installing pipx dependencies from pipx-requirements.txt${NC}"
echo

if [ ! -f "$PIPX_REQUIREMENTS" ]; then
    echo -e "${YELLOW}⚠️  pipx-requirements.txt not found: $PIPX_REQUIREMENTS${NC}"
    exit 1
fi

# Check if pipx is available
if ! command -v pipx &> /dev/null; then
    echo -e "${YELLOW}⚠️  pipx not found. Install with: sudo apt install pipx && pipx ensurepath${NC}"
    exit 1
fi

# Parse pipx-requirements.txt and install packages
main_packages=()
inject_packages=()

while IFS= read -r line; do
    # Skip empty lines and comments
    if [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]]; then
        continue
    fi

    # Check if this is an inject package
    if [[ "$line" =~ inject\ into\ ([^[:space:]]+) ]]; then
        inject_target="${BASH_REMATCH[1]}"
        package=$(echo "$line" | cut -d' ' -f1)
        inject_packages+=("$inject_target:$package")
        echo -e "${BLUE}  📋 Will inject: $package -> $inject_target${NC}"
    else
        # Main package
        package=$(echo "$line" | cut -d' ' -f1)
        main_packages+=("$package")
        echo -e "${BLUE}  📋 Will install: $package${NC}"
    fi
done < "$PIPX_REQUIREMENTS"

echo

# Install main packages
for package in "${main_packages[@]}"; do
    echo -e "${BLUE}📦 Installing: $package${NC}"
    if pipx install "$package" --force; then
        echo -e "${GREEN}✅ Installed: $package${NC}"
    else
        echo -e "${YELLOW}⚠️  Failed to install: $package${NC}"
    fi
    echo
done

# Inject dependencies
for injection in "${inject_packages[@]}"; do
    IFS=':' read -r target package <<< "$injection"
    echo -e "${BLUE}💉 Injecting: $package -> $target${NC}"
    if pipx inject "$target" "$package" --force; then
        echo -e "${GREEN}✅ Injected: $package -> $target${NC}"
    else
        echo -e "${YELLOW}⚠️  Failed to inject: $package -> $target${NC}"
    fi
    echo
done

echo -e "${GREEN}🎉 pipx dependency installation complete${NC}"
echo
echo "Verify installation:"
echo "  pipx list"
echo "  ansible --version"
