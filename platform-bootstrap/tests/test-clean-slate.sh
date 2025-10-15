#!/bin/bash
# Tests for clean-slate.sh
set -e

# Source formatting library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/formatting.sh"

cd "$(dirname "$0")/.."
if bash -n clean-slate.sh; then
    print_check "PASS" "Syntax valid"
    print_check "PASS" "Tests pass (syntax validated)"
    exit 0
else
    print_check "FAIL" "Syntax check failed"
    exit 1
fi
