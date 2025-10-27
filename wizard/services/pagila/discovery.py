"""Discovery functions for Pagila service artifacts."""

from typing import List, Dict, Any


def discover_containers(runner) -> List[Dict[str, str]]:
    """Find all pagila-related containers.

    Pagila doesn't have its own containers - it uses the postgres container.

    Args:
        runner: ActionRunner for executing queries

    Returns:
        List of dicts: [] (always empty for pagila)
    """
    return []


def discover_images(runner) -> List[Dict[str, str]]:
    """Find all pagila images.

    Args:
        runner: ActionRunner for executing queries

    Returns:
        List of dicts: [{'name': 'pagila-custom:latest', 'size': '50MB'}, ...]
        Usually empty unless custom image was built.
    """
    return []


def discover_volumes(runner) -> List[Dict[str, str]]:
    """Find pagila data volumes.

    Pagila doesn't have its own volumes - data is stored in postgres volume.

    Args:
        runner: ActionRunner for executing queries

    Returns:
        List of dicts: [] (always empty for pagila)
    """
    return []


def discover_files(runner) -> List[str]:
    """Find pagila configuration files.

    Args:
        runner: ActionRunner for executing queries

    Returns:
        List of file paths: ['platform-config.yaml', ...]
    """
    return []


def discover_custom(runner) -> Dict[str, Any]:
    """Find pagila-specific custom artifacts.

    Pagila has two custom artifacts:
    1. Git repository at /tmp/pagila
    2. Database schema in postgres (SELECT from pg_database WHERE datname='pagila')

    Args:
        runner: ActionRunner for executing queries

    Returns:
        Dict with repository and database info:
        {
            'repository': {'exists': True, 'path': '/tmp/pagila'},
            'database': {'exists': True, 'name': 'pagila'}
        }
    """
    return {
        'repository': {'exists': False, 'path': '/tmp/pagila'},
        'database': {'exists': False, 'name': 'pagila'}
    }
