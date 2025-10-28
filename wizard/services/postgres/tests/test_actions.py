"""Tests for PostgreSQL action functions - RED phase."""

import pytest
from wizard.services.postgres.actions import save_config, start_service, pull_image
from wizard.engine.runner import MockActionRunner


class TestSaveConfig:
    """Tests for save_config action."""

    def test_save_config_calls_runner_save_config(self):
        """Should call runner.save_config with correct config."""
        runner = MockActionRunner()
        ctx = {
            'services.postgres.image': 'postgres:17.5-alpine',
            'services.postgres.prebuilt': False,
            'services.postgres.auth_method': 'md5',
            'services.postgres.password': 'changeme'
        }

        save_config(ctx, runner)

        # Verify runner.save_config was called
        assert len(runner.calls) == 1
        call = runner.calls[0]
        assert call[0] == 'save_config'

        # Verify config structure
        config = call[1]
        assert 'services' in config
        assert 'postgres' in config['services']
        assert config['services']['postgres']['enabled'] is True
        assert config['services']['postgres']['image'] == 'postgres:17.5-alpine'
        assert config['services']['postgres']['prebuilt'] is False
        assert config['services']['postgres']['auth_method'] == 'md5'
        assert config['services']['postgres']['password'] == 'changeme'

        # Verify path
        assert call[2] == 'platform-config.yaml'

    def test_save_config_uses_defaults_for_missing_values(self):
        """Should use default values when context keys are missing."""
        runner = MockActionRunner()
        ctx = {
            'services.postgres.image': 'postgres:17.5-alpine'
        }

        save_config(ctx, runner)

        call = runner.calls[0]
        config = call[1]
        assert config['services']['postgres']['prebuilt'] is False
        assert config['services']['postgres']['auth_method'] == 'md5'
        assert config['services']['postgres']['password'] == 'changeme'


class TestStartService:
    """Tests for start_service action."""

    def test_start_service_calls_runner_run_shell(self):
        """Should call runner.run_shell with make start command."""
        runner = MockActionRunner()
        ctx = {}

        start_service(ctx, runner)

        # Verify runner.run_shell was called (filter out display calls)
        shell_calls = [c for c in runner.calls if c[0] == 'run_shell']
        assert len(shell_calls) == 1
        call = shell_calls[0]
        assert call[0] == 'run_shell'

        # Verify command
        command = call[1]
        assert command == ['make', '-C', 'platform-infrastructure', 'start']

    def test_start_service_no_context_required(self):
        """Should work with empty context."""
        runner = MockActionRunner()
        ctx = {}

        # Should not raise
        start_service(ctx, runner)
        shell_calls = [c for c in runner.calls if c[0] == 'run_shell']
        assert len(shell_calls) == 1


class TestPullImage:
    """Tests for pull_image action - validates prebuilt flag behavior."""

    def test_pull_image_layered_mode_pulls_image(self):
        """Layered mode (prebuilt=False): should pull image for customization."""
        runner = MockActionRunner()
        ctx = {
            'services.postgres.image': 'postgres:17.5-alpine',
            'services.postgres.prebuilt': False
        }

        pull_image(ctx, runner)

        # Verify docker pull was called
        shell_calls = [c for c in runner.calls if c[0] == 'run_shell']
        assert len(shell_calls) == 1
        command = shell_calls[0][1]
        assert command == ['docker', 'pull', 'postgres:17.5-alpine']

        # Verify appropriate message
        display_calls = [c for c in runner.calls if c[0] == 'display']
        assert any('Pulling' in str(c[1]) for c in display_calls)

    def test_pull_image_prebuilt_mode_still_pulls(self):
        """Prebuilt mode (prebuilt=True): should STILL pull image if needed.

        Prebuilt means 'use as-is without customization', not 'skip docker pull'.
        The image may still need to be pulled from registry.
        """
        runner = MockActionRunner()
        ctx = {
            'services.postgres.image': 'postgres:17.5-alpine',
            'services.postgres.prebuilt': True
        }

        pull_image(ctx, runner)

        # CRITICAL: Prebuilt should still pull image
        shell_calls = [c for c in runner.calls if c[0] == 'run_shell']
        assert len(shell_calls) == 1
        command = shell_calls[0][1]
        assert command == ['docker', 'pull', 'postgres:17.5-alpine']

        # Message should indicate using image as-is
        display_calls = [c for c in runner.calls if c[0] == 'display']
        assert any('prebuilt' in str(c[1]).lower() or 'as-is' in str(c[1]).lower()
                   for c in display_calls)

    def test_pull_image_uses_default_image(self):
        """Should use default image if not specified in context."""
        runner = MockActionRunner()
        ctx = {}

        pull_image(ctx, runner)

        shell_calls = [c for c in runner.calls if c[0] == 'run_shell']
        assert len(shell_calls) == 1
        command = shell_calls[0][1]
        assert command == ['docker', 'pull', 'postgres:17.5-alpine']

    def test_pull_image_handles_custom_image(self):
        """Should work with custom image URL."""
        runner = MockActionRunner()
        ctx = {
            'services.postgres.image': 'myorg/postgres:17-hardened',
            'services.postgres.prebuilt': True
        }

        pull_image(ctx, runner)

        shell_calls = [c for c in runner.calls if c[0] == 'run_shell']
        command = shell_calls[0][1]
        assert command == ['docker', 'pull', 'myorg/postgres:17-hardened']
