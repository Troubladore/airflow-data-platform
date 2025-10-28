#!/usr/bin/env python3
"""
Test script to reproduce the Pagila setup issue with custom settings.
This simulates what happens when a user sets up Pagila with:
- Custom image
- Custom repo URL
- Custom branch
- No password
"""

import subprocess
import sys
import os
import json

def run_command(cmd, capture=True):
    """Run command and return result."""
    print(f"Running: {' '.join(cmd)}")
    if capture:
        result = subprocess.run(cmd, capture_output=True, text=True)
        return result.returncode, result.stdout, result.stderr
    else:
        result = subprocess.run(cmd)
        return result.returncode, "", ""

def test_pagila_with_custom_settings():
    """Test Pagila setup with custom settings."""
    print("=" * 60)
    print("Testing Pagila setup with custom settings")
    print("=" * 60)

    # Clean up any existing state
    print("\n1. Cleaning up existing Pagila...")
    run_command(['docker', 'rm', '-f', 'pagila-postgres'], capture=False)
    run_command(['docker', 'rm', '-f', 'pagila-jsonb-restore'], capture=False)
    run_command(['docker', 'volume', 'rm', '-f', 'pagila_pgdata'], capture=False)

    # Remove pagila directory if it exists
    if os.path.exists('../pagila'):
        print("Removing existing pagila directory...")
        run_command(['rm', '-rf', '../pagila'])

    print("\n2. Setting up test environment variables...")
    # Simulate custom settings
    env = os.environ.copy()
    env['IMAGE_POSTGRES'] = 'mycorp.example.com/postgres:17.5-custom'
    env['PAGILA_REPO_URL'] = 'https://github.com/Troubladore/pagila.git'
    env['PAGILA_BRANCH'] = 'develop'
    env['PAGILA_AUTO_YES'] = '1'

    # First, create a mock image to simulate corporate registry
    print("\n3. Creating mock corporate image...")
    rc, _, _ = run_command(['docker', 'tag', 'postgres:17.5-alpine', env['IMAGE_POSTGRES']])
    if rc != 0:
        print("Failed to create mock image")
        return False

    print("\n4. Running Pagila setup with custom settings...")
    # Run the setup script directly
    cmd = [
        './platform-bootstrap/setup-scripts/setup-pagila.sh'
    ]

    proc = subprocess.Popen(cmd, env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    stdout, stderr = proc.communicate()

    print("STDOUT:")
    print(stdout)
    if stderr:
        print("STDERR:")
        print(stderr)

    if proc.returncode != 0:
        print(f"\n✗ Setup failed with return code: {proc.returncode}")

        # Check container status
        print("\n5. Checking container health...")
        rc, stdout, _ = run_command(['docker', 'ps', '-a', '--format', 'json'])
        if stdout:
            for line in stdout.strip().split('\n'):
                if line:
                    container = json.loads(line)
                    if 'pagila' in container.get('Names', ''):
                        print(f"Container: {container['Names']}")
                        print(f"  Status: {container.get('Status', 'Unknown')}")
                        print(f"  State: {container.get('State', 'Unknown')}")

        # Check container logs
        print("\n6. Checking container logs...")
        rc, stdout, stderr = run_command(['docker', 'logs', 'pagila-postgres', '--tail', '20'])
        if stdout:
            print("Container logs:")
            print(stdout)
        if stderr:
            print("Container errors:")
            print(stderr)

        # Check if pagila directory was created
        print("\n7. Checking pagila directory...")
        if os.path.exists('../pagila'):
            print("✓ Pagila directory exists")
            # Check docker-compose.yml
            compose_path = '../pagila/docker-compose.yml'
            if os.path.exists(compose_path):
                print(f"✓ docker-compose.yml exists")
                with open(compose_path, 'r') as f:
                    print("First 20 lines of docker-compose.yml:")
                    for i, line in enumerate(f):
                        if i >= 20:
                            break
                        print(f"  {line.rstrip()}")
            else:
                print("✗ docker-compose.yml not found")
        else:
            print("✗ Pagila directory not created")

        return False

    print("\n✓ Setup completed successfully")
    return True

if __name__ == "__main__":
    success = test_pagila_with_custom_settings()
    sys.exit(0 if success else 1)