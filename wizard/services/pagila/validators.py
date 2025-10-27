"""Pagila validators - GREEN phase implementation."""

import re
from typing import Dict, Any


def validate_git_url(value: str, ctx: Dict[str, Any]) -> str:
    """Validate git URL format.

    Accepts HTTPS URLs only (not HTTP or SSH).

    Args:
        value: Git URL to validate
        ctx: Context dictionary (unused)

    Returns:
        Validated and stripped git URL

    Raises:
        ValueError: If git URL is invalid
    """
    # Strip whitespace
    value = value.strip()

    # Check for empty
    if not value:
        raise ValueError("Git URL cannot be empty")

    # Must be HTTPS (not HTTP or SSH)
    if not value.startswith('https://'):
        raise ValueError("Git URL must use HTTPS")

    # Check for invalid characters
    if '<' in value or '>' in value:
        raise ValueError("Invalid characters in Git URL")

    # Basic URL pattern - should have domain and path
    # Pattern: https://domain.com/path or https://domain.com/path.git
    pattern = r'^https://[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}(/[a-zA-Z0-9._/-]+(\.git)?)?$'

    if not re.match(pattern, value):
        raise ValueError("Invalid Git URL format")

    return value


def validate_postgres_image_url(value: str, ctx: Dict[str, Any]) -> str:
    """Validate Docker image URL format for PostgreSQL.

    Accepts formats:
    - name:tag (e.g., postgres:17.5-alpine)
    - registry/name:tag (e.g., artifactory.company.com/postgres:17.5-alpine)
    - registry:port/name:tag (e.g., registry.local:5000/postgres:17.5)
    - registry/path/to/name:tag (e.g., mycorp.jfrog.io/team/project/postgres:17.5)

    Args:
        value: Image URL to validate
        ctx: Context dictionary (unused)

    Returns:
        Validated and stripped image URL

    Raises:
        ValueError: If image URL is invalid
    """
    # Strip whitespace
    value = value.strip()

    # Check for empty
    if not value:
        raise ValueError("Image URL cannot be empty")

    # Regex pattern for Docker image URL
    # Matches: [registry[:port]/]path/to/name:tag
    # Allows multiple path segments for registries like JFrog Artifactory
    pattern = r'^([a-zA-Z0-9._-]+(?:\:[0-9]+)?/)?([a-zA-Z0-9._-]+/)*[a-zA-Z0-9._-]+:[a-zA-Z0-9._-]+$'

    if not re.match(pattern, value):
        raise ValueError("Invalid image URL format")

    return value
