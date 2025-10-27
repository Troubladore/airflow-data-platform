"""Tests for Pagila validators - GREEN phase"""
import pytest
from wizard.services.pagila.validators import validate_git_url


def test_validate_git_url_valid_https_github():
    """Accepts valid HTTPS GitHub URL"""
    result = validate_git_url("https://github.com/devrimgunduz/pagila.git", {})
    assert isinstance(result, str)
    assert result == "https://github.com/devrimgunduz/pagila.git"


def test_validate_git_url_valid_https_github_no_git():
    """Accepts valid HTTPS GitHub URL without .git extension"""
    result = validate_git_url("https://github.com/devrimgunduz/pagila", {})
    assert isinstance(result, str)
    assert result == "https://github.com/devrimgunduz/pagila"


def test_validate_git_url_valid_https_gitlab():
    """Accepts valid HTTPS GitLab URL"""
    result = validate_git_url("https://gitlab.com/company/pagila.git", {})
    assert isinstance(result, str)
    assert result == "https://gitlab.com/company/pagila.git"


def test_validate_git_url_valid_corporate():
    """Accepts valid corporate Git server URL"""
    result = validate_git_url("https://git.company.com/repos/pagila.git", {})
    assert isinstance(result, str)
    assert result == "https://git.company.com/repos/pagila.git"


def test_validate_git_url_invalid_empty():
    """Rejects empty URL"""
    with pytest.raises(ValueError, match="cannot be empty"):
        validate_git_url("", {})


def test_validate_git_url_invalid_whitespace():
    """Rejects whitespace-only URL"""
    with pytest.raises(ValueError, match="cannot be empty"):
        validate_git_url("   ", {})


def test_validate_git_url_invalid_not_https():
    """Rejects non-HTTPS URL (security requirement)"""
    with pytest.raises(ValueError, match="must use HTTPS"):
        validate_git_url("http://github.com/devrimgunduz/pagila.git", {})


def test_validate_git_url_invalid_ssh():
    """Rejects SSH URL (HTTPS only for simplicity)"""
    with pytest.raises(ValueError, match="must use HTTPS"):
        validate_git_url("git@github.com:devrimgunduz/pagila.git", {})


def test_validate_git_url_invalid_malformed():
    """Rejects malformed URL"""
    with pytest.raises(ValueError):
        validate_git_url("not-a-valid-url", {})


def test_validate_git_url_invalid_special_chars():
    """Rejects URL with invalid characters"""
    with pytest.raises(ValueError, match="Invalid characters in Git URL"):
        validate_git_url("https://github.com/invalid<>repo.git", {})


# ============================================================================
# INTERFACE COMPLIANCE TESTS - GREEN PHASE
# ============================================================================

def test_validate_git_url_returns_validated_string():
    """Validator must return validated string, not boolean."""
    result = validate_git_url("https://github.com/user/repo.git", {})
    assert isinstance(result, str)
    assert result == "https://github.com/user/repo.git"


def test_validate_git_url_raises_valueerror_on_empty():
    """Validator must raise ValueError, not return False."""
    with pytest.raises(ValueError, match="cannot be empty"):
        validate_git_url("", {})


def test_validate_git_url_raises_valueerror_on_http():
    """Validator must raise ValueError for HTTP (not HTTPS)."""
    with pytest.raises(ValueError, match="must use HTTPS"):
        validate_git_url("http://github.com/user/repo.git", {})


def test_validate_git_url_accepts_ctx_parameter():
    """Validator must accept ctx parameter per interface."""
    ctx = {'some': 'context'}
    result = validate_git_url("https://github.com/user/repo.git", ctx)
    assert isinstance(result, str)
