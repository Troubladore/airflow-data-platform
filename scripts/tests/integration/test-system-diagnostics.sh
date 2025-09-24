#!/bin/bash
# Integration tests for the complete system diagnostic suite

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DIAGNOSTICS_SCRIPT="$SCRIPT_DIR/../../diagnostics/system-state.sh"

echo "🧪 System Diagnostics Integration Test"
echo "======================================"

# Test 1: Script exists and is executable
if [ -f "$DIAGNOSTICS_SCRIPT" ] && [ -x "$DIAGNOSTICS_SCRIPT" ]; then
    echo "✅ Diagnostic script exists and is executable"
else
    echo "❌ Diagnostic script missing or not executable: $DIAGNOSTICS_SCRIPT"
    exit 1
fi

# Test 2: Script runs without crashing
echo "🔍 Running full system diagnostic..."
if output=$("$DIAGNOSTICS_SCRIPT" 2>&1); then
    exit_code=0
else
    exit_code=$?
fi

echo "📊 Diagnostic Output:"
echo "===================="
echo "$output"
echo "===================="
echo "Exit code: $exit_code"

# Test 3: Output contains expected sections
sections=(
    "Certificate State Detection"
    "Hosts File State Detection"
    "Docker State Detection"
    "Platform Services State Detection"
    "Network State Detection"
    "Overall Status"
)

echo "🔍 Checking for required output sections:"
for section in "${sections[@]}"; do
    if echo "$output" | grep -q "$section"; then
        echo "✅ Found: $section"
    else
        echo "❌ Missing: $section"
        exit 1
    fi
done

# Test 4: Check for actionable diagnostics
actionable_items=(
    "mkcert:"
    "Certificates:"
    "Docker CLI:"
    "Docker daemon:"
)

echo "🔍 Checking for actionable diagnostic items:"
for item in "${actionable_items[@]}"; do
    if echo "$output" | grep -q "$item"; then
        echo "✅ Found diagnostic: $item"
    else
        echo "⚠️  Missing diagnostic: $item (may be environment-specific)"
    fi
done

# Test 5: Validate that we get actual status indicators
if echo "$output" | grep -q "✅\|❌\|⚠️"; then
    echo "✅ Output contains status indicators"
else
    echo "❌ Output missing status indicators"
    exit 1
fi

# Test 6: Check current system state matches what we expect
echo "🔍 Validating current system state:"

# Docker should be available (we know this from previous tests)
if echo "$output" | grep -q "Docker CLI: .*Available"; then
    echo "✅ Docker CLI correctly detected as available"
else
    echo "❌ Docker CLI detection failed"
    exit 1
fi

# Hosts should be configured (from earlier setup)
if echo "$output" | grep -q "registry.localhost.*127.0.0.1"; then
    echo "✅ Hosts file entries correctly detected"
else
    echo "⚠️  Hosts file entries not detected (may need Windows prerequisites)"
fi

echo "======================================"
echo "🎉 System diagnostic integration tests completed successfully!"
echo "   The diagnostic system is working and provides actionable information."
echo "   Exit code: $exit_code (0=all good, >0=issues detected)"
echo "======================================"
