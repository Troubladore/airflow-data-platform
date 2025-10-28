#!/usr/bin/env python3
"""Test clean-slate with corporate images."""

from wizard.engine.runner import RealActionRunner
from wizard.engine.engine import WizardEngine

# Create runner and engine
runner = RealActionRunner()
engine = WizardEngine(runner)

# Headless inputs to tear down everything
headless_inputs = {
    'teardown_postgres': True,
    'teardown_kerberos': True,
    'teardown_openmetadata': False,
    'teardown_pagila': False,
}

print("Running clean-slate to remove corporate images...")
try:
    engine.execute_flow('clean-slate', headless_inputs=headless_inputs)
    print("✅ Clean-slate completed successfully")
except Exception as e:
    print(f"❌ Clean-slate failed: {e}")
    import traceback
    traceback.print_exc()

# Check what's left
print("\nChecking remaining containers...")
import subprocess
result = subprocess.run(['docker', 'ps', '-a'], capture_output=True, text=True)
print(result.stdout)

print("\nChecking volumes...")
result = subprocess.run(['docker', 'volume', 'ls'], capture_output=True, text=True)
print(result.stdout)