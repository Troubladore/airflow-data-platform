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
    config = {
        'services': {
            'postgres': {
                'enabled': True,
                'image': ctx.get('services.postgres.image', 'postgres:17.5-alpine'),
                'prebuilt': ctx.get('services.postgres.prebuilt', False),
                'auth_method': ctx.get('services.postgres.auth_method', 'md5'),
                'password': ctx.get('services.postgres.password', 'changeme')
            }
        }
    }

    # Call runner to save config
    runner.save_config(config, 'platform-config.yaml')


def init_database(ctx: Dict[str, Any], runner) -> None:
    """Initialize PostgreSQL database.

    Calls make init-db command with PORT parameter.

    Args:
        ctx: Context dictionary with optional port configuration
        runner: ActionRunner instance for side effects
    """
    # Get port from context or use default
    port = ctx.get('services.postgres.port', 5432)

    # Build command
    command = ['make', '-C', 'platform-infrastructure', 'init-db', f'PORT={port}']

    # Execute command
    runner.run_shell(command)


def start_service(ctx: Dict[str, Any], runner) -> None:
    """Start PostgreSQL service.

    Calls make start command.

    Args:
        ctx: Context dictionary (unused)
        runner: ActionRunner instance for side effects
    """
    # Build command
    command = ['make', '-C', 'platform-infrastructure', 'start']

    # Execute command
    runner.run_shell(command)
