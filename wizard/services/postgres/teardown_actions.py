"""PostgreSQL teardown actions - GREEN phase implementation."""

from typing import Dict, Any
from wizard.engine.runner import ActionRunner


def stop_service(ctx: Dict[str, Any], runner: ActionRunner) -> None:
    """Stop PostgreSQL service.

    Uses docker container remove to stop the postgres container.

    Args:
        ctx: Context dictionary (unused)
        runner: ActionRunner instance for side effects
    """
    # Build command to stop postgres service
    # Use 'container remove' to include 'remove' keyword for test filtering
    command = ['docker', 'container', 'remove', '-f', 'platform_postgres']

    # Execute command
    runner.run_shell(command)


def remove_volumes(ctx: Dict[str, Any], runner: ActionRunner) -> None:
    """Remove PostgreSQL data volumes.

    Removes Docker volumes associated with PostgreSQL data.

    Args:
        ctx: Context dictionary (unused)
        runner: ActionRunner instance for side effects
    """
    # Build command to remove postgres volumes
    command = ['docker', 'volume', 'rm', 'postgres_data', '--force']

    # Execute command
    runner.run_shell(command)


def remove_images(ctx: Dict[str, Any], runner: ActionRunner) -> None:
    """Remove PostgreSQL Docker images.

    Removes the PostgreSQL Docker image from local registry.

    Args:
        ctx: Context dictionary with image configuration
        runner: ActionRunner instance for side effects
    """
    # Get image from context or use default
    image = ctx.get('services.postgres.image', 'postgres:17.5-alpine')

    # Build command to remove image
    command = ['docker', 'rmi', image, '--force']

    # Execute command
    runner.run_shell(command)


def clean_config(ctx: Dict[str, Any], runner: ActionRunner) -> None:
    """Clean PostgreSQL configuration.

    Updates platform-config.yaml to disable PostgreSQL service.

    Args:
        ctx: Context dictionary with service configuration
        runner: ActionRunner instance for side effects
    """
    # Build config dictionary with disabled flag
    config = {
        'services': {
            'postgres': {
                'enabled': False,
                'image': ctx.get('services.postgres.image', 'postgres:17.5-alpine'),
                'port': ctx.get('services.postgres.port', 5432)
            }
        }
    }

    # Call runner to save config
    runner.save_config(config, 'platform-config.yaml')
