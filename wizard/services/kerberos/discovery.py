"""Discovery functions for Kerberos service artifacts."""

from typing import List, Dict, Any


def discover_containers(runner) -> List[Dict[str, str]]:
    """Find all kerberos-related containers.

    Args:
        runner: ActionRunner for executing queries

    Returns:
        List of dicts: [{'name': 'kerberos-sidecar', 'status': 'Up 2 days'}, ...]
    """
    result = runner.run_shell([
        'docker', 'ps', '-a',
        '--filter', 'name=kerberos',
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
    """Find all kerberos-sidecar images.

    Args:
        runner: ActionRunner for executing queries

    Returns:
        List of dicts: [{'name': 'kerberos-sidecar:latest', 'size': '150MB'}, ...]
    """
    result = runner.run_shell([
        'docker', 'images',
        '--filter', 'reference=kerberos-sidecar',
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
    """Find kerberos-related Docker volumes.

    Args:
        runner: ActionRunner for executing queries

    Returns:
        List of dicts: [{'name': 'kerberos-mock-cache', 'driver': 'local'}, ...]
    """
    # Check for the mock Kerberos cache volume
    result = runner.run_shell([
        'docker', 'volume', 'ls',
        '--filter', 'name=kerberos',
        '--format', '{{.Name}}|{{.Driver}}'
    ])

    volumes = []
    if result.get('stdout'):
        for line in result['stdout'].strip().split('\n'):
            if '|' in line:
                name, driver = line.split('|', 1)
                volumes.append({'name': name, 'driver': driver})

    return volumes


def discover_files(runner) -> List[str]:
    """Find kerberos configuration files and keytabs.

    Args:
        runner: ActionRunner for executing queries

    Returns:
        List of file paths: ['/etc/security/keytabs/*.keytab', ...]
    """
    files = []

    # Check for keytab files
    result = runner.run_shell([
        'find', '/etc/security/keytabs',
        '-name', '*.keytab',
        '-type', 'f'
    ])

    if result.get('stdout'):
        for line in result['stdout'].strip().split('\n'):
            if line:  # Skip empty lines
                files.append(line)

    # Note: platform-bootstrap/.env is a shared platform file
    # and should not be counted as a service-specific artifact

    return files
