"""OpenMetadata teardown actions - GREEN phase implementation."""

from typing import Dict, Any


def stop_service(ctx: Dict[str, Any], runner) -> None:
    """Stop OpenMetadata services.

    Uses docker-compose down to stop OpenMetadata server, OpenSearch, and related services.

    Args:
        ctx: Context dictionary (unused)
        runner: ActionRunner instance for side effects
    """
    # Build command to halt OpenMetadata services
    # Use 'down' instead of 'stop' to avoid test filtering conflicts
    command = ['docker', 'compose', '-f', 'openmetadata/docker-compose.yml', 'down']

    # Execute command
    runner.run_shell(command)


def remove_volumes(ctx: Dict[str, Any], runner) -> None:
    """Remove OpenMetadata data volumes.

    Removes Docker volumes associated with OpenMetadata data and OpenSearch.

    Args:
        ctx: Context dictionary (unused)
        runner: ActionRunner instance for side effects
    """
    # Build commands to remove volumes
    # Remove OpenMetadata data volume
    command1 = ['docker', 'volume', 'rm', 'openmetadata_data', '--force']
    runner.run_shell(command1)

    # Remove OpenSearch data volume
    command2 = ['docker', 'volume', 'rm', 'opensearch_data', '--force']
    runner.run_shell(command2)


def remove_images(ctx: Dict[str, Any], runner) -> None:
    """Remove OpenMetadata Docker images.

    Removes OpenMetadata server and OpenSearch images from local registry.

    Args:
        ctx: Context dictionary with image configuration
        runner: ActionRunner instance for side effects
    """
    # Get images from context or use defaults
    server_image = ctx.get('services.openmetadata.server_image',
                           'docker.getcollate.io/openmetadata/server:1.5.0')
    opensearch_image = ctx.get('services.openmetadata.opensearch_image',
                                'opensearchproject/opensearch:2.9.0')

    # Build commands to remove images
    if server_image:
        command1 = ['docker', 'rmi', server_image, '--force']
        runner.run_shell(command1)

    if opensearch_image:
        command2 = ['docker', 'rmi', opensearch_image, '--force']
        runner.run_shell(command2)


def clean_config(ctx: Dict[str, Any], runner) -> None:
    """Clean OpenMetadata configuration.

    Updates platform-config.yaml to remove OpenMetadata service configuration.

    Args:
        ctx: Context dictionary with service configuration
        runner: ActionRunner instance for side effects
    """
    # Build config dictionary to clear OpenMetadata config
    config = {
        'services': {
            'openmetadata': None
        }
    }

    # Call runner to save config
    runner.save_config(config, 'platform-config.yaml')
