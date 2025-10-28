"""Kerberos validators - GREEN phase implementation."""

import re
from typing import Dict, Any


def validate_domain(value: str, ctx: Dict[str, Any]) -> str:
    """Validate Kerberos domain format (COMPANY.COM).

    Domain must be uppercase letters with dots, no spaces.

    Args:
        value: Domain to validate
        ctx: Context dictionary (unused)

    Returns:
        Validated and stripped domain string

    Raises:
        ValueError: If domain is invalid
    """
    # Strip whitespace
    value = value.strip()

    # Check for empty
    if not value:
        raise ValueError("Domain cannot be empty")

    # Must be uppercase letters, dots, no spaces
    pattern = r'^[A-Z]+(\.[A-Z]+)*$'
    if not re.match(pattern, value):
        raise ValueError("Invalid domain format. Use uppercase letters and dots only (e.g., COMPANY.COM)")

    return value


def validate_image_url(value: str, ctx: Dict[str, Any]) -> str:
    """Validate Docker image URL format.

    Accepts formats:
    - name:tag (e.g., ubuntu:22.04)
    - registry/name:tag (e.g., artifactory.company.com/kerberos:1.0)
    - registry:port/name:tag (e.g., registry.local:5000/kerberos:latest)
    - name (without tag) - only in prebuilt mode

    Args:
        value: Image URL to validate
        ctx: Context dictionary with use_prebuilt flag

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

    # Check if we're in prebuilt mode
    is_prebuilt = ctx.get('services.kerberos.use_prebuilt', False)

    # Tag validation - required unless in prebuilt mode
    if ':' not in value:
        if not is_prebuilt:
            raise ValueError("Image URL must include a tag (e.g., ubuntu:22.04)")
        # In prebuilt mode, images without tags are allowed

    # Basic validation: alphanumeric, dots, slashes, hyphens, colons, underscores
    if ':' in value:
        # Has a tag - validate full format
        pattern = r'^[a-zA-Z0-9._/-]+:[a-zA-Z0-9._-]+$'
    else:
        # No tag (prebuilt mode only) - validate name only
        pattern = r'^[a-zA-Z0-9._/-]+$'

    if not re.match(pattern, value):
        raise ValueError("Invalid image URL format")

    return value
