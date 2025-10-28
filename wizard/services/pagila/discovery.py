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

    Args:
        runner: ActionRunner for executing queries

    Returns:
        List of dicts: [{'name': 'pagila_pgdata', 'size': '100MB'}, ...]
    """
    result = runner.run_shell([
        'docker', 'volume', 'ls',
        '--filter', 'name=pagila',
        '--format', '{{.Name}}|{{.Size}}'
    ])

    volumes = []
    if result.get('stdout') and result.get('returncode') == 0:
        for line in result['stdout'].strip().split('\n'):
            if line and '|' in line:
                name, size = line.split('|', 1)
                volumes.append({'name': name, 'size': size})

    return volumes


def discover_files(runner) -> List[str]:
    """Find pagila configuration files.

    Args:
        runner: ActionRunner for executing queries

    Returns:
        List of file paths: ['platform-config.yaml', ...]
    """
    files = []

    # Check for platform-config.yaml using runner for mockability
    result = runner.run_shell(['test', '-f', 'platform-config.yaml'])
    if result.get('returncode') == 0:
        files.append('platform-config.yaml')

    return files


def discover_custom(runner) -> Dict[str, Any]:
    """Find pagila-specific custom artifacts.

    Pagila has two custom artifacts:
    1. Git repository (checks ~/repos/pagila and /tmp/pagila)
    2. Database schema in postgres (SELECT from pg_database WHERE datname='pagila')

    Args:
        runner: ActionRunner for executing queries

    Returns:
        Dict with repository and database info:
        {
            'repository': {'exists': True, 'path': '/home/user/repos/pagila'},
            'database': {'exists': True, 'name': 'pagila'}
        }
    """
    import os

    result = {
        'repository': {'exists': False, 'path': None},
        'database': {'exists': False, 'name': 'pagila'}
    }

    # Check for repository in common locations
    home_dir = os.path.expanduser('~')
    possible_paths = [
        os.path.join(home_dir, 'repos', 'pagila'),  # Primary location (setup-pagila.sh)
        '/tmp/pagila'  # Legacy/fallback location
    ]

    for path in possible_paths:
        repo_check = runner.run_shell(['test', '-d', path])
        if repo_check.get('returncode') == 0:
            result['repository']['exists'] = True
            result['repository']['path'] = path
            break

    # If not found, default to primary location
    if not result['repository']['path']:
        result['repository']['path'] = possible_paths[0]

    # Check for pagila database in postgres
    db_check = runner.run_shell([
        'docker', 'exec', 'postgres',
        'psql', '-U', 'postgres', '-tAc',
        "SELECT 1 FROM pg_database WHERE datname='pagila'"
    ])

    if db_check.get('returncode') == 0 and db_check.get('stdout', '').strip() == '1':
        result['database']['exists'] = True

    return result
