"""Test migration from services.postgres to services.base_platform."""

import pytest
from unittest.mock import Mock
from wizard.services.postgres.actions import migrate_legacy_postgres_config


class TestLegacyPostgresMigration:
    """Test migration of old services.postgres keys to services.base_platform."""

    def test_migrates_postgres_keys_to_base_platform(self):
        """Should migrate all services.postgres.* keys to services.base_platform.postgres.*"""
        # Arrange - Create context with old keys
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

        # Assert - New keys should exist
        assert ctx.get('services.base_platform.postgres.enabled') == True
        assert ctx.get('services.base_platform.postgres.image') == 'postgres:17.5-alpine'
        assert ctx.get('services.base_platform.postgres.port') == 5432
        assert ctx.get('services.base_platform.postgres.user') == 'platform_admin'
        assert ctx.get('services.base_platform.postgres.password') == 'changeme'
        assert ctx.get('services.base_platform.postgres.passwordless') == False

        # Assert - Old keys should be deleted
        assert 'services.postgres.enabled' not in ctx
        assert 'services.postgres.image' not in ctx
        assert 'services.postgres.port' not in ctx
        assert 'services.postgres.user' not in ctx
        assert 'services.postgres.password' not in ctx
        assert 'services.postgres.passwordless' not in ctx

    def test_does_nothing_when_no_old_keys_present(self):
        """Should be idempotent - safe to run when no old keys exist."""
        # Arrange - Context already has new keys
        ctx = {
            'services.base_platform.postgres.enabled': True,
            'services.base_platform.postgres.image': 'postgres:17.5-alpine'
        }

        mock_runner = Mock()
        mock_runner.save_config = Mock()

        # Act - Run migration
        migrate_legacy_postgres_config(ctx, mock_runner)

        # Assert - New keys still exist unchanged
        assert ctx.get('services.base_platform.postgres.enabled') == True
        assert ctx.get('services.base_platform.postgres.image') == 'postgres:17.5-alpine'

        # Assert - No errors occurred
        assert mock_runner.save_config.call_count <= 1

    def test_saves_config_after_migration(self):
        """Should save updated config after migration."""
        # Arrange
        ctx = {
            'services.postgres.enabled': True,
            'services.postgres.image': 'postgres:17.5-alpine'
        }

        mock_runner = Mock()
        mock_runner.save_config = Mock()

        # Act
        migrate_legacy_postgres_config(ctx, mock_runner)

        # Assert - save_config was called
        mock_runner.save_config.assert_called_once()

        # Verify the saved config has the new structure
        call_args = mock_runner.save_config.call_args[0]
        saved_config = call_args[0]

        assert 'services' in saved_config
        assert 'base_platform' in saved_config['services']
        assert 'postgres' in saved_config['services']['base_platform']
