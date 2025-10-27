"""
Real human interaction tests using pexpect.

These tests simulate ACTUAL human interaction with a PTY terminal,
exactly as a user would experience the wizard.
"""

import pytest
import pexpect
import sys
from pathlib import Path

# Get repo root
REPO_ROOT = Path(__file__).parent.parent.parent.parent


@pytest.mark.acceptance
class TestRealHumanInteraction:
    """Test wizard with real PTY interaction like a human."""

    def test_setup_all_defaults_human_experience(self):
        """Human pressing Enter for all prompts."""
        child = pexpect.spawn('./platform setup', timeout=30, cwd=str(REPO_ROOT))

        try:
            # Service selections - press Enter (use defaults = no)
            child.expect('Install OpenMetadata')
            child.sendline('')  # Press Enter

            child.expect('Install Kerberos')
            child.sendline('')

            child.expect('Install Pagila')
            child.sendline('')

            # PostgreSQL prompts
            child.expect('PostgreSQL image')
            child.sendline('')  # Use default

            child.expect('prebuilt')
            child.sendline('')

            child.expect('authentication')
            child.sendline('')

            child.expect('password')
            child.sendline('')

            child.expect('port')
            child.sendline('')

            # Should complete
            child.expect('complete', timeout=10)

            # Verify no errors
            output = child.before.decode() if isinstance(child.before, bytes) else child.before
            assert 'Error' not in output, "Should complete without errors"

        finally:
            child.close()

        assert child.exitstatus == 0, f"Should exit successfully, got {child.exitstatus}"

    def test_validation_error_recovery_human_experience(self):
        """Human makes a typo, sees error, presses Enter to use default."""
        child = pexpect.spawn('./platform setup', timeout=30, cwd=str(REPO_ROOT))

        try:
            # Skip service selections
            child.expect('OpenMetadata')
            child.sendline('n')
            child.expect('Kerberos')
            child.sendline('n')
            child.expect('Pagila')
            child.sendline('n')

            # Make a typo on image
            child.expect('PostgreSQL image')
            child.sendline('invalid!')  # Invalid input

            # Should see error
            child.expect('Error', timeout=5)

            # Should re-prompt
            child.expect('PostgreSQL image', timeout=5)

            # Press Enter to use default
            child.sendline('')

            # Should continue (not hang!)
            child.expect('prebuilt', timeout=5)
            child.sendline('n')

            child.expect('authentication', timeout=5)
            child.sendline('')

            child.expect('password', timeout=5)
            child.sendline('')

            child.expect('port', timeout=5)
            child.sendline('')

            child.expect('complete', timeout=10)

        finally:
            child.close()

        assert child.exitstatus == 0, "Should complete successfully after validation error"

    def test_custom_values_human_experience(self):
        """Human types custom values for everything."""
        child = pexpect.spawn('./platform setup', timeout=30, cwd=str(REPO_ROOT))

        try:
            # Select services
            child.expect('OpenMetadata')
            child.sendline('y')
            child.expect('Kerberos')
            child.sendline('n')
            child.expect('Pagila')
            child.sendline('y')

            # Custom postgres config
            child.expect('PostgreSQL image')
            child.sendline('postgres:16')

            child.expect('prebuilt')
            child.sendline('y')

            child.expect('authentication')
            child.sendline('trust')

            child.expect('password')
            child.sendline('')  # Skipped for trust

            child.expect('port')
            child.sendline('5433')

            child.expect('complete', timeout=10)

        finally:
            child.close()

        assert child.exitstatus == 0

    def test_terminal_output_is_readable(self):
        """Verify terminal output looks professional."""
        child = pexpect.spawn('./platform setup', timeout=30, cwd=str(REPO_ROOT))

        try:
            # Complete wizard with all defaults
            for _ in range(8):
                child.sendline('')

            child.expect('complete', timeout=10)

            # Get full output
            output = child.before.decode() if isinstance(child.before, bytes) else str(child.before)

            # Visual quality checks
            assert '[y/N]:' in output, "Boolean prompts should show [y/N]"
            assert '[False]' not in output, "Should not show boolean values literally"
            assert '{current_value}' not in output, "Should not show placeholders"

            # Count prompt occurrences (should be exactly 1 each)
            assert output.count('Install OpenMetadata?') == 1
            assert output.count('PostgreSQL image') == 1
            assert output.count('Use prebuilt') == 1

        finally:
            child.close()
