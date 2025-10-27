#!/usr/bin/env python3
"""Final validation with proper service-specific prompts."""

import pexpect

def test_postgres_only():
    """Test postgres only (simplest case)."""
    print("\n" + "="*60)
    print("Test: Postgres Only")
    print("="*60)

    child = pexpect.spawn('./platform setup', timeout=30, encoding='utf-8')

    try:
        # Services: n,n,n
        child.expect('OpenMetadata', timeout=10)
        child.sendline('n')
        child.expect('Kerberos', timeout=10)
        child.sendline('n')
        child.expect('Pagila', timeout=10)
        child.sendline('n')

        # Postgres: all defaults
        for prompt in ['PostgreSQL', 'prebuilt', 'Require password', 'password', 'port']:
            child.expect(prompt, timeout=10)
            child.sendline('')

        child.expect('complete', timeout=20)
        print("✓ PASS: Postgres only")
        child.close()
        return True
    except Exception as e:
        print(f"✗ FAIL: {e}")
        child.close()
        return False


def test_postgres_kerberos():
    """Test postgres + kerberos."""
    print("\n" + "="*60)
    print("Test: Postgres + Kerberos")
    print("="*60)

    child = pexpect.spawn('./platform setup', timeout=30, encoding='utf-8')

    try:
        # Services
        child.expect('OpenMetadata', timeout=10)
        child.sendline('n')
        child.expect('Kerberos', timeout=10)
        child.sendline('y')  # YES to Kerberos
        child.expect('Pagila', timeout=10)
        child.sendline('n')

        # Postgres config
        for prompt in ['PostgreSQL', 'prebuilt', 'Require password', 'password', 'port']:
            child.expect(prompt, timeout=10)
            child.sendline('')

        # Kerberos config
        child.expect('domain', timeout=10)
        child.sendline('EXAMPLE.COM')

        child.expect('image', timeout=10)  # Kerberos image
        child.sendline('')

        child.expect('complete', timeout=20)
        print("✓ PASS: Postgres + Kerberos")
        child.close()
        return True
    except Exception as e:
        print(f"✗ FAIL: {e}")
        print(f"   Buffer: {child.buffer if hasattr(child, 'buffer') else 'none'}")
        child.close()
        return False


def test_postgres_pagila():
    """Test postgres + pagila."""
    print("\n" + "="*60)
    print("Test: Postgres + Pagila")
    print("="*60)

    child = pexpect.spawn('./platform setup', timeout=30, encoding='utf-8')

    try:
        # Services
        child.expect('OpenMetadata', timeout=10)
        child.sendline('n')
        child.expect('Kerberos', timeout=10)
        child.sendline('n')
        child.expect('Pagila', timeout=10)
        child.sendline('y')  # YES to Pagila

        # Postgres config
        for prompt in ['PostgreSQL', 'prebuilt', 'Require password', 'password', 'port']:
            child.expect(prompt, timeout=10)
            child.sendline('')

        # Pagila config
        child.expect('repository', timeout=10)
        child.sendline('')  # Use default repo URL

        child.expect('complete', timeout=20)
        print("✓ PASS: Postgres + Pagila")
        child.close()
        return True
    except Exception as e:
        print(f"✗ FAIL: {e}")
        child.close()
        return False


def test_all_services_no_openmetadata():
    """Test kerberos + pagila."""
    print("\n" + "="*60)
    print("Test: Postgres + Kerberos + Pagila")
    print("="*60)

    child = pexpect.spawn('./platform setup', timeout=30, encoding='utf-8')

    try:
        # Services
        child.expect('OpenMetadata', timeout=10)
        child.sendline('n')  # No OpenMetadata (too slow)
        child.expect('Kerberos', timeout=10)
        child.sendline('y')
        child.expect('Pagila', timeout=10)
        child.sendline('y')

        # Postgres
        for prompt in ['PostgreSQL', 'prebuilt', 'Require password', 'password', 'port']:
            child.expect(prompt, timeout=10)
            child.sendline('')

        # Kerberos
        child.expect('domain', timeout=10)
        child.sendline('EXAMPLE.COM')
        child.expect('image', timeout=10)
        child.sendline('')

        # Pagila
        child.expect('repository', timeout=10)
        child.sendline('')

        child.expect('complete', timeout=20)
        print("✓ PASS: Postgres + Kerberos + Pagila")
        child.close()
        return True
    except Exception as e:
        print(f"✗ FAIL: {e}")
        child.close()
        return False


if __name__ == '__main__':
    print("COMPREHENSIVE WIZARD VALIDATION")
    print("Testing all combinations (OpenMetadata=n always)")

    tests = [
        test_postgres_only,
        test_postgres_kerberos,
        test_postgres_pagila,
        test_all_services_no_openmetadata
    ]

    results = [test() for test in tests]

    print("\n" + "="*60)
    print(f"FINAL: {sum(results)}/{len(results)} tests passing")
    print("="*60)

    if all(results):
        print("\n🎉 ALL TESTS PASS - Wizard is ready for your team!")
        sys.exit(0)
    else:
        print(f"\n❌ {len(results) - sum(results)} tests failing")
        sys.exit(1)
