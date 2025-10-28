"""Test diagnostic utilities for service failures."""

import pytest
import os
import tempfile
from datetime import datetime
from wizard.utils.diagnostics import (
    DiagnosticCollector,
    ServiceDiagnostics,
    create_diagnostic_summary
)


class MockRunner:
    """Mock runner for testing."""
    def __init__(self):
        self.displays = []
        self.commands = []
        self.mock_responses = {}

    def display(self, msg):
        self.displays.append(msg)

    def run_shell(self, cmd, **kwargs):
        self.commands.append(cmd)
        cmd_str = ' '.join(cmd) if isinstance(cmd, list) else cmd
        if cmd_str in self.mock_responses:
            return self.mock_responses[cmd_str]
        return {'returncode': 0, 'stdout': '', 'stderr': ''}


class TestDiagnosticCollector:
    """Test the diagnostic collection system."""

    def test_collector_captures_context_on_failure(self):
        """Should capture service, phase, and error details."""
        collector = DiagnosticCollector()

        # Record a failure
        collector.record_failure(
            service="postgres",
            phase="docker_compose_up",
            error="pull access denied",
            context={
                "image": "corp.registry/postgres:17",
                "command": "docker compose up -d",
                "working_dir": "platform-infrastructure"
            }
        )

        # Should have one failure recorded
        assert len(collector.failures) == 1
        failure = collector.failures[0]

        assert failure['service'] == 'postgres'
        assert failure['phase'] == 'docker_compose_up'
        assert failure['error'] == 'pull access denied'
        assert failure['context']['image'] == 'corp.registry/postgres:17'
        assert 'timestamp' in failure

    def test_collector_generates_summary(self):
        """Should generate human-readable summary of failures."""
        collector = DiagnosticCollector()

        # Record multiple failures
        collector.record_failure(
            service="postgres",
            phase="docker_compose_up",
            error="manifest unknown"
        )
        collector.record_failure(
            service="kerberos",
            phase="start_service",
            error="container exited"
        )

        summary = collector.get_summary()

        assert "2 service failures detected" in summary
        assert "postgres failed at: docker_compose_up" in summary
        assert "kerberos failed at: start_service" in summary

    def test_collector_saves_detailed_log(self):
        """Should save detailed diagnostics to timestamped log file."""
        collector = DiagnosticCollector()

        collector.record_failure(
            service="postgres",
            phase="pull_image",
            error="authentication required",
            context={"registry": "artifactory.corp.com"}
        )

        # Save to log
        with tempfile.TemporaryDirectory() as tmpdir:
            log_path = collector.save_log(directory=tmpdir)

            assert os.path.exists(log_path)
            assert "diagnostic_" in log_path
            assert log_path.endswith(".log")

            # Check content
            with open(log_path, 'r') as f:
                content = f.read()
                assert "POSTGRES" in content  # It's uppercase in the log
                assert "authentication required" in content
                assert "artifactory.corp.com" in content


class TestServiceDiagnostics:
    """Test service-specific diagnostic runners."""

    def test_postgres_diagnostics_check_container_exists(self):
        """Should check if postgres container was created."""
        runner = MockRunner()
        diagnostics = ServiceDiagnostics(runner)

        # Mock no container exists
        runner.mock_responses['docker ps -a --format {{.Names}}'] = {
            'returncode': 0,
            'stdout': 'other-container\n'
        }

        result = diagnostics.diagnose_postgres_failure({
            'services.postgres.image': 'postgres:17'
        })

        assert result['container_exists'] is False
        assert result['diagnosis'] == 'Container never created - Docker Compose failed'
        # Check that docker ps command was run
        assert any('docker' in cmd and 'ps' in cmd for cmd in runner.commands)

    def test_kerberos_diagnostics_check_prebuilt_mode(self):
        """Should detect prebuilt mode issues for Kerberos."""
        runner = MockRunner()
        diagnostics = ServiceDiagnostics(runner)

        result = diagnostics.diagnose_kerberos_failure({
            'services.kerberos.image': 'corp.registry/kerberos:latest',
            'services.kerberos.use_prebuilt': True
        })

        assert result['using_prebuilt'] is True
        # Check any note mentions prebuilt
        assert any('Prebuilt' in note or 'prebuilt' in note for note in result['notes'])

    def test_pagila_diagnostics_check_git_clone(self):
        """Should check if Pagila repo clone succeeded."""
        runner = MockRunner()
        diagnostics = ServiceDiagnostics(runner)

        # Mock that pagila directory doesn't exist
        runner.mock_responses['test -d ../pagila'] = {
            'returncode': 1  # Directory doesn't exist
        }

        result = diagnostics.diagnose_pagila_failure({
            'services.pagila.repo_url': 'https://github.com/devrimgunduz/pagila.git'
        })

        assert result['repo_cloned'] is False
        assert 'Git clone may have failed' in result['diagnosis']


class TestDiagnosticIntegration:
    """Test the full diagnostic flow integration."""

    def test_create_summary_formats_for_user(self):
        """Should create user-friendly summary with clear next steps."""
        failures = [
            {
                'service': 'postgres',
                'phase': 'docker_compose_up',
                'error': 'pull access denied',
                'diagnosis': 'Registry requires authentication'
            }
        ]

        summary = create_diagnostic_summary(failures, log_file='diagnostic_20251028.log')

        # Should have clear sections
        assert '🔴 SETUP FAILED' in summary
        assert 'What happened:' in summary
        assert 'postgres' in summary
        assert 'Next steps:' in summary
        assert 'docker login' in summary
        assert 'Full details saved' in summary
        assert 'diagnostic_20251028.log' in summary