"""Discovery functions for OpenMetadata service artifacts."""

from typing import List, Dict, Any


def discover_containers(runner) -> List[Dict[str, str]]:
    """Find all OpenMetadata-related containers.

    Args:
        runner: ActionRunner for executing queries

    Returns:
        List of dicts: [{'name': 'openmetadata-server', 'status': 'Up 5 days'}, ...]
    """
    return []


def discover_images(runner) -> List[Dict[str, str]]:
    """Find all OpenMetadata and OpenSearch images.

    Args:
        runner: ActionRunner for executing queries

    Returns:
        List of dicts: [{'name': 'openmetadata/server:1.2.3', 'size': '850MB'}, ...]
    """
    return []


def discover_volumes(runner) -> List[Dict[str, str]]:
    """Find OpenMetadata and OpenSearch data volumes.

    Args:
        runner: ActionRunner for executing queries

    Returns:
        List of dicts: [{'name': 'openmetadata_data'}, ...]
    """
    return []


def discover_files(runner) -> List[str]:
    """Find OpenMetadata configuration files.

    Args:
        runner: ActionRunner for executing queries

    Returns:
        List of file paths: ['platform-config.yaml', '.env', ...]
    """
    return []
