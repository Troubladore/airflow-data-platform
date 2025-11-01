#!/usr/bin/env python3
"""Complete end-to-end test of corporate image support."""

import subprocess
import sys

def run_command(cmd):
    """Run a command and return success/failure."""
    print(f"Running: {cmd}")
    result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
    if result.returncode != 0:
        print(f"  ❌ Failed: {result.stderr}")
        return False
    print(f"  ✅ Success")
    return True

print("=" * 60)
print("COMPLETE CORPORATE IMAGE FLOW TEST")
print("=" * 60)

# Step 1: Create mock corporate images
print("\n1. Creating mock corporate images...")
if not run_command("./mock-corporate-image.py create mycorp.jfrog.io/docker-mirror/postgres/17.5:2025.10.01"):
    print("Failed to create PostgreSQL mock image")
    sys.exit(1)

if not run_command("./mock-corporate-image.py build-kerberos mycorp.jfrog.io/docker-mirror/kerberos-base:latest"):
    print("Failed to create Kerberos prebuilt image")
    sys.exit(1)

# Step 2: List created images
print("\n2. Verifying mock images...")
run_command("./mock-corporate-image.py list")

# Step 3: Run wizard with corporate images
print("\n3. Testing wizard with corporate images...")
from wizard.engine.runner import RealActionRunner
from wizard.engine.engine import WizardEngine

runner = RealActionRunner()
engine = WizardEngine(runner)

# Set up for prebuilt Kerberos
engine.state['services.kerberos.use_prebuilt'] = True

headless_inputs = {
    'platform_name': 'corporate-test',
    'select_openmetadata': False,
    'select_kerberos': True,
    'select_pagila': False,
    'postgres_image': 'mycorp.jfrog.io/docker-mirror/postgres/17.5:2025.10.01',
    'postgres_prebuilt': False,
    'postgres_auth': False,
    'postgres_port': 5432,
    'image_input': 'mycorp.jfrog.io/docker-mirror/kerberos-base:latest',
    'domain_input': 'CORP.EXAMPLE.COM',
}

try:
    engine.execute_flow('setup', headless_inputs=headless_inputs)
    print("✅ Wizard accepted corporate images!")
    print(f"  PostgreSQL: {engine.state.get('services.base_platform.postgres.image')}")
    print(f"  Kerberos: {engine.state.get('services.kerberos.image')}")
    print(f"  Prebuilt: {engine.state.get('services.kerberos.use_prebuilt')}")
except Exception as e:
    print(f"❌ Wizard failed: {e}")
    sys.exit(1)

# Step 4: Verify services are running
print("\n4. Verifying services...")
result = subprocess.run(['docker', 'ps', '--format', 'table {{.Names}}\t{{.Image}}'],
                       capture_output=True, text=True)
print(result.stdout)

# Step 5: Clean up
print("\n5. Running clean-slate...")
engine = WizardEngine(runner)
headless_inputs = {
    'teardown_postgres': True,
    'teardown_kerberos': True,
    'teardown_openmetadata': False,
    'teardown_pagila': False,
}

try:
    engine.execute_flow('clean-slate', headless_inputs=headless_inputs)
    print("✅ Clean-slate completed")
except Exception as e:
    print(f"❌ Clean-slate failed: {e}")

# Step 6: Clean up mock container and images
print("\n6. Final cleanup...")
run_command("docker stop kerberos-sidecar-mock 2>/dev/null || true")
run_command("docker rm kerberos-sidecar-mock 2>/dev/null || true")
run_command("./mock-corporate-image.py remove mycorp.jfrog.io/docker-mirror/postgres/17.5:2025.10.01")
run_command("./mock-corporate-image.py remove mycorp.jfrog.io/docker-mirror/kerberos-base:latest")

print("\n" + "=" * 60)
print("TEST COMPLETE")
print("=" * 60)