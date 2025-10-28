#!/usr/bin/env python3
"""
Reproduce the exact issue: test what happens when docker-compose
creates a container that becomes unhealthy.
"""

import subprocess
import os
import time
import json

def run_command(cmd, cwd=None):
    """Run command and return result."""
    print(f"Running: {' '.join(cmd)}")
    if cwd:
        print(f"  in directory: {cwd}")
    result = subprocess.run(cmd, capture_output=True, text=True, cwd=cwd)
    return result.returncode, result.stdout, result.stderr

def simulate_unhealthy_container():
    """Simulate what happens when container becomes unhealthy."""
    print("=" * 60)
    print("Simulating unhealthy container scenario")
    print("=" * 60)

    # Clean up
    print("\n1. Cleaning up...")
    run_command(['docker', 'rm', '-f', 'pagila-postgres'])
    run_command(['docker', 'rm', '-f', 'pagila-jsonb-restore'])
    run_command(['docker', 'volume', 'rm', '-f', 'pagila_pgdata'])

    # Check if pagila exists and look at docker-compose.yml
    print("\n2. Checking pagila docker-compose.yml...")
    compose_path = '../pagila/docker-compose.yml'
    if os.path.exists(compose_path):
        print("Reading docker-compose.yml to understand health check...")
        with open(compose_path, 'r') as f:
            content = f.read()
            if 'healthcheck:' in content:
                print("Found healthcheck configuration:")
                lines = content.split('\n')
                for i, line in enumerate(lines):
                    if 'healthcheck:' in line:
                        for j in range(i, min(i+10, len(lines))):
                            print(f"  {lines[j]}")

    # Let's check what makes the container unhealthy
    print("\n3. Testing container health check...")

    # First, let's see if the issue is with the .env file
    pagila_env = '../pagila/.env'
    if os.path.exists(pagila_env):
        print("Current .env contents:")
        with open(pagila_env, 'r') as f:
            for line in f:
                if 'PASSWORD' in line or 'IMAGE' in line:
                    print(f"  {line.strip()}")

    # Now test if removing password causes issues
    print("\n4. Testing with no password (empty string)...")

    # Backup current .env
    if os.path.exists(pagila_env):
        with open(pagila_env, 'r') as f:
            original_env = f.read()

        # Create .env with no password
        new_env = original_env.replace(
            original_env[original_env.find('POSTGRES_PASSWORD='):original_env.find('\n', original_env.find('POSTGRES_PASSWORD='))],
            'POSTGRES_PASSWORD='
        )

        with open(pagila_env, 'w') as f:
            f.write(new_env)

        print("Updated .env to have empty password")

    # Try to start with empty password
    print("\n5. Starting container with empty password...")
    os.chdir('../pagila')
    rc, stdout, stderr = run_command(['docker', 'compose', 'up', '-d'], cwd='.')

    time.sleep(5)  # Wait for health checks

    # Check container health
    print("\n6. Checking container health status...")
    rc, stdout, _ = run_command(['docker', 'inspect', 'pagila-postgres', '--format', '{{.State.Health.Status}}'])
    if stdout:
        print(f"Health status: {stdout.strip()}")

    # Get logs if unhealthy
    if 'unhealthy' in stdout:
        print("\n7. Container is unhealthy! Getting logs...")
        rc, stdout, stderr = run_command(['docker', 'logs', 'pagila-postgres', '--tail', '30'])
        if stdout or stderr:
            print("Container logs showing the issue:")
            print(stdout)
            print(stderr)

    # Restore original .env
    if os.path.exists(pagila_env) and 'original_env' in locals():
        with open(pagila_env, 'w') as f:
            f.write(original_env)

    os.chdir('../.worktrees/fix-pagila-corp-setup')

def check_diagnostic_issue():
    """Check the specific 'No such file or directory' issue in diagnostics."""
    print("\n" + "=" * 60)
    print("Checking diagnostic 'No such file or directory' issue")
    print("=" * 60)

    # The diagnostic runs from wizard directory
    # Let's simulate what the diagnostic does
    print("\n1. Simulating diagnostic check from wizard...")

    # The diagnostic uses runner.run_shell(['test', '-d', '../pagila'])
    # When run from wizard directory, this would be:
    rc, stdout, stderr = run_command(['test', '-d', '../pagila'])
    print(f"test -d ../pagila: return code {rc}")

    if rc != 0:
        print("✗ This would cause 'No such file or directory' in diagnostic!")
        print("  The diagnostic is checking the wrong path!")

    # The issue is that the diagnostic is run from the wizard context,
    # but pagila is cloned relative to the platform-bootstrap directory
    print("\n2. Path analysis:")
    print(f"  Current dir: {os.getcwd()}")
    print(f"  Pagila actual location: /home/eru_admin/repos/airflow-data-platform/pagila")
    print(f"  Diagnostic checks: ../pagila (from wizard context)")
    print(f"  This resolves to: {os.path.abspath('../pagila')}")

if __name__ == "__main__":
    simulate_unhealthy_container()
    check_diagnostic_issue()