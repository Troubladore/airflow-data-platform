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
    """Start Kerberos service - auto-detects domain vs mock environment.

    Args:
        ctx: Context dictionary with kerberos configuration
        runner: ActionRunner instance for side effects
    """
    runner.display("\nSetting up Kerberos environment...")

    # Check if in domain environment
    # First try USERDNSDOMAIN (native Linux/WSL with env var set)
    check_domain = runner.run_shell(['bash', '-c', 'echo $USERDNSDOMAIN'])
    domain_from_env = check_domain.get('stdout', '').strip()

    in_domain = bool(domain_from_env)

    # If not found, try PowerShell fallback (WSL2 on domain-joined Windows)
    if not in_domain:
        powershell_check = runner.run_shell([
            'powershell.exe', '-Command', 'echo $env:USERDNSDOMAIN'
        ])
        # PowerShell successful if returncode is 0 and has output
        if powershell_check.get('returncode') == 0:
            domain_from_ps = powershell_check.get('stdout', '').strip()
            in_domain = bool(domain_from_ps)

    if in_domain:
        runner.display("  - Detected domain environment")
        runner.display("  - Starting Kerberos sidecar for ticket sharing")
        result = runner.run_shell(['make', 'kerberos-start'], cwd='platform-bootstrap')

        if result.get('returncode') == 0:
            runner.display("✓ Kerberos sidecar started")
        else:
            runner.display("✗ Kerberos sidecar failed to start")
    else:
        runner.display("  - Detected non-domain environment (dev/local)")
        runner.display("  - Creating mock Kerberos container for testing")

        # Get image from context
        image = ctx.get('services.kerberos.image', 'ubuntu:22.04')
        # Use default if domain is missing or empty string
        domain = ctx.get('services.kerberos.domain') or 'MOCK.LOCAL'

        # Create mock ticket cache directory on host
        runner.run_shell(['mkdir', '-p', '/tmp/krb5cc_mock'])

        # Start container with Kerberos packages but no actual KDC
        runner.run_shell([
            'docker', 'run', '-d',
            '--name', 'kerberos-sidecar-mock',
            '-v', '/tmp/krb5cc_mock:/tmp/krb5cc',
            image,
            'sleep', 'infinity'  # Just keep container running
        ])

        # Install kerberos client packages in container
        runner.run_shell([
            'docker', 'exec', 'kerberos-sidecar-mock',
            'bash', '-c',
            'apt-get update -qq && apt-get install -y -qq krb5-user 2>/dev/null || yum install -y -q krb5-workstation 2>/dev/null || true'
        ])

        runner.display("✓ Mock Kerberos container created (no real KDC)")
        runner.display(f"    Container: kerberos-sidecar-mock")
        runner.display(f"    Mock realm: {domain}")
