#!/usr/bin/env python3
"""Test wizard with corporate images directly."""

from wizard.engine.runner import RealActionRunner
from wizard.engine.engine import WizardEngine

# Create headless test
runner = RealActionRunner()
engine = WizardEngine(runner)

# Test inputs
headless_inputs = {
    'platform_name': 'corporate-test',
    'select_openmetadata': False,
    'select_kerberos': True,
    'select_pagila': False,
    'postgres_image': 'mycorp.jfrog.io/docker-mirror/mycorp-approved-images/postgres/17.5:2025.10.01',
    'postgres_prebuilt': False,
    'postgres_auth': False,
    'postgres_port': 5432,
    'image_input': 'mycorp.jfrog.io/docker-mirror/mycorp-approved-images/kerberos-base:latest',  # Match the step ID
    'domain_input': 'CORP.EXAMPLE.COM',  # Match the step ID
    'services.kerberos.use_prebuilt': True,  # Mark as prebuilt in state
}

print("Running wizard with corporate images...")

# Pre-set use_prebuilt in the state since the wizard spec doesn't ask for it
engine.state['services.kerberos.use_prebuilt'] = True

print(f"DEBUG: State before flow:")
print(f"  Kerberos use_prebuilt: {engine.state.get('services.kerberos.use_prebuilt')}")
print(f"  Kerberos image in inputs: {headless_inputs.get('image_input')}")

try:
    engine.execute_flow('setup', headless_inputs=headless_inputs)
    print("✅ SUCCESS: Wizard accepted corporate images!")
    print(f"PostgreSQL image: {engine.state.get('services.postgres.image')}")
    print(f"Kerberos image: {engine.state.get('services.kerberos.image')}")
    print(f"Kerberos use_prebuilt: {engine.state.get('services.kerberos.use_prebuilt')}")
except Exception as e:
    print(f"❌ FAILED: {e}")
    import traceback
    traceback.print_exc()