"""PostgreSQL validators - GREEN phase implementation."""

import re
from typing import Dict, Any


def validate_image_url(value: str, ctx: Dict[str, Any]) -> str:
    """Validate Docker image URL format.

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


def validate_port(value: int, ctx: Dict[str, Any]) -> int:
    """Validate PostgreSQL port number.

    Port must be between 1024 and 65535 (non-privileged ports).

    Args:
        value: Port number to validate
        ctx: Context dictionary (unused)

    Returns:
        Validated port number

    Raises:
        ValueError: If port is out of valid range
    """
    if not (1024 <= value <= 65535):
        raise ValueError("Port must be between 1024 and 65535")

    return value
