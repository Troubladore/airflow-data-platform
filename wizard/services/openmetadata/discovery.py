"""Discovery functions for OpenMetadata service artifacts."""

from typing import List, Dict, Any


def discover_containers(runner) -> List[Dict[str, str]]:
    """Find all OpenMetadata-related containers.

    Args:
        runner: ActionRunner for executing queries

    Returns:
        List of dicts: [{'name': 'openmetadata-server', 'status': 'Up 5 days'}, ...]
    """
    containers = []

    # Query for openmetadata containers
    for pattern in ['openmetadata', 'opensearch']:
        result = runner.run_shell([
            'docker', 'ps', '-a',
            '--filter', f'name={pattern}',
            '--format', '{{.Names}}|{{.Status}}'
        ])

        if result.get('stdout'):
            for line in result['stdout'].strip().split('\n'):
                if '|' in line:
                    name, status = line.split('|', 1)
                    containers.append({'name': name, 'status': status})

    return containers


def discover_images(runner) -> List[Dict[str, str]]:
    """Find all OpenMetadata and OpenSearch images.

    Args:
        runner: ActionRunner for executing queries

    Returns:
        List of dicts: [{'name': 'openmetadata/server:1.2.3', 'size': '850MB'}, ...]
    """
    images = []

    # Query for openmetadata and opensearchproject images
    for pattern in ['openmetadata', 'opensearchproject']:
        result = runner.run_shell([
            'docker', 'images',
            '--filter', f'reference={pattern}',
            '--format', '{{.Repository}}:{{.Tag}}|{{.Size}}'
        ])

        if result.get('stdout'):
            for line in result['stdout'].strip().split('\n'):
                if '|' in line:
                    name, size = line.split('|', 1)
                    images.append({'name': name, 'size': size})

    return images


def discover_volumes(runner) -> List[Dict[str, str]]:
    """Find OpenMetadata and OpenSearch data volumes.

    Args:
        runner: ActionRunner for executing queries

    Returns:
        List of dicts: [{'name': 'openmetadata_data'}, ...]
    """
    volumes = []

    # Query for openmetadata and opensearch volumes
    for pattern in ['openmetadata', 'opensearch']:
        result = runner.run_shell([
            'docker', 'volume', 'ls',
            '--filter', f'name={pattern}',
            '--format', '{{.Name}}'
        ])

        if result.get('stdout'):
            for line in result['stdout'].strip().split('\n'):
                if line:
                    volumes.append({'name': line})

    return volumes


def discover_files(runner) -> List[str]:
    """Find OpenMetadata configuration files.

    Args:
        runner: ActionRunner for executing queries

    Returns:
        List of file paths: ['platform-config.yaml', '.env', ...]
    """
    files = []

    # Check for platform-config.yaml
    if runner.file_exists('platform-config.yaml'):
        files.append('platform-config.yaml')

    # Check for .env files
    if runner.file_exists('platform-bootstrap/.env'):
        files.append('platform-bootstrap/.env')

    # Check for openmetadata directory
    if runner.file_exists('openmetadata'):
        files.append('openmetadata/')

    return files
