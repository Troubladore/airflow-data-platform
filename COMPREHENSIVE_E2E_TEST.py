#!/usr/bin/env python3
"""
Comprehensive end-to-end testing with Docker verification.
Tests both happy and unhappy paths.
"""

import subprocess
import time

def run_cmd(cmd, input_text=None):
    """Run command and return output."""
    result = subprocess.run(
        cmd,
        input=input_text,
        capture_output=True,
        text=True,
        timeout=120,
        shell=isinstance(cmd, str)
    )
    return result.stdout, result.stderr, result.returncode

def check_docker_containers():
    """Check what Docker containers exist."""
    stdout, _, _ = run_cmd(['docker', 'ps', '-a', '--format', '{{.Names}}'])
    return [name for name in stdout.strip().split('\n') if name]

def check_docker_images():
    """Check what Docker images exist."""
    stdout, _, _ = run_cmd(['docker', 'images', '--format', '{{.Repository}}:{{.Tag}}'])
    return [img for img in stdout.strip().split('\n') if img and img != '<none>:<none>']

print("="*70)
print("COMPREHENSIVE END-TO-END WIZARD TEST")
print("="*70)

# Test 1: Setup with Docker running
print("\n### TEST 1: Setup from clean state")
print("Expected: Creates postgres container")

containers_before = check_docker_containers()
print(f"Containers before: {containers_before}")

stdout, stderr, code = run_cmd(
    ['./platform', 'setup'],
    input_text='n\nn\nn\n\nn\nn\n5432\n'
)

if code != 0:
    print(f"✗ FAIL: Setup exited with code {code}")
    print(f"Error: {stderr}")
else:
    print("✓ Setup completed")

containers_after = check_docker_containers()
print(f"Containers after: {containers_after}")

new_containers = set(containers_after) - set(containers_before)
if new_containers:
    print(f"✓ PASS: Created containers: {new_containers}")
else:
    print("✗ FAIL: No containers created")

time.sleep(2)

# Test 2: Verify containers are actually running
print("\n### TEST 2: Verify postgres is accessible")

stdout, stderr, code = run_cmd([
    'docker', 'exec', 'platform-postgres',
    'psql', '-U', 'postgres', '-c', 'SELECT 1'
])

if code == 0:
    print("✓ PASS: PostgreSQL is accessible and running")
else:
    print(f"✗ FAIL: PostgreSQL not accessible: {stderr}")

# Test 3: Clean-slate discovery
print("\n### TEST 3: Clean-slate discovery")

# Just run discovery phase (will timeout after but that's ok)
proc = subprocess.Popen(
    ['./platform', 'clean-slate'],
    stdin=subprocess.PIPE,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    text=True
)

try:
    stdout, stderr = proc.communicate(timeout=5)
except subprocess.TimeoutExceeded:
    proc.kill()
    stdout, stderr = proc.communicate()

if 'Found' in stdout and 'artifacts' in stdout:
    print("✓ PASS: Discovery found artifacts")
    print(f"   Output: {[line for line in stdout.split('\\n') if 'Found' in line][0]}")
else:
    print("✗ FAIL: Discovery didn't run properly")

# Test 4: Setup with Docker stopped
print("\n### TEST 4: Setup with Docker stopped")

subprocess.run(['docker', 'stop', 'platform-postgres'], capture_output=True)
subprocess.run(['docker', 'rm', 'platform-postgres'], capture_output=True)
subprocess.run(['systemctl', 'stop', 'docker'], capture_output=True)  # Stop Docker daemon

time.sleep(2)

stdout, stderr, code = run_cmd(
    ['./platform', 'setup'],
    input_text='n\nn\nn\n\nn\nn\n5432\n'
)

if 'Docker' in stderr or 'docker' in stderr:
    print("✓ PASS: Gracefully handled Docker not running")
elif code == 0:
    print("⚠ WARN: Completed but Docker might not have started")
else:
    print(f"Result: Exit code {code}")

# Restart Docker
subprocess.run(['systemctl', 'start', 'docker'], capture_output=True)
time.sleep(3)

print("\n" + "="*70)
print("END-TO-END TEST COMPLETE")
print("="*70)
print("\nManual verification needed:")
print("1. Run './platform setup' interactively")
print("2. Check 'docker ps' shows container")
print("3. Run './platform clean-slate' and verify removal")
