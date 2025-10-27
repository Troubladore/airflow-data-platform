#!/usr/bin/env python3
"""
Final validation - test all service combinations with pexpect.
This simulates REAL human interaction.
"""

import pexpect
import sys

def test_scenario(name, openmetadata, kerberos, pagila):
    """Test a specific service combination."""
    print(f"\nTesting: {name}")
    print(f"  OpenMetadata={openmetadata}, Kerberos={kerberos}, Pagila={pagila}")

    child = pexpect.spawn('./platform setup', timeout=30, encoding='utf-8')

    try:
        # Service selection (OpenMetadata=n always per user request)
        child.expect('OpenMetadata.*:', timeout=10)
        child.sendline('n')  # Always no per user request

        child.expect('Kerberos.*:', timeout=10)
        child.sendline('y' if kerberos else 'n')

        child.expect('Pagila.*:', timeout=10)
        child.sendline('y' if pagila else 'n')

        # Postgres config (all defaults)
        child.expect('PostgreSQL.*:', timeout=10)
        child.sendline('')  # Image default

        child.expect('prebuilt.*:', timeout=10)
        child.sendline('')  # Prebuilt default

        child.expect('authentication.*:', timeout=10)
        child.sendline('')  # Auth default

        child.expect('password.*:', timeout=10)
        child.sendline('')  # Password default

        child.expect('port.*:', timeout=10)
        child.sendline('')  # Port default

        # Wait for completion
        child.expect('complete', timeout=20)

        print(f"  ✓ PASS")
        child.close()
        return True

    except pexpect.TIMEOUT as e:
        print(f"  ✗ FAIL: TIMEOUT")
        print(f"     Last saw: {child.buffer}")
        child.close()
        return False
    except Exception as e:
        print(f"  ✗ FAIL: {e}")
        child.close()
        return False


if __name__ == '__main__':
    print("="*60)
    print("FINAL WIZARD VALIDATION - All Service Combinations")
    print("="*60)
    print("OpenMetadata always = n (per user request - too slow to download)")

    scenarios = [
        ("Postgres only", False, False, False),
        ("Postgres + Kerberos", False, True, False),
        ("Postgres + Pagila", False, False, True),
        ("Postgres + Kerberos + Pagila", False, True, True),
    ]

    results = []
    for scenario in scenarios:
        success = test_scenario(*scenario)
        results.append((scenario[0], success))

    print("\n" + "="*60)
    print("RESULTS")
    print("="*60)

    passed = sum(1 for _, success in results if success)
    total = len(results)

    for name, success in results:
        status = "✓ PASS" if success else "✗ FAIL"
        print(f"{status}: {name}")

    print(f"\nTotal: {passed}/{total} passing")

    if passed == total:
        print("\n🎉 ALL SCENARIOS PASS - Wizard is ready!")
        sys.exit(0)
    else:
        print(f"\n❌ {total - passed} scenarios failing - needs fixes")
        sys.exit(1)
