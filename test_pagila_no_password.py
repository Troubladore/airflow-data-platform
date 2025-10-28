#!/usr/bin/env python3
"""
TDD Test: Reproduce the exact issue when user specifies NO PASSWORD.
The user said: "with no password" - this is the critical part.
"""

import subprocess
import os
import time
import shutil

def cleanup():
    """Clean up test artifacts."""
    subprocess.run(['docker', 'rm', '-f', 'pagila-postgres'], capture_output=True)
    subprocess.run(['docker', 'rm', '-f', 'pagila-jsonb-restore'], capture_output=True)
    subprocess.run(['docker', 'volume', 'rm', '-f', 'pagila_pgdata'], capture_output=True)
    if os.path.exists('../pagila'):
        shutil.rmtree('../pagila')

def test_pagila_setup_with_no_password():
    """
    Test what happens when user explicitly sets NO password (empty string).
    This simulates the wizard scenario where user leaves password blank.
    """
    print("=" * 60)
    print("TDD Test: Pagila Setup with NO PASSWORD (empty)")
    print("=" * 60)

    # Clean slate
    cleanup()

    # Create mock corporate image
    subprocess.run([
        'docker', 'tag', 'postgres:17.5-alpine',
        'mycorp.example.com/postgres:custom'
    ], check=True)

    print("\n1. Cloning Pagila repository first...")
    # Clone pagila manually
    result = subprocess.run([
        'git', 'clone', '-b', 'develop', '--single-branch',
        'https://github.com/Troubladore/pagila.git',
        '../pagila'
    ], capture_output=True, text=True)

    if result.returncode != 0:
        print("Failed to clone pagila")
        return False

    print("✓ Pagila cloned")

    # Create .env with EMPTY password (this is the key issue)
    print("\n2. Creating .env with NO PASSWORD (empty string)...")
    env_content = """# Pagila configuration
IMAGE_POSTGRES=mycorp.example.com/postgres:custom
POSTGRES_PASSWORD=
PAGILA_PORT=5432
"""

    with open('../pagila/.env', 'w') as f:
        f.write(env_content)

    print("✓ Created .env with empty POSTGRES_PASSWORD")

    # Start containers using docker-compose
    print("\n3. Starting Pagila containers with empty password...")
    os.chdir('../pagila')
    result = subprocess.run(
        ['docker', 'compose', 'up', '-d'],
        capture_output=True, text=True
    )

    if result.returncode != 0:
        print("✗ Docker Compose failed!")
        print("STDERR:", result.stderr)
        os.chdir('../.worktrees/fix-pagila-corp-setup')
        return False

    # Wait and check health
    print("\n4. Waiting for container health status...")
    time.sleep(10)  # Give it time to become unhealthy

    # Check health status
    result = subprocess.run(
        ['docker', 'inspect', 'pagila-postgres', '--format', '{{json .State}}'],
        capture_output=True, text=True
    )

    if result.returncode == 0:
        import json
        state = json.loads(result.stdout)
        health_status = state.get('Health', {}).get('Status', 'unknown')
        running = state.get('Running', False)

        print(f"Container running: {running}")
        print(f"Health status: {health_status}")

        if health_status == 'unhealthy':
            print("\n✗ Container is UNHEALTHY - this reproduces the issue!")

            # Get logs to understand why
            logs = subprocess.run(
                ['docker', 'logs', 'pagila-postgres', '--tail', '30'],
                capture_output=True, text=True
            )
            print("\nContainer logs showing the problem:")
            print(logs.stderr if logs.stderr else logs.stdout)

            os.chdir('../.worktrees/fix-pagila-corp-setup')
            return False  # Test correctly fails - found the issue

        elif health_status == 'healthy':
            print("✓ Container is healthy")
            os.chdir('../.worktrees/fix-pagila-corp-setup')
            return True

    os.chdir('../.worktrees/fix-pagila-corp-setup')
    return False

def test_postgres_password_requirement():
    """
    Test PostgreSQL behavior with empty vs missing password.
    PostgreSQL might require a password to be set even with trust auth.
    """
    print("\n" + "=" * 60)
    print("TDD Test: PostgreSQL Password Requirements")
    print("=" * 60)

    cleanup()

    print("\n1. Testing PostgreSQL with empty POSTGRES_PASSWORD...")

    # Start a plain postgres container with empty password
    result = subprocess.run([
        'docker', 'run', '-d',
        '--name', 'test-postgres-empty',
        '-e', 'POSTGRES_PASSWORD=',  # Empty password
        'postgres:17.5-alpine'
    ], capture_output=True, text=True)

    if result.returncode != 0:
        print("Failed to start container with empty password")

    time.sleep(5)

    # Check if it's running
    result = subprocess.run(
        ['docker', 'logs', 'test-postgres-empty', '--tail', '10'],
        capture_output=True, text=True
    )

    print("Logs with empty password:")
    output = result.stderr if result.stderr else result.stdout
    print(output[:500])

    # Clean up
    subprocess.run(['docker', 'rm', '-f', 'test-postgres-empty'], capture_output=True)

    # Check for the specific error
    if 'must specify POSTGRES_PASSWORD' in output:
        print("\n✗ PostgreSQL REQUIRES a non-empty password!")
        print("  This is the root cause of the issue")
        return False
    else:
        print("\n✓ PostgreSQL accepts empty password")
        return True

if __name__ == "__main__":
    # First test the core PostgreSQL requirement
    test2_result = test_postgres_password_requirement()

    # Then test our specific scenario
    test1_result = test_pagila_setup_with_no_password()

    print("\n" + "=" * 60)
    print("TDD TEST RESULTS:")
    print(f"  PostgreSQL password test: {'PASS' if test2_result else 'FAIL'}")
    print(f"  Pagila no-password test:  {'PASS' if test1_result else 'FAIL'}")
    print("=" * 60)

    if not test2_result:
        print("\n✓ Found root cause: PostgreSQL requires non-empty POSTGRES_PASSWORD")
        print("  Even with trust authentication, the env var cannot be empty")
        exit(1)  # Correct TDD failure - demonstrates the bug