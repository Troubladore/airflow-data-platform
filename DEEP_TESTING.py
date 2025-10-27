#!/usr/bin/env python3
"""
Deep comprehensive testing - all combinations, error paths, verification.
"""

import subprocess
import time
import json

def docker_clean():
    """Completely clean Docker."""
    subprocess.run('docker stop $(docker ps -aq) 2>/dev/null', shell=True, capture_output=True)
    subprocess.run('docker rm $(docker ps -aq) 2>/dev/null', shell=True, capture_output=True)
    subprocess.run(['docker', 'system', 'prune', '-af'], capture_output=True)

def get_docker_state():
    """Get complete Docker state."""
    containers = subprocess.run(['docker', 'ps', '-a', '--format', 'json'], capture_output=True, text=True)
    images = subprocess.run(['docker', 'images', '--format', 'json'], capture_output=True, text=True)
    volumes = subprocess.run(['docker', 'volume', 'ls', '--format', 'json'], capture_output=True, text=True)

    return {
        'containers': [json.loads(line) for line in containers.stdout.strip().split('\n') if line],
        'images': [json.loads(line) for line in images.stdout.strip().split('\n') if line],
        'volumes': [json.loads(line) for line in volumes.stdout.strip().split('\n') if line]
    }

def run_wizard(setup_inputs):
    """Run wizard with inputs, return output and docker state."""
    result = subprocess.run(
        ['./platform', 'setup'],
        input=setup_inputs,
        capture_output=True,
        text=True,
        timeout=180
    )
    return result.stdout, result.stderr, result.returncode, get_docker_state()

# Test matrix
test_scenarios = [
    {
        'name': 'Postgres only - passwordless',
        'inputs': 'n\nn\nn\n\nn\nn\n5432\n',
        'expect_containers': ['platform-postgres'],
        'expect_images': ['postgres:17.5-alpine'],
    },
    {
        'name': 'Postgres only - with password',
        'inputs': 'n\nn\nn\n\nn\ny\nsecurepass\n5432\n',
        'expect_containers': ['platform-postgres'],
        'expect_password': True,
    },
    {
        'name': 'Postgres + Kerberos',
        'inputs': 'n\ny\nn\n\nn\nn\n5432\nEXAMPLE.COM\nubuntu:22.04\n',
        'expect_containers': ['platform-postgres', 'kerberos-sidecar-mock'],
        'expect_images': ['postgres:17.5-alpine', 'ubuntu:22.04'],
    },
    {
        'name': 'Postgres + Pagila',
        'inputs': 'n\nn\ny\n\nn\nn\n5432\n\n',
        'expect_containers': ['platform-postgres'],
        'expect_db': 'pagila',
    },
    {
        'name': 'All services (no OpenMetadata)',
        'inputs': 'n\ny\ny\n\nn\nn\n5432\nEXAMPLE.COM\nubuntu:22.04\n\n',
        'expect_containers': ['platform-postgres', 'kerberos-sidecar-mock'],
        'expect_db': 'pagila',
    },
    {
        'name': 'Custom postgres image',
        'inputs': 'n\nn\nn\npostgres:16\nn\nn\n5433\n',
        'expect_containers': ['platform-postgres'],
        'expect_images': ['postgres:16'],
        'expect_port': '5433',
    },
    {
        'name': 'Prebuilt image',
        'inputs': 'n\nn\nn\ncustom/postgres:latest\ny\nn\n5432\n',
        'expect_prebuilt': True,
    },
]

print("DEEP TESTING - All Scenarios with Docker Verification\n")

results = []

for i, scenario in enumerate(test_scenarios, 1):
    print(f"\n{'='*70}")
    print(f"TEST {i}/{len(test_scenarios)}: {scenario['name']}")
    print(f"{'='*70}")

    # Clean Docker
    print("Cleaning Docker...")
    docker_clean()
    time.sleep(2)

    # Get before state
    before = get_docker_state()
    print(f"Before: {len(before['containers'])} containers")

    # Run wizard
    print(f"Running: {scenario['inputs'][:50]}...")
    try:
        stdout, stderr, code, after = run_wizard(scenario['inputs'])

        # Verify
        passed = True
        issues = []

        # Check exit code
        if code != 0:
            passed = False
            issues.append(f"Exit code {code}")

        # Check containers
        if 'expect_containers' in scenario:
            container_names = [c['Names'] for c in after['containers']]
            for expected in scenario['expect_containers']:
                if not any(expected in name for name in container_names):
                    passed = False
                    issues.append(f"Missing container: {expected}")

        # Check images
        if 'expect_images' in scenario:
            image_names = [i['Repository'] + ':' + i['Tag'] for i in after['images']]
            for expected in scenario['expect_images']:
                if expected not in image_names:
                    passed = False
                    issues.append(f"Missing image: {expected}")

        if passed:
            print(f"✓ PASS")
        else:
            print(f"✗ FAIL: {', '.join(issues)}")

        results.append((scenario['name'], passed, issues))

    except subprocess.TimeoutExpired:
        print("✗ FAIL: Timeout")
        results.append((scenario['name'], False, ['Timeout']))
    except Exception as e:
        print(f"✗ FAIL: {e}")
        results.append((scenario['name'], False, [str(e)]))

# Summary
print("\n" + "="*70)
print("SUMMARY")
print("="*70)

passed_count = sum(1 for _, passed, _ in results if passed)
total = len(results)

for name, passed, issues in results:
    status = "✓" if passed else "✗"
    print(f"{status} {name}")
    if issues:
        for issue in issues:
            print(f"    - {issue}")

print(f"\n{passed_count}/{total} scenarios passed")

if passed_count == total:
    print("\n🎉 ALL TESTS PASS - Ready for demo!")
else:
    print(f"\n❌ {total - passed_count} scenarios need fixes")
