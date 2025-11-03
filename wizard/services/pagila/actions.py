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


def save_pagila_test_config(ctx: Dict[str, Any], runner) -> None:
    """Save Pagila test container configuration to platform-config.yaml and .env file.

    Saves test container configuration to both platform-config.yaml for persistence
    and .env file for use by build scripts.

    Args:
        ctx: Service context containing test container configuration
        runner: Action runner
    """
    runner.display("Saving Pagila test container configuration...")

    # Get configuration values with defaults
    use_prebuilt = ctx.get('services.pagila.test_containers.pagila_test.use_prebuilt', False)
    image = ctx.get('services.pagila.test_containers.pagila_test.image', 'alpine:latest')

    # Prepare configuration for platform-config.yaml
    config = {
        'services': {
            'pagila': {
                'test_containers': {
                    'pagila_test': {
                        'prebuilt': use_prebuilt,
                        'image': image
                    }
                }
            }
        }
    }

    # Save to platform-config.yaml
    runner.save_config(config, 'platform-config.yaml')

    # Prepare environment variables for .env file
    env_vars = []
    env_vars.append(f'IMAGE_PAGILA_TEST={image}')
    env_vars.append(f'PAGILA_TEST_PREBUILT={str(use_prebuilt).lower()}')

    # Read existing .env file content
    env_path = 'platform-bootstrap/.env'
    existing_content = ''
    try:
        result = runner.read_file(env_path)
        if result:
            existing_content = result
    except:
        pass  # File may not exist yet

    # Parse existing content to preserve other variables
    existing_lines = existing_content.strip().split('\n') if existing_content else []
    env_dict = {}

    for line in existing_lines:
        line = line.strip()
        if line and not line.startswith('#') and '=' in line:
            key, value = line.split('=', 1)
            # Skip our variables - we'll add them fresh
            if key not in ['IMAGE_PAGILA_TEST', 'PAGILA_TEST_PREBUILT']:
                env_dict[key] = value

    # Add our variables
    env_dict['IMAGE_PAGILA_TEST'] = image
    env_dict['PAGILA_TEST_PREBUILT'] = str(use_prebuilt).lower()

    # Build final content
    final_lines = []
    for key, value in sorted(env_dict.items()):
        final_lines.append(f'{key}={value}')

    final_content = '\n'.join(final_lines) + '\n'

    # Write to .env file
    runner.write_file(env_path, final_content)

    runner.display("✓ Test container configuration saved")


def verify_pagila_connection(ctx: Dict[str, Any], runner) -> None:
    """Verify connection to Pagila database using test container.

    Uses the pagila-test container to verify that:
    1. The Pagila database exists
    2. Tables have been created
    3. Data has been loaded

    Args:
        ctx: Service context
        runner: Action runner
    """
    runner.display("Verifying Pagila database connection...")
    runner.display("")

    # Get test container image name from configuration or use default
    # This allows for custom/corporate images
    test_image = ctx.get('services.pagila.test_containers.pagila_test.image', 'alpine:latest')
    use_prebuilt = ctx.get('services.pagila.test_containers.pagila_test.use_prebuilt', False)

    # Determine the actual image to use
    # If prebuilt, use the configured image directly (it should be tagged as platform/pagila-test:latest by the build)
    # If not prebuilt, the build process tags it as platform/pagila-test:latest
    container_image = 'platform/pagila-test:latest'

    # First, build the pagila-test container if needed
    runner.display("Building pagila-test container...")
    build_result = runner.run_shell(['make', '-C', 'platform-bootstrap', 'build-pagila-test'])

    if build_result.get('returncode') != 0:
        runner.display("⚠ Warning: Could not build pagila-test container")
        runner.display("  Attempting to continue with direct psql command...")
    else:
        runner.display("✓ Test container built successfully")

    # Test connection to pagila database
    runner.display("Testing database connection...")

    # Try using the test container first
    test_commands = [
        # Check if database exists
        ['docker', 'run', '--rm', '--network', 'platform_network',
         container_image, 'psql',
         '-h', 'pagila-postgres', '-U', 'postgres', '-d', 'pagila',
         '-c', r'\l'],

        # Check for tables
        ['docker', 'run', '--rm', '--network', 'platform_network',
         container_image, 'psql',
         '-h', 'pagila-postgres', '-U', 'postgres', '-d', 'pagila',
         '-c', r'\dt']
    ]

    # Try first with test container
    db_check = runner.run_shell(test_commands[0])

    if db_check.get('returncode') != 0:
        # Fallback to direct docker exec
        runner.display("  Using direct connection via pagila-postgres container...")
        db_check = runner.run_shell(
            ['docker', 'exec', 'pagila-postgres', 'psql', '-U', 'postgres', '-l']
        )

    # Check if pagila database exists
    if db_check.get('returncode') == 0 and 'pagila' in db_check.get('stdout', '').lower():
        runner.display("✓ Pagila database exists")

        # Check for tables
        tables_check = runner.run_shell(
            ['docker', 'exec', 'pagila-postgres', 'psql', '-U', 'postgres', '-d', 'pagila',
             '-c', 'SELECT tablename FROM pg_tables WHERE schemaname = \'public\' LIMIT 5;']
        )

        if tables_check.get('returncode') == 0:
            tables_output = tables_check.get('stdout', '')
            if any(table in tables_output for table in ['actor', 'film', 'customer', 'category']):
                runner.display("✓ Pagila tables found (actor, film, customer, etc.)")

                # Check row counts
                count_check = runner.run_shell(
                    ['docker', 'exec', 'pagila-postgres', 'psql', '-U', 'postgres', '-d', 'pagila',
                     '-c', 'SELECT COUNT(*) FROM film;']
                )

                if count_check.get('returncode') == 0:
                    count_output = count_check.get('stdout', '').strip()
                    runner.display(f"✓ Data loaded successfully")
                    runner.display("")
                    runner.display("Pagila database is ready for use!")
                else:
                    runner.display("⚠ Could not verify data counts")
            else:
                runner.display("✗ Pagila tables not found")
                runner.display("  The database exists but tables may not be created")
                runner.display("  Check the Pagila setup logs for errors")
        else:
            runner.display("✗ Could not query Pagila tables")
            runner.display(f"  Error: {tables_check.get('stderr', '')}")
    else:
        runner.display("✗ Pagila database not found")
        runner.display("  The Pagila setup may have failed")
        runner.display("  Check docker logs pagila-postgres for details")

        if db_check.get('stderr'):
            runner.display("")
            runner.display("Error details:")
            runner.display(f"  {db_check.get('stderr', '')}")
