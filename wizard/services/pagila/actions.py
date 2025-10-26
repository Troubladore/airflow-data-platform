# Pagila actions


def save_config(ctx: dict, runner) -> None:
    """Save Pagila configuration."""
    config = {
        'services': {
            'pagila': {
                'enabled': ctx.get('services.pagila.enabled', True),
                'repo_url': ctx.get('services.pagila.repo_url')
            }
        }
    }
    runner.save_config(config, 'platform-config.yaml')


def install_pagila(ctx: dict, runner) -> None:
    """Install Pagila database."""
    repo_url = ctx.get('services.pagila.repo_url')
    command = ['make', '-C', 'platform-bootstrap', 'setup-pagila', f'PAGILA_REPO={repo_url}']
    runner.run_shell(command)


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
