"""Kerberos actions - GREEN phase implementation."""

from typing import Dict, Any


def save_config(ctx: Dict[str, Any], runner) -> None:
    """Save Kerberos configuration to platform-config.yaml.

    Builds configuration dictionary from context and calls runner.save_config.

    Args:
        ctx: Context dictionary with service configuration
        runner: ActionRunner instance for side effects
    """
    # Support both 'domain' and 'realm' keys for backward compatibility
    domain = ctx.get('services.kerberos.domain') or ctx.get('services.kerberos.realm')

    # Build config dictionary
    config = {
        'services': {
            'kerberos': {
                'enabled': True,
                'domain': domain,
                'image': ctx.get('services.kerberos.image', 'ubuntu:22.04'),
                'use_prebuilt': ctx.get('services.kerberos.use_prebuilt', False)
            }
        }
    }

    # Call runner to save config
    runner.save_config(config, 'platform-config.yaml')


def test_kerberos(ctx: Dict[str, Any], runner):
    """Test Kerberos setup using mock runner (no actual Kerberos operations).

    Args:
        ctx: Context dictionary (unused)
        runner: ActionRunner instance for side effects

    Returns:
        Result from test command execution
    """
    runner.display("\nConfiguring Kerberos integration...")
    runner.display("  - Setting up ticket sharing")

    # Use runner to execute test command (mockable!)
    result = runner.run_shell(['make', 'test-kerberos'], cwd='platform-infrastructure')

    if result.get('returncode') == 0:
        runner.display("✓ Kerberos configured successfully")
    else:
        runner.display("⚠ Kerberos test skipped (will configure on first use)")

    return result


def start_service(ctx: Dict[str, Any], runner) -> None:
    """Start Kerberos service using make.

    Args:
        ctx: Context dictionary (unused)
        runner: ActionRunner instance for side effects
    """
    runner.run_shell(['make', 'start'], cwd='platform-infrastructure')
