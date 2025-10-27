"""Tests for PostgreSQL validator functions - RED phase."""

import pytest
from wizard.services.postgres.validators import validate_image_url, validate_port


class TestValidateImageUrl:
    """Tests for validate_image_url function."""

    def test_validate_image_url_valid_simple(self):
        """Should accept simple Docker image URL."""
        result = validate_image_url("postgres:17.5-alpine", {})
        assert result == "postgres:17.5-alpine"

    def test_validate_image_url_valid_with_registry(self):
        """Should accept image URL with registry."""
        result = validate_image_url("artifactory.company.com/postgres:17.5-alpine", {})
        assert result == "artifactory.company.com/postgres:17.5-alpine"

    def test_validate_image_url_valid_with_port(self):
        """Should accept image URL with registry port."""
        result = validate_image_url("registry.local:5000/postgres:17.5", {})
        assert result == "registry.local:5000/postgres:17.5"

    def test_validate_image_url_valid_with_multi_path(self):
        """Should accept image URL with multiple path segments (e.g., JFrog Artifactory)."""
        result = validate_image_url("mycorp.jfrog.io/some-name/some-artifact/20.2:2022", {})
        assert result == "mycorp.jfrog.io/some-name/some-artifact/20.2:2022"

    def test_validate_image_url_strips_whitespace(self):
        """Should strip leading/trailing whitespace."""
        result = validate_image_url("  postgres:17.5-alpine  ", {})
        assert result == "postgres:17.5-alpine"

    def test_validate_image_url_invalid_empty(self):
        """Should reject empty string."""
        with pytest.raises(ValueError, match="Image URL cannot be empty"):
            validate_image_url("", {})

    def test_validate_image_url_invalid_no_tag(self):
        """Should reject image without tag."""
        with pytest.raises(ValueError, match="Invalid image URL format"):
            validate_image_url("postgres", {})

    def test_validate_image_url_invalid_malformed(self):
        """Should reject malformed URL."""
        with pytest.raises(ValueError, match="Invalid image URL format"):
            validate_image_url("not a valid url!", {})


class TestValidatePort:
    """Tests for validate_port function."""

    def test_validate_port_valid_standard(self):
        """Should accept standard PostgreSQL port."""
        result = validate_port(5432, {})
        assert result == 5432

    def test_validate_port_valid_custom(self):
        """Should accept custom valid port."""
        result = validate_port(15432, {})
        assert result == 15432

    def test_validate_port_valid_minimum(self):
        """Should accept minimum valid port (1024)."""
        result = validate_port(1024, {})
        assert result == 1024

    def test_validate_port_valid_maximum(self):
        """Should accept maximum valid port (65535)."""
        result = validate_port(65535, {})
        assert result == 65535

    def test_validate_port_invalid_too_low(self):
        """Should reject port below 1024."""
        with pytest.raises(ValueError, match="Port must be between 1024 and 65535"):
            validate_port(1023, {})

    def test_validate_port_invalid_too_high(self):
        """Should reject port above 65535."""
        with pytest.raises(ValueError, match="Port must be between 1024 and 65535"):
            validate_port(65536, {})

    def test_validate_port_invalid_zero(self):
        """Should reject port 0."""
        with pytest.raises(ValueError, match="Port must be between 1024 and 65535"):
            validate_port(0, {})

    def test_validate_port_invalid_negative(self):
        """Should reject negative port."""
        with pytest.raises(ValueError, match="Port must be between 1024 and 65535"):
            validate_port(-1, {})
