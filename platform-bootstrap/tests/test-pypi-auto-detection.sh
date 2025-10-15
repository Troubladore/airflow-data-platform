#!/bin/bash
# Tests for PyPI auto-detection from uv.toml and pip.conf

set -e

# Source formatting library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/formatting.sh"

PLATFORM_DIR="$(dirname "$SCRIPT_DIR")"

TESTS_PASSED=0
TESTS_FAILED=0

test_result() {
    if [ "$1" = "pass" ]; then
        print_check "PASS" "$2"
        ((TESTS_PASSED++))
    else
        print_check "FAIL" "$2"
        echo "  $3"
        ((TESTS_FAILED++))
    fi
}

print_header "PyPI Auto-Detection Tests"

# Test 1: Dockerfile uses UV
echo "Test 1: Dockerfile.test-image uses UV"
if grep -q "uv pip install" $PLATFORM_DIR/kerberos-sidecar/Dockerfile.test-image; then
    test_result "pass" "Dockerfile uses UV (not pip)"
else
    test_result "fail" "Dockerfile uses UV" "Should use 'uv pip install --system'"
fi
echo ""

# Test 2: Dockerfile accepts PIP_INDEX_URL
echo "Test 2: Dockerfile accepts PIP_INDEX_URL build arg"
if grep -q "ARG PIP_INDEX_URL" $PLATFORM_DIR/kerberos-sidecar/Dockerfile.test-image; then
    test_result "pass" "PIP_INDEX_URL build arg defined"
else
    test_result "fail" "PIP_INDEX_URL build arg" "Missing ARG PIP_INDEX_URL"
fi
echo ""

# Test 3: Makefile auto-detects from uv.toml
echo "Test 3: Makefile tries to detect from uv.toml"
if grep -q "\.config/uv/uv\.toml" $PLATFORM_DIR/kerberos-sidecar/Makefile; then
    test_result "pass" "Checks ~/.config/uv/uv.toml"
else
    test_result "fail" "UV config detection" "Should check uv.toml"
fi
echo ""

# Test 4: Makefile falls back to pip.conf
echo "Test 4: Makefile falls back to pip.conf"
if grep -q "\.pip/pip\.conf" $PLATFORM_DIR/kerberos-sidecar/Makefile; then
    test_result "pass" "Falls back to ~/.pip/pip.conf"
else
    test_result "fail" "pip.conf fallback" "Should check pip.conf"
fi
echo ""

# Test 5: Simulate uv.toml parsing
echo "Test 5: Simulate uv.toml parsing"
TEMP_TOML=$(mktemp --suffix=.toml)
cat > "$TEMP_TOML" <<'EOF'
[[index]]
name = "primary"
url = "https://artifactory.test.com/api/pypi/simple"
EOF

DETECTED=$(python3 -c "import tomllib; c=tomllib.load(open('$TEMP_TOML','rb')); print([i['url'] for i in c.get('index',[]) if i.get('name')=='primary'][0])" 2>/dev/null || echo "")
rm "$TEMP_TOML"

if [ "$DETECTED" = "https://artifactory.test.com/api/pypi/simple" ]; then
    test_result "pass" "UV TOML parsing works"
else
    test_result "fail" "UV TOML parsing" "Got: $DETECTED"
fi
echo ""

# Test 6: Simulate pip.conf parsing
echo "Test 6: Simulate pip.conf parsing"
TEMP_CONF=$(mktemp)
cat > "$TEMP_CONF" <<'EOF'
[global]
index-url = https://artifactory.test.com/pypi/simple
EOF

DETECTED=$(grep "index-url" "$TEMP_CONF" | cut -d= -f2- | tr -d ' ')
rm "$TEMP_CONF"

if [ "$DETECTED" = "https://artifactory.test.com/pypi/simple" ]; then
    test_result "pass" "pip.conf parsing works"
else
    test_result "fail" "pip.conf parsing" "Got: $DETECTED"
fi
echo ""

# Test 7: .env.example documents PIP variables
echo "Test 7: .env.example documents PIP configuration"
if grep -q "PIP_INDEX_URL" $PLATFORM_DIR/.env.example || grep -q "PIP_INDEX_URL" ../platform-bootstr$PLATFORM_DIR/.env.example; then
    test_result "pass" ".env.example has PIP_INDEX_URL docs"
else
    test_result "fail" ".env.example docs" "Missing PIP_INDEX_URL documentation"
fi
echo ""

print_section "Results"
print_msg "${GREEN}Passed: $TESTS_PASSED${NC}"
print_msg "${RED}Failed: $TESTS_FAILED${NC}"
echo ""

if [ $TESTS_FAILED -eq 0 ]; then
    print_success "All PyPI auto-detection tests passed!"
    exit 0
else
    print_error "Some tests failed"
    exit 1
fi
