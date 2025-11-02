"""Tests for PostgreSQL action functions - RED phase."""

import pytest
from wizard.services.base_platform.actions import save_config, start_service, pull_image
from wizard.engine.runner import MockActionRunner


class TestSaveConfig:
    """Tests for save_config action."""

    def test_save_config_calls_runner_save_config(self):
        """Should call runner.save_config with correct config."""
        runner = MockActionRunner()
        ctx = {
            'services.base_platform.postgres.image': 'postgres:17.5-alpine',
            'services.base_platform.postgres.require_password': True,
            'services.base_platform.postgres.password': 'changeme'
        }

        save_config(ctx, runner)

        # Verify runner.save_config was called
        save_config_calls = [c for c in runner.calls if c[0] == 'save_config']
        assert len(save_config_calls) == 1
        call = save_config_calls[0]
        assert call[0] == 'save_config'

        # Verify config structure
        config = call[1]
        assert 'services' in config
        assert 'base_platform' in config['services']
        assert config['services']['base_platform']['postgres']['enabled'] is True
        assert config['services']['base_platform']['postgres']['image'] == 'postgres:17.5-alpine'
        assert config['services']['base_platform']['postgres']['auth_method'] == 'md5'
        assert config['services']['base_platform']['postgres']['password'] == 'changeme'

        # Verify path
        assert call[2] == 'platform-config.yaml'

    def test_save_config_uses_defaults_for_missing_values(self):
        """Should use default values when context keys are missing."""
        runner = MockActionRunner()
        ctx = {
            'services.base_platform.postgres.image': 'postgres:17.5-alpine'
        }

        save_config(ctx, runner)

        call = runner.calls[0]
        config = call[1]
        # When require_password is not set, defaults to True (md5 auth)
        assert config['services']['base_platform']['postgres']['auth_method'] == 'md5'
        assert config['services']['base_platform']['postgres']['password'] == 'changeme'

    def test_save_config_creates_env_file(self):
        """Should create platform-bootstrap/.env file with required variables."""
        runner = MockActionRunner()
        ctx = {
            'services.base_platform.postgres.image': 'postgres:17.5-alpine',
            'services.base_platform.postgres.require_password': True,
            'services.base_platform.postgres.password': 'secret_password',
            'services.openmetadata.enabled': True,
            'services.kerberos.enabled': False,
            'services.pagila.enabled': True
        }

        save_config(ctx, runner)

        # Verify write_file was called
        write_calls = [c for c in runner.calls if c[0] == 'write_file']
        assert len(write_calls) == 1, "Should call write_file exactly once"

        call = write_calls[0]
        assert call[1] == 'platform-bootstrap/.env', "Should write to platform-bootstrap/.env"

        # Verify .env content
        env_content = call[2]
        assert 'PLATFORM_DB_PASSWORD=secret_password' in env_content, "Should set PLATFORM_DB_PASSWORD"
        assert 'OPENMETADATA_DB_PASSWORD=' in env_content, "Should include OPENMETADATA_DB_PASSWORD when enabled"
        assert 'ENABLE_OPENMETADATA=true' in env_content, "Should include service enable flag"
        assert 'ENABLE_KERBEROS=false' in env_content, "Should include service enable flag"
        assert 'ENABLE_PAGILA=true' in env_content, "Should include service enable flag"

    def test_save_config_creates_env_file_with_trust_auth(self):
        """Should create .env file even with trust authentication (no password)."""
        runner = MockActionRunner()
        ctx = {
            'services.base_platform.postgres.require_password': False,
            'services.base_platform.postgres.image': 'postgres:17.5-alpine',
            'services.openmetadata.enabled': False,
            'services.kerberos.enabled': False,
            'services.pagila.enabled': False
        }

        save_config(ctx, runner)

        # Verify write_file was called
        write_calls = [c for c in runner.calls if c[0] == 'write_file']
        assert len(write_calls) == 1

        call = write_calls[0]
        env_content = call[2]
        # With trust auth, we still need .env but password can be empty or placeholder
        assert 'PLATFORM_DB_PASSWORD=' in env_content, "Should include PLATFORM_DB_PASSWORD line"

    def test_save_config_persists_require_password_field(self):
        """Should save require_password to YAML so it can be loaded as default on next run.

        This ensures the user's choice (y/n for password) is remembered across
        wizard sessions, not just the derived auth_method.
        """
        runner = MockActionRunner()
        ctx = {
            'services.base_platform.postgres.image': 'postgres:17.5-alpine',
            'services.base_platform.postgres.require_password': False,  # User chose no password
        }

        save_config(ctx, runner)

        # Verify config was saved
        save_config_calls = [c for c in runner.calls if c[0] == 'save_config']
        assert len(save_config_calls) == 1

        config = save_config_calls[0][1]
        postgres_config = config['services']['base_platform']['postgres']

        # The config should save require_password so it can be used as default_from on next run
        assert 'require_password' in postgres_config, "Should save require_password field"
        assert postgres_config['require_password'] is False, "Should preserve the False value"

        # Should also save the derived auth_method for the platform
        assert postgres_config['auth_method'] == 'trust'


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
        """Should pull Docker Hub images."""
        runner = MockActionRunner()
        ctx = {
            'services.base_platform.postgres.image': 'postgres:17.5-alpine'
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
        """Docker Hub images should always be pulled to get the latest version.

        For standard Docker Hub images, we don't check local existence first.
        """
        runner = MockActionRunner()
        ctx = {
            'services.base_platform.postgres.image': 'postgres:17.5-alpine'
        }

        pull_image(ctx, runner)

        # Should pull Docker Hub images without checking local existence first
        shell_calls = [c for c in runner.calls if c[0] == 'run_shell']
        assert len(shell_calls) == 1
        command = shell_calls[0][1]
        assert command == ['docker', 'pull', 'postgres:17.5-alpine']

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
        """Should check if custom org image exists locally first."""
        runner = MockActionRunner()
        # Set up mock to return failure for docker inspect (image doesn't exist)
        runner.responses['run_shell'] = {
            tuple(['docker', 'image', 'inspect', 'myorg/postgres:17-hardened']):
                {'returncode': 1, 'stdout': '', 'stderr': 'Error: No such image'}
        }
        ctx = {
            'services.base_platform.postgres.image': 'myorg/postgres:17-hardened'
        }

        pull_image(ctx, runner)

        shell_calls = [c for c in runner.calls if c[0] == 'run_shell']
        # Custom org images (with /) are treated as corporate images
        # So it checks local existence first
        assert len(shell_calls) >= 1
        # First call should be docker image inspect (checking local existence)
        inspect_calls = [c for c in shell_calls if 'inspect' in c[1]]
        assert len(inspect_calls) == 1
        # Second call should be docker pull
        pull_calls = [c for c in shell_calls if 'pull' in c[1]]
        assert len(pull_calls) == 1
        assert pull_calls[0][1] == ['docker', 'pull', 'myorg/postgres:17-hardened']
