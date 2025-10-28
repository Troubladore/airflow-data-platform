#!/usr/bin/env python3
"""
Test Pagila setup through the wizard flow to identify the issue.
Tests what happens when using the wizard with custom settings.
"""

import subprocess
import sys
import os
import tempfile

def run_command(cmd, env=None):
    """Run command and return result."""
    print(f"Running: {' '.join(cmd)}")
    result = subprocess.run(cmd, capture_output=True, text=True, env=env)
    return result.returncode, result.stdout, result.stderr

def test_via_make():
    """Test via make command (how wizard calls it)."""
    print("=" * 60)
    print("Testing Pagila setup via make (wizard flow)")
    print("=" * 60)

    # Clean up first
    print("\n1. Cleaning up...")
    run_command(['docker', 'rm', '-f', 'pagila-postgres'])
    run_command(['docker', 'rm', '-f', 'pagila-jsonb-restore'])
    run_command(['docker', 'volume', 'rm', '-f', 'pagila_pgdata'])
    if os.path.exists('../pagila'):
        run_command(['rm', '-rf', '../pagila'])

    # Create mock image
    print("\n2. Creating mock corporate image...")
    run_command(['docker', 'tag', 'postgres:17.5-alpine', 'mycorp.example.com/postgres:17.5-custom'])

    # Test with make command (as wizard would call it)
    print("\n3. Running via make with custom settings...")
    cmd = [
        'make', '-C', 'platform-bootstrap', 'setup-pagila',
        'PAGILA_REPO_URL=https://github.com/Troubladore/pagila.git',
        'IMAGE_POSTGRES=mycorp.example.com/postgres:17.5-custom',
        'PAGILA_BRANCH=develop',
        'PAGILA_AUTO_YES=1'
    ]

    rc, stdout, stderr = run_command(cmd)
    print("Return code:", rc)
    if stdout:
        print("STDOUT:", stdout[:500])
    if stderr:
        print("STDERR:", stderr[:500])

    # Check container health
    print("\n4. Checking container status...")
    rc, stdout, _ = run_command(['docker', 'ps', '-a', '--filter', 'name=pagila'])
    print(stdout)

    return rc == 0

def test_password_handling():
    """Test what happens with no password set."""
    print("\n" + "=" * 60)
    print("Testing password handling")
    print("=" * 60)

    # Check if .env exists in pagila
    if os.path.exists('../pagila/.env'):
        print("Checking pagila/.env...")
        with open('../pagila/.env', 'r') as f:
            for line in f:
                if 'POSTGRES_PASSWORD' in line:
                    print(f"  {line.strip()}")

    # Check docker-compose.yml
    if os.path.exists('../pagila/docker-compose.yml'):
        print("\nChecking docker-compose.yml environment section...")
        with open('../pagila/docker-compose.yml', 'r') as f:
            in_env = False
            for line in f:
                if 'environment:' in line:
                    in_env = True
                    print(f"  {line.rstrip()}")
                elif in_env and ('POSTGRES_PASSWORD' in line or 'password' in line.lower()):
                    print(f"  {line.rstrip()}")
                elif in_env and line.strip() and not line.strip().startswith('-'):
                    in_env = False

def test_diagnostic_path():
    """Test the diagnostic path issue."""
    print("\n" + "=" * 60)
    print("Testing diagnostic file check")
    print("=" * 60)

    # The diagnostic checks '../pagila' - let's see what happens
    print("Checking relative path '../pagila' from different locations...")

    # From platform-bootstrap
    os.chdir('platform-bootstrap')
    print(f"From platform-bootstrap: ../pagila exists? {os.path.exists('../pagila')}")

    # From wizard location (where diagnostics run)
    os.chdir('..')  # back to worktree root
    print(f"From worktree root: ../pagila exists? {os.path.exists('../pagila')}")

    # Check where pagila actually is
    pagila_locations = [
        '../pagila',
        './pagila',
        '../airflow-data-platform/pagila',
        '/home/eru_admin/repos/airflow-data-platform/pagila'
    ]

    for loc in pagila_locations:
        if os.path.exists(loc):
            print(f"✓ Found pagila at: {loc}")

if __name__ == "__main__":
    success = test_via_make()
    test_password_handling()
    test_diagnostic_path()

    print("\n" + "=" * 60)
    if success:
        print("✓ Make command succeeded")
    else:
        print("✗ Make command failed - this might be the issue!")
    print("=" * 60)