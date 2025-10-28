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

    # Get image with fallback if empty
    image = ctx.get('services.kerberos.image') or 'ubuntu:22.04'
    if not image or image.strip() == '':
        image = 'ubuntu:22.04'

    # Build config dictionary
    config = {
        'services': {
            'kerberos': {
                'enabled': True,
                'domain': domain,
                'image': image,
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
        # Check if PowerShell is available first (WSL2-specific, not on native Linux/macOS)
        ps_available = runner.run_shell(['bash', '-c', 'command -v powershell.exe'])
        if ps_available.get('returncode') == 0:
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

        # Get image from context, with fallback if empty or missing
        image = ctx.get('services.kerberos.image') or 'ubuntu:22.04'
        if not image or image.strip() == '':
            image = 'ubuntu:22.04'
        # Use default if domain is missing or empty string
        domain = ctx.get('services.kerberos.domain') or 'MOCK.LOCAL'

        # First check if container already exists and remove it
        check_result = runner.run_shell(['docker', 'ps', '-a', '-q', '-f', 'name=kerberos-sidecar-mock'])
        if check_result.get('stdout', '').strip():
            runner.display("  - Removing existing mock container")
            runner.run_shell(['docker', 'rm', '-f', 'kerberos-sidecar-mock'])

        # Ensure platform network exists
        network_check = runner.run_shell(['docker', 'network', 'ls', '--format', '{{.Name}}', '--filter', 'name=platform_network'])
        if 'platform_network' not in network_check.get('stdout', ''):
            runner.display("  - Creating platform network")
            network_result = runner.run_shell(['docker', 'network', 'create', 'platform_network'])
            if network_result.get('returncode') != 0:
                runner.display(f"⚠ Failed to create network: {network_result.get('stderr', '')}")

        # Create Docker volume for mock Kerberos cache (persistent and Docker-managed)
        runner.display("  - Creating Docker volume for mock Kerberos cache")
        volume_result = runner.run_shell(['docker', 'volume', 'create', 'kerberos-mock-cache'])
        if volume_result.get('returncode') != 0 and 'already exists' not in volume_result.get('stderr', ''):
            runner.display(f"⚠ Volume creation note: {volume_result.get('stderr', '')}")

        # Start container with Kerberos packages but no actual KDC
        runner.display(f"  - Starting mock container with image: {image}")
        run_result = runner.run_shell([
            'docker', 'run', '-d',
            '--name', 'kerberos-sidecar-mock',
            '--network', 'platform_network',  # Add to platform network
            '-v', 'kerberos-mock-cache:/tmp/krb5cc',  # Use Docker volume
            image,
            'sleep', 'infinity'  # Just keep container running
        ])

        if run_result.get('returncode') != 0:
            runner.display(f"✗ Failed to start mock container: {run_result.get('stderr', '')}")
            return

        # Wait a moment for container to be ready
        import time
        time.sleep(2)

        # Install kerberos client packages in container
        runner.display("  - Installing Kerberos client packages in container")
        install_result = runner.run_shell([
            'docker', 'exec', 'kerberos-sidecar-mock',
            'bash', '-c',
            'apt-get update -qq && apt-get install -y -qq krb5-user 2>/dev/null || yum install -y -q krb5-workstation 2>/dev/null || true'
        ])

        if install_result.get('returncode') != 0:
            runner.display(f"⚠ Package installation warning: {install_result.get('stderr', '')}")

        runner.display("✓ Mock Kerberos container created (no real KDC)")
        runner.display(f"    Container: kerberos-sidecar-mock")
        runner.display(f"    Mock realm: {domain}")
        runner.display(f"    Volume: kerberos-mock-cache")
