"""Tests for OpenMetadata discovery functions."""

import pytest
from wizard.services.openmetadata import discovery
from wizard.engine.runner import MockActionRunner


class TestDiscoverContainers:
    """Test discovering OpenMetadata containers."""

    def test_discover_containers_returns_list(self):
        """discover_containers() should return list of dicts."""
        runner = MockActionRunner()
        result = discovery.discover_containers(runner)
        assert isinstance(result, list)

    def test_discover_containers_finds_openmetadata_server(self):
        """Should find openmetadata-server container when it exists."""
        runner = MockActionRunner()
        runner.responses['run_shell'] = {
            ('docker', 'ps', '-a', '--filter', 'name=openmetadata', '--format', '{{.Names}}|{{.Status}}'):
                'openmetadata-server|Up 5 days\nopenmetadata-ingestion|Up 5 days\n',
            ('docker', 'ps', '-a', '--filter', 'name=opensearch', '--format', '{{.Names}}|{{.Status}}'):
                'opensearch|Up 5 days\n'
        }

        result = discovery.discover_containers(runner)

        assert len(result) == 3
        assert result[0]['name'] == 'openmetadata-server'
        assert result[0]['status'] == 'Up 5 days'
        assert result[1]['name'] == 'openmetadata-ingestion'
        assert result[2]['name'] == 'opensearch'


class TestDiscoverImages:
    """Test discovering OpenMetadata images."""

    def test_discover_images_returns_list(self):
        """discover_images() should return list of dicts."""
        runner = MockActionRunner()
        result = discovery.discover_images(runner)
        assert isinstance(result, list)

    def test_discover_images_finds_openmetadata_images(self):
        """Should find openmetadata/* images with size."""
        runner = MockActionRunner()
        runner.responses['run_shell'] = {
            ('docker', 'images', '--filter', 'reference=openmetadata', '--format', '{{.Repository}}:{{.Tag}}|{{.Size}}'):
                'openmetadata/server:1.2.3|850MB\nopenmetadata/ingestion:1.2.3|1.2GB\n',
            ('docker', 'images', '--filter', 'reference=opensearchproject', '--format', '{{.Repository}}:{{.Tag}}|{{.Size}}'):
                ''
        }

        result = discovery.discover_images(runner)

        assert len(result) == 2
        assert result[0]['name'] == 'openmetadata/server:1.2.3'
        assert result[0]['size'] == '850MB'
        assert result[1]['name'] == 'openmetadata/ingestion:1.2.3'
        assert result[1]['size'] == '1.2GB'

    def test_discover_images_finds_opensearch_images(self):
        """Should find opensearchproject/* images."""
        runner = MockActionRunner()
        runner.responses['run_shell'] = {
            ('docker', 'images', '--filter', 'reference=openmetadata', '--format', '{{.Repository}}:{{.Tag}}|{{.Size}}'):
                '',
            ('docker', 'images', '--filter', 'reference=opensearchproject', '--format', '{{.Repository}}:{{.Tag}}|{{.Size}}'):
                'opensearchproject/opensearch:2.11.0|600MB\n'
        }

        result = discovery.discover_images(runner)

        assert len(result) == 1
        assert result[0]['name'] == 'opensearchproject/opensearch:2.11.0'
        assert result[0]['size'] == '600MB'


class TestDiscoverVolumes:
    """Test discovering OpenMetadata volumes."""

    def test_discover_volumes_returns_list(self):
        """discover_volumes() should return list of dicts."""
        runner = MockActionRunner()
        result = discovery.discover_volumes(runner)
        assert isinstance(result, list)

    def test_discover_volumes_finds_openmetadata_volumes(self):
        """Should find openmetadata_data and opensearch_data volumes."""
        runner = MockActionRunner()
        runner.responses['run_shell'] = {
            ('docker', 'volume', 'ls', '--filter', 'name=openmetadata', '--format', '{{.Name}}'):
                'openmetadata_data\n',
            ('docker', 'volume', 'ls', '--filter', 'name=opensearch', '--format', '{{.Name}}'):
                'opensearch_data\n'
        }

        result = discovery.discover_volumes(runner)

        assert len(result) == 2
        assert result[0]['name'] == 'openmetadata_data'
        assert result[1]['name'] == 'opensearch_data'


class TestDiscoverFiles:
    """Test discovering OpenMetadata config files."""

    def test_discover_files_returns_list(self):
        """discover_files() should return list of file paths."""
        runner = MockActionRunner()
        result = discovery.discover_files(runner)
        assert isinstance(result, list)
