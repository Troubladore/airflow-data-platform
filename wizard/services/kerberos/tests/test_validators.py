"""Tests for Kerberos validators - GREEN phase"""
import pytest
from wizard.services.kerberos.validators import validate_domain, validate_image_url


def test_validate_domain_valid_uppercase():
    """Accepts valid Kerberos domain in COMPANY.COM format"""
    result = validate_domain("COMPANY.COM", {})
    assert result == "COMPANY.COM"


def test_validate_domain_valid_multiple_parts():
    """Accepts valid domain with multiple parts like SUB.COMPANY.COM"""
    result = validate_domain("SUB.COMPANY.COM", {})
    assert result == "SUB.COMPANY.COM"


def test_validate_domain_valid_single_word():
    """Accepts single word domain like INTERNAL"""
    result = validate_domain("INTERNAL", {})
    assert result == "INTERNAL"


def test_validate_domain_invalid_empty():
    """Rejects empty domain"""
    with pytest.raises(ValueError, match="cannot be empty"):
        validate_domain("", {})


def test_validate_domain_invalid_whitespace():
    """Rejects whitespace-only domain"""
    with pytest.raises(ValueError, match="cannot be empty"):
        validate_domain("   ", {})


def test_validate_domain_invalid_lowercase():
    """Rejects lowercase domain (Kerberos requires uppercase)"""
    with pytest.raises(ValueError, match="Invalid domain"):
        validate_domain("company.com", {})


def test_validate_domain_invalid_mixed_case():
    """Rejects mixed case domain"""
    with pytest.raises(ValueError, match="Invalid domain"):
        validate_domain("Company.Com", {})


def test_validate_domain_invalid_special_chars():
    """Rejects domain with invalid special characters"""
    with pytest.raises(ValueError, match="Invalid domain"):
        validate_domain("COMPANY@#$.COM", {})


def test_validate_domain_invalid_spaces():
    """Rejects domain with spaces"""
    with pytest.raises(ValueError, match="Invalid domain"):
        validate_domain("COMPANY .COM", {})


def test_validate_image_url_valid_ubuntu():
    """Accepts valid Ubuntu image URL"""
    result = validate_image_url("ubuntu:22.04", {})
    assert result == "ubuntu:22.04"


def test_validate_image_url_valid_debian():
    """Accepts valid Debian image URL"""
    result = validate_image_url("debian:bullseye", {})
    assert result == "debian:bullseye"


def test_validate_image_url_valid_with_registry():
    """Accepts image URL with registry"""
    result = validate_image_url("docker.io/ubuntu:22.04", {})
    assert result == "docker.io/ubuntu:22.04"


def test_validate_image_url_valid_custom_registry():
    """Accepts image URL with custom registry"""
    result = validate_image_url("myregistry.com/kerberos-base:latest", {})
    assert result == "myregistry.com/kerberos-base:latest"


def test_validate_image_url_valid_multi_path():
    """Accepts image URL with multiple path segments (e.g., JFrog Artifactory)"""
    result = validate_image_url("mycorp.jfrog.io/some-name/some-artifact/20.2:2022", {})
    assert result == "mycorp.jfrog.io/some-name/some-artifact/20.2:2022"


def test_validate_image_url_invalid_empty():
    """Rejects empty image URL"""
    with pytest.raises(ValueError, match="cannot be empty"):
        validate_image_url("", {})


def test_validate_image_url_invalid_whitespace():
    """Rejects whitespace-only image URL"""
    with pytest.raises(ValueError, match="cannot be empty"):
        validate_image_url("   ", {})


def test_validate_image_url_invalid_no_tag():
    """Rejects image URL without tag"""
    with pytest.raises(ValueError, match="tag"):
        validate_image_url("ubuntu", {})


def test_validate_image_url_invalid_special_chars():
    """Rejects image URL with invalid characters"""
    with pytest.raises(ValueError, match="Invalid image"):
        validate_image_url("invalid@#$%:tag", {})


# ============================================================================
# RED PHASE: Interface Compliance Tests (MUST FAIL)
# ============================================================================
# These tests verify validators follow the wizard interface:
# - Accept (value, ctx) parameters
# - Return validated string on success
# - Raise ValueError with clear message on failure
# ============================================================================


def test_validate_domain_returns_validated_string():
    """Validator must return validated string, not boolean."""
    result = validate_domain("COMPANY.COM", {})
    assert isinstance(result, str)
    assert result == "COMPANY.COM"


def test_validate_domain_raises_valueerror_on_empty():
    """Validator must raise ValueError, not return False."""
    with pytest.raises(ValueError, match="cannot be empty"):
        validate_domain("", {})


def test_validate_domain_raises_valueerror_on_invalid():
    """Validator must raise ValueError with clear message."""
    with pytest.raises(ValueError, match="Invalid domain"):
        validate_domain("no-dots-here", {})


def test_validate_domain_accepts_ctx_parameter():
    """Validator must accept ctx parameter per interface."""
    ctx = {'some': 'context'}
    result = validate_domain("COMPANY.COM", ctx)
    assert isinstance(result, str)


def test_validate_image_url_returns_validated_string():
    """Validator must return string, not boolean."""
    result = validate_image_url("ubuntu:22.04", {})
    assert isinstance(result, str)
    assert result == "ubuntu:22.04"


def test_validate_image_url_raises_valueerror():
    """Validator must raise ValueError."""
    with pytest.raises(ValueError):
        validate_image_url("", {})
