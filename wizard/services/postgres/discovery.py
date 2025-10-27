"""Discovery functions for PostgreSQL service artifacts."""

from typing import List, Dict, Any


def discover_containers(runner) -> List[Dict[str, str]]:
    """Find all postgres-related containers.

    Args:
        runner: ActionRunner for executing queries

    Returns:
        List of dicts: [{'name': 'postgres', 'status': 'Up 2 days'}, ...]
    """
    result = runner.run_shell([
        'docker', 'ps', '-a',
        '--filter', 'name=postgres',
        '--format', '{{.Names}}|{{.Status}}'
    ])

    containers = []
    if result.get('stdout'):
        for line in result['stdout'].strip().split('\n'):
            if '|' in line:
                name, status = line.split('|', 1)
                containers.append({'name': name, 'status': status})

    return containers


def discover_images(runner) -> List[Dict[str, str]]:
    """Find all postgres images.

    Args:
        runner: ActionRunner for executing queries

    Returns:
        List of dicts: [{'name': 'postgres:17.5', 'size': '400MB'}, ...]
    """
    result = runner.run_shell([
        'docker', 'images',
        '--filter', 'reference=postgres',
        '--format', '{{.Repository}}:{{.Tag}}|{{.Size}}'
    ])

    images = []
    if result.get('stdout'):
        for line in result['stdout'].strip().split('\n'):
            if '|' in line:
                name, size = line.split('|', 1)
                images.append({'name': name, 'size': size})

    return images


def discover_volumes(runner) -> List[Dict[str, str]]:
    """Find postgres data volumes.

    Args:
        runner: ActionRunner for executing queries

    Returns:
        List of dicts: [{'name': 'postgres_data', 'size': '2.3GB'}, ...]
    """
    result = runner.run_shell([
        'docker', 'volume', 'ls',
        '--filter', 'name=postgres',
        '--format', '{{.Name}}'
    ])

    volumes = []
    if result.get('stdout'):
        for line in result['stdout'].strip().split('\n'):
            if line:
                volumes.append({'name': line})

    return volumes


def discover_files(runner) -> List[str]:
    """Find postgres configuration files.

    Args:
        runner: ActionRunner for executing queries

    Returns:
        List of file paths: ['platform-config.yaml', ...]
    """
    files = []

    # Check for platform-config.yaml
    if runner.file_exists('platform-config.yaml'):
        files.append('platform-config.yaml')

    # Check for .env files
    if runner.file_exists('platform-bootstrap/.env'):
        files.append('platform-bootstrap/.env')

    return files
