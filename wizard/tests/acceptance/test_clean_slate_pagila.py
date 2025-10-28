"""
Focused acceptance tests for clean-slate and Pagila-only setup.

These tests simulate real user interaction using pexpect.
Run individually or together for specific scenarios.
"""

import pexpect
import subprocess
import pytest


def test_clean_slate_interactive():
    """
    Expectation: Clean-slate wizard should interactively remove all platform artifacts.
    User answers 'y' to all teardown confirmations.

    Success criteria:
    - Wizard completes without errors
    - All containers removed
    - All images optionally removed
    - Clean exit with success message
    """
    print("\n" + "=" * 60)
    print("TEST: Clean-Slate Interactive Teardown")
    print("=" * 60)

    child = pexpect.spawn('./platform clean-slate', timeout=60, encoding='utf-8')
    child.logfile = open('/tmp/clean_slate_output.txt', 'w')

    try:
        # Answer 'y' to all teardown questions (up to 20 prompts)
        for i in range(20):
            index = child.expect([r'\[.*\]:', 'complete', pexpect.EOF, pexpect.TIMEOUT], timeout=5)
            if index == 0:
                child.sendline('y')  # Confirm all teardowns
            elif index == 1:
                print("✓ Wizard completed successfully")
                break
            else:
                break

        child.wait()
        output = open('/tmp/clean_slate_output.txt').read()

        # Observe: Check containers after clean-slate
        result = subprocess.run(
            ['docker', 'ps', '-a', '--filter', 'name=platform'],
            capture_output=True,
            text=True
        )

        # Evaluate
        assert 'platform-postgres' not in result.stdout, "Platform containers should be removed"
        assert '✗' not in output, "Should complete without errors"

        print("✓ Clean-slate PASSED")
        return True

    except pexpect.TIMEOUT as e:
        pytest.fail(f"Clean-slate timed out: {e}")
    finally:
        child.close()


def test_pagila_only_setup():
    """
    Expectation: Setup with Pagila only (n,n,y) should:
    - Create platform-bootstrap/.env with correct flags
    - Start platform-postgres successfully
    - Proceed to Pagila configuration
    - Show success messages, not errors

    Success criteria:
    - "✓ PostgreSQL started successfully" (not "✗ failed")
    - platform-bootstrap/.env exists
    - ENABLE_PAGILA=true in .env
    - ENABLE_OPENMETADATA=false, ENABLE_KERBEROS=false
    - platform-postgres container running
    """
    print("\n" + "=" * 60)
    print("TEST: Pagila-Only Setup (n,n,y)")
    print("=" * 60)

    child = pexpect.spawn('./platform setup', timeout=90, encoding='utf-8')
    child.logfile = open('/tmp/pagila_setup_output.txt', 'w')

    try:
        # Service selection: n, n, y
        child.expect(r'OpenMetadata.*\[.*\]:', timeout=10)
        child.sendline('n')

        child.expect(r'Kerberos.*\[.*\]:', timeout=10)
        child.sendline('n')

        child.expect(r'Pagila.*\[.*\]:', timeout=10)
        child.sendline('y')

        # PostgreSQL config: Accept all defaults (press Enter ~5 times)
        for i in range(10):  # PostgreSQL prompts
            index = child.expect([r'\[.*\]:', 'Starting PostgreSQL', pexpect.TIMEOUT], timeout=10)
            if index == 0:
                child.sendline('')  # Accept default
            elif index == 1:
                print("PostgreSQL starting...")
                break

        # Wait for Pagila prompts or completion
        for i in range(10):  # Pagila prompts
            index = child.expect([r'\[.*\]:', 'complete', pexpect.EOF, pexpect.TIMEOUT], timeout=15)
            if index == 0:
                child.sendline('')  # Accept defaults
            elif index == 1:
                print("✓ Setup completed")
                break
            else:
                break

        child.wait()
        output = open('/tmp/pagila_setup_output.txt').read()

        # Observe: Check what was created

        # 1. .env file
        with open('platform-bootstrap/.env', 'r') as f:
            env_content = f.read()

        # 2. Containers
        containers = subprocess.run(
            ['docker', 'ps', '--format', '{{.Names}}'],
            capture_output=True,
            text=True
        ).stdout

        # 3. PostgreSQL health
        pg_status = subprocess.run(
            ['docker', 'exec', 'platform-postgres', 'psql', '-U', 'platform_admin', '-c', 'SELECT 1;'],
            capture_output=True,
            text=True
        )

        # Evaluate
        print("\n--- EVALUATION ---")

        # Check .env flags
        assert 'ENABLE_PAGILA=true' in env_content, ".env should enable Pagila"
        assert 'ENABLE_OPENMETADATA=false' in env_content, ".env should disable OpenMetadata"
        assert 'ENABLE_KERBEROS=false' in env_content, ".env should disable Kerberos"
        print("✓ .env flags correct")

        # Check PostgreSQL started
        assert '✓ PostgreSQL started successfully' in output, "Should show PostgreSQL success"
        assert '✗ PostgreSQL failed' not in output, "Should NOT show PostgreSQL failure"
        print("✓ PostgreSQL success message shown")

        # Check container running
        assert 'platform-postgres' in containers, "platform-postgres should be running"
        print("✓ platform-postgres container running")

        # Check PostgreSQL responds
        assert pg_status.returncode == 0, "PostgreSQL should respond to queries"
        print("✓ PostgreSQL responsive")

        # UX Quality
        assert output.count('PostgreSQL image') == 1, "Prompts should not duplicate"
        assert '[False]' not in output, "Should use [y/N] not [False]"
        assert '{current_value}' not in output, "Should interpolate placeholders"
        print("✓ UX quality acceptable")

        print("\n✅ PAGILA SETUP PASSED")
        return True

    except AssertionError as e:
        print(f"\n❌ PAGILA SETUP FAILED: {e}")
        pytest.fail(str(e))
    except pexpect.TIMEOUT as e:
        pytest.fail(f"Setup timed out: {e}")
    finally:
        child.close()


if __name__ == '__main__':
    """Run tests manually."""
    test_clean_slate_interactive()
    test_pagila_only_setup()
