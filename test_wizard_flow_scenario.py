#!/usr/bin/env python3
"""
Test the exact wizard flow that users experience to reproduce the issue.
This simulates what happens when users run through the wizard with custom settings.
"""

import subprocess
import os
import time
import shutil

def cleanup():
    """Clean up everything."""
    subprocess.run(['docker', 'rm', '-f', 'pagila-postgres'], capture_output=True)
    subprocess.run(['docker', 'rm', '-f', 'pagila-jsonb-restore'], capture_output=True)
    subprocess.run(['docker', 'volume', 'rm', '-f', 'pagila_pgdata'], capture_output=True)
    if os.path.exists('../pagila'):
        shutil.rmtree('../pagila')

def simulate_user_wizard_flow():
    """
    Simulate exactly what happens when a user runs through the wizard
    with custom settings for Pagila.
    """
    print("=" * 60)
    print("SIMULATING USER WIZARD FLOW")
    print("=" * 60)

    # Clean start
    cleanup()

    # Simulate what wizard does: set up environment
    print("\n1. Setting up environment (as wizard would)...")

    # Create .env with custom settings (simulating wizard save)
    env_content = """# Custom settings from wizard
IMAGE_POSTGRES=mycorp.example.com/postgres:custom
PAGILA_REPO_URL=https://github.com/Troubladore/pagila.git
PAGILA_BRANCH=develop
"""

    with open('platform-bootstrap/.env', 'w') as f:
        f.write(env_content)

    # Create mock corporate image
    subprocess.run([
        'docker', 'tag', 'postgres:17.5-alpine',
        'mycorp.example.com/postgres:custom'
    ], capture_output=True)

    print("✓ Environment configured")

    # Run setup-pagila through make (as wizard would)
    print("\n2. Running make setup-pagila (as wizard would)...")
    result = subprocess.run(
        ['make', '-C', 'platform-bootstrap', 'setup-pagila', 'PAGILA_AUTO_YES=1'],
        capture_output=True,
        text=True,
        timeout=120
    )

    print(f"Return code: {result.returncode}")

    if result.returncode != 0:
        print("\n✗ Setup failed!")
        print("\nSTDOUT:")
        print(result.stdout[-1000:] if len(result.stdout) > 1000 else result.stdout)
        print("\nSTDERR:")
        print(result.stderr[-1000:] if len(result.stderr) > 1000 else result.stderr)

        # Check container status
        print("\n3. Checking container status after failure...")
        status = subprocess.run(
            ['docker', 'ps', '-a', '--filter', 'name=pagila', '--format',
             'table {{.Names}}\\t{{.Status}}\\t{{.State}}'],
            capture_output=True,
            text=True
        )
        print(status.stdout)

        # Get container logs
        print("\n4. Container logs (last 30 lines)...")
        logs = subprocess.run(
            ['docker', 'logs', 'pagila-postgres', '--tail', '30'],
            capture_output=True,
            text=True
        )
        print("STDERR (postgres logs):")
        print(logs.stderr)
        if logs.stdout:
            print("STDOUT:")
            print(logs.stdout)

        # Check health check details
        print("\n5. Health check details...")
        health = subprocess.run(
            ['docker', 'inspect', 'pagila-postgres',
             '--format', '{{json .State.Health}}'],
            capture_output=True,
            text=True
        )
        if health.stdout:
            import json
            try:
                health_data = json.loads(health.stdout)
                if health_data:
                    print(f"Status: {health_data.get('Status', 'unknown')}")
                    if 'Log' in health_data and health_data['Log']:
                        print("Last health check:")
                        last_check = health_data['Log'][-1]
                        print(f"  Exit Code: {last_check.get('ExitCode')}")
                        print(f"  Output: {last_check.get('Output', '').strip()}")
            except json.JSONDecodeError:
                print("Could not parse health data")

        return False

    print("✓ Setup completed successfully")
    return True

def test_timing_issue():
    """Test if this is a timing/race condition issue."""
    print("\n" + "=" * 60)
    print("TESTING TIMING/RACE CONDITION")
    print("=" * 60)

    # Monitor container for longer period
    print("\nMonitoring container health over time...")

    health_timeline = []
    for i in range(60):  # Monitor for 60 seconds
        result = subprocess.run(
            ['docker', 'inspect', 'pagila-postgres', '--format',
             '{{.State.Running}}|{{.State.Health.Status}}'],
            capture_output=True,
            text=True
        )

        if result.returncode == 0 and result.stdout:
            parts = result.stdout.strip().split('|')
            running = parts[0] == 'true'
            health = parts[1] if len(parts) > 1 else 'unknown'
            health_timeline.append((i, running, health))

            # Only print when status changes
            if i == 0 or health_timeline[-1] != health_timeline[-2]:
                print(f"  [{i}s] Running: {running}, Health: {health}")

            if not running or health == 'unhealthy':
                print(f"  ✗ Problem detected at {i} seconds!")
                break

        time.sleep(1)

    # Analyze timeline
    print("\nHealth timeline analysis:")
    healthy_count = sum(1 for _, _, h in health_timeline if h == 'healthy')
    unhealthy_count = sum(1 for _, _, h in health_timeline if h == 'unhealthy')
    print(f"  Healthy: {healthy_count} seconds")
    print(f"  Unhealthy: {unhealthy_count} seconds")

    if unhealthy_count > 0:
        print("\n  ✗ Container becomes unhealthy over time!")
        return False

    return True

if __name__ == "__main__":
    # Test the wizard flow
    wizard_success = simulate_user_wizard_flow()

    if wizard_success:
        # If setup succeeded, monitor for timing issues
        timing_ok = test_timing_issue()

        print("\n" + "=" * 60)
        print("RESULTS")
        print("=" * 60)
        print(f"Wizard flow: {'✓ PASS' if wizard_success else '✗ FAIL'}")
        print(f"Health stability: {'✓ STABLE' if timing_ok else '✗ UNSTABLE'}")
    else:
        print("\n" + "=" * 60)
        print("RESULTS")
        print("=" * 60)
        print("✗ Failed to reproduce user's issue in test environment")
        print("\nPossible environment differences:")
        print("  • WSL2 vs native Linux")
        print("  • Different Docker version")
        print("  • Network/firewall settings")
        print("  • File system permissions")
        print("  • Different pagila branch state")