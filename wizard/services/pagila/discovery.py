"""Discovery functions for Pagila service artifacts."""

from typing import List, Dict, Any


def discover_containers(runner) -> List[Dict[str, str]]:
    """Find all pagila-related containers.

    Pagila creates its own containers:
    - pagila-postgres: Main PostgreSQL container for Pagila
    - pagila-jsonb-restore: Container created by docker-compose for data restoration

    Args:
        runner: ActionRunner for executing queries

    Returns:
        List of dicts: [{'name': 'pagila-postgres', 'status': 'Up 2 days'}, ...]
    """
    result = runner.run_shell([
        'docker', 'ps', '-a',
        '--filter', 'name=pagila',
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
        List of file paths: [] (Pagila doesn't have service-specific config files)
    """
    files = []

    # Note: platform-config.yaml is a shared platform file
    # and should not be counted as a service-specific artifact
    # Pagila configuration is stored in the shared platform files

    # Check for pagila-specific files (if any exist in the future)
    # Currently, Pagila uses only the shared platform configuration

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
