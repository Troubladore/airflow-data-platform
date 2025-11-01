"""Test corporate registry image paths - RED phase for TDD."""

import pytest
from wizard.services.base_platform.validators import validate_image_url


class TestCorporateImagePaths:
    """Comprehensive tests for complex corporate Docker registry paths.

    These tests ensure the platform handles enterprise registry configurations
    as reported in issue #98.
    """

    def test_jfrog_deep_path_with_date_tag(self):
        """Should accept JFrog Artifactory with deep path and date-based tag."""
        # This is the exact path from issue #98 that users need
        image = "mycorp.jfrog.io/docker-mirror/mycorp-approved-images/postgres/17.5:2025.10.01"
        result = validate_image_url(image, {})
        assert result == image

    def test_registry_with_port_and_versioned_tag(self):
        """Should accept registry URL with port number and complex version tag."""
        image = "internal.artifactory.company.com:8443/docker-prod/postgres/17.5:v2025.10-hardened"
        result = validate_image_url(image, {})
        assert result == image

    def test_registry_with_port_5000(self):
        """Should accept registry with common Docker registry port 5000."""
        image = "company.registry.io:5000/security/kerberos/debian:12-slim-krb5-v1.20"
        result = validate_image_url(image, {})
        assert result == image

    def test_openmetadata_corporate_registry(self):
        """Should accept OpenMetadata server from corporate registry."""
        image = "artifactory.corp.net/docker-public/openmetadata/server:1.5.11-approved"
        result = validate_image_url(image, {})
        assert result == image

    def test_opensearch_enterprise_registry(self):
        """Should accept OpenSearch with enterprise suffix."""
        image = "docker-registry.internal.company.com/data/opensearch:2.18.0-enterprise"
        result = validate_image_url(image, {})
        assert result == image

    def test_kerberos_prebuilt_corporate_path(self):
        """Should accept Kerberos prebuilt image with complex corporate path."""
        image = "mycorp.jfrog.io/docker-mirror/mycorp-approved-images/kerberos-base:latest"
        result = validate_image_url(image, {})
        assert result == image

    def test_five_level_deep_registry_path(self):
        """Should accept extremely deep registry paths (5+ levels)."""
        image = "registry.corp.com/division/team/project/subproject/postgres:17.5-alpine"
        result = validate_image_url(image, {})
        assert result == image

    def test_numeric_segments_in_path(self):
        """Should accept path segments with numbers."""
        image = "artifactory.company.com/docker-prod-2025/db-images-v3/postgres-17:latest"
        result = validate_image_url(image, {})
        assert result == image

    def test_rejects_image_with_quotes(self):
        """Should reject image path wrapped in quotes (common config error)."""
        # This tests the bug we found - configs sometimes have extra quotes
        image = '"mycorp.jfrog.io/docker-mirror/postgres:17.5"'
        with pytest.raises(ValueError, match="Invalid image URL format"):
            validate_image_url(image, {})

    def test_rejects_image_with_single_quotes(self):
        """Should reject image path wrapped in single quotes."""
        image = "'mycorp.jfrog.io/docker-mirror/postgres:17.5'"
        with pytest.raises(ValueError, match="Invalid image URL format"):
            validate_image_url(image, {})

    def test_strips_whitespace_from_corporate_path(self):
        """Should strip whitespace but preserve the corporate path."""
        image = "  mycorp.jfrog.io/docker-mirror/postgres:17.5  "
        result = validate_image_url(image, {})
        assert result == "mycorp.jfrog.io/docker-mirror/postgres:17.5"

    def test_azure_container_registry_format(self):
        """Should accept Azure Container Registry format."""
        image = "mycompany.azurecr.io/platform/postgres:17.5-enterprise"
        result = validate_image_url(image, {})
        assert result == image

    def test_aws_ecr_format(self):
        """Should accept AWS ECR format with account ID."""
        image = "123456789012.dkr.ecr.us-west-2.amazonaws.com/postgres:17.5"
        result = validate_image_url(image, {})
        assert result == image

    def test_google_artifact_registry_format(self):
        """Should accept Google Artifact Registry format."""
        image = "us-central1-docker.pkg.dev/my-project/my-repo/postgres:17.5"
        result = validate_image_url(image, {})
        assert result == image