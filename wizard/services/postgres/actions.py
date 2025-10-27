"""PostgreSQL actions - GREEN phase implementation."""

from typing import Dict, Any


def save_config(ctx: Dict[str, Any], runner) -> None:
    """Save PostgreSQL configuration to platform-config.yaml.

    Builds configuration dictionary from context and calls runner.save_config.

    Args:
        ctx: Context dictionary with service configuration
        runner: ActionRunner instance for side effects
    """
    # Build config dictionary
    # Map require_password boolean to auth_method
    require_password = ctx.get('services.postgres.require_password', True)
    auth_method = 'md5' if require_password else 'trust'

    config = {
        'services': {
            'postgres': {
                'enabled': True,
                'image': ctx.get('services.postgres.image', 'postgres:17.5-alpine'),
                'prebuilt': ctx.get('services.postgres.prebuilt', False),
                'auth_method': auth_method,
                'password': ctx.get('services.postgres.password', 'changeme') if require_password else None
            }
        }
    }

    # Call runner to save config
    runner.save_config(config, 'platform-config.yaml')


def pull_image(ctx: Dict[str, Any], runner) -> None:
    """Pull PostgreSQL Docker image.

    Args:
        ctx: Context dictionary with image URL
        runner: ActionRunner instance for side effects
    """
    image = ctx.get('services.postgres.image', 'postgres:17.5-alpine')
    prebuilt = ctx.get('services.postgres.prebuilt', False)

    if not prebuilt:
        runner.display(f"\nPulling Docker image: {image}")
        result = runner.run_shell(['docker', 'pull', image])

        if result.get('returncode') == 0:
            runner.display(f"✓ Image pulled: {image}")
        else:
            runner.display(f"✗ Failed to pull image: {image}")
    else:
        runner.display(f"\n✓ Using prebuilt image: {image}")


def start_service(ctx: Dict[str, Any], runner) -> None:
    """Start PostgreSQL service.

    Calls make start command.

    Args:
        ctx: Context dictionary (unused)
        runner: ActionRunner instance for side effects
    """
    runner.display("Starting PostgreSQL service...")

    # Build command
    command = ['make', '-C', 'platform-infrastructure', 'start']

    # Execute command
    result = runner.run_shell(command)

    if result.get('returncode') == 0:
        runner.display("✓ PostgreSQL started successfully")
    else:
        runner.display("✗ PostgreSQL failed to start")
