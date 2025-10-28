#!/usr/bin/env python3
"""
Comprehensive diagnostic for Pagila health check failures.
This script reproduces the issue and captures detailed diagnostics.
"""

import subprocess
import os
import time
import json
import shutil

def run_cmd(cmd, capture=True, cwd=None):
    """Run command and return result."""
    print(f"Running: {' '.join(cmd) if isinstance(cmd, list) else cmd}")
    if capture:
        result = subprocess.run(cmd, capture_output=True, text=True, cwd=cwd, shell=isinstance(cmd, str))
        return result.returncode, result.stdout, result.stderr
    else:
        result = subprocess.run(cmd, cwd=cwd, shell=isinstance(cmd, str))
        return result.returncode, "", ""

def cleanup():
    """Clean up test environment."""
    print("Cleaning up...")
    run_cmd(['docker', 'rm', '-f', 'pagila-postgres'], capture=False)
    run_cmd(['docker', 'rm', '-f', 'pagila-jsonb-restore'], capture=False)
    run_cmd(['docker', 'volume', 'rm', '-f', 'pagila_pgdata'], capture=False)

def diagnose_unhealthy_container():
    """Diagnose why Pagila container becomes unhealthy."""
    print("=" * 60)
    print("PAGILA HEALTH CHECK DIAGNOSTIC")
    print("=" * 60)

    # Check if pagila exists
    pagila_path = '../pagila'
    if not os.path.exists(pagila_path):
        print(f"✗ Pagila not found at {pagila_path}")
        print("  Run: git clone https://github.com/Troubladore/pagila.git ../pagila")
        return

    print(f"✓ Found pagila at {os.path.abspath(pagila_path)}")

    # Check critical files
    print("\n1. Checking critical files...")
    critical_files = [
        'docker-compose.yml',
        'pg_hba.conf',
        'postgresql.conf',
        '.env',
        'pagila-schema.sql',
        'pagila-data.sql'
    ]

    missing_files = []
    for file in critical_files:
        filepath = os.path.join(pagila_path, file)
        if os.path.exists(filepath):
            print(f"  ✓ {file}")
            # Check specific content for config files
            if file == 'pg_hba.conf':
                with open(filepath, 'r') as f:
                    content = f.read()
                    if 'trust' not in content:
                        print(f"    ⚠ Missing 'trust' authentication in pg_hba.conf")

            elif file == 'postgresql.conf':
                with open(filepath, 'r') as f:
                    content = f.read()
                    print(f"    Content: {content[:100]}")

            elif file == '.env':
                with open(filepath, 'r') as f:
                    for line in f:
                        if 'POSTGRES_PASSWORD' in line:
                            pwd_value = line.split('=', 1)[1].strip()
                            if pwd_value:
                                print(f"    Password is set: {pwd_value[:10]}...")
                            else:
                                print(f"    ⚠ PASSWORD IS EMPTY!")
        else:
            print(f"  ✗ {file} - MISSING")
            missing_files.append(file)

    if missing_files:
        print(f"\n⚠ Missing files will cause failures: {', '.join(missing_files)}")

    # Check docker-compose.yml for the command and healthcheck
    print("\n2. Checking docker-compose.yml configuration...")
    compose_path = os.path.join(pagila_path, 'docker-compose.yml')
    if os.path.exists(compose_path):
        with open(compose_path, 'r') as f:
            content = f.read()

        # Check for the postgres command
        if 'postgres -c' in content:
            print("  ✓ Custom postgres command found")
            if 'config_file=/etc/postgresql/postgresql.conf' in content:
                print("    Using custom postgresql.conf")
        else:
            print("  ⚠ No custom postgres command")

        # Check healthcheck
        if 'healthcheck:' in content:
            print("  ✓ Healthcheck configured")
            # Extract healthcheck details
            lines = content.split('\n')
            for i, line in enumerate(lines):
                if 'healthcheck:' in line:
                    for j in range(i+1, min(i+6, len(lines))):
                        if 'test:' in lines[j]:
                            print(f"    Test command: {lines[j].strip()}")

        # Check volume mounts
        if 'pg_hba.conf:/etc/postgresql/pg_hba.conf' in content:
            print("  ✓ pg_hba.conf mounted")
        else:
            print("  ✗ pg_hba.conf NOT mounted")

        if 'postgresql.conf:/etc/postgresql/postgresql.conf' in content:
            print("  ✓ postgresql.conf mounted")
        else:
            print("  ✗ postgresql.conf NOT mounted")

    # Start container and monitor health
    print("\n3. Starting container and monitoring health...")
    cleanup()  # Clean first

    os.chdir(pagila_path)
    print(f"  Working directory: {os.getcwd()}")

    # Start with docker-compose
    rc, stdout, stderr = run_cmd(['docker', 'compose', 'up', '-d'])
    if rc != 0:
        print(f"  ✗ Docker compose failed: {stderr}")
        os.chdir('..')
        return

    print("  Container started, monitoring health...")

    # Monitor health status for 30 seconds
    unhealthy_detected = False
    for i in range(30):
        rc, stdout, stderr = run_cmd([
            'docker', 'inspect', 'pagila-postgres',
            '--format', '{{json .State}}'
        ])

        if rc == 0 and stdout:
            try:
                state = json.loads(stdout)
                health = state.get('Health', {}).get('Status', 'unknown')
                running = state.get('Running', False)
                exit_code = state.get('ExitCode', 0)

                print(f"  [{i+1}s] Running: {running}, Health: {health}", end='')

                if health == 'unhealthy':
                    print(" ← UNHEALTHY DETECTED!")
                    unhealthy_detected = True
                    break
                elif health == 'healthy':
                    print(" ✓")
                    break
                else:
                    print()

                if not running:
                    print(f"  ✗ Container stopped! Exit code: {exit_code}")
                    break

            except json.JSONDecodeError:
                print(f"  Error parsing state: {stdout}")

        time.sleep(1)

    # Get detailed logs
    print("\n4. Container logs analysis...")
    rc, stdout, stderr = run_cmd(['docker', 'logs', 'pagila-postgres', '--tail', '100'])
    logs = stderr if stderr else stdout

    # Analyze logs for specific issues
    issues_found = []

    if 'POSTGRES_PASSWORD' in logs and 'must specify' in logs:
        issues_found.append("PostgreSQL requires non-empty password")

    if 'FATAL' in logs:
        fatal_lines = [line for line in logs.split('\n') if 'FATAL' in line]
        for line in fatal_lines[:3]:  # Show first 3 fatal errors
            print(f"  FATAL: {line.strip()}")
            issues_found.append(f"Fatal error: {line.strip()[:100]}")

    if 'config_file' in logs and 'No such file' in logs:
        issues_found.append("Configuration file not found")
        print("  ✗ Config file issue detected")

    if 'permission denied' in logs.lower():
        issues_found.append("Permission issues")
        print("  ✗ Permission denied errors found")

    if 'could not open' in logs:
        open_errors = [line for line in logs.split('\n') if 'could not open' in line]
        for line in open_errors[:2]:
            print(f"  File error: {line.strip()}")

    # Check what the health check actually does
    print("\n5. Testing health check commands manually...")

    # Test pg_isready
    rc, stdout, stderr = run_cmd([
        'docker', 'exec', 'pagila-postgres',
        'pg_isready', '-U', 'postgres', '-d', 'pagila'
    ])
    print(f"  pg_isready: {'✓ PASS' if rc == 0 else '✗ FAIL'}")
    if rc != 0:
        print(f"    Error: {stderr}")

    # Test psql connection
    rc, stdout, stderr = run_cmd([
        'docker', 'exec', 'pagila-postgres',
        'psql', '-U', 'postgres', '-d', 'pagila', '-c', 'SELECT 1'
    ])
    print(f"  psql SELECT 1: {'✓ PASS' if rc == 0 else '✗ FAIL'}")
    if rc != 0:
        print(f"    Error: {stderr}")

    # Check if database exists
    rc, stdout, stderr = run_cmd([
        'docker', 'exec', 'pagila-postgres',
        'psql', '-U', 'postgres', '-lqt'
    ])
    if rc == 0:
        if 'pagila' in stdout:
            print("  ✓ pagila database exists")
        else:
            print("  ✗ pagila database NOT found")
            print(f"    Databases: {stdout}")

    # Check process list inside container
    print("\n6. Checking processes inside container...")
    rc, stdout, stderr = run_cmd([
        'docker', 'exec', 'pagila-postgres',
        'ps', 'aux'
    ])
    if rc == 0:
        postgres_procs = [line for line in stdout.split('\n') if 'postgres' in line]
        print(f"  Found {len(postgres_procs)} postgres processes")
        if len(postgres_procs) < 3:
            print("  ⚠ Fewer processes than expected")

    # Check mounted files inside container
    print("\n7. Checking mounted config files inside container...")
    config_files = [
        '/etc/postgresql/pg_hba.conf',
        '/etc/postgresql/postgresql.conf',
        '/var/lib/postgresql/data',
        '/docker-entrypoint-initdb.d'
    ]

    for filepath in config_files:
        rc, stdout, stderr = run_cmd([
            'docker', 'exec', 'pagila-postgres',
            'ls', '-la', filepath
        ])
        if rc == 0:
            print(f"  ✓ {filepath} exists")
            if 'pg_hba.conf' in filepath or 'postgresql.conf' in filepath:
                # Check if file is readable
                rc2, stdout2, stderr2 = run_cmd([
                    'docker', 'exec', 'pagila-postgres',
                    'head', '-n', '5', filepath
                ])
                if rc2 == 0:
                    print(f"    Readable: Yes")
                else:
                    print(f"    ⚠ Not readable: {stderr2}")
        else:
            print(f"  ✗ {filepath} NOT FOUND")

    os.chdir('..')

    # Summary
    print("\n" + "=" * 60)
    print("DIAGNOSTIC SUMMARY")
    print("=" * 60)

    if unhealthy_detected:
        print("✗ Container becomes UNHEALTHY")
        print("\nIssues found:")
        for issue in issues_found:
            print(f"  • {issue}")

        print("\nRecommended fixes:")
        if "password" in str(issues_found).lower():
            print("  1. Ensure POSTGRES_PASSWORD is not empty in .env")
        if "config" in str(issues_found).lower():
            print("  1. Check pg_hba.conf and postgresql.conf exist and are readable")
        if "permission" in str(issues_found).lower():
            print("  1. Fix file permissions: chmod 644 pagila/*.conf")
    else:
        print("✓ Container is healthy")

if __name__ == "__main__":
    diagnose_unhealthy_container()