#!/bin/bash
# Test that all color codes render properly
# Catches echo statements missing -e flag

set -e

echo "Testing color code rendering in scripts..."
echo ""

FAILED=0

# Check setup-kerberos.sh
echo "Checking setup-kerberos.sh..."
BAD_ECHOS=$(grep 'echo ".*\${CYAN}\|echo ".*\${GREEN}\|echo ".*\${YELLOW}\|echo ".*\${RED}\|echo ".*\${BLUE}' ../setup-kerberos.sh | grep -v "echo -e" | wc -l)

if [ "$BAD_ECHOS" -gt 0 ]; then
    echo "✗ Found $BAD_ECHOS echo statements without -e flag"
    echo "  These will print literal \\033 codes"
    echo ""
    echo "  Examples:"
    grep 'echo ".*\${CYAN}\|echo ".*\${GREEN}\|echo ".*\${YELLOW}\|echo ".*\${RED}\|echo ".*\${BLUE}' ../setup-kerberos.sh | grep -v "echo -e" | head -5
    FAILED=1
else
    echo "✓ All color codes use echo -e"
fi

echo ""

# Check diagnose-kerberos.sh
echo "Checking diagnose-kerberos.sh..."
BAD_ECHOS=$(grep 'echo ".*\${CYAN}\|echo ".*\${GREEN}\|echo ".*\${YELLOW}\|echo ".*\${RED}\|echo ".*\${BLUE}' ../diagnose-kerberos.sh | grep -v "echo -e" | wc -l)

if [ "$BAD_ECHOS" -gt 0 ]; then
    echo "✗ Found $BAD_ECHOS echo statements without -e flag"
    FAILED=1
else
    echo "✓ All color codes use echo -e"
fi

echo ""

if [ $FAILED -eq 0 ]; then
    echo "✓ All color code tests passed"
    exit 0
else
    echo "✗ Color code tests failed"
    echo ""
    echo "Fix: Change 'echo \"...\" to 'echo -e \"...\" for lines with color variables"
    exit 1
fi
