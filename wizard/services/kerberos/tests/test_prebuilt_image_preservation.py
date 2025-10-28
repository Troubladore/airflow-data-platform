"""Test that Kerberos prebuilt images are preserved, not overridden."""

import pytest
from wizard.services.kerberos.actions import save_config


class MockRunner:
    """Mock runner to capture save_config calls."""
    def __init__(self):
        self.saved_config = None

    def save_config(self, config, filename):
        self.saved_config = config


class TestPrebuiltImagePreservation:
    """Tests for issue #98 - prebuilt corporate images must be preserved."""

    def test_prebuilt_mode_preserves_corporate_image(self):
        """Should preserve corporate image path when use_prebuilt is True."""
        # Given: A corporate Kerberos image and prebuilt mode
        ctx = {
            'services.kerberos.image': 'mycorp.jfrog.io/docker-mirror/mycorp-approved-images/kerberos-base:latest',
            'services.kerberos.use_prebuilt': True,
            'services.kerberos.domain': 'CORP.EXAMPLE.COM'
        }
        runner = MockRunner()

        # When: Saving the Kerberos config
        save_config(ctx, runner)

        # Then: The corporate image should be preserved
        config = runner.saved_config
        assert config['services']['kerberos']['image'] == 'mycorp.jfrog.io/docker-mirror/mycorp-approved-images/kerberos-base:latest'
        # And NOT overridden to ubuntu:22.04
        assert 'ubuntu:22.04' not in config['services']['kerberos']['image']
        assert config['services']['kerberos']['use_prebuilt'] is True

    def test_layered_mode_uses_ubuntu_base(self):
        """Should use ubuntu base when use_prebuilt is False."""
        # Given: Layered mode (builds on top of base image)
        ctx = {
            'services.kerberos.use_prebuilt': False,
            'services.kerberos.domain': 'TEST.EXAMPLE.COM'
        }
        runner = MockRunner()

        # When: Saving the Kerberos config
        save_config(ctx, runner)

        # Then: Should use ubuntu base for layered build
        config = runner.saved_config
        assert config['services']['kerberos']['image'] == 'ubuntu:22.04'

    def test_missing_mode_defaults_to_layered(self):
        """Should default to layered mode when use_prebuilt not specified."""
        # Given: No use_prebuilt specified
        ctx = {
            'services.kerberos.domain': 'TEST.EXAMPLE.COM'
        }
        runner = MockRunner()

        # When: Saving the Kerberos config
        save_config(ctx, runner)

        # Then: Should use ubuntu base (layered default)
        config = runner.saved_config
        assert config['services']['kerberos']['image'] == 'ubuntu:22.04'

    def test_prebuilt_without_image_should_error(self):
        """Should error when use_prebuilt is true but no image provided."""
        # Given: Prebuilt mode but no image
        ctx = {
            'services.kerberos.use_prebuilt': True,
            'services.kerberos.domain': 'CORP.EXAMPLE.COM'
            # Note: No image provided
        }
        runner = MockRunner()

        # When/Then: Should raise an error
        with pytest.raises(ValueError, match="Prebuilt mode requires a Docker image"):
            save_config(ctx, runner)

    def test_prebuilt_with_registry_port_preserved(self):
        """Should preserve registry URLs with port numbers in prebuilt mode."""
        # Given: Corporate image with port number
        ctx = {
            'services.kerberos.image': 'internal.artifactory.company.com:8443/docker-prod/kerberos:v1.20',
            'services.kerberos.use_prebuilt': True,
            'services.kerberos.domain': 'CORP.EXAMPLE.COM'
        }
        runner = MockRunner()

        # When: Saving the Kerberos config
        save_config(ctx, runner)

        # Then: The corporate image with port should be preserved
        config = runner.saved_config
        assert config['services']['kerberos']['image'] == 'internal.artifactory.company.com:8443/docker-prod/kerberos:v1.20'