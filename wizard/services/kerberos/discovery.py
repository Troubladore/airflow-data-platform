"""Discovery functions for Kerberos service artifacts."""

from typing import List, Dict, Any


def discover_containers(runner) -> List[Dict[str, str]]:
    """Find all kerberos-related containers.

    Args:
        runner: ActionRunner for executing queries

    Returns:
        List of dicts: [{'name': 'kerberos-sidecar', 'status': 'Up 2 days'}, ...]
    """
    return []


def discover_images(runner) -> List[Dict[str, str]]:
    """Find all kerberos-sidecar images.

    Args:
        runner: ActionRunner for executing queries

    Returns:
        List of dicts: [{'name': 'kerberos-sidecar:latest', 'size': '150MB'}, ...]
    """
    return []


def discover_volumes(runner) -> List[Dict[str, str]]:
    """Find kerberos volumes (none - uses host keytabs).

    Args:
        runner: ActionRunner for executing queries

    Returns:
        List of dicts: [] (Kerberos doesn't use Docker volumes)
    """
    return []


def discover_files(runner) -> List[str]:
    """Find kerberos configuration files and keytabs.

    Args:
        runner: ActionRunner for executing queries

    Returns:
        List of file paths: ['/etc/security/keytabs/*.keytab', 'platform-bootstrap/.env', ...]
    """
    return []
