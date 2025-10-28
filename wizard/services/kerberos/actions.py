"""Kerberos actions - GREEN phase implementation."""

from typing import Dict, Any
from wizard.utils.diagnostics import DiagnosticCollector, ServiceDiagnostics, create_diagnostic_summary
from wizard.services.kerberos.detection import KerberosDetector
from wizard.services.kerberos.progressive_tests import KerberosProgressiveTester


def detect_configuration(ctx: Dict[str, Any], runner) -> None:
    """Auto-detect Kerberos configuration from the system.

    Detects domain, ticket cache, and principal from various sources
    and updates the context with detected values.

    Args:
        ctx: Context dictionary to update with detected values
        runner: ActionRunner instance for side effects
    """
    # Clear section header for Kerberos configuration
    runner.display("\n" + "="*60)
    runner.display("🔐 KERBEROS AUTHENTICATION CONFIGURATION")
    runner.display("="*60)
    runner.display("\nConfiguring secure authentication for SQL Server and other")
    runner.display("corporate services using Kerberos/Active Directory.\n")

    runner.display("🔍 Auto-detecting your Kerberos environment...")

    # Create detector with runner for command execution
    detector = KerberosDetector(runner)

    # Detect all configuration
    detection = detector.detect_all()

    # Update context with detected values
    if detection['domain']:
        runner.display(f"  ✓ Detected domain: {detection['domain']}")
        ctx['services.kerberos.domain'] = detection['domain']
    else:
        runner.display("  ⚠ Could not auto-detect domain")

    if detection['ticket_cache']:
        cache = detection['ticket_cache']
        runner.display(f"  ✓ Detected ticket cache: {cache['format']} at {cache['path']}")
        if cache['directory']:
            ctx['services.kerberos.ticket_dir'] = cache['directory']
    else:
        runner.display("  ⚠ No ticket cache detected")

    if detection['principal']:
        runner.display(f"  ✓ Detected principal: {detection['principal']}")
        ctx['services.kerberos.principal'] = detection['principal']
    elif detection['domain']:
        # Try to infer from username and domain
        import os
        username = os.environ.get('USER', os.environ.get('USERNAME', ''))
        if username:
            suggested_principal = f"{username}@{detection['domain']}"
            runner.display(f"  ℹ Suggested principal: {suggested_principal}")
            ctx['services.kerberos.principal'] = suggested_principal

    # Check for tickets
    if detection['has_tickets']:
        runner.display("  ✓ Valid Kerberos tickets found")
        ctx['services.kerberos.has_tickets'] = True
    else:
        runner.display("  ⚠ No valid Kerberos tickets found")
        if detection['domain']:
            runner.display(f"     Run: kinit YOUR_USERNAME@{detection['domain']}")

    # Get diagnostic info for advanced troubleshooting
    diag_info = detector.get_diagnostic_info()

    # Show suggestions if any issues
    if diag_info['suggestions']:
        runner.display("\n  Suggestions:")
        for key, suggestion in diag_info['suggestions'].items():
            for line in suggestion.split('\n'):
                runner.display(f"    • {line}")

    runner.display("")


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
    """Test Kerberos configuration and connectivity.

    Performs comprehensive tests:
    1. Check for klist command
    2. Verify Kerberos tickets
    3. Test domain connectivity
    4. Validate ticket cache format

    Args:
        ctx: Context dictionary with configuration
        runner: ActionRunner instance for side effects

    Returns:
        Result from test execution
    """
    import os
    import re

    runner.display("\nTesting Kerberos configuration...")

    # Create detector for testing
    detector = KerberosDetector(runner)
    test_results = []
    all_passed = True

    # Test 1: Check klist command availability
    runner.display("  Testing Kerberos tools...")
    klist_check = runner.run_shell(['which', 'klist'])
    if klist_check.get('returncode') == 0:
        runner.display("    ✓ klist command found")
        test_results.append(('klist', True))
    else:
        runner.display("    ✗ klist command not found")
        runner.display("      Install with: sudo apt-get install krb5-user")
        test_results.append(('klist', False))
        all_passed = False

    # Test 2: Check for valid tickets
    runner.display("  Testing Kerberos tickets...")
    tickets_check = runner.run_shell(['klist', '-s'])
    if tickets_check.get('returncode') == 0:
        runner.display("    ✓ Valid Kerberos tickets found")
        test_results.append(('tickets', True))

        # Get ticket details
        klist_output = runner.run_shell(['klist'])
        if klist_output.get('returncode') == 0:
            # Parse principal
            principal_match = re.search(r'Default principal:\s*(.+)', klist_output.get('stdout', ''))
            if principal_match:
                runner.display(f"      Principal: {principal_match.group(1)}")

            # Parse ticket expiry
            expiry_match = re.search(r'krbtgt/.+@.+\s+(\d+/\d+/\d+\s+\d+:\d+:\d+)', klist_output.get('stdout', ''))
            if expiry_match:
                runner.display(f"      Expires: {expiry_match.group(1)}")
    else:
        runner.display("    ✗ No valid Kerberos tickets")
        test_results.append(('tickets', False))
        all_passed = False

        # Provide kinit guidance
        domain = ctx.get('services.kerberos.domain', 'DOMAIN.COM')
        runner.display(f"      Run: kinit YOUR_USERNAME@{domain}")

    # Test 3: Check ticket cache format for Docker compatibility
    runner.display("  Testing ticket cache compatibility...")
    cache_info = detector.detect_ticket_cache()
    if cache_info:
        if cache_info['format'] == 'KCM':
            runner.display(f"    ⚠ KCM format detected - needs conversion for Docker")
            runner.display("      Run: export KRB5CCNAME=FILE:/tmp/krb5cc_$(id -u)")
            test_results.append(('cache_format', False))
            all_passed = False
        else:
            runner.display(f"    ✓ {cache_info['format']} format is Docker-compatible")
            test_results.append(('cache_format', True))

            # Verify the cache file/directory exists
            if cache_info['directory'] and os.path.exists(cache_info['directory']):
                runner.display(f"      Cache directory: {cache_info['directory']}")
            elif cache_info['path'] and os.path.exists(cache_info['path']):
                runner.display(f"      Cache path: {cache_info['path']}")
    else:
        runner.display("    ⚠ No ticket cache detected")
        test_results.append(('cache_format', False))

    # Test 4: Test domain connectivity (if in corporate environment)
    domain = ctx.get('services.kerberos.domain')
    if domain and domain != 'MOCK.LOCAL':
        runner.display(f"  Testing domain connectivity ({domain})...")

        # Try to resolve KDC via DNS
        kdc_check = runner.run_shell(['nslookup', f'_kerberos._tcp.{domain.lower()}'])
        if kdc_check.get('returncode') == 0:
            runner.display(f"    ✓ Domain {domain} is resolvable")
            test_results.append(('domain', True))
        else:
            runner.display(f"    ⚠ Could not resolve {domain} (may need VPN)")
            test_results.append(('domain', False))

    # Test 5: Check if krb5.conf exists
    runner.display("  Testing Kerberos configuration files...")
    krb5_paths = ['/etc/krb5.conf', '/usr/local/etc/krb5.conf']
    krb5_found = False
    for path in krb5_paths:
        check = runner.run_shell(['test', '-f', path])
        if check.get('returncode') == 0:
            runner.display(f"    ✓ krb5.conf found at {path}")
            krb5_found = True
            test_results.append(('krb5.conf', True))
            break

    if not krb5_found:
        runner.display("    ⚠ krb5.conf not found")
        runner.display("      Kerberos will use default configuration")
        test_results.append(('krb5.conf', False))

    # Summary
    runner.display("\nTest Summary:")
    passed = sum(1 for _, result in test_results if result)
    total = len(test_results)

    if all_passed:
        runner.display(f"✓ All {total} tests passed - Kerberos is ready!")
        result = {'returncode': 0, 'stdout': 'All tests passed', 'stderr': ''}
    elif passed > 0:
        runner.display(f"⚠ {passed}/{total} tests passed - Kerberos partially configured")
        runner.display("  Review the warnings above for full functionality")
        result = {'returncode': 0, 'stdout': 'Partial success', 'stderr': ''}
    else:
        runner.display(f"✗ {passed}/{total} tests passed - Kerberos needs configuration")
        result = {'returncode': 1, 'stdout': '', 'stderr': 'Tests failed'}

    # Store test results in context for later reference
    ctx['services.kerberos.test_results'] = test_results
    ctx['services.kerberos.tests_passed'] = all_passed

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
            runner.display(f"✗ Failed to start mock container")

            # Run automatic diagnostics
            _run_kerberos_diagnostics(ctx, runner, run_result, "docker_run_failed")
            return

        # Wait a moment for container to be ready
        import time
        time.sleep(2)

        # Only install packages if not using a prebuilt image
        if not ctx.get('services.kerberos.use_prebuilt', False):
            # Install kerberos client packages in container
            runner.display("  - Installing Kerberos client packages in container")
            install_result = runner.run_shell([
                'docker', 'exec', 'kerberos-sidecar-mock',
                'bash', '-c',
                'apt-get update -qq && apt-get install -y -qq krb5-user 2>/dev/null || yum install -y -q krb5-workstation 2>/dev/null || true'
            ])

            if install_result.get('returncode') != 0:
                runner.display(f"⚠ Package installation warning: {install_result.get('stderr', '')}")
        else:
            runner.display("  - Using prebuilt image (packages already installed)")

        runner.display("✓ Mock Kerberos container created (no real KDC)")
        runner.display(f"    Container: kerberos-sidecar-mock")
        runner.display(f"    Mock realm: {domain}")
        runner.display(f"    Volume: kerberos-mock-cache")


def _run_kerberos_diagnostics(ctx: Dict[str, Any], runner, result, failure_phase: str) -> None:
    """Run automatic diagnostics when Kerberos fails.

    Args:
        ctx: Service context
        runner: Action runner
        result: Result from failed command
        failure_phase: Phase where failure occurred
    """
    runner.display("")
    runner.display("Running automatic diagnostics...")
    runner.display("")

    # Create diagnostic collector
    collector = DiagnosticCollector()
    service_diag = ServiceDiagnostics(runner)

    # Record the failure
    error_msg = result.get('stderr', '') or result.get('stdout', '') or 'Unknown error'
    collector.record_failure(
        service="kerberos",
        phase=failure_phase,
        error=error_msg[:200],  # Truncate long errors
        context={
            "image": ctx.get('services.kerberos.image', 'ubuntu:22.04'),
            "use_prebuilt": ctx.get('services.kerberos.use_prebuilt', False),
            "domain": ctx.get('services.kerberos.domain', 'MOCK.LOCAL')
        }
    )

    # Run Kerberos-specific diagnostics
    diag_result = service_diag.diagnose_kerberos_failure(ctx)

    # Display key findings
    if diag_result.get('using_prebuilt'):
        runner.display("📦 Using prebuilt image mode")
        if '/' in ctx.get('services.kerberos.image', ''):
            runner.display("  • Corporate registry image detected")
            runner.display(f"  • Image: {ctx.get('services.kerberos.image')}")

    if 'pull access denied' in error_msg.lower():
        runner.display("🔒 Registry authentication required")
        registry = ctx.get('services.kerberos.image', '').split('/')[0]
        runner.display(f"  • Run: docker login {registry}")

    elif 'manifest unknown' in error_msg.lower():
        runner.display("❌ Image not found in registry")
        runner.display(f"  • Verify image exists: {ctx.get('services.kerberos.image')}")

    # Check if container exists
    container_check = runner.run_shell(['docker', 'ps', '-a', '--format', '{{.Names}}'])
    if 'kerberos-sidecar-mock' not in container_check.get('stdout', ''):
        runner.display("  • Container was never created")

    # Save detailed log
    log_file = collector.save_log()
    runner.display("")
    runner.display(f"💾 Full diagnostics saved to: {log_file}")
    runner.display(f"   View with: cat {log_file}")


def run_progressive_tests_conditional(ctx: Dict[str, Any], runner) -> None:
    """Conditionally run progressive tests based on user choice.

    Args:
        ctx: Context dictionary with configuration
        runner: ActionRunner instance
    """
    if ctx.get('services.kerberos.run_progressive_tests', True):
        runner.display("\n" + "-"*60)
        runner.display("🧪 Running Progressive Kerberos Tests")
        runner.display("-"*60)

        tester = KerberosProgressiveTester(runner)
        results = tester.run_progressive_tests(ctx)

        # Store results in context
        ctx['services.kerberos.progressive_test_results'] = results
        ctx['services.kerberos.highest_level'] = results['highest_level']
    else:
        runner.display("\n  ℹ️  Skipping progressive tests (you can run them later)")
        runner.display("     Command: ./kerberos/diagnostics/diagnose-kerberos.sh")


def complete_configuration(ctx: Dict[str, Any], runner) -> None:
    """Complete the Kerberos configuration section with summary.

    Args:
        ctx: Context dictionary with all configuration
        runner: ActionRunner instance
    """
    runner.display("\n" + "="*60)
    runner.display("✅ KERBEROS CONFIGURATION COMPLETE")
    runner.display("="*60)

    # Summary of what was configured
    runner.display("\n📋 Configuration Summary:")

    domain = ctx.get('services.kerberos.domain', 'Not configured')
    runner.display(f"  • Domain: {domain}")

    if ctx.get('services.kerberos.principal'):
        runner.display(f"  • Principal: {ctx['services.kerberos.principal']}")

    if ctx.get('services.kerberos.ticket_dir'):
        runner.display(f"  • Ticket Directory: {ctx['services.kerberos.ticket_dir']}")

    image = ctx.get('services.kerberos.image', 'ubuntu:22.04')
    runner.display(f"  • Container Image: {image}")

    if ctx.get('services.kerberos.use_prebuilt'):
        runner.display("  • Using prebuilt image with Kerberos packages")

    # Test results summary
    if ctx.get('services.kerberos.tests_passed'):
        runner.display("\n✅ All validation tests passed")
    elif ctx.get('services.kerberos.test_results'):
        results = ctx['services.kerberos.test_results']
        passed = sum(1 for _, r in results if r)
        total = len(results)
        runner.display(f"\n⚠️  {passed}/{total} validation tests passed")

    # Progressive test results
    if ctx.get('services.kerberos.highest_level'):
        level = ctx['services.kerberos.highest_level']
        runner.display(f"\n📊 Progressive Testing: Level {level}/5 achieved")

        if level == 5:
            runner.display("   🎉 Full SQL Server connectivity verified!")
        elif level >= 3:
            runner.display("   ✅ Docker integration working")
        elif level >= 2:
            runner.display("   ✅ Kerberos tickets valid")

    # Next steps
    runner.display("\n📚 Next Steps:")
    runner.display("  1. View full diagnostics: ./kerberos/diagnostics/diagnose-kerberos.sh")
    runner.display("  2. Test SQL connectivity: ./kerberos/diagnostics/test-sql-simple.sh SERVER DB")
    runner.display("  3. Monitor sidecar: docker logs -f kerberos-sidecar-mock")

    # Quick reference
    runner.display("\n🔑 Quick Reference:")
    runner.display("  • Refresh tickets: kdestroy && kinit")
    runner.display("  • Check tickets: klist")
    runner.display("  • Restart sidecar: docker restart kerberos-sidecar-mock")

    runner.display("\n" + "-"*60)
    runner.display("Kerberos setup complete. Moving to next service...")
    runner.display("-"*60 + "\n")

