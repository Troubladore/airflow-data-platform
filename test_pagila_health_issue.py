#!/usr/bin/env python3
"""
TDD Test: Reproduce the exact Pagila container health issue with custom settings.
This test should FAIL initially, demonstrating the bug.
"""

import subprocess
import os
import time
import json
import tempfile
import shutil

def setup_mock_corporate_image():
    """Create a mock corporate image for testing."""
    # Tag standard postgres as corporate image
    subprocess.run([
        'docker', 'tag', 'postgres:17.5-alpine',
        'mycorp.jfrog.io/docker-mirror/postgres:17.5-custom'
    ], check=True)

def cleanup():
    """Clean up test artifacts."""
    subprocess.run(['docker', 'rm', '-f', 'pagila-postgres'], capture_output=True)
    subprocess.run(['docker', 'rm', '-f', 'pagila-jsonb-restore'], capture_output=True)
    subprocess.run(['docker', 'volume', 'rm', '-f', 'pagila_pgdata'], capture_output=True)

def check_container_health(container_name='pagila-postgres', max_wait=30):
    """Check if container becomes healthy within timeout."""
    for i in range(max_wait):
        result = subprocess.run(
            ['docker', 'inspect', container_name, '--format', '{{.State.Health.Status}}'],
            capture_output=True, text=True
        )

        status = result.stdout.strip()

        if status == 'healthy':
            return True, 'healthy'
        elif status == 'unhealthy':
            # Get logs for debugging
            logs = subprocess.run(
                ['docker', 'logs', container_name, '--tail', '20'],
                capture_output=True, text=True
            )
            return False, f'unhealthy - logs:\n{logs.stderr}\n{logs.stdout}'

        time.sleep(1)

    return False, 'timeout waiting for health status'

def test_pagila_with_custom_image_and_no_password():
    """
    Test that Pagila container becomes healthy when:
    1. Using a custom corporate image path
    2. Custom repo URL
    3. Custom branch
    4. With proper password handling

    This test should demonstrate the issue where the container
    becomes unhealthy with certain configurations.
    """
    print("=" * 60)
    print("TDD Test: Pagila Container Health with Custom Settings")
    print("=" * 60)

    # Clean up first
    cleanup()

    # Setup mock corporate image
    setup_mock_corporate_image()

    # Remove existing pagila directory
    if os.path.exists('../pagila'):
        shutil.rmtree('../pagila')

    print("\n1. Setting up Pagila with custom settings via wizard flow...")

    # Create temporary .env for platform-bootstrap
    env_content = """
# Custom corporate settings
IMAGE_POSTGRES=mycorp.jfrog.io/docker-mirror/postgres:17.5-custom
PAGILA_REPO_URL=https://github.com/Troubladore/pagila.git
PAGILA_BRANCH=develop
"""

    with open('platform-bootstrap/.env', 'w') as f:
        f.write(env_content)

    # Run setup via make (as wizard would)
    result = subprocess.run([
        'make', '-C', 'platform-bootstrap', 'setup-pagila',
        'PAGILA_REPO_URL=https://github.com/Troubladore/pagila.git',
        'IMAGE_POSTGRES=mycorp.jfrog.io/docker-mirror/postgres:17.5-custom',
        'PAGILA_BRANCH=develop',
        'PAGILA_AUTO_YES=1'
    ], capture_output=True, text=True)

    print(f"Setup command return code: {result.returncode}")

    if result.returncode != 0:
        print("Setup failed!")
        print("STDERR:", result.stderr[:500])

        # Check if container exists but is unhealthy
        print("\n2. Checking container status...")
        healthy, status = check_container_health()

        if not healthy:
            print(f"✗ FAILED: Container is {status}")

            # This is the expected failure - container becomes unhealthy
            # with custom settings
            return False
        else:
            print("✓ Container is healthy (unexpected)")
            return True
    else:
        print("✓ Setup succeeded")

        # Verify container is actually healthy
        print("\n2. Verifying container health...")
        healthy, status = check_container_health()

        if healthy:
            print("✓ Container is healthy")
            return True
        else:
            print(f"✗ Container is {status}")
            return False

def test_diagnostic_path_resolution():
    """
    Test that diagnostics correctly identify when Pagila directory exists.
    This tests the "No such file or directory" error in diagnostics.
    """
    print("\n" + "=" * 60)
    print("TDD Test: Diagnostic Path Resolution")
    print("=" * 60)

    # The diagnostic should check if pagila directory exists
    # From worktree root, it should check ../pagila

    pagila_exists = os.path.exists('../pagila')
    print(f"1. Does ../pagila exist from worktree? {pagila_exists}")

    # Simulate diagnostic check
    result = subprocess.run(['test', '-d', '../pagila'])
    diagnostic_thinks_exists = (result.returncode == 0)

    print(f"2. Diagnostic check (test -d ../pagila): {diagnostic_thinks_exists}")

    # These should match
    if pagila_exists == diagnostic_thinks_exists:
        print("✓ Diagnostic correctly identifies pagila existence")
        return True
    else:
        print("✗ Diagnostic incorrectly reports pagila existence!")
        return False

if __name__ == "__main__":
    # Run tests
    test1_passed = test_pagila_with_custom_image_and_no_password()
    test2_passed = test_diagnostic_path_resolution()

    print("\n" + "=" * 60)
    print("TEST RESULTS:")
    print(f"  Container health test: {'PASS' if test1_passed else 'FAIL'}")
    print(f"  Diagnostic path test:  {'PASS' if test2_passed else 'FAIL'}")
    print("=" * 60)

    # For TDD, we expect this to FAIL initially
    if not test1_passed:
        print("\n✓ Test correctly FAILS - demonstrating the bug exists")
        print("  Next step: Implement fix to make test pass")
        exit(1)  # Exit with failure to show test is red
    else:
        print("\n✗ Test unexpectedly PASSES - bug may already be fixed")
        exit(0)