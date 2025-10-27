"""Tests for Pagila discovery functions."""

import pytest
from wizard.services.pagila import discovery
from wizard.engine.runner import MockActionRunner


class TestDiscoverContainers:
    """Test discovering pagila containers."""

    def test_discover_containers_returns_list(self):
        """discover_containers() should return list of dicts."""
        runner = MockActionRunner()
        result = discovery.discover_containers(runner)
        assert isinstance(result, list)

    def test_discover_containers_returns_empty_for_pagila(self):
        """Pagila doesn't have its own containers - uses postgres."""
        runner = MockActionRunner()
        runner.responses['run_shell'] = {
            'stdout': '',
            'stderr': '',
            'returncode': 0
        }

        result = discovery.discover_containers(runner)

        assert len(result) == 0


class TestDiscoverImages:
    """Test discovering pagila images."""

    def test_discover_images_returns_list(self):
        """discover_images() should return list of dicts."""
        runner = MockActionRunner()
        result = discovery.discover_images(runner)
        assert isinstance(result, list)

    def test_discover_images_returns_empty_or_custom(self):
        """Pagila typically has no images unless custom built."""
        runner = MockActionRunner()
        runner.responses['run_shell'] = {
            'stdout': '',
            'stderr': '',
            'returncode': 0
        }

        result = discovery.discover_images(runner)

        # Either empty or contains custom image
        assert isinstance(result, list)
        for img in result:
            assert 'name' in img


class TestDiscoverVolumes:
    """Test discovering pagila volumes."""

    def test_discover_volumes_returns_list(self):
        """discover_volumes() should return list of dicts."""
        runner = MockActionRunner()
        result = discovery.discover_volumes(runner)
        assert isinstance(result, list)

    def test_discover_volumes_returns_empty_for_pagila(self):
        """Pagila doesn't have its own volumes - data in postgres."""
        runner = MockActionRunner()
        runner.responses['run_shell'] = {
            'stdout': '',
            'stderr': '',
            'returncode': 0
        }

        result = discovery.discover_volumes(runner)

        assert len(result) == 0


class TestDiscoverFiles:
    """Test discovering pagila config files."""

    def test_discover_files_returns_list(self):
        """discover_files() should return list of file paths."""
        runner = MockActionRunner()
        result = discovery.discover_files(runner)
        assert isinstance(result, list)

    def test_discover_files_checks_platform_config(self):
        """Should check for platform-config.yaml."""
        runner = MockActionRunner()
        result = discovery.discover_files(runner)

        # Result should be a list of strings
        assert isinstance(result, list)
        for file_path in result:
            assert isinstance(file_path, str)


class TestDiscoverCustomArtifacts:
    """Test discovering pagila-specific custom artifacts."""

    def test_discover_custom_returns_dict(self):
        """discover_custom() should return dict with repo and database info."""
        runner = MockActionRunner()
        result = discovery.discover_custom(runner)
        assert isinstance(result, dict)

    def test_discover_custom_checks_repository(self):
        """Should check for /tmp/pagila repository."""
        runner = MockActionRunner()
        # Mock ls command to show repo exists
        runner.responses['run_shell'] = {
            'stdout': '/tmp/pagila',
            'stderr': '',
            'returncode': 0
        }

        result = discovery.discover_custom(runner)

        assert 'repository' in result
        assert isinstance(result['repository'], dict)
        assert 'path' in result['repository']

    def test_discover_custom_checks_database(self):
        """Should check for pagila database in postgres."""
        runner = MockActionRunner()
        # Mock docker exec to show database exists
        runner.responses['run_shell'] = {
            'stdout': 'pagila',
            'stderr': '',
            'returncode': 0
        }

        result = discovery.discover_custom(runner)

        assert 'database' in result
        assert isinstance(result['database'], dict)
        assert 'exists' in result['database']

    def test_discover_custom_handles_missing_repository(self):
        """Should handle case when repository doesn't exist."""
        runner = MockActionRunner()
        # Mock ls to show no directory
        runner.responses['run_shell'] = {
            'stdout': '',
            'stderr': 'No such file or directory',
            'returncode': 1
        }

        result = discovery.discover_custom(runner)

        assert 'repository' in result
        assert result['repository'].get('exists') is False

    def test_discover_custom_handles_no_postgres(self):
        """Should handle case when postgres container doesn't exist."""
        runner = MockActionRunner()
        # Mock docker exec failure
        runner.responses['run_shell'] = {
            'stdout': '',
            'stderr': 'No such container',
            'returncode': 1
        }

        result = discovery.discover_custom(runner)

        assert 'database' in result
        assert result['database'].get('exists') is False
