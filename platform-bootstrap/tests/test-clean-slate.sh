#!/bin/bash
# Tests for clean-slate.sh
set -e
cd "$(dirname "$0")/.."
bash -n clean-slate.sh && echo "✓ Syntax valid" || exit 1
echo "✓ Tests pass (syntax validated)"
