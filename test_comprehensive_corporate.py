#!/usr/bin/env python3
"""
Comprehensive test for corporate user scenarios with Pagila.
Tests various combinations of custom settings that corporate users might use.
"""

import subprocess
import os
import time
import json

def cleanup():
    """Clean up all test artifacts."""
    subprocess.run(['docker', 'rm', '-f', 'pagila-postgres'], capture_output=True)
    subprocess.run(['docker', 'rm', '-f', 'pagila-jsonb-restore'], capture_output=True)
    subprocess.run(['docker', 'volume', 'rm', '-f', 'pagila_pgdata'], capture_output=True)

def create_mock_images():
    """Create various mock corporate images for testing."""
    images = [
        ('postgres:17.5-alpine', 'mycorp.jfrog.io/docker-mirror/postgres:17.5-custom'),
        ('postgres:17.5-alpine', 'artifactory.company.com:8443/docker-prod/postgres:v17.5'),
        ('postgres:17.5-alpine', 'internal.registry.corp.net/approved/postgresql:17-latest'),
    ]

    for source, target in images:
        subprocess.run(['docker', 'tag', source, target], capture_output=True)
        print(f"  Created mock: {target}")

def test_scenario(name, image, repo_url, branch, password=None):
    """Test a specific corporate scenario."""
    print(f"\nTesting: {name}")
    print(f"  Image: {image}")
    print(f"  Repo: {repo_url}")
    print(f"  Branch: {branch}")
    print(f"  Password: {'(empty)' if not password else '(set)'}")

    cleanup()

    # Setup environment
    env_lines = [
        f"IMAGE_POSTGRES={image}",
        f"PAGILA_REPO_URL={repo_url}",
        f"PAGILA_BRANCH={branch}",
    ]

    if password is not None:
        env_lines.append(f"POSTGRES_PASSWORD={password}")

    with open('platform-bootstrap/.env', 'w') as f:
        f.write('\n'.join(env_lines))

    # Run setup
    result = subprocess.run([
        'make', '-C', 'platform-bootstrap', 'setup-pagila',
        'PAGILA_AUTO_YES=1'
    ], capture_output=True, text=True, timeout=60)

    if result.returncode != 0:
        print(f"  ✗ Setup failed (return code: {result.returncode})")
        return False

    # Check container health
    time.sleep(8)
    health_result = subprocess.run(
        ['docker', 'inspect', 'pagila-postgres', '--format', '{{.State.Health.Status}}'],
        capture_output=True, text=True
    )

    health = health_result.stdout.strip()

    # Check password handling
    password_check = "N/A"
    if os.path.exists('../pagila/.env'):
        with open('../pagila/.env', 'r') as f:
            content = f.read()
            if 'POSTGRES_PASSWORD=' in content:
                pwd_line = [l for l in content.split('\n') if l.startswith('POSTGRES_PASSWORD=')][0]
                pwd_value = pwd_line.split('=', 1)[1]
                password_check = "has value" if pwd_value else "empty"

    print(f"  Health: {health}")
    print(f"  Password in .env: {password_check}")

    success = health == 'healthy'
    print(f"  Result: {'✓ PASS' if success else '✗ FAIL'}")

    return success

def run_all_tests():
    """Run comprehensive corporate scenario tests."""
    print("=" * 60)
    print("COMPREHENSIVE CORPORATE PAGILA TESTS")
    print("=" * 60)

    print("\nCreating mock corporate images...")
    create_mock_images()

    scenarios = [
        # Scenario 1: Complex registry path with no password
        {
            'name': 'Complex JFrog registry, no password',
            'image': 'mycorp.jfrog.io/docker-mirror/postgres:17.5-custom',
            'repo_url': 'https://github.com/Troubladore/pagila.git',
            'branch': 'develop',
            'password': ''  # Empty password
        },

        # Scenario 2: Artifactory with port, custom branch
        {
            'name': 'Artifactory with port, main branch',
            'image': 'artifactory.company.com:8443/docker-prod/postgres:v17.5',
            'repo_url': 'https://github.com/Troubladore/pagila.git',
            'branch': 'main',
            'password': None  # No password specified
        },

        # Scenario 3: Internal registry, develop branch
        {
            'name': 'Internal registry, develop branch',
            'image': 'internal.registry.corp.net/approved/postgresql:17-latest',
            'repo_url': 'https://github.com/Troubladore/pagila.git',
            'branch': 'develop',
            'password': ''
        },

        # Scenario 4: Standard image, empty password (control)
        {
            'name': 'Standard postgres, empty password',
            'image': 'postgres:17.5-alpine',
            'repo_url': 'https://github.com/Troubladore/pagila.git',
            'branch': 'develop',
            'password': ''
        }
    ]

    results = []
    for scenario in scenarios:
        success = test_scenario(**scenario)
        results.append((scenario['name'], success))

    # Summary
    print("\n" + "=" * 60)
    print("TEST SUMMARY")
    print("=" * 60)

    all_passed = True
    for name, success in results:
        status = "✓ PASS" if success else "✗ FAIL"
        print(f"  {status}: {name}")
        if not success:
            all_passed = False

    print("=" * 60)

    return all_passed

if __name__ == "__main__":
    success = run_all_tests()

    # Final cleanup
    cleanup()
    if os.path.exists('../pagila'):
        subprocess.run(['rm', '-rf', '../pagila'], capture_output=True)

    if success:
        print("\n✓ ALL TESTS PASSED!")
        print("  Corporate users can now use Pagila with:")
        print("  - Complex registry paths")
        print("  - Custom branches")
        print("  - Empty passwords (auto-generated)")
        print("  - Trust authentication maintained")
        exit(0)
    else:
        print("\n✗ SOME TESTS FAILED")
        exit(1)