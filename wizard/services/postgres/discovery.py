"""Discovery functions for PostgreSQL service artifacts."""

from typing import List, Dict, Any


def discover_containers(runner) -> List[Dict[str, str]]:
    """Find all postgres-related containers.

    Args:
        runner: ActionRunner for executing queries

    Returns:
        List of dicts: [{'name': 'postgres', 'status': 'Up 2 days'}, ...]
    """
    return []


def discover_images(runner) -> List[Dict[str, str]]:
    """Find all postgres images.

    Args:
        runner: ActionRunner for executing queries

    Returns:
        List of dicts: [{'name': 'postgres:17.5', 'size': '400MB'}, ...]
    """
    return []


def discover_volumes(runner) -> List[Dict[str, str]]:
    """Find postgres data volumes.

    Args:
        runner: ActionRunner for executing queries

    Returns:
        List of dicts: [{'name': 'postgres_data', 'size': '2.3GB'}, ...]
    """
    return []


def discover_files(runner) -> List[str]:
    """Find postgres configuration files.

    Args:
        runner: ActionRunner for executing queries

    Returns:
        List of file paths: ['platform-config.yaml', ...]
    """
    return []
