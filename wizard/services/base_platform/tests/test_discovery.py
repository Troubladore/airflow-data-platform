"""Tests for PostgreSQL discovery functions."""

import pytest
from wizard.services.base_platform import discovery
from wizard.engine.runner import MockActionRunner


class TestDiscoverContainers:
    """Test discovering postgres containers."""

    def test_discover_containers_returns_list(self):
        """discover_containers() should return list of dicts."""
        runner = MockActionRunner()
        result = discovery.discover_containers(runner)
        assert isinstance(result, list)

    def test_discover_containers_finds_postgres(self):
        """Should find postgres container when it exists."""
        runner = MockActionRunner()
        runner.responses['run_shell'] = {
            ('docker', 'ps', '-a', '--filter', 'name=postgres', '--format', '{{.Names}}|{{.Status}}'):
                'postgres|Up 2 days\nplatform-postgres|Exited\n'
        }

        result = discovery.discover_containers(runner)

        assert len(result) == 2
        assert result[0]['name'] == 'postgres'
        assert result[0]['status'] == 'Up 2 days'
        assert result[1]['name'] == 'platform-postgres'


class TestDiscoverImages:
    """Test discovering postgres images."""

    def test_discover_images_returns_list(self):
        """discover_images() should return list of dicts."""
        runner = MockActionRunner()
        result = discovery.discover_images(runner)
        assert isinstance(result, list)

    def test_discover_images_finds_postgres_images(self):
        """Should find postgres images with size."""
        runner = MockActionRunner()
        runner.responses['run_shell'] = {
            ('docker', 'images', '--filter', 'reference=postgres', '--format', '{{.Repository}}:{{.Tag}}|{{.Size}}'):
                'postgres:17.5|400MB\npostgres:16|380MB\n'
        }

        result = discovery.discover_images(runner)

        assert len(result) == 2
        assert result[0]['name'] == 'postgres:17.5'
        assert result[0]['size'] == '400MB'


class TestDiscoverVolumes:
    """Test discovering postgres volumes."""

    def test_discover_volumes_returns_list(self):
        """discover_volumes() should return list of dicts."""
        runner = MockActionRunner()
        result = discovery.discover_volumes(runner)
        assert isinstance(result, list)

    def test_discover_volumes_finds_postgres_volumes(self):
        """Should find postgres data volumes."""
        runner = MockActionRunner()
        runner.responses['run_shell'] = {
            ('docker', 'volume', 'ls', '--filter', 'name=postgres', '--format', '{{.Name}}'):
                'postgres_data\npostgres_logs\n'
        }

        result = discovery.discover_volumes(runner)

        assert len(result) == 2
        assert result[0]['name'] == 'postgres_data'


class TestDiscoverFiles:
    """Test discovering postgres config files."""

    def test_discover_files_returns_list(self):
        """discover_files() should return list of file paths."""
        runner = MockActionRunner()
        result = discovery.discover_files(runner)
        assert isinstance(result, list)
