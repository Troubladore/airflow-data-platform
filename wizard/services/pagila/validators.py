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
