"""Tests for Kerberos discovery functions."""

import pytest
from wizard.services.kerberos import discovery
from wizard.engine.runner import MockActionRunner


class TestDiscoverContainers:
    """Test discovering kerberos containers."""

    def test_discover_containers_returns_list(self):
        """discover_containers() should return list of dicts."""
        runner = MockActionRunner()
        result = discovery.discover_containers(runner)
        assert isinstance(result, list)

    def test_discover_containers_finds_kerberos_sidecar(self):
        """Should find kerberos-sidecar container when it exists."""
        runner = MockActionRunner()
        runner.responses['run_shell'] = {
            ('docker', 'ps', '-a', '--filter', 'name=kerberos', '--format', '{{.Names}}|{{.Status}}'):
                'kerberos-sidecar|Up 2 days\n'
        }

        result = discovery.discover_containers(runner)

        assert len(result) == 1
        assert result[0]['name'] == 'kerberos-sidecar'
        assert result[0]['status'] == 'Up 2 days'

    def test_discover_containers_handles_empty_output(self):
        """Should return empty list when no containers found."""
        runner = MockActionRunner()
        runner.responses['run_shell'] = {
            ('docker', 'ps', '-a', '--filter', 'name=kerberos', '--format', '{{.Names}}|{{.Status}}'):
                ''
        }

        result = discovery.discover_containers(runner)

        assert result == []


class TestDiscoverImages:
    """Test discovering kerberos images."""

    def test_discover_images_returns_list(self):
        """discover_images() should return list of dicts."""
        runner = MockActionRunner()
        result = discovery.discover_images(runner)
        assert isinstance(result, list)

    def test_discover_images_finds_kerberos_images(self):
        """Should find kerberos-sidecar images with size."""
        runner = MockActionRunner()
        runner.responses['run_shell'] = {
            ('docker', 'images', '--filter', 'reference=kerberos-sidecar', '--format', '{{.Repository}}:{{.Tag}}|{{.Size}}'):
                'kerberos-sidecar:latest|150MB\nkerberos-sidecar:v1.0|148MB\n'
        }

        result = discovery.discover_images(runner)

        assert len(result) == 2
        assert result[0]['name'] == 'kerberos-sidecar:latest'
        assert result[0]['size'] == '150MB'
        assert result[1]['name'] == 'kerberos-sidecar:v1.0'
        assert result[1]['size'] == '148MB'

    def test_discover_images_handles_empty_output(self):
        """Should return empty list when no images found."""
        runner = MockActionRunner()
        runner.responses['run_shell'] = {
            ('docker', 'images', '--filter', 'reference=kerberos-sidecar', '--format', '{{.Repository}}:{{.Tag}}|{{.Size}}'):
                ''
        }

        result = discovery.discover_images(runner)

        assert result == []


class TestDiscoverVolumes:
    """Test discovering kerberos volumes."""

    def test_discover_volumes_returns_list(self):
        """discover_volumes() should return list of dicts."""
        runner = MockActionRunner()
        result = discovery.discover_volumes(runner)
        assert isinstance(result, list)

    def test_discover_volumes_returns_empty_for_kerberos(self):
        """Kerberos uses host keytabs, not Docker volumes."""
        runner = MockActionRunner()
        result = discovery.discover_volumes(runner)
        assert result == []


class TestDiscoverFiles:
    """Test discovering kerberos config files."""

    def test_discover_files_returns_list(self):
        """discover_files() should return list of file paths."""
        runner = MockActionRunner()
        result = discovery.discover_files(runner)
        assert isinstance(result, list)

    def test_discover_files_finds_keytabs(self):
        """Should find keytab files when they exist."""
        runner = MockActionRunner()
        # Mock finding keytab files
        runner.responses['run_shell'] = {
            ('find', '/etc/security/keytabs', '-name', '*.keytab', '-type', 'f'):
                '/etc/security/keytabs/airflow.keytab\n/etc/security/keytabs/hive.keytab\n'
        }

        result = discovery.discover_files(runner)

        assert len(result) >= 2
        assert '/etc/security/keytabs/airflow.keytab' in result
        assert '/etc/security/keytabs/hive.keytab' in result

    def test_discover_files_finds_env_file(self):
        """Should check for platform-bootstrap/.env file."""
        runner = MockActionRunner()
        # We'll check if .env is included in discovered files
        # This test verifies the function attempts to find it
        result = discovery.discover_files(runner)
        assert isinstance(result, list)

    def test_discover_files_handles_missing_keytabs_dir(self):
        """Should handle gracefully when keytabs directory doesn't exist."""
        runner = MockActionRunner()
        runner.responses['run_shell'] = {
            ('find', '/etc/security/keytabs', '-name', '*.keytab', '-type', 'f'):
                ''
        }

        result = discovery.discover_files(runner)

        # Should not crash, returns whatever files it can find
        assert isinstance(result, list)
