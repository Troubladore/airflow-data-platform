#!/bin/bash

# Supply Chain Security Scanner
# Identifies potential supply chain risks in the workstation setup

set -e

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

echo "🔍 Scanning workstation setup for supply chain risks..."
echo "📁 Project root: $PROJECT_ROOT"
echo

# Colors for output
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

ISSUES_FOUND=0

check_unpinned_dependencies() {
    echo "📦 Checking for unpinned dependencies..."

    # Check for unpinned pip/pipx installations
    if grep -r "pipx install\|pip install" . --include="*.sh" --include="*.md" --include="*.yml" --exclude-dir=".git" | grep -v "=="; then
        echo -e "${YELLOW}⚠️  Found unpinned Python dependencies${NC}"
        ISSUES_FOUND=$((ISSUES_FOUND + 1))
    else
        echo -e "${GREEN}✅ All Python dependencies appear to be pinned${NC}"
    fi
    echo
}

check_dangerous_downloads() {
    echo "🌐 Checking for dangerous download patterns..."

    # Check for pipe-to-shell patterns
    if grep -r "curl.*|.*bash\|wget.*|.*bash\|curl.*|.*sh\|wget.*|.*sh" . --include="*.sh" --include="*.md" --include="*.yml" --exclude-dir=".git"; then
        echo -e "${RED}🚨 Found pipe-to-shell patterns (curl|bash, wget|sh)${NC}"
        echo -e "${YELLOW}   These bypass package managers and security verification${NC}"
        ISSUES_FOUND=$((ISSUES_FOUND + 1))
    else
        echo -e "${GREEN}✅ No dangerous pipe-to-shell patterns found${NC}"
    fi
    echo
}

check_ansible_security() {
    echo "🤖 Checking Ansible playbooks for security issues..."

    # Check for dynamic downloads in Ansible
    if find ansible -name "*.yml" -exec grep -l "win_shell:\|shell:\|command:" {} \; 2>/dev/null | \
       xargs grep -n "curl\|wget\|Invoke-WebRequest\|iwr\|iex" 2>/dev/null; then
        echo -e "${YELLOW}⚠️  Found dynamic downloads in Ansible tasks${NC}"
        ISSUES_FOUND=$((ISSUES_FOUND + 1))
    else
        echo -e "${GREEN}✅ No dynamic downloads found in Ansible tasks${NC}"
    fi

    # Check for hardcoded secrets (basic patterns)
    if find ansible -name "*.yml" -exec grep -i "password\|secret\|key\|token" {} \; 2>/dev/null | \
       grep -v "no_log\|vault" | grep -v "password:\|secret:\|key:\|token:" | head -5; then
        echo -e "${YELLOW}⚠️  Potential hardcoded secrets found${NC}"
        echo -e "${YELLOW}   Review above results for actual secrets${NC}"
        ISSUES_FOUND=$((ISSUES_FOUND + 1))
    else
        echo -e "${GREEN}✅ No obvious hardcoded secrets found${NC}"
    fi
    echo
}

check_docker_security() {
    echo "🐳 Checking Docker configurations..."

    # Check for latest tags
    if find . -name "Dockerfile*" -o -name "docker-compose*.yml" | \
       xargs grep -n ":latest\|FROM.*:" 2>/dev/null | grep -v "# Latest is OK for"; then
        echo -e "${YELLOW}⚠️  Found Docker images without version pins${NC}"
        ISSUES_FOUND=$((ISSUES_FOUND + 1))
    else
        echo -e "${GREEN}✅ Docker images appear to be version-pinned${NC}"
    fi
    echo
}

check_windows_security() {
    echo "🪟 Checking Windows-specific security patterns..."

    # Check for ExecutionPolicy bypasses
    if grep -r "ExecutionPolicy.*Bypass\|ExecutionPolicy.*Unrestricted" . --include="*.yml" --include="*.ps1" --exclude-dir=".git"; then
        echo -e "${RED}🚨 Found PowerShell execution policy bypasses${NC}"
        ISSUES_FOUND=$((ISSUES_FOUND + 1))
    else
        echo -e "${GREEN}✅ No PowerShell execution policy bypasses found${NC}"
    fi

    # Check for admin privilege escalation without justification
    if find ansible -name "*.yml" -exec grep -l "become.*yes\|become:.*true" {} \; 2>/dev/null | \
       xargs grep -B2 -A2 "become" | grep -v "# Admin required for\|# Requires elevated"; then
        echo -e "${YELLOW}⚠️  Found privilege escalation without clear justification${NC}"
        echo -e "${YELLOW}   Ensure admin operations are documented${NC}"
        ISSUES_FOUND=$((ISSUES_FOUND + 1))
    fi
    echo
}

check_requirements_files() {
    echo "📄 Checking for pinned requirements files..."

    if [ -f "ansible/requirements.txt" ]; then
        echo -e "${GREEN}✅ Found ansible/requirements.txt${NC}"

        # Check if requirements are pinned
        if grep -q "==" ansible/requirements.txt; then
            echo -e "${GREEN}✅ Requirements appear to be pinned${NC}"
        else
            echo -e "${YELLOW}⚠️  Requirements file exists but may not be pinned${NC}"
            ISSUES_FOUND=$((ISSUES_FOUND + 1))
        fi
    else
        echo -e "${YELLOW}⚠️  No ansible/requirements.txt found${NC}"
        echo -e "${YELLOW}   Consider creating one with pinned Python dependencies${NC}"
        ISSUES_FOUND=$((ISSUES_FOUND + 1))
    fi

    if [ -f "ansible/requirements.yml" ]; then
        echo -e "${GREEN}✅ Found ansible/requirements.yml for Galaxy dependencies${NC}"
    else
        echo -e "${YELLOW}⚠️  No ansible/requirements.yml found${NC}"
        echo -e "${YELLOW}   Consider creating one for Ansible Galaxy dependencies${NC}"
    fi
    echo
}

generate_recommendations() {
    echo "📋 Security Recommendations:"
    echo

    if [ $ISSUES_FOUND -eq 0 ]; then
        echo -e "${GREEN}🎉 No major supply chain security issues found!${NC}"
        echo
        echo "Consider these proactive measures:"
        echo "- Regular dependency updates with security review"
        echo "- Implement pre-commit hooks for security scanning"
        echo "- Add checksum verification for critical downloads"
        echo "- Consider running Ansible from containerized environment"
    else
        echo -e "${RED}Found $ISSUES_FOUND potential security issues${NC}"
        echo
        echo "Recommended actions:"
        echo "1. Pin all Python dependencies in ansible/requirements.txt"
        echo "2. Replace pipe-to-shell patterns with package manager installs"
        echo "3. Add checksum verification for direct downloads"
        echo "4. Document and justify all admin privilege operations"
        echo "5. Use specific version tags for Docker images"
        echo
        echo "For detailed guidance, see: SECURITY.md"
    fi
}

# Run all checks
check_unpinned_dependencies
check_dangerous_downloads
check_ansible_security
check_docker_security
check_windows_security
check_requirements_files
generate_recommendations

exit $ISSUES_FOUND