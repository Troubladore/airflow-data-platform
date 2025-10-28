#!/usr/bin/env python3
"""Test the diagnostic system by simulating failures in all services."""

import os
import sys
import tempfile
from pathlib import Path

# Add wizard to path
sys.path.insert(0, str(Path(__file__).parent))

from wizard.utils.diagnostics import DiagnosticCollector, ServiceDiagnostics, create_diagnostic_summary
from wizard.services.postgres import actions as postgres_actions
from wizard.services.kerberos import actions as kerberos_actions
from wizard.services.pagila import actions as pagila_actions


class TestRunner:
    """Test runner that simulates failures."""

    def __init__(self, failure_mode=None):
        self.displays = []
        self.commands = []
        self.failure_mode = failure_mode
        self.configs_saved = []

    def display(self, msg):
        print(msg)
        self.displays.append(msg)

    def save_config(self, config, filename):
        self.configs_saved.append((config, filename))

    def run_shell(self, cmd, **kwargs):
        self.commands.append(cmd)
        cmd_str = ' '.join(cmd) if isinstance(cmd, list) else cmd

        # Simulate various failures based on mode
        if self.failure_mode == 'postgres_pull_denied':
            if 'make' in cmd_str and 'start' in cmd_str:
                return {
                    'returncode': 1,
                    'stderr': 'pull access denied for corp.registry/postgres:17',
                    'stdout': ''
                }

        elif self.failure_mode == 'kerberos_manifest_unknown':
            if 'docker' in cmd_str and 'run' in cmd_str and 'kerberos' in cmd_str:
                return {
                    'returncode': 1,
                    'stderr': 'manifest unknown: image not found',
                    'stdout': ''
                }

        elif self.failure_mode == 'pagila_git_fail':
            if 'make' in cmd_str and 'setup-pagila' in cmd_str:
                return {
                    'returncode': 1,
                    'stderr': 'fatal: could not resolve host: github.com',
                    'stdout': 'Cloning repository...'
                }

        # Default responses for diagnostic checks
        if 'docker ps' in cmd_str:
            if '--format' in cmd_str:
                # Return empty - no containers
                return {'returncode': 0, 'stdout': '', 'stderr': ''}
            return {'returncode': 0, 'stdout': 'CONTAINER ID  NAME', 'stderr': ''}

        if 'test -d ../pagila' in cmd_str:
            # Directory doesn't exist
            return {'returncode': 1, 'stdout': '', 'stderr': ''}

        # Default success
        return {'returncode': 0, 'stdout': '', 'stderr': ''}


def test_postgres_diagnostics():
    """Test PostgreSQL diagnostic on authentication failure."""
    print("\n" + "="*60)
    print("Testing PostgreSQL diagnostics - Registry Auth Failure")
    print("="*60)

    runner = TestRunner(failure_mode='postgres_pull_denied')
    ctx = {
        'services.postgres.enabled': True,
        'services.postgres.port': 5432,
        'services.postgres.image': 'corp.registry/postgres:17',
        'services.postgres.no_password_mode': True
    }

    # This should trigger diagnostics
    postgres_actions.start_service(ctx, runner)

    # Verify diagnostics ran
    assert any("Running automatic diagnostics" in d for d in runner.displays), \
        "Diagnostics should have been triggered"
    assert any("Registry authentication required" in d or "registry" in d.lower() for d in runner.displays), \
        "Should mention registry authentication"
    print("\n✓ PostgreSQL diagnostics correctly identified registry auth issue")


def test_kerberos_diagnostics():
    """Test Kerberos diagnostic on image not found."""
    print("\n" + "="*60)
    print("Testing Kerberos diagnostics - Image Not Found")
    print("="*60)

    runner = TestRunner(failure_mode='kerberos_manifest_unknown')
    ctx = {
        'services.kerberos.domain': 'CORP.LOCAL',
        'services.kerberos.image': 'corp.registry/kerberos:latest',
        'services.kerberos.use_prebuilt': True
    }

    # This should trigger diagnostics
    kerberos_actions.start_service(ctx, runner)

    # Verify diagnostics ran
    assert any("Running automatic diagnostics" in d for d in runner.displays), \
        "Diagnostics should have been triggered"
    assert any("Image not found" in d or "manifest" in d.lower() for d in runner.displays), \
        "Should mention image not found"
    assert any("prebuilt" in d.lower() for d in runner.displays), \
        "Should mention prebuilt mode"
    print("\n✓ Kerberos diagnostics correctly identified missing image")


def test_pagila_diagnostics():
    """Test Pagila diagnostic on git clone failure."""
    print("\n" + "="*60)
    print("Testing Pagila diagnostics - Git Clone Failure")
    print("="*60)

    runner = TestRunner(failure_mode='pagila_git_fail')
    ctx = {
        'services.pagila.enabled': True,
        'services.pagila.repo_url': 'https://github.com/devrimgunduz/pagila.git',
        'services.pagila.postgres_image': 'postgres:17.5-alpine',
        'services.postgres.enabled': True,
        'services.postgres.port': 5432
    }

    # This should trigger diagnostics
    pagila_actions.install_pagila(ctx, runner)

    # Verify diagnostics ran
    assert any("Running automatic diagnostics" in d for d in runner.displays), \
        "Diagnostics should have been triggered"
    assert any("Repository not cloned" in d or "Git clone" in d for d in runner.displays), \
        "Should mention git clone failure"
    assert any("DNS" in d or "resolve host" in d.lower() for d in runner.displays), \
        "Should identify DNS resolution issue"
    print("\n✓ Pagila diagnostics correctly identified git clone failure")


def test_diagnostic_log_creation():
    """Test that diagnostic logs are created properly."""
    print("\n" + "="*60)
    print("Testing Diagnostic Log Creation")
    print("="*60)

    collector = DiagnosticCollector()

    # Record multiple failures
    collector.record_failure(
        service="postgres",
        phase="docker_compose_up",
        error="pull access denied",
        context={"image": "corp.registry/postgres:17"}
    )

    collector.record_failure(
        service="kerberos",
        phase="docker_run",
        error="manifest unknown",
        context={"image": "corp.registry/kerberos:latest", "use_prebuilt": True}
    )

    collector.record_failure(
        service="pagila",
        phase="git_clone",
        error="could not resolve host",
        context={"repo_url": "https://github.com/devrimgunduz/pagila.git"}
    )

    # Save log
    with tempfile.TemporaryDirectory() as tmpdir:
        log_file = collector.save_log(tmpdir)
        assert Path(log_file).exists(), "Log file should be created"

        # Check contents
        with open(log_file) as f:
            content = f.read()
            assert "POSTGRES" in content
            assert "KERBEROS" in content
            assert "PAGILA" in content
            assert "pull access denied" in content
            assert "manifest unknown" in content
            assert "could not resolve host" in content

        print(f"\n✓ Diagnostic log created successfully at: {log_file}")

        # Test summary generation
        summary = create_diagnostic_summary(
            collector.failures,
            log_file=Path(log_file).name
        )

        assert "SETUP FAILED" in summary
        assert "docker login" in summary
        assert all(svc in summary.lower() for svc in ["postgres", "kerberos", "pagila"])

        print("\n✓ Summary generated correctly")
        print("\nSample summary output:")
        print("-" * 40)
        print(summary)


if __name__ == "__main__":
    print("\nRunning Diagnostic System Tests")
    print("================================\n")

    try:
        test_postgres_diagnostics()
        test_kerberos_diagnostics()
        test_pagila_diagnostics()
        test_diagnostic_log_creation()

        print("\n" + "="*60)
        print("✅ All diagnostic tests passed!")
        print("="*60)
        print("\nThe diagnostic system is working correctly:")
        print("• Automatic diagnostics trigger on service failures")
        print("• Service-specific checks identify common issues")
        print("• Detailed logs are saved with timestamps")
        print("• User-friendly summaries provide clear next steps")

    except AssertionError as e:
        print(f"\n❌ Test failed: {e}")
        sys.exit(1)
    except Exception as e:
        print(f"\n❌ Unexpected error: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)