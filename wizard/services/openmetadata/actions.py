"""OpenMetadata actions - GREEN phase implementation."""

from typing import Dict, Any


def save_config(ctx: Dict[str, Any], runner) -> None:
    """Save OpenMetadata configuration to platform-config.yaml.

    Builds configuration dictionary from context and calls runner.save_config.

    Args:
        ctx: Context dictionary with service configuration
        runner: ActionRunner instance for side effects
    """
    # Build config dictionary
    openmetadata_config = {
        'port': ctx.get('services.openmetadata.port', 8585),
        'use_prebuilt': ctx.get('services.openmetadata.use_prebuilt', False)
    }

    # Only add images if they're provided (not None)
    server_image = ctx.get('services.openmetadata.server_image')
    if server_image is not None:
        openmetadata_config['server_image'] = server_image

    opensearch_image = ctx.get('services.openmetadata.opensearch_image')
    if opensearch_image is not None:
        openmetadata_config['opensearch_image'] = opensearch_image

    config = {
        'services': {
            'openmetadata': openmetadata_config
        }
    }

    # Call runner to save config
    runner.save_config(config, 'platform-config.yaml')


def start_service(ctx: Dict[str, Any], runner) -> None:
    """Start OpenMetadata service.

    Calls make start command.

    Args:
        ctx: Context dictionary (unused)
        runner: ActionRunner instance for side effects
    """
    # Build command
    command = ['make', '-C', 'openmetadata', 'start']

    # Execute command
    runner.run_shell(command)


def check_dependencies(ctx: Dict[str, Any], runner) -> bool:
    """Check that required dependencies (postgres) are running.

    Args:
        ctx: Context dictionary (unused)
        runner: ActionRunner instance for side effects

    Returns:
        True if postgres is running, False otherwise
    """
    # Build command to check for postgres container
    command = ['docker', 'ps', '--filter', 'name=postgres', '--format', '{{.Names}}']

    # Execute command
    result = runner.run_shell(command)

    # Check if postgres appears in the output
    if result['returncode'] != 0:
        return False

    output = result.get('stdout', '').strip()
    return 'postgres' in output
