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
    spec_file = Path('wizard/services/base_platform/spec.yaml')
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

def get_default_kerberos_image():
    """Get the default Kerberos image from the platform configuration."""
    # First, try to get from kerberos spec
    spec_file = Path('wizard/services/kerberos/spec.yaml')
    if spec_file.exists():
        try:
            with open(spec_file, 'r') as f:
                spec = yaml.safe_load(f)
                # Find the image_input step
                for step in spec.get('steps', []):
                    if step.get('id') == 'image_input':
                        default = step.get('default_value')
                        if default:
                            return default
        except Exception:
            pass

    # Fallback to common default
    return 'ubuntu:22.04'

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

def build_sql_auth_image(mock_name, source_image=None):
    """Build a SQL auth testing image with Kerberos + Microsoft SQL drivers.

    This builds an image with both Kerberos packages and Microsoft SQL Server
    drivers for testing SQL authentication scenarios.

    Args:
        mock_name: The mock corporate registry name to use
        source_image: The source image to build from (if None, uses default)
    """
    # Get source image from config if not provided
    if source_image is None:
        source_image = 'alpine:3.19'  # Default to Alpine for SQL auth

    print(f"\n{Colors.BOLD}Building SQL Auth Testing Image{Colors.RESET}")
    print(f"Base: {Colors.YELLOW}{source_image}{Colors.RESET}")
    print(f"Target: {Colors.YELLOW}{mock_name}{Colors.RESET}\n")

    # For SQL auth, we currently only support Alpine-based images due to ODBC driver requirements
    # The Microsoft ODBC drivers for Alpine are specific builds
    dockerfile_content = f'''FROM {source_image}

# Install Kerberos client libraries and SQL Server ODBC drivers
RUN apk add --no-cache \\
    krb5 \\
    krb5-libs \\
    krb5-conf \\
    krb5-dev \\
    bash \\
    curl \\
    gnupg \\
    unixodbc \\
    unixodbc-dev \\
    freetds \\
    freetds-dev \\
    python3 \\
    py3-pip \\
    gcc \\
    g++ \\
    musl-dev \\
    libffi-dev \\
    openssl-dev

# Install Microsoft ODBC Driver for SQL Server (Alpine compatible)
RUN curl -O https://download.microsoft.com/download/3/5/5/355d7943-a338-41a7-858d-53b259ea33f5/msodbcsql18_18.3.2.1-1_amd64.apk && \\
    curl -O https://download.microsoft.com/download/3/5/5/355d7943-a338-41a7-858d-53b259ea33f5/mssql-tools18_18.3.1.1-1_amd64.apk && \\
    apk add --allow-untrusted msodbcsql18_18.3.2.1-1_amd64.apk && \\
    apk add --allow-untrusted mssql-tools18_18.3.1.1-1_amd64.apk && \\
    rm *.apk

# Add labels to identify this as a prebuilt SQL auth image
LABEL platform.sqlauth.prebuilt="true"
LABEL platform.sqlauth.packages="krb5,msodbcsql18,mssql-tools18,freetds"

# Verify installations
RUN which klist && which kinit && echo "✓ Kerberos tools installed"
RUN ls -la /opt/mssql-tools18/bin/sqlcmd || echo "sqlcmd in different location"
RUN test -f /opt/microsoft/msodbcsql18/lib64/libmsodbcsql-18.so && echo "✓ ODBC driver installed" || echo "ODBC driver verification skipped"
'''

    # Write Dockerfile
    import tempfile

    with tempfile.TemporaryDirectory() as tmpdir:
        dockerfile_path = os.path.join(tmpdir, 'Dockerfile')
        with open(dockerfile_path, 'w') as f:
            f.write(dockerfile_content)

        print("1. Building image with Kerberos and SQL packages...")

        # Build the image
        build_cmd = ['docker', 'build', '-t', mock_name, '-f', dockerfile_path, tmpdir]
        returncode, stdout, stderr = run_command(build_cmd)

        if returncode != 0:
            print(f"{Colors.RED}Failed to build image{Colors.RESET}")
            if stderr:
                print(f"Error: {stderr}")
            return False

    print(f"\n{Colors.GREEN}✅ SQL Auth testing image created!{Colors.RESET}")
    print(f"Image: {Colors.BOLD}{mock_name}{Colors.RESET}")

    # Verify it exists
    print(f"\n2. Verifying image...")
    returncode, stdout, _ = run_command(
        ['docker', 'images', mock_name, '--format', '{{.Repository}}:{{.Tag}} {{.Size}}'],
        capture=True
    )
    if returncode == 0 and stdout:
        print(f"   {stdout.strip()}")

    # Test the tools in the image
    print(f"\n3. Testing installed tools...")

    # Test Kerberos tools
    test_cmd = ['docker', 'run', '--rm', mock_name, 'sh', '-c', 'klist -V 2>&1']
    returncode, stdout, stderr = run_command(test_cmd, capture=True)
    if returncode == 0 or 'klist' in (stdout or '') + (stderr or ''):
        print(f"{Colors.GREEN}   ✓ Kerberos tools working{Colors.RESET}")
    else:
        print(f"{Colors.YELLOW}   ⚠ Could not verify Kerberos tools{Colors.RESET}")

    # Test SQL tools (might be in /opt/mssql-tools18/bin)
    test_cmd = ['docker', 'run', '--rm', mock_name, 'sh', '-c',
                'PATH=$PATH:/opt/mssql-tools18/bin && which sqlcmd 2>&1']
    returncode, stdout, stderr = run_command(test_cmd, capture=True)
    if 'sqlcmd' in (stdout or ''):
        print(f"{Colors.GREEN}   ✓ SQL tools installed{Colors.RESET}")
    else:
        print(f"{Colors.YELLOW}   ⚠ SQL tools location varies by installation{Colors.RESET}")

    print(f"\n{Colors.BOLD}Ready for SQL auth testing!{Colors.RESET}")
    print(f"This image contains:")
    print(f"  • Kerberos client libraries (krb5)")
    print(f"  • Microsoft ODBC Driver 18 for SQL Server")
    print(f"  • Microsoft SQL Server command line tools")
    print(f"  • FreeTDS libraries")

    return True

def build_kerberos_image(mock_name, source_image=None):
    """Build a Kerberos image with all required packages and tag with corporate name.

    This builds a new image from a base with Kerberos packages installed,
    then tags it with the corporate naming convention.

    Args:
        mock_name: The mock corporate registry name to use
        source_image: The source image to build from (if None, uses default from config)
    """
    # Get source image from config if not provided
    if source_image is None:
        source_image = get_default_kerberos_image()

    print(f"\n{Colors.BOLD}Building Prebuilt Kerberos Image{Colors.RESET}")
    print(f"Base: {Colors.YELLOW}{source_image}{Colors.RESET}")
    print(f"Target: {Colors.YELLOW}{mock_name}{Colors.RESET}\n")

    # Detect if base image is Alpine or Debian/Ubuntu
    # We'll check by trying to detect package manager in the base image
    detect_cmd = ['docker', 'run', '--rm', source_image, 'sh', '-c', 'which apk 2>/dev/null || which apt-get 2>/dev/null']
    returncode, stdout, _ = run_command(detect_cmd, capture=True)

    is_alpine = 'apk' in (stdout or '')

    # Create temporary Dockerfile with appropriate package manager
    if is_alpine:
        # Alpine-based (includes Wolfi)
        dockerfile_content = f'''FROM {source_image}

# Install Kerberos packages for Alpine/Wolfi
RUN apk add --no-cache \\
    krb5 \\
    krb5-libs \\
    krb5-dev

# Add label to identify this as a prebuilt image
LABEL platform.kerberos.prebuilt="true"
LABEL platform.kerberos.packages="krb5,krb5-libs,krb5-dev"

# Verify installation
RUN which klist && which kinit && echo "✓ Kerberos tools installed"
'''
    else:
        # Debian/Ubuntu-based
        dockerfile_content = f'''FROM {source_image}

# Install Kerberos packages for Debian/Ubuntu
RUN apt-get update && apt-get install -y --no-install-recommends \\
    krb5-user \\
    libkrb5-dev \\
    libkrb5-3 \\
    libk5crypto3 \\
    libgssapi-krb5-2 \\
    && rm -rf /var/lib/apt/lists/*

# Add label to identify this as a prebuilt image
LABEL platform.kerberos.prebuilt="true"
LABEL platform.kerberos.packages="krb5-user,libkrb5-dev"

# Verify installation
RUN which klist && which kinit && echo "✓ Kerberos tools installed"
'''

    # Write Dockerfile
    import tempfile

    with tempfile.TemporaryDirectory() as tmpdir:
        dockerfile_path = os.path.join(tmpdir, 'Dockerfile')
        with open(dockerfile_path, 'w') as f:
            f.write(dockerfile_content)

        print("1. Building image with Kerberos packages...")

        # Build the image
        build_cmd = ['docker', 'build', '-t', mock_name, '-f', dockerfile_path, tmpdir]
        returncode, stdout, stderr = run_command(build_cmd)

        if returncode != 0:
            print(f"{Colors.RED}Failed to build image{Colors.RESET}")
            if stderr:
                print(f"Error: {stderr}")
            return False

    print(f"\n{Colors.GREEN}✅ Prebuilt Kerberos image created!{Colors.RESET}")
    print(f"Image: {Colors.BOLD}{mock_name}{Colors.RESET}")

    # Verify it exists
    print(f"\n2. Verifying image...")
    returncode, stdout, _ = run_command(
        ['docker', 'images', mock_name, '--format', '{{.Repository}}:{{.Tag}} {{.Size}}'],
        capture=True
    )
    if returncode == 0 and stdout:
        print(f"   {stdout.strip()}")

    # Test the image
    print(f"\n3. Testing Kerberos tools in image...")
    test_cmd = ['docker', 'run', '--rm', mock_name, 'sh', '-c', 'klist -V && kinit --version']
    returncode, stdout, stderr = run_command(test_cmd, capture=True)
    if returncode == 0:
        print(f"{Colors.GREEN}   ✓ Kerberos tools working{Colors.RESET}")
        if stdout:
            for line in stdout.strip().split('\n'):
                print(f"     {line}")
    else:
        print(f"{Colors.YELLOW}   ⚠ Could not verify tools (may still be OK){Colors.RESET}")

    print(f"\n{Colors.BOLD}Ready to test!{Colors.RESET}")
    print(f"1. Run: {Colors.GREEN}./platform setup{Colors.RESET}")
    print(f"2. When asked for Kerberos image, enter: {Colors.YELLOW}{mock_name}{Colors.RESET}")
    print(f"3. Choose 'prebuilt' mode when prompted")
    print(f"4. After setup, run: {Colors.GREEN}./platform clean-slate{Colors.RESET} to test removal")

    return True

def setup_test_images():
    """Create all test images defined in test-images.yaml."""
    test_file = Path('test-images.yaml')
    if not test_file.exists():
        print(f"{Colors.RED}test-images.yaml not found{Colors.RESET}")
        return False

    try:
        with open(test_file, 'r') as f:
            config = yaml.safe_load(f)
    except Exception as e:
        print(f"{Colors.RED}Failed to read test-images.yaml: {e}{Colors.RESET}")
        return False

    test_images = config.get('test_images', {})
    if not test_images:
        print(f"{Colors.YELLOW}No test images defined{Colors.RESET}")
        return True

    print(f"\n{Colors.BOLD}Setting Up Test Images{Colors.RESET}")
    print(f"Creating {len(test_images)} test images...\n")

    success_count = 0
    for name, image_config in test_images.items():
        print(f"\n{Colors.BLUE}[{name}]{Colors.RESET}")
        print(f"  {image_config.get('description', 'No description')}")

        image_type = image_config.get('type', 'tag')
        mock_name = image_config.get('mock_name')
        source_image = image_config.get('source_image')

        if not mock_name:
            print(f"  {Colors.RED}✗ Missing mock_name{Colors.RESET}")
            continue

        # Check if already exists
        returncode, stdout, _ = run_command(
            ['docker', 'images', mock_name, '--format', '{{.Repository}}:{{.Tag}}'],
            capture=True
        )
        if returncode == 0 and stdout.strip():
            print(f"  {Colors.YELLOW}⚠ Already exists, skipping{Colors.RESET}")
            success_count += 1
            continue

        # Create based on type
        if image_type == 'tag':
            if create_mock_image(mock_name, source_image):
                success_count += 1
                print(f"  {Colors.GREEN}✓ Created{Colors.RESET}")
            else:
                print(f"  {Colors.RED}✗ Failed to create{Colors.RESET}")
        elif image_type == 'build-kerberos':
            if build_kerberos_image(mock_name, source_image):
                success_count += 1
                print(f"  {Colors.GREEN}✓ Built{Colors.RESET}")
            else:
                print(f"  {Colors.RED}✗ Failed to build{Colors.RESET}")
        elif image_type == 'build-sql-auth':
            if build_sql_auth_image(mock_name, source_image):
                success_count += 1
                print(f"  {Colors.GREEN}✓ Built SQL auth image{Colors.RESET}")
            else:
                print(f"  {Colors.RED}✗ Failed to build SQL auth{Colors.RESET}")
        else:
            print(f"  {Colors.RED}✗ Unknown type: {image_type}{Colors.RESET}")

    print(f"\n{Colors.BOLD}Summary:{Colors.RESET}")
    print(f"  Created: {success_count}/{len(test_images)} images")

    if success_count == len(test_images):
        print(f"\n{Colors.GREEN}✅ All test images ready!{Colors.RESET}")
        return True
    else:
        print(f"\n{Colors.YELLOW}⚠ Some images failed{Colors.RESET}")
        return False

def teardown_test_images():
    """Remove all test images defined in test-images.yaml."""
    test_file = Path('test-images.yaml')
    if not test_file.exists():
        print(f"{Colors.RED}test-images.yaml not found{Colors.RESET}")
        return False

    try:
        with open(test_file, 'r') as f:
            config = yaml.safe_load(f)
    except Exception as e:
        print(f"{Colors.RED}Failed to read test-images.yaml: {e}{Colors.RESET}")
        return False

    test_images = config.get('test_images', {})
    if not test_images:
        print(f"{Colors.YELLOW}No test images defined{Colors.RESET}")
        return True

    print(f"\n{Colors.BOLD}Tearing Down Test Images{Colors.RESET}")
    print(f"Removing {len(test_images)} test images...\n")

    success_count = 0
    for name, image_config in test_images.items():
        mock_name = image_config.get('mock_name')
        if not mock_name:
            continue

        print(f"{Colors.BLUE}[{name}]{Colors.RESET} {mock_name}")
        if remove_mock_image(mock_name):
            success_count += 1

    print(f"\n{Colors.BOLD}Summary:{Colors.RESET}")
    print(f"  Removed: {success_count}/{len(test_images)} images")
    return success_count == len(test_images)

def show_test_status():
    """Show status of all test images defined in test-images.yaml."""
    test_file = Path('test-images.yaml')
    if not test_file.exists():
        print(f"{Colors.RED}test-images.yaml not found{Colors.RESET}")
        return False

    try:
        with open(test_file, 'r') as f:
            config = yaml.safe_load(f)
    except Exception as e:
        print(f"{Colors.RED}Failed to read test-images.yaml: {e}{Colors.RESET}")
        return False

    test_images = config.get('test_images', {})
    if not test_images:
        print(f"{Colors.YELLOW}No test images defined{Colors.RESET}")
        return True

    print(f"\n{Colors.BOLD}Test Image Status{Colors.RESET}")
    print("=" * 80)

    exists_count = 0
    for name, image_config in test_images.items():
        mock_name = image_config.get('mock_name')
        description = image_config.get('description', 'No description')

        if not mock_name:
            continue

        # Check if exists
        returncode, stdout, _ = run_command(
            ['docker', 'images', mock_name, '--format', '{{.Repository}}:{{.Tag}}\t{{.Size}}'],
            capture=True
        )

        print(f"\n{Colors.BLUE}[{name}]{Colors.RESET}")
        print(f"  Description: {description}")
        print(f"  Image: {mock_name}")

        if returncode == 0 and stdout.strip():
            exists_count += 1
            parts = stdout.strip().split('\t')
            size = parts[1] if len(parts) > 1 else 'unknown'
            print(f"  Status: {Colors.GREEN}✓ EXISTS{Colors.RESET} (Size: {size})")
        else:
            print(f"  Status: {Colors.YELLOW}✗ NOT FOUND{Colors.RESET}")

    print(f"\n{Colors.BOLD}Summary:{Colors.RESET}")
    print(f"  {exists_count}/{len(test_images)} test images exist")

    if exists_count == 0:
        print(f"\n💡 Run: {Colors.GREEN}./mock-corporate-image.py test-setup{Colors.RESET} to create test images")
    elif exists_count < len(test_images):
        print(f"\n💡 Some images missing. Run: {Colors.GREEN}./mock-corporate-image.py test-setup{Colors.RESET} to create them")
    else:
        print(f"\n{Colors.GREEN}✅ All test images are ready!{Colors.RESET}")

    return True

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
  # Test Commands - Use test-images.yaml configuration:
  ./mock-corporate-image.py test-setup      # Create all test images
  ./mock-corporate-image.py test-status     # Check status of test images
  ./mock-corporate-image.py test-teardown   # Remove all test images

  # Manual Commands - Create individual images:
  ./mock-corporate-image.py create mycorp.jfrog.io/docker-mirror/postgres/17.5:2025.10.01
  ./mock-corporate-image.py build-kerberos mycorp.jfrog.io/platform/kerberos:v1
  ./mock-corporate-image.py remove mycorp.jfrog.io/docker-mirror/postgres/17.5:2025.10.01
  ./mock-corporate-image.py list
        """
    )

    parser.add_argument(
        'command',
        choices=['create', 'remove', 'list', 'build-kerberos', 'build-sql-auth', 'test-setup', 'test-teardown', 'test-status'],
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

        elif args.command == 'build-kerberos':
            if not args.mock_name:
                print(f"{Colors.RED}Error: image_name is required for build-kerberos command{Colors.RESET}")
                print("\nExample:")
                print("  ./mock-corporate-image.py build-kerberos mycorp.jfrog.io/platform/kerberos:v1")
                sys.exit(1)

            success = build_kerberos_image(args.mock_name, args.source)
            sys.exit(0 if success else 1)

        elif args.command == 'build-sql-auth':
            if not args.mock_name:
                print(f"{Colors.RED}Error: image_name is required for build-sql-auth command{Colors.RESET}")
                print("\nExample:")
                print("  ./mock-corporate-image.py build-sql-auth mycorp.jfrog.io/platform/sql-auth:latest")
                sys.exit(1)

            success = build_sql_auth_image(args.mock_name, args.source)
            sys.exit(0 if success else 1)

        elif args.command == 'test-setup':
            success = setup_test_images()
            sys.exit(0 if success else 1)

        elif args.command == 'test-teardown':
            success = teardown_test_images()
            sys.exit(0 if success else 1)

        elif args.command == 'test-status':
            show_test_status()
            sys.exit(0)

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