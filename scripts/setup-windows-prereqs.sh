#!/bin/bash
# WSL2 wrapper to run Windows prerequisites setup
# Handles PowerShell invocation across Windows/WSL2 boundary

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WIN_PREREQS_SCRIPT="$SCRIPT_DIR/win-prereqs.ps1"

echo -e "${BLUE}🪟 Windows Prerequisites Setup (from WSL2)${NC}"
echo
echo "This script will run Windows setup from WSL2 by:"
echo "1. Converting WSL2 paths to Windows paths"
echo "2. Invoking PowerShell.exe on Windows side"
echo "3. Running the Windows prerequisites script"
echo

# Check if we're in WSL2
if ! grep -qi microsoft /proc/version 2>/dev/null; then
    echo -e "${RED}❌ This script must be run from WSL2${NC}"
    exit 1
fi

# Check if PowerShell script exists
if [ ! -f "$WIN_PREREQS_SCRIPT" ]; then
    echo -e "${RED}❌ Windows prerequisites script not found: $WIN_PREREQS_SCRIPT${NC}"
    exit 1
fi

# Convert WSL2 path to Windows path
echo -e "${BLUE}📁 Converting WSL2 path to Windows path...${NC}"
WIN_SCRIPT_PATH=$(wslpath -w "$WIN_PREREQS_SCRIPT")
echo "Windows path: $WIN_SCRIPT_PATH"

# Find PowerShell executable
POWERSHELL_CMD=""
POWERSHELL_PATHS=(
    "/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe"
    "/mnt/c/Windows/SysWOW64/WindowsPowerShell/v1.0/powershell.exe"
    "powershell.exe"  # In case Windows PATH is available
)

echo -e "${BLUE}🔍 Looking for PowerShell executable...${NC}"
for ps_path in "${POWERSHELL_PATHS[@]}"; do
    if command -v "$ps_path" >/dev/null 2>&1 || [ -f "$ps_path" ]; then
        POWERSHELL_CMD="$ps_path"
        echo "Found PowerShell at: $POWERSHELL_CMD"
        break
    fi
done

if [ -z "$POWERSHELL_CMD" ]; then
    echo -e "${RED}❌ PowerShell not found. Tried:${NC}"
    for ps_path in "${POWERSHELL_PATHS[@]}"; do
        echo "  - $ps_path"
    done
    echo
    echo -e "${YELLOW}💡 Manual steps:${NC}"
    echo "1. Copy this command:"
    echo "   & \"$WIN_SCRIPT_PATH\""
    echo "2. Open Windows PowerShell"
    echo "3. Paste and run the command"
    echo "4. Return to WSL2 and continue with: ansible-playbook -i ansible/inventory/local-dev.ini ansible/site.yml"
    exit 1
fi

# Parse arguments
SKIP_HOSTS=""
FORCE=""
while [[ $# -gt 0 ]]; do
    case $1 in
        --skip-hosts)
            SKIP_HOSTS="-SkipHostsFile"
            shift
            ;;
        --force)
            FORCE="-Force"
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --skip-hosts    Skip hosts file modification"
            echo "  --force         Force certificate regeneration"
            echo "  -h, --help      Show this help"
            exit 0
            ;;
        *)
            echo -e "${YELLOW}⚠️  Unknown option: $1${NC}"
            shift
            ;;
    esac
done

# Ask for confirmation
echo -e "${YELLOW}⚠️  About to run Windows prerequisites setup...${NC}"
echo "This will:"
echo "  • Install Scoop package manager (if needed)"
echo "  • Install mkcert via Scoop"
echo "  • Generate development certificates"
echo "  • Update Windows hosts file (if admin)"
echo
read -p "Continue? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${BLUE}ℹ️  Windows setup cancelled${NC}"
    exit 0
fi

# Run the PowerShell script
echo -e "${BLUE}🚀 Running Windows prerequisites setup...${NC}"
echo "Command: $POWERSHELL_CMD -ExecutionPolicy Bypass -File \"$WIN_SCRIPT_PATH\" $SKIP_HOSTS $FORCE"
echo

if "$POWERSHELL_CMD" -ExecutionPolicy Bypass -File "$WIN_SCRIPT_PATH" $SKIP_HOSTS $FORCE; then
    echo
    echo -e "${GREEN}✅ Windows prerequisites setup completed!${NC}"
    echo
    echo -e "${BLUE}🐧 Next steps (continue in WSL2):${NC}"
    echo "  cd $(pwd)"
    echo "  ansible-playbook -i ansible/inventory/local-dev.ini ansible/site.yml"
    echo
else
    echo
    echo -e "${RED}❌ Windows prerequisites setup failed${NC}"
    echo
    echo -e "${YELLOW}💡 Troubleshooting steps:${NC}"
    echo
    echo -e "${BLUE}Common Issue: PowerShell Version Compatibility${NC}"
    echo "If you see 'Get-FileHash' or 'mkcert' not recognized errors:"
    echo "1. Try PowerShell 7+ instead of Windows PowerShell 5.1"
    echo "2. Or run these commands manually in Windows PowerShell:"
    echo
    echo -e "${BLUE}Manual Installation Commands:${NC}"
    echo "# Install Scoop"
    echo "iex (new-object net.webclient).downloadstring('https://get.scoop.sh')"
    echo
    echo "# Install mkcert"
    echo "scoop install mkcert"
    echo
    echo "# Generate certificates"
    echo "mkcert -install"
    echo "mkdir \$env:LOCALAPPDATA\\mkcert; cd \$env:LOCALAPPDATA\\mkcert"
    echo "mkcert -cert-file dev-localhost-wild.crt -key-file dev-localhost-wild.key *.localhost localhost"
    echo "mkcert -cert-file dev-registry.localhost.crt -key-file dev-registry.localhost.key registry.localhost"
    echo
    echo -e "${BLUE}After manual setup:${NC}"
    echo "Return to WSL2 and run: ansible-playbook -i ansible/inventory/local-dev.ini ansible/site.yml"
    exit 1
fi
