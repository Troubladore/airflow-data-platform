"""Tests for Pagila validators - GREEN phase"""
import pytest
from wizard.services.pagila.validators import validate_git_url, validate_postgres_image_url


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


def test_validate_git_url_valid_azure_devops():
    """Accepts valid Azure DevOps URL with @ character"""
    result = validate_git_url("https://mycorp@dev.azure.com/team_folder/_git/pagila", {})
    assert isinstance(result, str)
    assert result == "https://mycorp@dev.azure.com/team_folder/_git/pagila"


def test_validate_git_url_valid_azure_devops_with_git():
    """Accepts valid Azure DevOps URL with .git extension"""
    result = validate_git_url("https://mycorp@dev.azure.com/team/_git/pagila.git", {})
    assert isinstance(result, str)
    assert result == "https://mycorp@dev.azure.com/team/_git/pagila.git"


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


# ============================================================================
# PAGILA POSTGRESQL IMAGE VALIDATOR TESTS - RED PHASE
# ============================================================================

def test_validate_postgres_image_url_valid_simple():
    """Accepts simple image with tag"""
    result = validate_postgres_image_url("postgres:17.5-alpine", {})
    assert result == "postgres:17.5-alpine"


def test_validate_postgres_image_url_valid_registry():
    """Accepts registry with image"""
    result = validate_postgres_image_url("artifactory.company.com/postgres:17.5-alpine", {})
    assert result == "artifactory.company.com/postgres:17.5-alpine"


def test_validate_postgres_image_url_valid_registry_with_port():
    """Accepts registry with port"""
    result = validate_postgres_image_url("registry.local:5000/postgres:17.5", {})
    assert result == "registry.local:5000/postgres:17.5"


def test_validate_postgres_image_url_valid_nested_path():
    """Accepts nested registry paths (e.g., JFrog Artifactory)"""
    result = validate_postgres_image_url("mycorp.jfrog.io/team/project/postgres:17.5", {})
    assert result == "mycorp.jfrog.io/team/project/postgres:17.5"


def test_validate_postgres_image_url_invalid_empty():
    """Rejects empty image URL"""
    with pytest.raises(ValueError, match="cannot be empty"):
        validate_postgres_image_url("", {})


def test_validate_postgres_image_url_invalid_whitespace():
    """Rejects whitespace-only URL"""
    with pytest.raises(ValueError, match="cannot be empty"):
        validate_postgres_image_url("   ", {})


def test_validate_postgres_image_url_invalid_no_tag():
    """Rejects image without tag"""
    with pytest.raises(ValueError, match="Invalid image URL format"):
        validate_postgres_image_url("postgres", {})


def test_validate_postgres_image_url_invalid_format():
    """Rejects malformed image URL"""
    with pytest.raises(ValueError, match="Invalid image URL format"):
        validate_postgres_image_url("not@valid:image", {})


def test_validate_postgres_image_url_strips_whitespace():
    """Validator strips leading/trailing whitespace"""
    result = validate_postgres_image_url("  postgres:17.5-alpine  ", {})
    assert result == "postgres:17.5-alpine"


def test_validate_postgres_image_url_returns_string():
    """Validator must return validated string, not boolean"""
    result = validate_postgres_image_url("postgres:17.5-alpine", {})
    assert isinstance(result, str)


def test_validate_postgres_image_url_accepts_ctx_parameter():
    """Validator must accept ctx parameter per interface"""
    ctx = {'some': 'context'}
    result = validate_postgres_image_url("postgres:17.5-alpine", ctx)
    assert isinstance(result, str)
