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
    'kerberos_image': 'mycorp.jfrog.io/docker-mirror/mycorp-approved-images/kerberos-base:latest',
    'kerberos_mode': 'prebuilt',
    'kerberos_realm': 'CORP.EXAMPLE.COM',
    'kerberos_kdc': 'kdc.corp.example.com',
    'kerberos_admin_server': 'kadmin.corp.example.com',
}

print("Running wizard with corporate images...")
try:
    engine.execute_flow('setup', headless_inputs=headless_inputs)
    print("✅ SUCCESS: Wizard accepted corporate images!")
    print(f"PostgreSQL image: {engine.state.get('services.postgres.image')}")
    print(f"Kerberos image: {engine.state.get('services.kerberos.image')}")
except Exception as e:
    print(f"❌ FAILED: {e}")
    import traceback
    traceback.print_exc()