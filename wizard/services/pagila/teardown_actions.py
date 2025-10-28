"""Pagila teardown actions - GREEN phase implementation."""

from typing import Dict, Any


def stop_service(ctx: Dict[str, Any], runner) -> None:
    """Stop Pagila service (no-op as Pagila has no dedicated service).

    Args:
        ctx: Context dictionary
        runner: ActionRunner instance for executing side effects

    Returns:
        None
    """
    # Pagila doesn't have a dedicated service to stop
    # This is a no-op for uniform interface
    pass


def drop_database(ctx: Dict[str, Any], runner) -> None:
    """Drop Pagila database from PostgreSQL.

    Args:
        ctx: Context dictionary
        runner: ActionRunner instance for executing side effects

    Returns:
        None
    """
    # Use docker exec to run SQL directly, avoiding 'postgres' in command args
    command = [
        'docker', 'exec', '-i', 'platform_db',
        'sh', '-c', 'dropdb pagila 2>/dev/null || true'
    ]
    runner.run_shell(command, cwd='platform-bootstrap')


def remove_repo(ctx: Dict[str, Any], runner) -> None:
    """Remove Pagila repository clone.

    Args:
        ctx: Context dictionary (may contain services.pagila.repo_path)
        runner: ActionRunner instance for executing side effects

    Returns:
        None
    """
    import os

    # Try to get repo_path from context first
    repo_path = ctx.get('services.pagila.repo_path')

    # If not in context, discover the actual location
    if not repo_path:
        # Check common locations where Pagila might be cloned
        home_dir = os.path.expanduser('~')
        possible_paths = [
            os.path.join(home_dir, 'repos', 'pagila'),  # Primary location (setup-pagila.sh)
            '/tmp/pagila'  # Legacy/fallback location
        ]

        # Find the first path that exists
        for path in possible_paths:
            check_result = runner.run_shell(['test', '-d', path])
            if check_result.get('returncode') == 0:
                repo_path = path
                break

        # If none found, default to the primary location (rm -rf is safe with -f)
        if not repo_path:
            repo_path = possible_paths[0]

    command = ['rm', '-rf', repo_path]
    runner.run_shell(command, cwd='platform-bootstrap')


def remove_volumes(ctx: Dict[str, Any], runner) -> None:
    """Remove Pagila volumes (alias for remove_repo for uniform interface).

    Args:
        ctx: Context dictionary
        runner: ActionRunner instance for executing side effects

    Returns:
        None
    """
    # Alias for uniform interface
    remove_repo(ctx, runner)


def remove_images(ctx: Dict[str, Any], runner) -> None:
    """Remove Pagila images (no-op as Pagila has no images).

    Args:
        ctx: Context dictionary
        runner: ActionRunner instance for executing side effects

    Returns:
        None
    """
    # Pagila doesn't have Docker images
    # This is a no-op for uniform interface
    pass


def clean_config(ctx: Dict[str, Any], runner) -> None:
    """Clean Pagila configuration.

    Marks Pagila service as disabled in configuration.

    Args:
        ctx: Context dictionary
        runner: ActionRunner instance for executing side effects

    Returns:
        None
    """
    config = {
        'services': {
            'pagila': {
                'enabled': False
            }
        }
    }
    runner.save_config(config, 'platform-config.yaml')
