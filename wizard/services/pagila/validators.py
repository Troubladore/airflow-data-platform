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
    # Pattern: https://[username@]domain.com/path or https://[username@]domain.com/path.git
    # Supports Azure DevOps format: https://org@dev.azure.com/team/_git/repo
    pattern = r'^https://([a-zA-Z0-9.-]+@)?[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}(/[a-zA-Z0-9._/-]+(\.git)?)?$'

    if not re.match(pattern, value):
        raise ValueError("Invalid Git URL format")

    return value


def validate_postgres_image_url(value: str, ctx: Dict[str, Any]) -> str:
    """Validate Docker image URL format for PostgreSQL and auto-append :latest if no tag.

    Accepts formats:
    - name (auto-appends :latest)
    - name:tag (e.g., postgres:17.5-alpine)
    - registry/name (auto-appends :latest)
    - registry/name:tag (e.g., artifactory.company.com/postgres:17.5-alpine)
    - registry:port/name (auto-appends :latest)
    - registry:port/name:tag (e.g., registry.local:5000/postgres:17.5)
    - registry/path/to/name (auto-appends :latest)
    - registry/path/to/name:tag (e.g., mycorp.jfrog.io/team/project/postgres:17.5)

    Args:
        value: Image URL to validate
        ctx: Context dictionary (unused)

    Returns:
        Validated image URL with tag (auto-appends :latest if missing)

    Raises:
        ValueError: If image URL is invalid
    """
    # Strip whitespace
    value = value.strip()

    # Check for empty
    if not value:
        raise ValueError("Image URL cannot be empty")

    # Auto-append :latest if no tag is specified
    # Check if the last segment (after the last /) contains a colon
    # But be careful not to confuse registry:port with image:tag
    parts = value.split('/')
    last_part = parts[-1]

    # If the last part doesn't have a colon, or if it's a port number (all digits after colon)
    # then we need to append :latest
    if ':' not in last_part:
        # No tag at all - append :latest
        value = f"{value}:latest"
    elif len(parts) == 1 and ':' in last_part:
        # Single segment with colon - could be image:tag or registry:port
        # If what's after the colon is all digits, it's a port, not a tag
        colon_parts = last_part.split(':', 1)
        if colon_parts[1].isdigit():
            # It's a port number like "registry:5000", not a tag
            value = f"{value}/image:latest"  # Need an image name too
            raise ValueError("Registry URL must include an image name (e.g., registry:5000/myimage)")
    elif len(parts) > 1:
        # Multi-segment path - check if last segment has a tag
        if ':' not in last_part:
            value = f"{value}:latest"

    # Now validate the complete image URL with tag
    # Regex pattern for Docker image URL with required tag
    # Matches: [registry[:port]/]path/to/name:tag
    pattern = r'^([a-zA-Z0-9._-]+(?:\:[0-9]+)?/)?([a-zA-Z0-9._-]+/)*[a-zA-Z0-9._-]+:[a-zA-Z0-9._-]+$'

    if not re.match(pattern, value):
        raise ValueError(f"Invalid image URL format: {value}")

    return value
