#!/usr/bin/env python3
"""
Mock Corporate Image Utility
=============================
Creates local Docker images tagged with corporate registry naming conventions
for testing the platform installer with complex image paths.

Usage:
    ./mock-corporate-image.py create <mock-name>     # Create mock with custom name
    ./mock-corporate-image.py remove <mock-name>     # Remove mock image
    ./mock-corporate-image.py list                   # List all docker images that look like mocks

Examples:
    ./mock-corporate-image.py create mycorp.jfrog.io/docker-mirror/mycorp-approved-images/postgres/17.5:2025.10.01
    ./mock-corporate-image.py create registry.company.com/data/postgres/prod:v2025
    ./mock-corporate-image.py remove mycorp.jfrog.io/docker-mirror/mycorp-approved-images/postgres/17.5:2025.10.01
"""

import subprocess
import sys
import argparse
import json
import yaml
import os
from pathlib import Path

class Colors:
    GREEN = '\033[92m'
    RED = '\033[91m'
    YELLOW = '\033[93m'
    BLUE = '\033[94m'
    RESET = '\033[0m'
    BOLD = '\033[1m'

def get_default_postgres_image():
    """Get the default PostgreSQL image from the platform configuration."""
    # First, try to get from postgres spec
    spec_file = Path('wizard/services/postgres/spec.yaml')
    if spec_file.exists():
        try:
            with open(spec_file, 'r') as f:
                spec = yaml.safe_load(f)
                # Find the postgres_image step
                for step in spec.get('steps', []):
                    if step.get('id') == 'postgres_image':
                        default = step.get('default_value')
                        if default:
                            return default
        except Exception:
            pass

    # Fallback to hardcoded default
    return 'postgres:17.5-alpine'

def run_command(cmd, capture=False):
    """Run a shell command and return result."""
    if not capture:
        print(f"{Colors.BLUE}Running: {' '.join(cmd)}{Colors.RESET}")

    if capture:
        result = subprocess.run(cmd, capture_output=True, text=True)
        return result.returncode, result.stdout, result.stderr
    else:
        result = subprocess.run(cmd)
        return result.returncode, "", ""

def create_mock_image(mock_name, source_image=None):
    """Create a mock corporate image by tagging an existing image.

    Args:
        mock_name: The mock corporate registry name to use
        source_image: The source image to tag (if None, uses default from config)
    """
    # Get source image from config if not provided
    if source_image is None:
        source_image = get_default_postgres_image()

    print(f"\n{Colors.BOLD}Creating Mock Corporate Image{Colors.RESET}")
    print(f"Source: {Colors.YELLOW}{source_image}{Colors.RESET}")
    print(f"Target: {Colors.YELLOW}{mock_name}{Colors.RESET}\n")

    # First, ensure we have the source image
    print(f"1. Pulling source image...")
    returncode, _, _ = run_command(['docker', 'pull', source_image])
    if returncode != 0:
        print(f"{Colors.RED}Failed to pull source image{Colors.RESET}")
        return False

    # Tag it with the corporate naming
    print(f"\n2. Creating mock corporate tag...")
    returncode, _, _ = run_command(['docker', 'tag', source_image, mock_name])
    if returncode != 0:
        print(f"{Colors.RED}Failed to tag image{Colors.RESET}")
        return False

    print(f"\n{Colors.GREEN}✅ Mock corporate image created successfully!{Colors.RESET}")
    print(f"Image: {Colors.BOLD}{mock_name}{Colors.RESET}")

    # Verify it exists
    print(f"\n3. Verifying image...")
    returncode, stdout, _ = run_command(
        ['docker', 'images', mock_name, '--format', '{{.Repository}}:{{.Tag}} {{.Size}}'],
        capture=True
    )
    if returncode == 0 and stdout:
        print(f"   {stdout.strip()}")

    print(f"\n{Colors.BOLD}Ready to test!{Colors.RESET}")
    print(f"1. Run: {Colors.GREEN}./platform setup{Colors.RESET}")
    print(f"2. Enter this image when prompted: {Colors.YELLOW}{mock_name}{Colors.RESET}")
    print(f"3. After setup, run: {Colors.GREEN}./platform clean-slate{Colors.RESET} to test removal")

    return True

def remove_mock_image(mock_name):
    """Remove a mock corporate image."""
    print(f"\n{Colors.BOLD}Removing Mock Corporate Image{Colors.RESET}")
    print(f"Target: {Colors.YELLOW}{mock_name}{Colors.RESET}\n")

    returncode, _, stderr = run_command(['docker', 'rmi', mock_name], capture=True)

    if returncode == 0:
        print(f"{Colors.GREEN}✅ Mock image removed successfully{Colors.RESET}")
        return True
    elif "No such image" in stderr:
        print(f"{Colors.YELLOW}Image doesn't exist (already removed){Colors.RESET}")
        return True
    else:
        print(f"{Colors.RED}Failed to remove image: {stderr}{Colors.RESET}")
        return False

def list_mock_images():
    """List potential mock corporate images (those with registry-like names)."""
    print(f"\n{Colors.BOLD}Potential Mock Corporate Images{Colors.RESET}")
    print("(Images that look like corporate registry paths)")
    print("=" * 70)

    # Get all images
    returncode, stdout, _ = run_command(
        ['docker', 'images', '--format', '{{.Repository}}:{{.Tag}}\t{{.Size}}\t{{.ID}}'],
        capture=True
    )

    if returncode != 0:
        print(f"{Colors.RED}Failed to list images{Colors.RESET}")
        return

    found_mocks = []
    for line in stdout.strip().split('\n'):
        if line:
            parts = line.split('\t')
            if len(parts) >= 1:
                image_name = parts[0]
                # Check if it looks like a corporate registry path
                # (has domain-like prefix with dots or multiple path segments)
                if ('.' in image_name.split('/')[0] or
                    image_name.count('/') >= 2 or
                    ':' in image_name.split('/')[0].split(':')[0]):  # Port number

                    found_mocks.append(line)

    if found_mocks:
        print(f"\n{Colors.GREEN}Found {len(found_mocks)} potential mock images:{Colors.RESET}\n")
        for image_line in found_mocks:
            parts = image_line.split('\t')
            image = parts[0]
            size = parts[1] if len(parts) > 1 else 'unknown'
            print(f"  {Colors.YELLOW}{image}{Colors.RESET}")
            print(f"    Size: {size}")
    else:
        print(f"\n{Colors.YELLOW}No mock corporate images found{Colors.RESET}")
        print("Create one with: ./mock-corporate-image.py create <mock-name>")

def main():
    parser = argparse.ArgumentParser(
        description='Mock Corporate Image Utility for testing complex Docker image paths',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Create a mock using your corporate registry naming:
  ./mock-corporate-image.py create mycorp.jfrog.io/docker-mirror/postgres/17.5:2025.10.01

  # Create with custom source image:
  ./mock-corporate-image.py create mycorp.jfrog.io/postgres:latest --source postgres:16-alpine

  # Remove the mock:
  ./mock-corporate-image.py remove mycorp.jfrog.io/docker-mirror/postgres/17.5:2025.10.01

  # List all potential mock images:
  ./mock-corporate-image.py list
        """
    )

    parser.add_argument(
        'command',
        choices=['create', 'remove', 'list'],
        help='Command to execute'
    )

    parser.add_argument(
        'mock_name',
        nargs='?',
        help='Mock image name (required for create/remove)'
    )

    parser.add_argument(
        '--source',
        help='Source image to use (default: reads from platform config)'
    )

    args = parser.parse_args()

    try:
        if args.command == 'create':
            if not args.mock_name:
                print(f"{Colors.RED}Error: mock_name is required for create command{Colors.RESET}")
                print("\nExample:")
                print("  ./mock-corporate-image.py create mycorp.jfrog.io/postgres:17.5")
                sys.exit(1)

            success = create_mock_image(args.mock_name, args.source)
            sys.exit(0 if success else 1)

        elif args.command == 'remove':
            if not args.mock_name:
                print(f"{Colors.RED}Error: mock_name is required for remove command{Colors.RESET}")
                sys.exit(1)

            success = remove_mock_image(args.mock_name)
            sys.exit(0 if success else 1)

        elif args.command == 'list':
            list_mock_images()

    except KeyboardInterrupt:
        print(f"\n{Colors.YELLOW}Interrupted by user{Colors.RESET}")
        sys.exit(1)
    except Exception as e:
        print(f"{Colors.RED}Error: {e}{Colors.RESET}")
        import traceback
        traceback.print_exc()
        sys.exit(1)

if __name__ == '__main__':
    main()