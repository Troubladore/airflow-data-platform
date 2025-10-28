#!/usr/bin/env python3
"""
TDD Verification: Test that the fix handles empty passwords correctly.
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

def test_fixed_setup_handles_empty_password():
    """
    Test that setup-pagila.sh now handles empty passwords correctly.
    """
    print("=" * 60)
    print("TDD GREEN: Verify Fix Handles Empty Password")
    print("=" * 60)

    # Clean slate
    cleanup()

    # Create mock corporate image
    subprocess.run([
        'docker', 'tag', 'postgres:17.5-alpine',
        'mycorp.example.com/postgres:custom'
    ], check=True)

    print("\n1. Running setup with empty password in environment...")

    # Create .env with empty password in platform-bootstrap
    env_content = """IMAGE_POSTGRES=mycorp.example.com/postgres:custom
PAGILA_REPO_URL=https://github.com/Troubladore/pagila.git
PAGILA_BRANCH=develop
POSTGRES_PASSWORD=
"""

    with open('platform-bootstrap/.env', 'w') as f:
        f.write(env_content)

    # Run the fixed setup script
    result = subprocess.run([
        'make', '-C', 'platform-bootstrap', 'setup-pagila',
        'PAGILA_AUTO_YES=1'
    ], capture_output=True, text=True)

    print(f"Setup return code: {result.returncode}")

    if result.returncode != 0:
        print("✗ Setup failed")
        print("STDERR:", result.stderr[:500])
        return False

    print("✓ Setup completed")

    # Verify the .env file now has a non-empty password
    print("\n2. Checking if password was auto-generated...")
    if os.path.exists('../pagila/.env'):
        with open('../pagila/.env', 'r') as f:
            content = f.read()
            if 'POSTGRES_PASSWORD=' in content:
                lines = content.split('\n')
                for line in lines:
                    if line.startswith('POSTGRES_PASSWORD='):
                        password = line.split('=', 1)[1]
                        if password:
                            print(f"✓ Password generated: {password[:10]}... (truncated)")
                        else:
                            print("✗ Password still empty!")
                            return False
                        break

    # Check container health
    print("\n3. Checking container health...")
    time.sleep(10)  # Wait for health checks

    result = subprocess.run(
        ['docker', 'inspect', 'pagila-postgres', '--format', '{{.State.Health.Status}}'],
        capture_output=True, text=True
    )

    health_status = result.stdout.strip()
    print(f"Health status: {health_status}")

    if health_status == 'healthy':
        print("✓ Container is healthy - fix works!")
        return True
    else:
        print(f"✗ Container is {health_status}")
        # Get logs for debugging
        logs = subprocess.run(
            ['docker', 'logs', 'pagila-postgres', '--tail', '20'],
            capture_output=True, text=True
        )
        print("Container logs:")
        print(logs.stderr if logs.stderr else logs.stdout)
        return False

def test_existing_env_with_empty_password():
    """
    Test that the fix also handles existing .env files with empty password.
    """
    print("\n" + "=" * 60)
    print("TDD GREEN: Verify Fix Updates Existing Empty Password")
    print("=" * 60)

    cleanup()

    # Clone pagila first
    print("\n1. Setting up pagila with existing empty password .env...")
    subprocess.run([
        'git', 'clone', '-b', 'develop', '--single-branch',
        'https://github.com/Troubladore/pagila.git',
        '../pagila'
    ], capture_output=True)

    # Create .env with empty password
    with open('../pagila/.env', 'w') as f:
        f.write("POSTGRES_PASSWORD=\n")

    print("✓ Created .env with empty password")

    # Run setup script
    print("\n2. Running setup-pagila.sh...")
    result = subprocess.run([
        './platform-bootstrap/setup-scripts/setup-pagila.sh', '--yes'
    ], capture_output=True, text=True)

    # Check if script detected and fixed empty password
    if 'Empty password detected' in result.stdout:
        print("✓ Script detected empty password")

    # Verify password was updated
    with open('../pagila/.env', 'r') as f:
        content = f.read()
        if 'POSTGRES_PASSWORD=' in content:
            password = content.split('POSTGRES_PASSWORD=')[1].split('\n')[0]
            if password:
                print(f"✓ Password updated: {password[:10]}... (truncated)")
                return True
            else:
                print("✗ Password still empty")
                return False

    return False

if __name__ == "__main__":
    test1_result = test_fixed_setup_handles_empty_password()
    test2_result = test_existing_env_with_empty_password()

    print("\n" + "=" * 60)
    print("TDD VERIFICATION RESULTS:")
    print(f"  Empty password handling: {'PASS' if test1_result else 'FAIL'}")
    print(f"  Existing .env update:    {'PASS' if test2_result else 'FAIL'}")
    print("=" * 60)

    if test1_result and test2_result:
        print("\n✓ All tests PASS - fix is complete!")
        exit(0)
    else:
        print("\n✗ Some tests still fail - fix needs more work")
        exit(1)