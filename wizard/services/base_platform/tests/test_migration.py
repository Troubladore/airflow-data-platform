"""Test migration from services.postgres to services.base_platform."""

import pytest
from unittest.mock import Mock
from wizard.services.base_platform.actions import migrate_legacy_postgres_config


class TestLegacyPostgresMigration:
    """Test migration of old services.postgres keys to services.base_platform."""

    def test_migrates_postgres_keys_to_base_platform(self):
        """Should migrate all services.postgres.* keys to services.base_platform.postgres.*"""
        # Test migration from OLD keys (services.postgres.*) to NEW keys (services.base_platform.postgres.*)
        ctx = {
            'services.postgres.enabled': True,
            'services.postgres.image': 'postgres:17.5-alpine',
            'services.postgres.port': 5432,
            'services.postgres.user': 'platform_admin',
            'services.postgres.password': 'changeme',
            'services.postgres.passwordless': False
        }

        mock_runner = Mock()
        mock_runner.save_config = Mock()

        # Act - Run migration
        migrate_legacy_postgres_config(ctx, mock_runner)

        # Assert - OLD keys should be deleted
        assert 'services.postgres.enabled' not in ctx
        assert 'services.postgres.image' not in ctx
        assert 'services.postgres.port' not in ctx
        assert 'services.postgres.user' not in ctx
        assert 'services.postgres.password' not in ctx
        assert 'services.postgres.passwordless' not in ctx

        # Assert - NEW keys should be created in context
        assert ctx['services.base_platform.postgres.enabled'] == True
        assert ctx['services.base_platform.postgres.image'] == 'postgres:17.5-alpine'
        assert ctx['services.base_platform.postgres.port'] == 5432
        assert ctx['services.base_platform.postgres.user'] == 'platform_admin'
        assert ctx['services.base_platform.postgres.password'] == 'changeme'
        assert ctx['services.base_platform.postgres.passwordless'] == False

        # Assert - Migration was called and saved config
        mock_runner.save_config.assert_called_once()

        # Verify the saved config has the correct structure (NEW keys)
        call_args = mock_runner.save_config.call_args[0]
        saved_config = call_args[0]

        assert 'services' in saved_config
        assert 'base_platform' in saved_config['services']
        assert 'postgres' in saved_config['services']['base_platform']
        assert saved_config['services']['base_platform']['postgres']['enabled'] == True
        assert saved_config['services']['base_platform']['postgres']['image'] == 'postgres:17.5-alpine'

    def test_does_nothing_when_no_old_keys_present(self):
        """Should be idempotent - safe to run when no old keys exist."""
        # Arrange - Context with no migration keys
        ctx = {}

        mock_runner = Mock()
        mock_runner.save_config = Mock()

        # Act - Run migration
        migrate_legacy_postgres_config(ctx, mock_runner)

        # Assert - No keys were added
        assert len(ctx) == 0

        # Assert - save_config was not called (no migration needed)
        assert mock_runner.save_config.call_count == 0

    def test_saves_config_after_migration(self):
        """Should save updated config after migration."""
        # Arrange - Use OLD keys that need migration
        ctx = {
            'services.postgres.enabled': True,
            'services.postgres.image': 'postgres:17.5-alpine'
        }

        mock_runner = Mock()
        mock_runner.save_config = Mock()

        # Act
        migrate_legacy_postgres_config(ctx, mock_runner)

        # Assert - OLD keys should be deleted
        assert 'services.postgres.enabled' not in ctx
        assert 'services.postgres.image' not in ctx

        # Assert - NEW keys should be in context
        assert ctx['services.base_platform.postgres.enabled'] == True
        assert ctx['services.base_platform.postgres.image'] == 'postgres:17.5-alpine'

        # Assert - save_config was called
        mock_runner.save_config.assert_called_once()

        # Verify the saved config has the new structure
        call_args = mock_runner.save_config.call_args[0]
        saved_config = call_args[0]

        assert 'services' in saved_config
        assert 'base_platform' in saved_config['services']
        assert 'postgres' in saved_config['services']['base_platform']
