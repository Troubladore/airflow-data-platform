"""Test case verifying the fix for shared files in clean-slate discovery.

The issue: Previously, all services would detect the shared platform configuration files
(platform-config.yaml and platform-bootstrap/.env) as their own artifacts, causing the
clean-slate wizard to prompt for tearing down all services even when only one service
had actual artifacts.

The fix: Service discovery modules now only report service-specific artifacts, not
shared platform configuration files.
"""

import pytest
from wizard.engine.engine import WizardEngine
from wizard.engine.runner import MockActionRunner


class TestSharedFilesFix:
    """Test that shared platform files don't cause all services to be prompted."""

    def test_only_services_with_real_artifacts_are_prompted(self):
        """Verify that only services with real artifacts are prompted for teardown."""
        runner = MockActionRunner()

        # Simulate only platform-config.yaml and platform-bootstrap/.env existing
        # (these are shared files, not service-specific)
        runner.responses['file_exists'] = {
            'platform-config.yaml': True,
            'platform-bootstrap/.env': True,
            # No service-specific files
            'openmetadata/.env': False,
            'kerberos/krb5.conf': False,
            'pagila/.env': False,
        }

        # Add ONE Docker artifact so the flow doesn't exit early
        # (total_artifacts check doesn't count files, only docker artifacts)
        runner.responses['run_shell'] = {
            # One postgres container exists
            ('docker', 'ps', '-a', '--filter', 'name=postgres', '--format', '{{.Names}}|{{.Status}}'): 'postgres-test|Up\n',
            # No other Docker artifacts
            ('docker', 'ps', '-a', '--filter', 'name=openmetadata', '--format', '{{.Names}}|{{.Status}}'): '',
            ('docker', 'ps', '-a', '--filter', 'name=opensearch', '--format', '{{.Names}}|{{.Status}}'): '',
            ('docker', 'ps', '-a', '--filter', 'name=kerberos', '--format', '{{.Names}}|{{.Status}}'): '',
            ('docker', 'ps', '-a', '--filter', 'name=pagila', '--format', '{{.Names}}|{{.Status}}'): '',
            ('docker', 'images', '--filter', 'reference=postgres', '--format', '{{.Repository}}:{{.Tag}}|{{.Size}}'): '',
            ('docker', 'images', '--filter', 'reference=openmetadata', '--format', '{{.Repository}}:{{.Tag}}|{{.Size}}'): '',
            ('docker', 'images', '--filter', 'reference=opensearchproject', '--format', '{{.Repository}}:{{.Tag}}|{{.Size}}'): '',
            ('docker', 'images', '--filter', 'reference=kerberos-sidecar', '--format', '{{.Repository}}:{{.Tag}}|{{.Size}}'): '',
            ('docker', 'images', '--filter', 'reference=pagila', '--format', '{{.Repository}}:{{.Tag}}|{{.Size}}'): '',
            ('docker', 'volume', 'ls', '--filter', 'name=postgres', '--format', '{{.Name}}'): '',
            ('docker', 'volume', 'ls', '--filter', 'name=openmetadata', '--format', '{{.Name}}'): '',
            ('docker', 'volume', 'ls', '--filter', 'name=opensearch', '--format', '{{.Name}}'): '',
            ('docker', 'volume', 'ls', '--filter', 'name=kerberos', '--format', '{{.Name}}'): '',
            ('docker', 'volume', 'ls', '--filter', 'name=pagila', '--format', '{{.Name}}'): '',
            ('find', '/etc/security/keytabs', '-name', '*.keytab', '-type', 'f'): '',
        }

        # Track which services were asked about
        prompts_asked = []

        # Capture prompts
        def capture_input(prompt, default=None):
            prompts_asked.append(prompt)
            # Say no to all
            return 'n'

        runner.get_input = capture_input

        # Run clean-slate flow
        engine = WizardEngine(runner=runner, base_path='wizard')
        engine.execute_flow('clean-slate')

        # Bug behavior: Because all services detect the shared files,
        # ALL services are prompted for teardown
        teardown_prompts = [p for p in prompts_asked if 'Tear down' in p]

        # The FIX: Now only services with real artifacts are prompted
        # Only postgres should be prompted (it has a real container)
        assert len(teardown_prompts) == 1, \
            f"Fix verified: Only {len(teardown_prompts)} service prompted (postgres with container)"

        # Verify it's postgres that was prompted
        assert 'PostgreSQL' in teardown_prompts[0], \
            f"Should prompt for PostgreSQL, got: {teardown_prompts[0]}"