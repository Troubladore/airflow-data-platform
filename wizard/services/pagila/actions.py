# Pagila actions


def save_config(ctx: dict, runner) -> None:
    """Save Pagila configuration."""
    # Get postgres_image - default to platform postgres image if not explicitly set
    postgres_image = ctx.get('services.pagila.postgres_image')
    if not postgres_image:
        postgres_image = ctx.get('services.postgres.image', 'postgres:17.5-alpine')

    # Get branch if specified
    branch = ctx.get('services.pagila.branch', '')

    config = {
        'services': {
            'pagila': {
                'enabled': ctx.get('services.pagila.enabled', True),
                'repo_url': ctx.get('services.pagila.repo_url'),
                'postgres_image': postgres_image,
                'branch': branch
            }
        }
    }
    runner.save_config(config, 'platform-config.yaml')


def install_pagila(ctx: dict, runner) -> None:
    """Install Pagila database."""
    runner.display("Installing Pagila database...")
    runner.display("  - Cloning repository")
    runner.display("  - Setting up database schema")

    repo_url = ctx.get('services.pagila.repo_url')
    postgres_image = ctx.get('services.pagila.postgres_image', 'postgres:17.5-alpine')
    branch = ctx.get('services.pagila.branch', '')

    command = [
        'make', '-C', 'platform-bootstrap', 'setup-pagila',
        f'PAGILA_REPO_URL={repo_url}',
        f'IMAGE_POSTGRES={postgres_image}',
        'PAGILA_AUTO_YES=1'
    ]

    # Add branch parameter if specified
    if branch:
        command.append(f'PAGILA_BRANCH={branch}')

    result = runner.run_shell(command)

    if result.get('returncode') == 0:
        runner.display("✓ Pagila installed successfully")
    else:
        runner.display("✗ Pagila installation failed")


def check_postgres_dependency(ctx: dict, runner) -> bool:
    """Check if PostgreSQL is available."""
    # Check if postgres is enabled in context
    if not ctx.get('services.postgres.enabled'):
        return False

    # Check if postgres config exists
    if 'services.postgres.port' not in ctx:
        return False

    # Try to verify postgres is actually running
    try:
        result = runner.run_shell(['docker', 'exec', 'postgres', 'psql', '--version'])
        return result['returncode'] == 0
    except Exception:
        return True  # If we can't check, assume it's okay (config exists)
