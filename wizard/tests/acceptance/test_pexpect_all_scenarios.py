"""
Comprehensive pexpect tests for all wizard scenarios.
Tests REAL terminal interaction exactly as humans experience it.
"""

import pexpect
import pytest


def run_setup_scenario(service_answers, postgres_answers, scenario_name):
    """Helper to run a setup scenario and verify completion."""
    child = pexpect.spawn('./platform setup', timeout=30)

    try:
        # Service selection (3 questions)
        for i, answer in enumerate(service_answers):
            child.expect('[y/N]:', timeout=10)
            child.sendline(answer)

        # Postgres configuration (5 questions)
        for answer in postgres_answers:
            child.expect(['image', 'prebuilt', 'method', 'password', 'port'], timeout=10)
            child.sendline(answer)

        # Wait for completion
        child.expect('complete', timeout=15)

        print(f"✓ {scenario_name}: SUCCESS")
        return True, None

    except pexpect.TIMEOUT as e:
        error_msg = f"TIMEOUT in {scenario_name}. Buffer: {child.buffer}"
        print(f"✗ {scenario_name}: {error_msg}")
        return False, error_msg

    except Exception as e:
        print(f"✗ {scenario_name}: {str(e)}")
        return False, str(e)

    finally:
        child.close()


@pytest.mark.acceptance
class TestAllServiceCombinations:
    """Test every possible service selection combination."""

    def test_no_additional_services(self):
        """Just postgres (n,n,n)."""
        success, error = run_setup_scenario(
            service_answers=['n', 'n', 'n'],
            postgres_answers=['', '', '', '', ''],
            scenario_name="No additional services"
        )
        assert success, error

    def test_only_openmetadata(self):
        """Postgres + OpenMetadata (y,n,n)."""
        success, error = run_setup_scenario(
            service_answers=['y', 'n', 'n'],
            postgres_answers=['', '', '', '', ''],
            scenario_name="Only OpenMetadata"
        )
        assert success, error

    def test_only_kerberos(self):
        """Postgres + Kerberos (n,y,n)."""
        success, error = run_setup_scenario(
            service_answers=['n', 'y', 'n'],
            postgres_answers=['', '', '', '', ''],
            scenario_name="Only Kerberos"
        )
        assert success, error

    def test_only_pagila(self):
        """Postgres + Pagila (n,n,y)."""
        success, error = run_setup_scenario(
            service_answers=['n', 'n', 'y'],
            postgres_answers=['', '', '', '', ''],
            scenario_name="Only Pagila"
        )
        assert success, error

    def test_openmetadata_and_kerberos(self):
        """Postgres + OpenMetadata + Kerberos (y,y,n)."""
        success, error = run_setup_scenario(
            service_answers=['y', 'y', 'n'],
            postgres_answers=['', '', '', '', ''],
            scenario_name="OpenMetadata + Kerberos"
        )
        assert success, error

    def test_openmetadata_and_pagila(self):
        """Postgres + OpenMetadata + Pagila (y,n,y)."""
        success, error = run_setup_scenario(
            service_answers=['y', 'n', 'y'],
            postgres_answers=['', '', '', '', ''],
            scenario_name="OpenMetadata + Pagila"
        )
        assert success, error

    def test_kerberos_and_pagila(self):
        """Postgres + Kerberos + Pagila (n,y,y)."""
        success, error = run_setup_scenario(
            service_answers=['n', 'y', 'y'],
            postgres_answers=['', '', '', '', ''],
            scenario_name="Kerberos + Pagila"
        )
        assert success, error

    def test_all_services(self):
        """All services (y,y,y)."""
        success, error = run_setup_scenario(
            service_answers=['y', 'y', 'y'],
            postgres_answers=['', '', '', '', ''],
            scenario_name="All services"
        )
        assert success, error


@pytest.mark.acceptance
class TestInputVariations:
    """Test different input variations."""

    def test_custom_postgres_config(self):
        """Custom postgres values."""
        success, error = run_setup_scenario(
            service_answers=['n', 'n', 'n'],
            postgres_answers=['postgres:16', 'y', 'trust', '', '5433'],
            scenario_name="Custom postgres config"
        )
        assert success, error

    def test_validation_error_recovery(self):
        """Recover from validation error."""
        child = pexpect.spawn('./platform setup', timeout=30)

        try:
            # Service selections
            for _ in range(3):
                child.expect('[y/N]:', timeout=10)
                child.sendline('n')

            # Invalid image
            child.expect('image', timeout=10)
            child.sendline('bad!')

            # Should see error
            child.expect('Error', timeout=10)

            # Should re-prompt
            child.expect('image', timeout=10)
            child.sendline('')  # Use default

            # Continue
            child.expect('prebuilt', timeout=10)
            child.sendline('')

            child.expect('method', timeout=10)
            child.sendline('')

            child.expect('password', timeout=10)
            child.sendline('')

            child.expect('port', timeout=10)
            child.sendline('')

            child.expect('complete', timeout=15)

            return True

        except pexpect.TIMEOUT as e:
            pytest.fail(f"Validation recovery failed: {e}")

        finally:
            child.close()


if __name__ == '__main__':
    """Run tests manually to see output."""
    print("Testing all service combinations...\n")

    combos = [
        ("No services", ['n','n','n']),
        ("OpenMetadata only", ['y','n','n']),
        ("Kerberos only", ['n','y','n']),
        ("Pagila only", ['n','n','y']),
        ("OpenMeta+Kerb", ['y','y','n']),
        ("OpenMeta+Pagila", ['y','n','y']),
        ("Kerb+Pagila", ['n','y','y']),
        ("All services", ['y','y','y']),
    ]

    postgres_defaults = ['', '', '', '', '']

    for name, services in combos:
        run_setup_scenario(services, postgres_defaults, name)
