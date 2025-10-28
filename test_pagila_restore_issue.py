#!/usr/bin/env python3
"""
Test if the pagila-jsonb-restore container is causing the postgres shutdown.
Phase 2: Pattern Analysis - comparing working vs broken scenarios.
"""

import subprocess
import os
import time
import json

def run_cmd(cmd, capture=True):
    """Run command and return result."""
    if capture:
        result = subprocess.run(cmd, capture_output=True, text=True, shell=isinstance(cmd, str))
        return result.returncode, result.stdout, result.stderr
    else:
        result = subprocess.run(cmd, shell=isinstance(cmd, str))
        return result.returncode, "", ""

def cleanup():
    """Clean up containers."""
    run_cmd('docker rm -f pagila-postgres pagila-jsonb-restore 2>/dev/null', capture=False)
    run_cmd('docker volume rm -f pagila_pgdata 2>/dev/null', capture=False)

def monitor_container_health(container_name, duration=30):
    """Monitor container health over time."""
    health_log = []

    for i in range(duration):
        rc, stdout, _ = run_cmd([
            'docker', 'inspect', container_name,
            '--format', '{{json .State}}'
        ])

        if rc == 0 and stdout:
            try:
                state = json.loads(stdout)
                health = state.get('Health', {}).get('Status', 'unknown')
                running = state.get('Running', False)
                health_log.append((i, running, health))
                print(f"  [{i}s] Running: {running}, Health: {health}")

                if not running:
                    print("  ✗ Container stopped!")
                    break

            except json.JSONDecodeError:
                pass

        time.sleep(1)

    return health_log

def test_postgres_only():
    """Test running only the postgres container without restore."""
    print("\n" + "=" * 60)
    print("TEST 1: PostgreSQL Container Only (no restore)")
    print("=" * 60)

    cleanup()

    # Start only postgres container
    print("Starting only pagila-postgres container...")
    os.chdir('../pagila')

    # Use docker-compose but only start the pagila service
    rc, stdout, stderr = run_cmd(['docker', 'compose', 'up', '-d', 'pagila'])
    if rc != 0:
        print(f"Failed to start: {stderr}")
        os.chdir('..')
        return False

    print("Monitoring health for 30 seconds...")
    health_log = monitor_container_health('pagila-postgres', 30)

    # Check if jsonb-restore container was started
    rc, stdout, _ = run_cmd(['docker', 'ps', '-a', '--format', '{{.Names}}'])
    if 'pagila-jsonb-restore' in stdout:
        print("✗ jsonb-restore container was started (unexpected)")
    else:
        print("✓ jsonb-restore container NOT started (as expected)")

    # Get final status
    final_health = health_log[-1] if health_log else (0, False, 'unknown')
    success = final_health[1] and final_health[2] == 'healthy'

    os.chdir('..')
    return success

def test_with_restore():
    """Test with both containers."""
    print("\n" + "=" * 60)
    print("TEST 2: With JSONB Restore Container")
    print("=" * 60)

    cleanup()

    # Check if backup files exist
    print("Checking backup files...")
    backup_files = [
        '../pagila/pagila-data-apt-jsonb.backup',
        '../pagila/pagila-data-yum-jsonb.backup'
    ]

    for file in backup_files:
        if os.path.exists(file):
            size = os.path.getsize(file)
            print(f"  ✓ {os.path.basename(file)} ({size} bytes)")
        else:
            print(f"  ✗ {os.path.basename(file)} MISSING")

    # Start both containers
    print("\nStarting both containers...")
    os.chdir('../pagila')

    rc, stdout, stderr = run_cmd(['docker', 'compose', 'up', '-d'])
    if rc != 0:
        print(f"Failed to start: {stderr}")
        os.chdir('..')
        return False

    print("Monitoring postgres health...")
    health_log = monitor_container_health('pagila-postgres', 30)

    # Check restore container status
    print("\nChecking restore container...")
    rc, stdout, _ = run_cmd([
        'docker', 'inspect', 'pagila-jsonb-restore',
        '--format', '{{.State.Status}}'
    ])
    if rc == 0:
        restore_status = stdout.strip()
        print(f"  Restore container status: {restore_status}")

        # Get restore container logs
        rc, stdout, stderr = run_cmd(['docker', 'logs', 'pagila-jsonb-restore', '--tail', '20'])
        if 'error' in (stdout + stderr).lower() or 'fatal' in (stdout + stderr).lower():
            print("  ✗ Errors in restore container:")
            for line in (stdout + stderr).split('\n'):
                if 'error' in line.lower() or 'fatal' in line.lower():
                    print(f"    {line.strip()}")

    # Get postgres logs during restore
    print("\nPostgreSQL logs during restore:")
    rc, stdout, stderr = run_cmd(['docker', 'logs', 'pagila-postgres', '--tail', '30'])
    for line in (stderr + stdout).split('\n'):
        if 'shutdown' in line.lower() or 'terminating' in line.lower() or 'fatal' in line.lower():
            print(f"  ! {line.strip()}")

    final_health = health_log[-1] if health_log else (0, False, 'unknown')
    success = final_health[1] and final_health[2] == 'healthy'

    os.chdir('..')
    return success

def test_hypothesis():
    """
    Phase 3: Hypothesis Testing
    Hypothesis: The jsonb-restore container or missing backup files cause postgres to shutdown
    """
    print("\n" + "=" * 60)
    print("HYPOTHESIS TEST: Restore Container Interference")
    print("=" * 60)

    # First check if this is the actual scenario the user is experiencing
    print("\n1. Checking current state...")

    # Check what containers exist
    rc, stdout, _ = run_cmd(['docker', 'ps', '-a', '--format', '{{.Names}}|{{.State}}|{{.Status}}'])
    if stdout:
        print("Current containers:")
        for line in stdout.strip().split('\n'):
            if 'pagila' in line:
                print(f"  {line}")

    # Run isolated tests
    postgres_only_result = test_postgres_only()

    time.sleep(5)  # Brief pause between tests
    cleanup()

    with_restore_result = test_with_restore()

    # Analysis
    print("\n" + "=" * 60)
    print("HYPOTHESIS TEST RESULTS")
    print("=" * 60)

    if postgres_only_result and not with_restore_result:
        print("✓ HYPOTHESIS CONFIRMED:")
        print("  PostgreSQL works alone but fails with restore container")
        print("  Root cause: jsonb-restore container or backup files issue")
        print("\n  Suggested fix:")
        print("  1. Check if backup files exist in pagila/")
        print("  2. Disable jsonb-restore in docker-compose.yml")
        print("  3. Or fix the restore process")
        return True

    elif not postgres_only_result:
        print("✗ HYPOTHESIS REJECTED:")
        print("  PostgreSQL fails even without restore container")
        print("  Root cause is in the main postgres configuration")
        print("\n  Need to investigate:")
        print("  1. PostgreSQL initialization issues")
        print("  2. Volume permissions")
        print("  3. Config file problems")
        return False

    else:
        print("? INCONCLUSIVE:")
        print(f"  Postgres only: {postgres_only_result}")
        print(f"  With restore: {with_restore_result}")
        return None

if __name__ == "__main__":
    result = test_hypothesis()

    # Clean up after tests
    cleanup()

    if result is True:
        print("\nNext step: Fix the jsonb-restore issue")
        exit(0)
    elif result is False:
        print("\nNext step: Debug postgres container itself")
        exit(1)
    else:
        print("\nNext step: Gather more evidence")
        exit(2)