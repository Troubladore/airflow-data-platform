"""PostgreSQL teardown actions - GREEN phase implementation."""

from typing import Dict, Any
from wizard.engine.runner import ActionRunner


def stop_service(ctx: Dict[str, Any], runner: ActionRunner) -> None:
    """Stop and remove PostgreSQL container.

    Args:
        ctx: Context dictionary (unused)
        runner: ActionRunner instance for side effects
    """
    runner.display("\nRemoving PostgreSQL container...")

    # Stop and remove container
    command = ['docker', 'container', 'remove', '-f', 'platform-postgres']
    result = runner.run_shell(command)

    if result.get('returncode') == 0:
        runner.display("✓ PostgreSQL container removed")
    else:
        runner.display("⚠ Container may not exist (already removed)")


def remove_volumes(ctx: Dict[str, Any], runner: ActionRunner) -> None:
    """Remove PostgreSQL data volumes.

    Removes Docker volumes associated with PostgreSQL data.

    Args:
        ctx: Context dictionary (unused)
        runner: ActionRunner instance for side effects
    """
    # Build command to remove postgres volumes
    command = ['docker', 'volume', 'rm', 'platform_postgres_data', '--force']

    # Execute command
    runner.run_shell(command)


def remove_images(ctx: Dict[str, Any], runner: ActionRunner) -> None:
    """Remove PostgreSQL Docker images.

    Removes the PostgreSQL Docker image from local registry.
    Reads custom image from platform-bootstrap/.env if present.
    Also removes test container images (postgres-test, sqlcmd-test).

    Args:
        ctx: Context dictionary with image configuration
        runner: ActionRunner instance for side effects
    """
    # First, try to get the image from the .env file (where custom images are stored)
    image = None
    env_file = 'platform-bootstrap/.env'

    if runner.file_exists(env_file):
        # Read the .env file to get the custom image if set
        result = runner.run_shell(['grep', '^IMAGE_POSTGRES=', env_file])
        if result.get('returncode') == 0 and result.get('stdout'):
            # Extract the image name from IMAGE_POSTGRES=image:tag
            line = result['stdout'].strip()
            if '=' in line:
                image = line.split('=', 1)[1].strip()

    # Fall back to context or default if not found in .env
    if not image:
        image = ctx.get('services.base_platform.postgres.image', 'postgres:17.5-alpine')

    # Build command to remove main postgres image
    command = ['docker', 'rmi', image, '--force']
    runner.run_shell(command)

    # Remove test container images
    test_images = [
        'platform/postgres-test:latest',
        'platform/sqlcmd-test:latest',
        'test-postgres-build:latest',
        'test-sqlcmd-build:latest'
    ]

    for test_image in test_images:
        command = ['docker', 'rmi', test_image, '--force']
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
                'image': ctx.get('services.base_platform.postgres.image', 'postgres:17.5-alpine'),
                'port': ctx.get('services.base_platform.postgres.port', 5432)
            }
        }
    }

    # Call runner to save config
    runner.save_config(config, 'platform-config.yaml')
