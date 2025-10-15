#!/bin/bash
# Test that all color codes render properly
# Catches echo statements missing -e flag

set -e

# Source formatting library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/formatting.sh"

print_header "Color Code Rendering Tests"

FAILED=0

# Check setup-kerberos.sh
print_section "Checking setup-kerberos.sh"
BAD_ECHOS=$(grep 'echo ".*\${CYAN}\|echo ".*\${GREEN}\|echo ".*\${YELLOW}\|echo ".*\${RED}\|echo ".*\${BLUE}' ../setup-kerberos.sh | grep -v "echo -e" | wc -l)

if [ "$BAD_ECHOS" -gt 0 ]; then
    print_check "FAIL" "Found $BAD_ECHOS echo statements without -e flag"
    echo "  These will print literal \\033 codes"
    echo ""
    echo "  Examples:"
    grep 'echo ".*\${CYAN}\|echo ".*\${GREEN}\|echo ".*\${YELLOW}\|echo ".*\${RED}\|echo ".*\${BLUE}' ../setup-kerberos.sh | grep -v "echo -e" | head -5
    FAILED=1
else
    print_check "PASS" "All color codes use echo -e"
fi

echo ""

# Check diagnose-kerberos.sh
print_section "Checking diagnose-kerberos.sh"
BAD_ECHOS=$(grep 'echo ".*\${CYAN}\|echo ".*\${GREEN}\|echo ".*\${YELLOW}\|echo ".*\${RED}\|echo ".*\${BLUE}' ../diagnose-kerberos.sh | grep -v "echo -e" | wc -l)

if [ "$BAD_ECHOS" -gt 0 ]; then
    print_check "FAIL" "Found $BAD_ECHOS echo statements without -e flag"
    FAILED=1
else
    print_check "PASS" "All color codes use echo -e"
fi

echo ""

if [ $FAILED -eq 0 ]; then
    print_success "All color code tests passed"
    exit 0
else
    print_error "Color code tests failed"
    echo ""
    echo "Fix: Change 'echo \"...\" to 'echo -e \"...\" for lines with color variables"
    exit 1
fi
