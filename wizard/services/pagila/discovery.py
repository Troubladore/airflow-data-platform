"""Discovery functions for Pagila service artifacts."""

from typing import List, Dict, Any
import os


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
    # Check for custom pagila images
    result = runner.run_shell([
        'docker', 'images',
        '--filter', 'reference=pagila*',
        '--format', '{{.Repository}}:{{.Tag}}|{{.Size}}'
    ])

    images = []
    if result.get('stdout') and result.get('returncode') == 0:
        for line in result['stdout'].strip().split('\n'):
            if line and '|' in line:
                name, size = line.split('|', 1)
                images.append({'name': name, 'size': size})

    return images


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
    files = []

    # Check for platform-config.yaml
    if os.path.exists('platform-config.yaml'):
        files.append('platform-config.yaml')

    return files


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
    result = {
        'repository': {'exists': False, 'path': '/tmp/pagila'},
        'database': {'exists': False, 'name': 'pagila'}
    }

    # Check for repository at /tmp/pagila
    repo_check = runner.run_shell(['test', '-d', '/tmp/pagila'])
    if repo_check.get('returncode') == 0:
        result['repository']['exists'] = True

    # Check for pagila database in postgres
    db_check = runner.run_shell([
        'docker', 'exec', 'postgres',
        'psql', '-U', 'postgres', '-tAc',
        "SELECT 1 FROM pg_database WHERE datname='pagila'"
    ])

    if db_check.get('returncode') == 0 and db_check.get('stdout', '').strip() == '1':
        result['database']['exists'] = True

    return result
