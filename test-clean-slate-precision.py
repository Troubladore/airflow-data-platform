#!/usr/bin/env python3
"""
Precision RED/GREEN Acceptance Test for Clean-Slate Wizard
===========================================================
Follows CLAUDE.md rules (lines 151-223) for precision testing.

Test Protocol:
1. SETUP Phase: Create known state
2. RED Phase: Verify artifacts EXIST before removal
3. Execute Action: Run clean-slate with all yes answers
4. GREEN Phase: Verify correct artifacts removed/kept
5. Report: Grade with detailed evidence
"""

import subprocess
import sys
import json
from typing import Dict, List, Set
from pathlib import Path

# ANSI colors for output
GREEN = '\033[92m'
RED = '\033[91m'
YELLOW = '\033[93m'
BLUE = '\033[94m'
BOLD = '\033[1m'
RESET = '\033[0m'

class PrecisionTester:
    def __init__(self, working_dir: str):
        self.working_dir = Path(working_dir)
        self.manifest_before = {}
        self.manifest_after = {}
        self.red_results = []
        self.green_results = []
        self.failures = []

    def print_phase(self, phase: str):
        """Print phase header"""
        print(f"\n{BOLD}{BLUE}{'='*80}{RESET}")
        print(f"{BOLD}{BLUE}{phase.center(80)}{RESET}")
        print(f"{BOLD}{BLUE}{'='*80}{RESET}\n")

    def print_success(self, msg: str):
        print(f"{GREEN}✓{RESET} {msg}")

    def print_failure(self, msg: str):
        print(f"{RED}✗{RESET} {msg}")

    def print_info(self, msg: str):
        print(f"{BLUE}ℹ{RESET} {msg}")

    def run_command(self, cmd: List[str], input_str: str = None, check=False) -> subprocess.CompletedProcess:
        """Run command and return result"""
        return subprocess.run(
            cmd,
            cwd=self.working_dir,
            input=input_str,
            capture_output=True,
            text=True,
            check=check
        )

    def get_docker_containers(self) -> Set[str]:
        """Get all container names"""
        result = self.run_command(['docker', 'ps', '-a', '--format', '{{.Names}}'])
        if result.returncode == 0 and result.stdout.strip():
            return set(result.stdout.strip().split('\n'))
        return set()

    def get_docker_images(self) -> Set[str]:
        """Get all image names with tags"""
        result = self.run_command(['docker', 'images', '--format', '{{.Repository}}:{{.Tag}}'])
        if result.returncode == 0 and result.stdout.strip():
            return set(result.stdout.strip().split('\n'))
        return set()

    def get_docker_volumes(self) -> Set[str]:
        """Get all volume names"""
        result = self.run_command(['docker', 'volume', 'ls', '--format', '{{.Name}}'])
        if result.returncode == 0 and result.stdout.strip():
            return set(result.stdout.strip().split('\n'))
        return set()

    def get_platform_config(self) -> str:
        """Get platform-config.yaml contents"""
        config_path = self.working_dir / 'platform-config.yaml'
        if config_path.exists():
            return config_path.read_text()
        return ""

    def capture_system_state(self) -> Dict:
        """Capture complete system state"""
        return {
            'containers': self.get_docker_containers(),
            'images': self.get_docker_images(),
            'volumes': self.get_docker_volumes(),
            'config': self.get_platform_config(),
            'config_exists': (self.working_dir / 'platform-config.yaml').exists()
        }

    def setup_phase(self):
        """SETUP Phase: Create known state with postgres + kerberos"""
        self.print_phase("SETUP PHASE: Creating Known State")

        print("Running: ./platform setup with postgres + kerberos...")
        print(f"{YELLOW}This will be interactive - answer prompts as follows:{RESET}")
        print("  - PostgreSQL: y")
        print("  - Kerberos: y")
        print("  - Other services: n")
        print("  - Use defaults for all configurations")

        # Setup inputs: Follow wizard flow
        # Service selection: OpenMetadata=n, Kerberos=y, Pagila=n
        # PostgreSQL (always enabled): image=default, prebuilt=n, password=n, port=default
        # Kerberos: domain=EXAMPLE.COM, image=ubuntu:22.04
        setup_inputs = (
            "n\n"               # Install OpenMetadata? [y/N]
            "y\n"               # Install Kerberos? [y/N]
            "n\n"               # Install Pagila? [y/N]
            "\n"                # PostgreSQL Docker image [postgres:17.5-alpine] (use default)
            "n\n"               # Use prebuilt image? [y/N]
            "n\n"               # Require password for PostgreSQL database? [Y/n]
            "\n"                # PostgreSQL port [5432] (use default)
            "EXAMPLE.COM\n"     # Enter Kerberos domain
            "ubuntu:22.04\n"    # Enter Docker image for Kerberos
        )

        result = self.run_command(['./platform', 'setup'], input_str=setup_inputs)

        print(f"\n{BOLD}Setup Output:{RESET}")
        print(result.stdout)
        if result.stderr:
            print(f"{YELLOW}Setup Stderr:{RESET}")
            print(result.stderr)

        if result.returncode != 0:
            self.print_failure(f"Setup failed with exit code {result.returncode}")
            self.failures.append({
                'phase': 'SETUP',
                'issue': 'Setup wizard failed',
                'exit_code': result.returncode,
                'stdout': result.stdout,
                'stderr': result.stderr
            })
            return False

        self.print_success(f"Setup completed with exit code {result.returncode}")

        # Verify containers were created
        containers = self.get_docker_containers()
        expected = ['platform-postgres', 'kerberos-sidecar']

        print(f"\nVerifying containers created...")
        for container in expected:
            if container in containers:
                self.print_success(f"Container '{container}' exists")
            else:
                self.print_failure(f"Container '{container}' NOT found")
                self.failures.append({
                    'phase': 'SETUP',
                    'issue': f'Expected container {container} not created'
                })

        return True

    def red_phase(self):
        """RED Phase: Capture state and verify artifacts EXIST"""
        self.print_phase("RED PHASE: Manifest Before (Artifacts Should EXIST)")

        self.manifest_before = self.capture_system_state()

        print(f"{BOLD}System State Before Clean-Slate:{RESET}")
        print(f"\nContainers ({len(self.manifest_before['containers'])}):")
        for container in sorted(self.manifest_before['containers']):
            print(f"  - {container}")

        print(f"\nImages ({len(self.manifest_before['images'])}):")
        for image in sorted(self.manifest_before['images']):
            if 'postgres' in image.lower() or 'ubuntu' in image.lower():
                print(f"  - {image}")

        print(f"\nVolumes ({len(self.manifest_before['volumes'])}):")
        for volume in sorted(self.manifest_before['volumes']):
            if 'postgres' in volume.lower():
                print(f"  - {volume}")

        print(f"\nConfig file exists: {self.manifest_before['config_exists']}")

        # RED Phase Tests: Verify target artifacts EXIST
        print(f"\n{BOLD}RED Phase Validation (Artifacts should EXIST):{RESET}")

        expected_artifacts = [
            ('container', 'platform-postgres'),
            ('container', 'kerberos-sidecar'),
            ('config', 'platform-config.yaml'),
        ]

        all_exist = True
        for artifact_type, artifact_name in expected_artifacts:
            if artifact_type == 'container':
                exists = artifact_name in self.manifest_before['containers']
            elif artifact_type == 'config':
                exists = self.manifest_before['config_exists']
            else:
                exists = False

            if exists:
                self.print_success(f"RED PASS: {artifact_name} exists before removal")
                self.red_results.append({
                    'artifact': artifact_name,
                    'expected': 'EXISTS',
                    'actual': 'EXISTS',
                    'pass': True
                })
            else:
                self.print_failure(f"RED FAIL: {artifact_name} should exist but doesn't")
                self.red_results.append({
                    'artifact': artifact_name,
                    'expected': 'EXISTS',
                    'actual': 'MISSING',
                    'pass': False
                })
                self.failures.append({
                    'phase': 'RED',
                    'issue': f'{artifact_name} should exist before clean-slate but is missing',
                    'severity': 'CRITICAL',
                    'evidence': 'Setup phase did not create expected artifacts'
                })
                all_exist = False

        return all_exist

    def execute_action(self):
        """Execute Action: Run clean-slate with ALL yes answers"""
        self.print_phase("EXECUTE ACTION: Running Clean-Slate with ALL YES")

        print("Running: ./platform clean-slate")
        print(f"{YELLOW}Answering YES to ALL removal prompts:{RESET}")
        print("  - Remove postgres? y")
        print("  - Remove kerberos? y")
        print("  - Remove images? y")
        print("  - Remove volumes? y")
        print("  - Remove config? y")

        # Clean-slate inputs: y for all services and all removal options
        # Service selection phase
        # Then for each selected service: images, volumes/keytabs, config
        cleanslate_inputs = (
            # Service selection
            "y\n"  # Tear down PostgreSQL? [y/N]
            "n\n"  # Tear down OpenMetadata? [y/N] (not installed)
            "y\n"  # Tear down Kerberos? [y/N]
            "n\n"  # Tear down Pagila? [y/N] (not installed)
            # PostgreSQL teardown options
            "y\n"  # Remove PostgreSQL Docker images? [y/N]
            "y\n"  # Remove PostgreSQL data volumes? [y/N]
            "y\n"  # Remove from platform configuration? [y/N]
            # Kerberos teardown options
            "y\n"  # Remove Kerberos Docker images? [y/N]
            "y\n"  # Remove keytab files? [y/N]
            "y\n"  # Remove from platform configuration? [y/N]
        )

        result = self.run_command(['./platform', 'clean-slate'], input_str=cleanslate_inputs)

        print(f"\n{BOLD}Clean-Slate Output:{RESET}")
        print(result.stdout)
        if result.stderr:
            print(f"{YELLOW}Clean-Slate Stderr:{RESET}")
            print(result.stderr)

        if result.returncode != 0:
            self.print_failure(f"Clean-slate failed with exit code {result.returncode}")
            self.failures.append({
                'phase': 'EXECUTE',
                'issue': 'Clean-slate wizard failed',
                'exit_code': result.returncode,
                'stdout': result.stdout,
                'stderr': result.stderr
            })
            return False

        self.print_success(f"Clean-slate completed with exit code {result.returncode}")
        return True

    def green_phase(self):
        """GREEN Phase: Verify correct artifacts removed"""
        self.print_phase("GREEN PHASE: Precision Validation (Correct Removals)")

        self.manifest_after = self.capture_system_state()

        print(f"{BOLD}System State After Clean-Slate:{RESET}")
        print(f"\nContainers ({len(self.manifest_after['containers'])}):")
        for container in sorted(self.manifest_after['containers']):
            print(f"  - {container}")

        print(f"\nImages ({len(self.manifest_after['images'])}):")
        for image in sorted(self.manifest_after['images']):
            if 'postgres' in image.lower() or 'ubuntu' in image.lower():
                print(f"  - {image}")

        print(f"\nVolumes ({len(self.manifest_after['volumes'])}):")
        for volume in sorted(self.manifest_after['volumes']):
            if 'postgres' in volume.lower():
                print(f"  - {volume}")

        print(f"\nConfig file exists: {self.manifest_after['config_exists']}")

        # GREEN Phase Tests: Verify artifacts were REMOVED
        print(f"\n{BOLD}GREEN Phase Validation (Artifacts should be REMOVED):{RESET}")

        # We selected to remove EVERYTHING
        targets_to_remove = [
            ('container', 'platform-postgres'),
            ('container', 'kerberos-sidecar'),
            ('config', 'platform-config.yaml'),
        ]

        all_removed = True
        for artifact_type, artifact_name in targets_to_remove:
            if artifact_type == 'container':
                still_exists = artifact_name in self.manifest_after['containers']
            elif artifact_type == 'config':
                still_exists = self.manifest_after['config_exists']
            else:
                still_exists = False

            if not still_exists:
                self.print_success(f"GREEN PASS: {artifact_name} removed correctly")
                self.green_results.append({
                    'artifact': artifact_name,
                    'expected': 'REMOVED',
                    'actual': 'REMOVED',
                    'pass': True
                })
            else:
                self.print_failure(f"GREEN FAIL: {artifact_name} should be removed but still exists")
                self.green_results.append({
                    'artifact': artifact_name,
                    'expected': 'REMOVED',
                    'actual': 'STILL_EXISTS',
                    'pass': False
                })
                self.failures.append({
                    'phase': 'GREEN',
                    'issue': f'{artifact_name} should be removed but still exists',
                    'severity': 'CRITICAL',
                    'evidence': f'User selected to remove {artifact_name} but clean-slate did not remove it',
                    'user_action': f'User answered YES to remove {artifact_name}'
                })
                all_removed = False

        # Check for unintended removals (things NOT in our manifest before)
        containers_removed = self.manifest_before['containers'] - self.manifest_after['containers']
        containers_unexpected = containers_removed - {'platform-postgres', 'kerberos-sidecar'}

        if containers_unexpected:
            print(f"\n{YELLOW}Warning: Unexpected containers removed:{RESET}")
            for container in containers_unexpected:
                print(f"  - {container}")
                self.failures.append({
                    'phase': 'GREEN',
                    'issue': f'Unintended removal of container {container}',
                    'severity': 'MEDIUM',
                    'evidence': f'Container {container} was removed but was not a platform service'
                })

        return all_removed

    def generate_report(self):
        """Generate final report with grade"""
        self.print_phase("TEST REPORT")

        # Count results
        red_pass = sum(1 for r in self.red_results if r['pass'])
        red_total = len(self.red_results)
        green_pass = sum(1 for r in self.green_results if r['pass'])
        green_total = len(self.green_results)

        print(f"{BOLD}Test Summary:{RESET}")
        print(f"  RED Phase:   {red_pass}/{red_total} passed")
        print(f"  GREEN Phase: {green_pass}/{green_total} passed")
        print(f"  Failures:    {len(self.failures)}")

        # Grade calculation
        if len(self.failures) == 0 and red_pass == red_total and green_pass == green_total:
            grade = 'A'
            description = 'PERFECT - All artifacts correctly removed'
        elif len(self.failures) <= 1 and green_pass >= green_total - 1:
            grade = 'B'
            description = 'GOOD - Minor issues'
        elif len(self.failures) <= 3 and green_pass >= green_total - 2:
            grade = 'C'
            description = 'ACCEPTABLE - Some issues'
        elif green_pass >= green_total / 2:
            grade = 'D'
            description = 'POOR - Multiple failures'
        else:
            grade = 'F'
            description = 'FAILED - Critical failures'

        print(f"\n{BOLD}{'='*80}{RESET}")
        print(f"{BOLD}FINAL GRADE: {grade} - {description}{RESET}")
        print(f"{BOLD}{'='*80}{RESET}")

        if self.failures:
            print(f"\n{BOLD}{RED}Failure Details:{RESET}")
            for i, failure in enumerate(self.failures, 1):
                print(f"\n{i}. {failure.get('issue', 'Unknown issue')}")
                print(f"   Phase: {failure.get('phase', 'Unknown')}")
                print(f"   Severity: {failure.get('severity', 'Unknown')}")
                if 'evidence' in failure:
                    print(f"   Evidence: {failure['evidence']}")
                if 'user_action' in failure:
                    print(f"   User Action: {failure['user_action']}")

        # Detailed results
        print(f"\n{BOLD}Detailed Results:{RESET}")
        print(f"\n{BOLD}RED Phase (Before - Artifacts Should Exist):{RESET}")
        for result in self.red_results:
            status = f"{GREEN}PASS{RESET}" if result['pass'] else f"{RED}FAIL{RESET}"
            print(f"  [{status}] {result['artifact']}: expected={result['expected']}, actual={result['actual']}")

        print(f"\n{BOLD}GREEN Phase (After - Artifacts Should Be Removed):{RESET}")
        for result in self.green_results:
            status = f"{GREEN}PASS{RESET}" if result['pass'] else f"{RED}FAIL{RESET}"
            print(f"  [{status}] {result['artifact']}: expected={result['expected']}, actual={result['actual']}")

        return grade


def main():
    print(f"{BOLD}{BLUE}")
    print("="*80)
    print("PRECISION RED/GREEN ACCEPTANCE TEST".center(80))
    print("Clean-Slate Wizard: Remove Every Component".center(80))
    print("="*80)
    print(RESET)

    working_dir = "/home/troubladore/repos/airflow-data-platform"
    tester = PrecisionTester(working_dir)

    try:
        # SETUP Phase
        if not tester.setup_phase():
            print(f"\n{RED}SETUP phase failed - cannot continue{RESET}")
            sys.exit(1)

        # RED Phase
        if not tester.red_phase():
            print(f"\n{YELLOW}WARNING: RED phase found missing artifacts{RESET}")
            print("Continuing with test, but setup may have issues...")

        # Execute Action
        if not tester.execute_action():
            print(f"\n{RED}EXECUTE phase failed - clean-slate wizard crashed{RESET}")
            tester.generate_report()
            sys.exit(1)

        # GREEN Phase
        tester.green_phase()

        # Report
        grade = tester.generate_report()

        # Exit code based on grade
        if grade in ['A', 'B']:
            sys.exit(0)
        elif grade == 'C':
            sys.exit(1)
        else:
            sys.exit(2)

    except KeyboardInterrupt:
        print(f"\n{YELLOW}Test interrupted by user{RESET}")
        sys.exit(130)
    except Exception as e:
        print(f"\n{RED}Test failed with exception: {e}{RESET}")
        import traceback
        traceback.print_exc()
        sys.exit(3)


if __name__ == '__main__':
    main()
