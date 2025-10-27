"""Kerberos teardown actions - GREEN phase implementation."""

from typing import Dict, Any


def stop_service(ctx: Dict[str, Any], runner) -> None:
    """Stop and remove Kerberos container.

    Args:
        ctx: Context dictionary (unused)
        runner: ActionRunner instance for side effects
    """
    runner.display("\nRemoving Kerberos container...")

    # Try both real and mock container names
    for container in ['kerberos-sidecar', 'kerberos-sidecar-mock']:
        result = runner.run_shell(['docker', 'rm', '-f', container])
        if result.get('returncode') == 0:
            runner.display(f"✓ Removed {container}")
            break
    else:
        runner.display("⚠ Kerberos container not found (may already be removed)")


def remove_keytabs(ctx: Dict[str, Any], runner) -> None:
    """Remove Kerberos keytab files.

    Args:
        ctx: Context dictionary with optional keytab path
        runner: ActionRunner instance for side effects
    """
    # Get keytab path from context or use default
    keytab_path = ctx.get('services.kerberos.keytab_path', '/etc/security/keytabs/*.keytab')

    # Use shell to handle glob patterns and ignore errors if files don't exist
    runner.run_shell(
        ['rm', '-f', keytab_path],
        cwd='platform-bootstrap'
    )


def remove_volumes(ctx: Dict[str, Any], runner) -> None:
    """Remove Kerberos volumes (alias for remove_keytabs for uniform interface).

    Args:
        ctx: Context dictionary with optional keytab path
        runner: ActionRunner instance for side effects
    """
    # Kerberos doesn't have docker volumes, but remove keytabs for uniform interface
    remove_keytabs(ctx, runner)


def remove_images(ctx: Dict[str, Any], runner) -> None:
    """Remove Kerberos Docker images.

    Args:
        ctx: Context dictionary with image name
        runner: ActionRunner instance for side effects
    """
    image = ctx.get('services.kerberos.image', 'ubuntu:22.04')

    result = runner.run_shell(
        ['docker', 'rmi', image],
        cwd='platform-bootstrap'
    )
    # Note: Errors are logged but don't fail teardown
    # Image may already be removed or in use by other containers


def clean_configuration(ctx: Dict[str, Any], runner) -> None:
    """Disable Kerberos service while preserving domain/image configuration.

    Args:
        ctx: Context dictionary with current configuration
        runner: ActionRunner instance for side effects
    """
    # Build config dictionary with Kerberos disabled
    config = {
        'services': {
            'kerberos': {
                'enabled': False,
                'domain': ctx.get('services.kerberos.domain', ''),
                'image': ctx.get('services.kerberos.image', 'ubuntu:22.04')
            }
        }
    }

    # Call runner to save config
    runner.save_config(config, 'platform-config.yaml')


def clean_config(ctx: Dict[str, Any], runner) -> None:
    """Alias for clean_configuration for uniform interface.

    Args:
        ctx: Context dictionary with current configuration
        runner: ActionRunner instance for side effects
    """
    clean_configuration(ctx, runner)
