# Pagila actions

from typing import Dict, Any
from wizard.utils.diagnostics import DiagnosticCollector, ServiceDiagnostics, create_diagnostic_summary


def save_config(ctx: dict, runner) -> None:
    """Save Pagila configuration."""
    # Get postgres_image - default to platform postgres image if not explicitly set
    postgres_image = ctx.get('services.pagila.postgres_image')
    if not postgres_image:
        postgres_image = ctx.get('services.base_platform.postgres.image', 'postgres:17.5-alpine')

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
    """Install Pagila database with automatic diagnostics on failure."""
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

        # Run health check
        runner.display("")
        runner.display("Verifying Pagila health...")

        service_diag = ServiceDiagnostics(runner)
        health = service_diag.verify_pagila_health(ctx)

        if health['healthy']:
            # Display detailed success message
            runner.display(health['summary'])
        else:
            # Save diagnostics and warn (but continue)
            runner.display(f"⚠️  Health check failed: {health['error']}")

            collector = DiagnosticCollector()
            collector.record_failure('pagila', 'health_check', health['error'], {
                'details': health['details']
            })
            log_file = collector.save_log()

            runner.display(f"💾 Diagnostics saved to: {log_file}")
            runner.display("   Continuing setup...")
            runner.display("")
    else:
        runner.display("✗ Pagila installation failed")

        # Run automatic diagnostics
        _run_pagila_diagnostics(ctx, runner, result, "make_setup_pagila")


def check_postgres_dependency(ctx: dict, runner) -> bool:
    """Check if PostgreSQL is available."""
    # Check if postgres is enabled in context
    if not ctx.get('services.base_platform.postgres.enabled'):
        return False

    # Check if postgres config exists
    if 'services.base_platform.postgres.port' not in ctx:
        return False

    # Try to verify postgres is actually running
    try:
        result = runner.run_shell(['docker', 'exec', 'postgres', 'psql', '--version'])
        return result['returncode'] == 0
    except Exception:
        return True  # If we can't check, assume it's okay (config exists)


def _run_pagila_diagnostics(ctx: Dict[str, Any], runner, result, failure_phase: str) -> None:
    """Run automatic diagnostics when Pagila installation fails.

    Args:
        ctx: Service context
        runner: Action runner
        result: Result from failed command
        failure_phase: Phase where failure occurred
    """
    runner.display("")
    runner.display("Running automatic diagnostics...")

    # Detect environment
    import platform
    is_wsl = 'microsoft' in platform.uname().release.lower()
    if is_wsl:
        runner.display("🖥️ WSL2 environment detected")

    runner.display("")

    # Create diagnostic collector
    collector = DiagnosticCollector()
    service_diag = ServiceDiagnostics(runner)

    # Record the failure
    error_msg = result.get('stderr', '') or result.get('stdout', '') or 'Unknown error'
    collector.record_failure(
        service="pagila",
        phase=failure_phase,
        error=error_msg[:200],  # Truncate long errors
        context={
            "repo_url": ctx.get('services.pagila.repo_url'),
            "postgres_image": ctx.get('services.pagila.postgres_image', 'postgres:17.5-alpine'),
            "branch": ctx.get('services.pagila.branch', 'main')
        }
    )

    # Run Pagila-specific diagnostics
    diag_result = service_diag.diagnose_pagila_failure(ctx)

    # Display diagnosis and suggestions from improved diagnostic
    if 'diagnosis' in diag_result and diag_result['diagnosis']:
        runner.display(f"📊 Diagnosis: {diag_result['diagnosis']}")

    if 'suggestions' in diag_result and diag_result['suggestions']:
        runner.display("💡 Suggestions:")
        for suggestion in diag_result['suggestions']:
            runner.display(f"  • {suggestion}")

    # Display key findings
    if not diag_result.get('repo_cloned'):
        runner.display("📂 Repository not cloned")
        runner.display("  • Git clone may have failed")
        runner.display(f"  • Check network access to: {ctx.get('services.pagila.repo_url')}")

        # Check for common git errors in output
        if 'could not resolve host' in error_msg.lower():
            runner.display("  • DNS resolution failed")
        elif 'connection timed out' in error_msg.lower():
            runner.display("  • Network timeout - firewall or proxy issue?")
        elif 'repository not found' in error_msg.lower():
            runner.display("  • Repository URL may be incorrect")

    else:
        runner.display("📂 Repository cloned successfully")

        # Check for Docker-related errors
        if 'unhealthy' in error_msg.lower() or 'health' in error_msg.lower():
            runner.display("🏥 Container health check issue detected")

            # WSL2-specific checks
            if is_wsl:
                runner.display("  • WSL2 may have file permission issues")
                runner.display("  • Try: chmod 644 ../pagila/*.conf")
                runner.display("  • Or slower I/O may cause timing issues")

        elif 'docker' in error_msg.lower():
            runner.display("🐳 Docker setup issue detected")

            if 'permission denied' in error_msg.lower():
                runner.display("  • Docker permission issue")
                runner.display("  • Try: sudo usermod -aG docker $USER")
            elif 'cannot connect' in error_msg.lower():
                runner.display("  • Docker daemon not running")
                runner.display("  • Try: sudo systemctl start docker")

        # Check for PostgreSQL connectivity
        if 'postgres' in error_msg.lower():
            runner.display("🗄️ PostgreSQL connection issue")

            # Check if postgres container is running
            pg_check = runner.run_shell(['docker', 'ps', '--format', '{{.Names}}'])
            if 'platform-postgres' not in pg_check.get('stdout', ''):
                runner.display("  • PostgreSQL container not running")
                runner.display("  • Run: ./platform setup postgres")

    # Check if using custom PostgreSQL image
    postgres_image = ctx.get('services.pagila.postgres_image', '')
    if '/' in postgres_image:
        runner.display("📦 Using custom PostgreSQL image")
        runner.display(f"  • Image: {postgres_image}")
        runner.display("  • Ensure you're authenticated to the registry")

    # Save detailed log
    log_file = collector.save_log()
    runner.display("")
    runner.display(f"💾 Full diagnostics saved to: {log_file}")
    runner.display(f"   View with: cat {log_file}")
